//
//  GraphRecallTests.swift
//  com.stakwork.sphinx.desktopTests
//
//  Recall (job 3): read API on the in-memory store, ranking, summary builder and tool output.
//  The service-level ranking test uses an in-memory Core Data journal like GraphJournalServiceTests.
//

import XCTest
import CoreData
@testable import Sphinx

private struct FixedClientId: GraphClientIdProviding {
    func clientId() throws -> String { "client-A" }
}

private struct FakeSource: GraphRecallSource {
    var ranked: [GraphRankedNode] = []
    var matches: [GraphNodeRecord] = []
    var hood = GraphNeighborhood()
    var fail = false
    var delayNanoseconds: UInt64 = 0

    func rankedNodes(limit: Int) async throws -> [GraphRankedNode] {
        if delayNanoseconds > 0 { try await Task.sleep(nanoseconds: delayNanoseconds) }
        if fail { throw GraphJournalError.storeNotOpen }
        return Array(ranked.prefix(limit))
    }
    func findNodes(query: String, limit: Int) async throws -> [GraphNodeRecord] {
        if fail { throw GraphJournalError.storeNotOpen }
        return Array(matches.prefix(limit))
    }
    func neighbors(of node: UUID, hops: Int) async throws -> GraphNeighborhood {
        if fail { throw GraphJournalError.storeNotOpen }
        return hood
    }
}

final class GraphRecallTests: XCTestCase {

    // MARK: Fixtures

    private func id(_ type: GraphNodeType, _ name: String) -> UUID {
        GraphIdentifiers.nodeID(type: type, name: name)
    }

    private func nodePayload(_ type: String, name: String, aliases: [String] = [], extra: [String: String] = [:]) -> GraphStoredNode {
        var props: [String: Any] = ["name": name]
        if !aliases.isEmpty { props["aliases"] = aliases }
        for (k, v) in extra { props[k] = v }
        let data = try! JSONSerialization.data(withJSONObject: ["type": type, "properties": props], options: [.sortedKeys])
        return GraphStoredNode(kind: type, payload: String(data: data, encoding: .utf8)!)
    }

    private func edge(_ a: UUID, _ rel: String, _ b: UUID) -> (UUID, GraphStoredEdge) {
        (UUID(), GraphStoredEdge(src: a, dst: b, type: rel, payload: "{}"))
    }

    /// Alice(2 edges), Paris(1), Bob(1), Carol(0) ; Alice -lives_in-> Paris, Alice -knows-> Bob.
    private func sampleSnapshot() -> GraphStoreSnapshot {
        var snap = GraphStoreSnapshot()
        snap.nodes[id(.person, "Alice")] = nodePayload("Person", name: "Alice", aliases: ["Ally"], extra: ["role": "sister"])
        snap.nodes[id(.place, "Paris")] = nodePayload("Place", name: "Paris")
        snap.nodes[id(.person, "Bob")] = nodePayload("Person", name: "Bob")
        snap.nodes[id(.person, "Carol")] = nodePayload("Person", name: "Carol")
        for (eid, e) in [edge(id(.person, "Alice"), "lives_in", id(.place, "Paris")),
                         edge(id(.person, "Alice"), "knows", id(.person, "Bob"))] {
            snap.edges[eid] = e
        }
        return snap
    }

    private func ranked(_ name: String, degree: Int) -> GraphRankedNode {
        GraphRankedNode(
            node: GraphNodeRecord(id: id(.person, name), kind: "Person", name: name),
            degree: degree,
            relations: []
        )
    }

    // MARK: Lookup

    func testLookupExactBeforeSubstringAndNormalized() {
        var snap = sampleSnapshot()
        snap.nodes[id(.person, "Alice Smith")] = nodePayload("Person", name: "Alice  Smith")
        let found = GraphReadQueries.findNodes(in: snap, query: "  ALICE ", limit: 10)
        XCTAssertEqual(found.map { $0.name }, ["Alice", "Alice  Smith"])
    }

