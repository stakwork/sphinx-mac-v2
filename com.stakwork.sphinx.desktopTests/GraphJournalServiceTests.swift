//
//  GraphJournalServiceTests.swift
//  com.stakwork.sphinx.desktopTests
//
//  Journal/apply/tombstone/rebuild coverage. The journal uses an in-memory Core Data
//  store; most tests use the in-memory fake GraphStore, the rebuild test also runs
//  against a real Ladybug store in a temp directory.
//

import XCTest
import CoreData
@testable import Sphinx

private struct FixedClientId: GraphClientIdProviding {
    let id: String
    func clientId() throws -> String { id }
}

final class GraphJournalServiceTests: XCTestCase {

    private var container: NSPersistentContainer!
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let bundle = Bundle(for: GraphJournalEntry.self)
        let modelURL = try XCTUnwrap(bundle.url(forResource: "com_stakwork_sphinx_desktop", withExtension: "momd"))
        let model = try XCTUnwrap(NSManagedObjectModel(contentsOf: modelURL))
        container = NSPersistentContainer(name: "GraphJournalTests", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }

        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GraphJournalTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        container = nil
        try super.tearDownWithError()
    }

    private func makeService(store: GraphStore, clientId: String = "client-A") -> GraphJournalService {
        GraphJournalService(
            container: container,
            store: store,
            clientIdProvider: FixedClientId(id: clientId)
        )
    }

    private struct JournalRow {
        let clientId: String
        let seq: Int64
        let timestamp: Date
        let operationType: GraphOpType?
        let entityId: UUID
        let payload: Data
        let schemaVersion: Int16
    }

    private func journalRows() throws -> [JournalRow] {
        let request = GraphJournalEntry.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "seq", ascending: true)]
        let context = container.newBackgroundContext()
        return try context.performAndWait {
            try context.fetch(request).map {
                JournalRow(
                    clientId: $0.clientId,
                    seq: $0.seq,
                    timestamp: $0.timestamp,
                    operationType: $0.operationType,
                    entityId: $0.entityId,
                    payload: $0.payload,
                    schemaVersion: $0.schemaVersion
                )
            }
        }
    }

    private func journalCount() throws -> Int {
        let context = container.newBackgroundContext()
        return try context.performAndWait {
            try context.count(for: GraphJournalEntry.fetchRequest())
        }
    }

    // MARK: apply

    func testApplyWritesJournalRowWithAllFields() async throws {
        let store = InMemoryGraphStore()
        let service = makeService(store: store)
        try await service.start()

        let nodeId = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let operation = try GraphOperation.upsertNode(id: nodeId, type: "Person", properties: ["name": "Ada"], timestamp: timestamp)
        let result = try await service.apply(operation)

        XCTAssertEqual(result, .applied(clientId: "client-A", seq: 1))
        let rows = try journalRows()
        XCTAssertEqual(rows.count, 1)
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row.clientId, "client-A")
        XCTAssertEqual(row.seq, 1)
        XCTAssertEqual(row.timestamp, timestamp)
        XCTAssertEqual(row.operationType, .nodeUpsert)
        XCTAssertEqual(row.entityId, nodeId)
        XCTAssertEqual(row.payload, operation.payload)
        XCTAssertEqual(row.schemaVersion, GraphOperation.currentSchemaVersion)

        let snapshot = try await service.storeSnapshot()
        XCTAssertEqual(snapshot.nodes[nodeId]?.kind, "Person")
    }

    func testSeqIncrementsPerClientAndBatchWritesAllRows() async throws {
        let store = InMemoryGraphStore()
        let service = makeService(store: store)
        try await service.start()

        let batch = try (0..<3).map { _ in try GraphOperation.upsertNode(id: UUID(), type: "T") }
        let results = try await service.apply(batch)
        XCTAssertEqual(results, [
            .applied(clientId: "client-A", seq: 1),
            .applied(clientId: "client-A", seq: 2),
            .applied(clientId: "client-A", seq: 3)
        ])
        XCTAssertEqual(store.performCalls, 1, "a batch is one store transaction")

        let next = try await service.apply(try GraphOperation.upsertNode(id: UUID(), type: "T"))
        XCTAssertEqual(next, .applied(clientId: "client-A", seq: 4))

        // Another client has its own sequence.
        var other = try GraphOperation.upsertNode(id: UUID(), type: "T")
        other.clientId = "client-B"
        let otherResult = try await service.apply(other)
        XCTAssertEqual(otherResult, .applied(clientId: "client-B", seq: 1))
        XCTAssertEqual(try journalCount(), 5)
    }

    func testDuplicateClientIdAndSeqIsNoOp() async throws {
        let store = InMemoryGraphStore()
        let service = makeService(store: store)
        try await service.start()

        let nodeId = UUID()
        var first = try GraphOperation.upsertNode(id: nodeId, type: "Original")
        first.clientId = "client-B"
        first.seq = 7
        var duplicate = try GraphOperation.upsertNode(id: nodeId, type: "Changed")
        duplicate.clientId = "client-B"
        duplicate.seq = 7

        let r1 = try await service.apply(first)
        let r2 = try await service.apply(duplicate)
        XCTAssertEqual(r1, .applied(clientId: "client-B", seq: 7))
        XCTAssertEqual(r2, .duplicate(clientId: "client-B", seq: 7))
        XCTAssertEqual(try journalCount(), 1)
        let snapshot = try await service.storeSnapshot()
        XCTAssertEqual(snapshot.nodes[nodeId]?.kind, "Original")

        // Duplicate inside one batch as well.
        let batch = try await service.apply([first, duplicate])
        XCTAssertEqual(batch, [.duplicate(clientId: "client-B", seq: 7), .duplicate(clientId: "client-B", seq: 7)])
        XCTAssertEqual(try journalCount(), 1)
    }

    func testInvalidPayloadRejectsBatchWithoutWriting() async throws {
        let store = InMemoryGraphStore()
        let service = makeService(store: store)
        try await service.start()

        let good = try GraphOperation.upsertNode(id: UUID(), type: "T")
        let bad = GraphOperation(opType: .edgeUpsert, entityId: UUID(), payload: Data("{}".utf8))
        do {
            _ = try await service.apply([good, bad])
            XCTFail("expected invalidPayload")
        } catch {
            XCTAssertEqual(error as? GraphJournalError, .invalidPayload("edge payload needs src, dst (UUIDs) and type"))
        }
        XCTAssertEqual(try journalCount(), 0)
    }

    // MARK: tombstones

    func testDeleteNodeRemovesNodeAndEdgesAndKeepsTombstoneRow() async throws {
        let store = InMemoryGraphStore()
        let service = makeService(store: store)
        try await service.start()

        let a = UUID(), b = UUID(), edge = UUID()
        try await service.apply([
            try GraphOperation.upsertNode(id: a, type: "T"),
            try GraphOperation.upsertNode(id: b, type: "T"),
            try GraphOperation.upsertEdge(id: edge, src: a, dst: b, type: "KNOWS")
        ])
        var snapshot = try await service.storeSnapshot()
        XCTAssertEqual(snapshot.nodes.count, 2)
        XCTAssertEqual(snapshot.edges[edge]?.type, "KNOWS")

        try await service.apply(GraphOperation.deleteNode(id: a))

        snapshot = try await service.storeSnapshot()
        XCTAssertNil(snapshot.nodes[a])
        XCTAssertNotNil(snapshot.nodes[b])
        XCTAssertTrue(snapshot.edges.isEmpty)

        let rows = try journalRows()
        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(rows.last?.operationType, .nodeDelete)
        XCTAssertEqual(rows.last?.entityId, a)
    }

    func testDeleteEdgeKeepsTombstoneRow() async throws {
        let store = InMemoryGraphStore()
        let service = makeService(store: store)
        try await service.start()

        let a = UUID(), b = UUID(), edge = UUID()
        try await service.apply([
            try GraphOperation.upsertNode(id: a, type: "T"),
            try GraphOperation.upsertNode(id: b, type: "T"),
            try GraphOperation.upsertEdge(id: edge, src: a, dst: b, type: "KNOWS")
        ])
        try await service.apply(GraphOperation.deleteEdge(id: edge))

        let snapshot = try await service.storeSnapshot()
        XCTAssertEqual(snapshot.nodes.count, 2)
        XCTAssertTrue(snapshot.edges.isEmpty)
        XCTAssertEqual(try journalCount(), 4)
        XCTAssertEqual(try journalRows().last?.operationType, .edgeDelete)
    }

    // MARK: rebuild

    private func seedOperations() throws -> [GraphOperation] {
        let a = UUID(), b = UUID(), c = UUID()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        return [
            try GraphOperation.upsertNode(id: a, type: "T", properties: ["n": 1], timestamp: base),
            try GraphOperation.upsertNode(id: b, type: "T", timestamp: base.addingTimeInterval(1)),
            try GraphOperation.upsertNode(id: c, type: "T", timestamp: base.addingTimeInterval(2)),
            try GraphOperation.upsertEdge(id: UUID(), src: a, dst: b, type: "R", timestamp: base.addingTimeInterval(3)),
            try GraphOperation.upsertEdge(id: UUID(), src: b, dst: c, type: "R", timestamp: base.addingTimeInterval(4)),
            GraphOperation.deleteNode(id: c, timestamp: base.addingTimeInterval(5))
        ]
    }

    func testRebuildFromJournalAfterFakeStoreLoss() async throws {
        let store = InMemoryGraphStore()
        let service = makeService(store: store)
        try await service.start()
        try await service.apply(try seedOperations())
        let before = try await service.storeSnapshot()
        XCTAssertEqual(before.nodes.count, 2)
        XCTAssertEqual(before.edges.count, 1)

        store.simulateFileLoss()
        try await service.start()

        let after = try await service.storeSnapshot()
        XCTAssertEqual(after, before)
        XCTAssertEqual(try journalCount(), 6)
    }

    func testRebuildAfterFailedStoreWriteKeepsJournalRow() async throws {
        let store = InMemoryGraphStore()
        let service = makeService(store: store)
        try await service.start()

        let id = UUID()
        store.failNextPerform = true
        try await service.apply(try GraphOperation.upsertNode(id: id, type: "T"))

        let snapshot = try await service.storeSnapshot()
        XCTAssertNotNil(snapshot.nodes[id], "cache is rebuilt from the journal after a failed store write")
        XCTAssertEqual(try journalCount(), 1)
    }

    func testRealLadybugRebuildAfterDeletedAndCorruptedFile() async throws {
        let fileURL = tempDirectory.appendingPathComponent(LadybugGraphStore.fileName)
        let store = LadybugGraphStore(fileURL: fileURL)
        let service = makeService(store: store)
        try await service.start()
        try await service.apply(try seedOperations())
        let before = try await service.storeSnapshot()
        XCTAssertEqual(before.nodes.count, 2)
        XCTAssertEqual(before.edges.count, 1)

        // 1. File deleted (with sidecars).
        await service.close()
        let names = try FileManager.default.contentsOfDirectory(atPath: tempDirectory.path)
        for name in names {
            try FileManager.default.removeItem(at: tempDirectory.appendingPathComponent(name))
        }
        try await service.start()
        var after = try await service.storeSnapshot()
        XCTAssertEqual(after, before)
        XCTAssertEqual(try journalCount(), 6)

        // 2. File corrupted.
        await service.close()
        try Data("not a ladybug database".utf8).write(to: fileURL)
        try await service.start()
        after = try await service.storeSnapshot()
        XCTAssertEqual(after, before)
        XCTAssertEqual(try journalCount(), 6)
    }
}
