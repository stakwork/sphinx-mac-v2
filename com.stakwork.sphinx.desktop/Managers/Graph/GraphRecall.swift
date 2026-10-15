//
//  GraphRecall.swift
//  sphinx
//
//  Job 3: the personal agent uses what it stored. Pure, testable pieces:
//  - ranking (degree, then latest journal timestamp, then name/id),
//  - the passive per-turn summary section (<= maxFacts facts, <= maxSummaryCharacters),
//  - the output of the recall_personal_knowledge tool (capped).
//  See docs/graph-recall.md. Every failure degrades to "no graph context"; nothing here throws.
//
import Foundation

/// What recall needs from the graph. `GraphJournalService` conforms; tests use fakes.
protocol GraphRecallSource: Sendable {
    func rankedNodes(limit: Int) async throws -> [GraphRankedNode]
    func findNodes(query: String, limit: Int) async throws -> [GraphNodeRecord]
    func neighbors(of node: UUID, hops: Int) async throws -> GraphNeighborhood
}

extension GraphJournalService: GraphRecallSource {}

enum GraphRecallRanking {
    /// degree desc, then latest journal timestamp desc (entities never journaled last),
    /// then name, then id (deterministic). A node's timestamp is the newest of its own
    /// journal rows and the rows of its incident edges: extraction skips unchanged nodes,
    /// so "seen again" often shows up only as a new edge.
    static func sort(_ nodes: [GraphRankedNode], latest: [UUID: Date]) -> [GraphRankedNode] {
        func recency(_ n: GraphRankedNode) -> Date {
            var best = latest[n.node.id] ?? .distantPast
            for relation in n.relations {
                if let d = latest[relation.edgeId], d > best { best = d }
            }
            return best
        }
        return nodes.sorted { lhs, rhs in
            if lhs.degree != rhs.degree { return lhs.degree > rhs.degree }
            let lr = recency(lhs), rr = recency(rhs)
            if lr != rr { return lr > rr }
            return GraphReadQueries.nameOrder(lhs.node, rhs.node)
        }
    }
}

enum GraphRecall {

    // MARK: Caps

    static let maxFacts = 15
    static let maxSummaryCharacters = 1_200
    static let maxFactCharacters = 160
    static let maxRelationsPerFact = 3
    /// Bounded wait for the passive summary so a slow graph never slows the turn.
    static let summaryTimeoutSeconds: Double = 1.5

    static let defaultHops = 1
    static let maxToolMatches = 5
    static let maxToolRelationsPerMatch = 15
    static let maxToolOutputCharacters = 3_000

    static let summaryHeader = "Personal knowledge about the user (remembered from earlier chats; may be incomplete or outdated):"

    // MARK: Summary