    func testLookupByAliasAndFullwidth() {
        let snap = sampleSnapshot()
        XCTAssertEqual(GraphReadQueries.findNodes(in: snap, query: "ally", limit: 10).map { $0.name }, ["Alice"])
        XCTAssertEqual(GraphReadQueries.findNodes(in: snap, query: "Ｐａｒｉｓ", limit: 10).map { $0.name }, ["Paris"])
    }

    func testLookupSubstringEmptyAndLimit() {
        let snap = sampleSnapshot()
        XCTAssertEqual(GraphReadQueries.findNodes(in: snap, query: "ar", limit: 10).map { $0.name }, ["Carol", "Paris"])
        XCTAssertEqual(GraphReadQueries.findNodes(in: snap, query: "ar", limit: 1).count, 1)
        XCTAssertTrue(GraphReadQueries.findNodes(in: snap, query: "   ", limit: 10).isEmpty)
        XCTAssertTrue(GraphReadQueries.findNodes(in: snap, query: "zzz", limit: 10).isEmpty)
    }

    func testInMemoryStoreReadMethodsMatchPureQueries() throws {
        let store = InMemoryGraphStore()
        _ = try store.open()
        try store.perform([
            .upsertNode(id: id(.person, "Alice"), kind: "Person", payload: nodePayload("Person", name: "Alice").payload)
        ])
        XCTAssertEqual(try store.findNodes(query: "alice", limit: 5).count, 1)
        XCTAssertEqual(try store.rankedNodes().count, 1)
        store.failReads = true
        XCTAssertThrowsError(try store.findNodes(query: "alice", limit: 5))
    }

    // MARK: Hops

    func testOneHop() {
        let snap = sampleSnapshot()
        let hood = GraphReadQueries.neighbors(in: snap, of: id(.person, "Alice"), hops: 1)
        XCTAssertEqual(Set(hood.nodes.map { $0.name }), ["Paris", "Bob"])
        XCTAssertEqual(hood.edges.count, 2)
    }

    func testTwoHopsNoDuplicatesAndCyclesAndClamp() {
        var snap = sampleSnapshot()
        // Bob -> Paris closes a cycle Alice-Paris-Bob; Paris -> Alice adds a parallel back edge.
        let e1 = edge(id(.person, "Bob"), "lives_in", id(.place, "Paris"))
        let e2 = edge(id(.place, "Paris"), "related_to", id(.person, "Alice"))
        snap.edges[e1.0] = e1.1
        snap.edges[e2.0] = e2.1
        snap.nodes[id(.person, "Dan")] = nodePayload("Person", name: "Dan")
        let e3 = edge(id(.person, "Bob"), "knows", id(.person, "Dan"))
        snap.edges[e3.0] = e3.1

        let one = GraphReadQueries.neighbors(in: snap, of: id(.person, "Alice"), hops: 1)
        XCTAssertFalse(one.nodes.contains { $0.name == "Dan" })

        let two = GraphReadQueries.neighbors(in: snap, of: id(.person, "Alice"), hops: 2)
        XCTAssertEqual(two.nodes.count, Set(two.nodes.map { $0.id }).count)
        XCTAssertEqual(two.edges.count, Set(two.edges.map { $0.edgeId }).count)
        XCTAssertEqual(Set(two.nodes.map { $0.name }), ["Paris", "Bob", "Dan"])
        XCTAssertFalse(two.nodes.contains { $0.name == "Alice" })
        XCTAssertEqual(two.edges.count, 5)

        // hops 0 and 9 are clamped to 1 and 2.
        XCTAssertEqual(GraphReadQueries.neighbors(in: snap, of: id(.person, "Alice"), hops: 0), one)
        XCTAssertEqual(GraphReadQueries.neighbors(in: snap, of: id(.person, "Alice"), hops: 9), two)
        XCTAssertTrue(GraphReadQueries.neighbors(in: snap, of: UUID(), hops: 1).nodes.isEmpty)
    }

