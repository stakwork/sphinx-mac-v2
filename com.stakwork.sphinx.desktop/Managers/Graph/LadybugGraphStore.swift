//
//  LadybugGraphStore.swift
//  sphinx
//
//  Ladybug adapter for GraphStore. The .lbug file is a rebuildable cache of the
//  Core Data journal. Nodes and edges are keyed by app-created UUID strings, never
//  by Ladybug internal IDs.
//
//  Threading: every method must run off the main thread and, in practice, on the
//  single serial queue owned by GraphJournalService (the instance holds mutable
//  handles and is not otherwise synchronized).
//
import Foundation
import Ladybug

/// @unchecked Sendable: `database`/`connection` are only touched from
/// GraphJournalService's serial queue (enforced by that service, asserted non-main here).
final class LadybugGraphStore: GraphStore, @unchecked Sendable {

    static let fileName = "graph.lbug"

    let fileURL: URL
    private var database: Database?
    private var connection: Connection?

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// `<Application Support>/<bundle id>/Graph/graph.lbug`. The app is sandboxed
    /// (see entitlements), so Application Support resolves inside the app's own
    /// container. No App Group or shared location is used.
    static func defaultFileURL() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return support
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.gl.sphinx.v2", isDirectory: true)
            .appendingPathComponent("Graph", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    // MARK: GraphStore

    func open() throws -> GraphStoreOpenResult {
        precondition(!Thread.isMainThread, "Ladybug must not be used on the main thread")
        if connection != nil { return .existing }

        let fm = FileManager.default
        try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let existed = fm.fileExists(atPath: fileURL.path)

        do {
            let db = try Database(fileURL.path)
            database = db
            connection = try Connection(db)
            try createSchema()
        } catch {
            close()
            throw error
        }
        return existed ? .existing : .created
    }

    func close() {
        precondition(!Thread.isMainThread, "Ladybug must not be used on the main thread")
        connection = nil
        database = nil
    }

    func reset() throws {
        precondition(!Thread.isMainThread, "Ladybug must not be used on the main thread")
        close()
        try deleteFiles()
        _ = try open()
    }

    func destroy() throws {
        precondition(!Thread.isMainThread, "Ladybug must not be used on the main thread")
        close()
        try deleteFiles()
    }

    func perform(_ mutations: [GraphMutation]) throws {
        precondition(!Thread.isMainThread, "Ladybug must not be used on the main thread")
        guard connection != nil else { throw GraphJournalError.storeNotOpen }
        guard !mutations.isEmpty else { return }

        // One transaction per batch: single-row writes ran at ~213 rows/s (Phase 0).
        try run("BEGIN TRANSACTION")
        do {
            for mutation in mutations {
                try apply(mutation)
            }
            try run("COMMIT")
        } catch {
            _ = try? run("ROLLBACK")
            throw error
        }
    }

    func snapshot() throws -> GraphStoreSnapshot {
        precondition(!Thread.isMainThread, "Ladybug must not be used on the main thread")
        guard let connection else { throw GraphJournalError.storeNotOpen }
        var snapshot = GraphStoreSnapshot()

        let nodes = try connection.query("MATCH (n:GNode) RETURN n.id, n.kind, n.payload")
        while nodes.hasNext() {
            guard let row = try nodes.getNext() else { break }
            guard
                let idString = try row.getValue(0) as? String, let id = UUID(uuidString: idString),
                let kind = try row.getValue(1) as? String,
                let payload = try row.getValue(2) as? String
            else { continue }
            snapshot.nodes[id] = GraphStoredNode(kind: kind, payload: payload)
        }

        let edges = try connection.query(
            "MATCH (a:GNode)-[e:GEdge]->(b:GNode) RETURN e.id, a.id, b.id, e.type, e.payload"
        )
        while edges.hasNext() {
            guard let row = try edges.getNext() else { break }
            guard
                let idString = try row.getValue(0) as? String, let id = UUID(uuidString: idString),
                let srcString = try row.getValue(1) as? String, let src = UUID(uuidString: srcString),
                let dstString = try row.getValue(2) as? String, let dst = UUID(uuidString: dstString),
                let type = try row.getValue(3) as? String,
                let payload = try row.getValue(4) as? String
            else { continue }
            snapshot.edges[id] = GraphStoredEdge(src: src, dst: dst, type: type, payload: payload)
        }
        return snapshot
    }

    // Read API. The personal graph is small and node payloads are JSON strings, so these
    // read through `snapshot()` and share the pure logic in GraphReadQueries with the
    // in-memory store (one behaviour, no Cypher to keep in sync).

    func findNodes(query: String, limit: Int) throws -> [GraphNodeRecord] {
        GraphReadQueries.findNodes(in: try snapshot(), query: query, limit: limit)
    }

    func neighbors(of node: UUID, hops: Int) throws -> GraphNeighborhood {
        GraphReadQueries.neighbors(in: try snapshot(), of: node, hops: hops)
    }

    func rankedNodes() throws -> [GraphRankedNode] {
        GraphReadQueries.rankedNodes(in: try snapshot())
    }

    // MARK: Private

    private func createSchema() throws {
        try run("CREATE NODE TABLE IF NOT EXISTS GNode(id STRING PRIMARY KEY, kind STRING, payload STRING)")
        try run("CREATE REL TABLE IF NOT EXISTS GEdge(FROM GNode TO GNode, id STRING, type STRING, payload STRING)")
    }

    private func apply(_ mutation: GraphMutation) throws {
        switch mutation {
        case let .upsertNode(id, kind, payload):
            try run(
                "MERGE (n:GNode {id: $id}) SET n.kind = $kind, n.payload = $payload",
                ["id": id.uuidString, "kind": kind, "payload": payload]
            )
        case let .deleteNode(id):
            try run(
                "MATCH (n:GNode) WHERE n.id = $id DETACH DELETE n",
                ["id": id.uuidString]
            )
        case let .upsertEdge(id, src, dst, type, payload):
            // Edge upsert = replace by id. Endpoints that do not exist (e.g. already
            // tombstoned) make the CREATE match nothing; replay behaves identically.
            try run(
                "MATCH (:GNode)-[e:GEdge]->(:GNode) WHERE e.id = $id DELETE e",
                ["id": id.uuidString]
            )
            try run(
                "MATCH (a:GNode), (b:GNode) WHERE a.id = $src AND b.id = $dst "
                    + "CREATE (a)-[:GEdge {id: $id, type: $type, payload: $payload}]->(b)",
                ["id": id.uuidString, "src": src.uuidString, "dst": dst.uuidString, "type": type, "payload": payload]
            )
        case let .deleteEdge(id):
            try run(
                "MATCH (:GNode)-[e:GEdge]->(:GNode) WHERE e.id = $id DELETE e",
                ["id": id.uuidString]
            )
        }
    }

    private func run(_ cypher: String, _ parameters: [String: String?] = [:]) throws {
        guard let connection else { throw GraphJournalError.storeNotOpen }
        if parameters.isEmpty {
            _ = try connection.query(cypher)
        } else {
            let statement = try connection.prepare(cypher)
            _ = try connection.execute(statement, parameters)
        }
    }

    /// Deletes the .lbug file and every sidecar (.wal, .shadow, ...). A leftover
    /// .wal from a killed run makes the next create fail (Phase 0 findings, §6).
    private func deleteFiles() throws {
        let fm = FileManager.default
        let directory = fileURL.deletingLastPathComponent()
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return }
        let base = fileURL.lastPathComponent
        for name in names where name == base || name.hasPrefix(base + ".") {
            try fm.removeItem(at: directory.appendingPathComponent(name))
        }
    }
}