    /// Lets exactly one of two racing, independent tasks resume a continuation; the second
    /// caller's attempt is silently dropped rather than crashing on a double resume.
    private final class ResumeOnce: @unchecked Sendable {
        private let lock = NSLock()
        private var fired = false
        /// Returns true iff this call was the one that ran `action` (first caller wins).
        @discardableResult
        func fireOnce(_ action: () -> Void) -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard !fired else { return false }
            fired = true
            action()
            return true
        }
    }

    /// The section appended AFTER the constant system prompt, or nil when there is nothing to add.
    /// Starts with a blank line so it can be concatenated directly.
    ///
    /// NOTE: this is deliberately NOT a `withTaskGroup` race. Structured concurrency implicitly
    /// waits for every child task to finish before the group returns -- including a cancelled one
    /// that never polls `Task.isCancelled` -- and the real read (GraphJournalService's
    /// serial-queue dispatch, wrapped in a plain continuation) never does. A `withTaskGroup`-based
    /// race would still block for the read's full duration on a slow graph, not the timeout,
    /// silently defeating the whole point of this function. Racing via two independent
    /// `Task.detached` closures that resume a single continuation is not a structured child of
    /// anything this function awaits, so it returns the instant whichever one wins fires,
    /// regardless of how long the loser takes.
    static func summarySection(from source: GraphRecallSource?, timeoutSeconds: Double = summaryTimeoutSeconds) async -> String? {
        guard let source = source else { return nil }

        let collected: [String]? = await withCheckedContinuation { (continuation: CheckedContinuation<[String]?, Never>) in
            let resumeOnce = ResumeOnce()

            Task.detached {
                let facts: [String]?
                do {
                    let ranked = try await source.rankedNodes(limit: maxFacts)
                    facts = GraphRecall.facts(from: ranked)
                } catch {
                    print("GraphRecall: summary read failed – \(error)")
                    facts = nil
                }
                resumeOnce.fireOnce { continuation.resume(returning: facts) }
            }

            Task.detached {
                try? await Task.sleep(nanoseconds: UInt64(max(timeoutSeconds, 0) * 1_000_000_000))
                let firedNow = resumeOnce.fireOnce { continuation.resume(returning: nil) }
                if firedNow {
                    print("GraphRecall: summary timed out after \(timeoutSeconds)s, continuing without it")
                }
            }
        }

        guard let collected = collected, !collected.isEmpty else { return nil }
        return section(from: collected)
    }

    /// One line per node, at most `maxFacts`: "- Alice (Person, aka Ally): role: sister; lives_in Paris; knows Bob".
    static func facts(from ranked: [GraphRankedNode]) -> [String] {
        var lines: [String] = []
        for entry in ranked.prefix(maxFacts) {
            guard !entry.node.name.isEmpty else { continue }
            lines.append(truncate(factLine(entry), to: maxFactCharacters))
        }
        return lines
    }

    /// Header + facts, dropping trailing facts so the whole section stays within the hard cap.
    static func section(from facts: [String]) -> String? {
        var text = "\n\n" + summaryHeader
        var count = 0
        for fact in facts.prefix(maxFacts) {
            let candidate = text + "\n" + fact
            if candidate.count > maxSummaryCharacters { break }
            text = candidate
            count += 1
        }
        return count == 0 ? nil : text
    }

    private static func factLine(_ entry: GraphRankedNode) -> String {
        let node = entry.node
        var head = "- \(node.name) (\(node.kind)"
        if !node.aliases.isEmpty { head += ", aka " + node.aliases.joined(separator: "/") }
        head += ")"

        var parts: [String] = node.properties.keys.sorted().map { "\($0): \(node.properties[$0] ?? "")" }
        for relation in entry.relations.prefix(maxRelationsPerFact) {
            parts.append(relationText(relation))
        }
        return parts.isEmpty ? head : head + ": " + parts.joined(separator: "; ")
    }

    private static func relationText(_ relation: GraphRelation) -> String {
        let other = relation.otherName.isEmpty ? "(unnamed)" : relation.otherName
        return relation.outgoing ? "\(relation.type) \(other)" : "\(other) \(relation.type) this"
    }

    // MARK: Tool

    /// Clamps hops to 1...2; nil -> default.
    static func clampHops(_ hops: Int?) -> Int {
        min(max(hops ?? defaultHops, 1), GraphReadQueries.maxHops)
    }

    /// Output of recall_personal_knowledge. Never throws; failures read as "unavailable".
    static func toolOutput(query: String, hops: Int?, source: GraphRecallSource?) async -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !GraphIdentifiers.normalize(trimmed).isEmpty else {
            return "Error: missing query parameter."
        }
        guard let source = source else { return "Personal knowledge is unavailable right now." }
        let depth = clampHops(hops)

        do {
            let matches = try await source.findNodes(query: trimmed, limit: maxToolMatches)
            guard !matches.isEmpty else { return "No personal knowledge found for '\(trimmed)'." }

            var blocks: [String] = []
            for match in matches {
                let hood = try await source.neighbors(of: match.id, hops: depth)
                blocks.append(block(for: match, hood: hood))
            }
            let header = "Personal knowledge matching '\(trimmed)' (\(matches.count) match\(matches.count == 1 ? "" : "es")):"
            return truncate(header + "\n" + blocks.joined(separator: "\n"), to: maxToolOutputCharacters)
        } catch {
            print("GraphRecall: recall tool read failed – \(error)")
            return "Personal knowledge is unavailable right now."
        }
    }

    private static func block(for match: GraphNodeRecord, hood: GraphNeighborhood) -> String {
        var head = "- \(match.displayName) (\(match.kind)"
        if !match.aliases.isEmpty { head += ", aka " + match.aliases.joined(separator: "/") }
        head += ")"
        let props = match.properties.keys.sorted().map { "\($0): \(match.properties[$0] ?? "")" }
        if !props.isEmpty { head += ": " + props.joined(separator: "; ") }

        var lines = [head]
        for edge in hood.edges.prefix(maxToolRelationsPerMatch) {
            let src = edge.srcName.isEmpty ? "(unnamed)" : edge.srcName
            let dst = edge.dstName.isEmpty ? "(unnamed)" : edge.dstName
            lines.append("    \(src) \(edge.type) \(dst)")
        }
        if hood.edges.count > maxToolRelationsPerMatch {
            lines.append("    (+\(hood.edges.count - maxToolRelationsPerMatch) more relations)")
        }
        return lines.joined(separator: "\n")
    }

    static func truncate(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(max(limit - 1, 0))) + "…"
    }
}