    // MARK: Ranking

    func testRankedNodesByDegreeThenName() {
        let list = GraphReadQueries.rankedNodes(in: sampleSnapshot())
        XCTAssertEqual(list.map { $0.node.name }, ["Alice", "Bob", "Paris", "Carol"])
        XCTAssertEqual(list.map { $0.degree }, [2, 1, 1, 0])
    }

    func testRankingDegreeThenRecencyThenName() {
        let a = ranked("Zed", degree: 2)
        let b = ranked("Amy", degree: 1)   // older
        let c = ranked("Bea", degree: 1)   // newer
        let d = ranked("Cat", degree: 1)   // no timestamp
        let e = ranked("Abe", degree: 1)   // no timestamp, wins name tiebreak over Cat
        let now = Date()
        let latest: [UUID: Date] = [
            b.node.id: now.addingTimeInterval(-100),
            c.node.id: now
        ]
        let sorted = GraphRecallRanking.sort([d, b, a, e, c], latest: latest)
        XCTAssertEqual(sorted.map { $0.node.name }, ["Zed", "Bea", "Amy", "Abe", "Cat"])
    }

    func testRecencyUsesIncidentEdgeTimestamps() {
        let edgeId = UUID()
        var a = ranked("Amy", degree: 1)
        a.relations = [GraphRelation(edgeId: edgeId, type: "knows", otherId: UUID(), otherName: "X", outgoing: true)]
        let b = ranked("Bea", degree: 1)
        let sorted = GraphRecallRanking.sort([b, a], latest: [b.node.id: Date(timeIntervalSince1970: 10), edgeId: Date()])
        XCTAssertEqual(sorted.first?.node.name, "Amy")
    }

    func testServiceRankingUsesJournalTimestamps() async throws {
        let bundle = Bundle(for: GraphJournalEntry.self)
        let modelURL = try XCTUnwrap(bundle.url(forResource: "com_stakwork_sphinx_desktop", withExtension: "momd"))
        let model = try XCTUnwrap(NSManagedObjectModel(contentsOf: modelURL))
        let container = NSPersistentContainer(name: "GraphRecallTests", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }

        let store = InMemoryGraphStore()
        let service = GraphJournalService(container: container, store: store, clientIdProvider: FixedClientId())
        try await service.start()

        let old = Date(timeIntervalSince1970: 1_000)
        let new = Date(timeIntervalSince1970: 2_000)
        try await service.apply([
            try .upsertNode(id: id(.person, "Amy"), type: "Person", properties: ["name": "Amy"], timestamp: old),
            try .upsertNode(id: id(.person, "Bea"), type: "Person", properties: ["name": "Bea"], timestamp: new)
        ])
        let top = try await service.rankedNodes(limit: 15)
        XCTAssertEqual(top.map { $0.node.name }, ["Bea", "Amy"])
    }

    // MARK: Summary

    func testSummaryEmptyGraphYieldsNothing() async {
        let none = await GraphRecall.summarySection(from: FakeSource())
        XCTAssertNil(none)
        let noSource = await GraphRecall.summarySection(from: nil)
        XCTAssertNil(noSource)
    }

    func testSummaryAtMostFifteenFactsAndPlainFormat() async throws {
        let many = (0..<40).map { ranked(String(format: "Person%02d", $0), degree: 40 - $0) }
        let section = await GraphRecall.summarySection(from: FakeSource(ranked: many))
        let text = try XCTUnwrap(section)
        XCTAssertTrue(text.hasPrefix("\n\n" + GraphRecall.summaryHeader))
        let factLines = text.split(separator: "\n").filter { $0.hasPrefix("- ") }
        XCTAssertEqual(factLines.count, GraphRecall.maxFacts)
    }

