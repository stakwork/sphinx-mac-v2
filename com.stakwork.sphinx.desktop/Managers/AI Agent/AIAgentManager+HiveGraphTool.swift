//
//  AIAgentManager+HiveGraphTool.swift
//  Sphinx
//
//  Created on 2026-06-16.
//  Copyright © 2026 Sphinx. All rights reserved.
//

import Foundation
import SwiftAISDK

// MARK: - HiveGraphBridge

/// Bridges GraphChatSSEManager delegate callbacks to a CheckedContinuation.
private class HiveGraphBridge: GraphChatSSEDelegate {

    var continuation: CheckedContinuation<String, Never>?
    var sseManager: GraphChatSSEManager?
    var buffer: String = ""
    var resumed: Bool = false

    func onTextDelta(_ delta: String) {
        buffer += delta
    }

    func onFinish() {
        guard !resumed else { return }
        resumed = true
        let result = buffer.isEmpty ? "No response." : buffer
        print("AIAgent [HiveGraph] SSE finished, buffer length: \(buffer.count)")
        sseManager?.stopStream()
        continuation?.resume(returning: result)
    }

    func onError(_ text: String) {
        guard !resumed else { return }
        resumed = true
        print("AIAgent [HiveGraph] SSE error: \(text)")
        sseManager?.stopStream()
        continuation?.resume(returning: "Hive graph error: \(text)")
    }

    func onToolInputAvailable(_ toolName: String, _ input: String) {}
    func onToolCall(_ toolName: String, _ input: String) {}
    func onToolOutputAvailable(_ toolName: String, _ output: String) {}
}

// MARK: - AIAgentManager+HiveGraphTool

extension AIAgentManager {

    private struct QueryHiveGraphInput: Codable, Sendable {
        let workspace_name: String
        let question: String
    }

    func buildQueryHiveGraphTool() -> TypedTool<QueryHiveGraphInput, JSONValue> {
        tool(
            description: "Query a Hive workspace knowledge graph by workspace name and question. Use this when the user asks about their codebase, project structure, recent commits, or any information that lives in a Hive workspace graph.",
            execute: { (input: QueryHiveGraphInput, _: ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> in
                let result = await AIAgentManager.executeQueryHiveGraph(
                    workspaceName: input.workspace_name,
                    question: input.question
                )
                return .value(.string(result))
            }
        )
    }

    private static func executeQueryHiveGraph(
        workspaceName: String,
        question: String
    ) async -> String {

        // Step 1: Fetch workspaces
        let workspaces: [Workspace]? = await withCheckedContinuation { continuation in
            API.sharedInstance.fetchWorkspacesWithAuth(
                callback: { workspaces in
                    continuation.resume(returning: workspaces)
                },
                errorCallback: {
                    continuation.resume(returning: nil)
                }
            )
        }

        guard let workspaces = workspaces, !workspaces.isEmpty else {
            return "Failed to fetch Hive workspaces. Make sure your Hive token is configured."
        }

        // Step 2: Fuzzy-match workspace name
        let matchResult = resolveWorkspace(name: workspaceName, from: workspaces)
        switch matchResult {
        case .noMatch:
            let names = workspaces.map { $0.name }.joined(separator: ", ")
            return "No Hive workspace found matching '\(workspaceName)'. Available workspaces: \(names)"
        case .ambiguous(let candidates):
            return "Multiple workspaces match '\(workspaceName)': \(candidates.joined(separator: ", ")). Please be more specific."
        case .found(let matchedWorkspace):
            // Use slug if available, fall back to name
            let slug = matchedWorkspace.slug ?? matchedWorkspace.name

            print("AIAgent [HiveGraph] querying workspace '\(slug)': \(question)")

            // Step 3: Resolve auth token
            let token: String? = await withCheckedContinuation { continuation in
                API.sharedInstance.resolveHiveToken(
                    callback: { token in
                        continuation.resume(returning: token)
                    },
                    errorCallback: {
                        continuation.resume(returning: nil)
                    }
                )
            }

            guard let token = token else {
                return "Hive authentication failed. Please check your Hive configuration."
            }

            // Step 4: Stream the graph response
            let bridge = HiveGraphBridge()
            let sseManager = GraphChatSSEManager()
            bridge.sseManager = sseManager
            sseManager.delegate = bridge

            let result: String = await withCheckedContinuation { continuation in
                bridge.continuation = continuation
                sseManager.startStream(
                    messages: [["role": "user", "content": question]],
                    workspaceSlug: slug,
                    token: token
                )
            }

            return result
        }
    }

    // MARK: - Workspace Fuzzy Matching

    private enum WorkspaceMatchResult {
        case found(Workspace)
        case ambiguous([String])
        case noMatch
    }

    private static func resolveWorkspace(name: String, from workspaces: [Workspace]) -> WorkspaceMatchResult {
        let normalizedQuery = hiveNormalizeName(name)

        // Pass 1: exact normalized match
        if let exact = workspaces.first(where: { hiveNormalizeName($0.name) == normalizedQuery }) {
            return .found(exact)
        }

        // Pass 2: case-insensitive contains
        let containsMatches = workspaces.filter { ws in
            hiveNormalizeName(ws.name).contains(normalizedQuery) ||
            normalizedQuery.contains(hiveNormalizeName(ws.name))
        }
        if containsMatches.count == 1 {
            return .found(containsMatches[0])
        }
        if containsMatches.count > 1 {
            return .ambiguous(containsMatches.map { $0.name })
        }

        // Pass 3: Levenshtein fuzzy match
        let threshold = max(1, normalizedQuery.count / 4)
        let fuzzyMatches = workspaces
            .map { ws -> (workspace: Workspace, dist: Int) in
                let dist = hiveLevenshtein(hiveNormalizeName(ws.name), normalizedQuery)
                return (ws, dist)
            }
            .filter { $0.dist <= threshold }
            .sorted { $0.dist < $1.dist }

        if fuzzyMatches.count == 1 {
            return .found(fuzzyMatches[0].workspace)
        }
        if fuzzyMatches.count > 1 {
            // If best is clearly better (gap >= 2), pick it
            if fuzzyMatches[0].dist + 2 <= fuzzyMatches[1].dist {
                return .found(fuzzyMatches[0].workspace)
            }
            return .ambiguous(fuzzyMatches.map { $0.workspace.name })
        }

        return .noMatch
    }

    // Local copies to avoid accessing private members of AIAgentManager from extension
    private static func hiveNormalizeName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let underscoresAsSpaces = trimmed.replacingOccurrences(of: "_", with: " ")
        let components = underscoresAsSpaces.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        return components.joined(separator: " ").lowercased()
    }

    private static func hiveLevenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a), bChars = Array(b)
        let m = aChars.count, n = bChars.count
        if m == 0 { return n }
        if n == 0 { return m }
        var prev = Array(0...n)
        var curr = [Int](repeating: 0, count: n + 1)
        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                curr[j] = aChars[i-1] == bChars[j-1]
                    ? prev[j-1]
                    : 1 + min(prev[j-1], prev[j], curr[j-1])
            }
            prev = curr
        }
        return prev[n]
    }
}