    func testSummaryHonoursCharacterCap() throws {
        let longName = String(repeating: "x", count: 150)
        let nodes = (0..<15).map { ranked("\(longName)\($0)", degree: 1) }
        let facts = GraphRecall.facts(from: nodes)
        XCTAssertTrue(facts.allSatisfy { $0.count <= GraphRecall.maxFactCharacters })
        let text = try XCTUnwrap(GraphRecall.section(from: facts))
        XCTAssertLessThanOrEqual(text.count, GraphRecall.maxSummaryCharacters)
        XCTAssertLessThan(text.split(separator: "\n").filter { $0.hasPrefix("- ") }.count, 15)
    }

    func testSummaryFactMentionsAliasPropertyAndRelations() {
        let entry = GraphReadQueries.rankedNodes(in: sampleSnapshot())[0]
        let fact = GraphRecall.facts(from: [entry])[0]
        XCTAssertEqual(fact, "- Alice (Person, aka Ally): role: sister; knows Bob; lives_in Paris")
    }

    func testGraphFailureYieldsNoContext() async {
        let section = await GraphRecall.summarySection(from: FakeSource(fail: true))
        XCTAssertNil(section)
    }

    func testSlowGraphTimesOutWithNoContext() async {
        let source = FakeSource(ranked: [ranked("Alice", degree: 1)], delayNanoseconds: 2_000_000_000)
        let section = await GraphRecall.summarySection(from: source, timeoutSeconds: 0.05)
        XCTAssertNil(section)
    }

    // MARK: Tool

    func testToolOutputCapsMatchesAndSize() async {
        let nodes = (0..<20).map { GraphNodeRecord(id: UUID(), kind: "Person", name: "Alice \($0)") }
        var hood = GraphNeighborhood()
        for i in 0..<100 {
            hood.edges.append(GraphWalkEdge(
                edgeId: UUID(), type: "knows", srcId: UUID(), srcName: String(repeating: "S", count: 80) + "\(i)",
                dstId: UUID(), dstName: String(repeating: "D", count: 80), depth: 1))
        }
        let output = await GraphRecall.toolOutput(query: "alice", hops: 2, source: FakeSource(matches: nodes, hood: hood))
        XCTAssertLessThanOrEqual(output.count, GraphRecall.maxToolOutputCharacters)
        XCTAssertLessThanOrEqual(output.split(separator: "\n").filter { $0.hasPrefix("- ") }.count, GraphRecall.maxToolMatches)
    }

    func testToolOutputReadableTextAndHopClamp() async {
        let source = FakeSource(matches: [GraphReadQueries.rankedNodes(in: sampleSnapshot())[0].node],
                                hood: GraphReadQueries.neighbors(in: sampleSnapshot(), of: id(.person, "Alice"), hops: 1))
        let output = await GraphRecall.toolOutput(query: "ally", hops: nil, source: source)
        XCTAssertTrue(output.contains("- Alice (Person, aka Ally): role: sister"))
        XCTAssertTrue(output.contains("Alice lives_in Paris"))
        XCTAssertEqual(GraphRecall.clampHops(nil), 1)
        XCTAssertEqual(GraphRecall.clampHops(0), 1)
        XCTAssertEqual(GraphRecall.clampHops(2), 2)
        XCTAssertEqual(GraphRecall.clampHops(7), 2)
    }

    func testToolNoMatchEmptyQueryAndFailure() async {
        let none = await GraphRecall.toolOutput(query: "nobody", hops: 1, source: FakeSource())
        XCTAssertTrue(none.hasPrefix("No personal knowledge found"))
        let empty = await GraphRecall.toolOutput(query: "  ", hops: 1, source: FakeSource())
        XCTAssertTrue(empty.hasPrefix("Error:"))
        let failed = await GraphRecall.toolOutput(query: "alice", hops: 1, source: FakeSource(fail: true))
        XCTAssertEqual(failed, "Personal knowledge is unavailable right now.")
        let missing = await GraphRecall.toolOutput(query: "alice", hops: 1, source: nil)
        XCTAssertEqual(missing, "Personal knowledge is unavailable right now.")
    }
}
