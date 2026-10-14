//
//  GraphStore.swift
//  sphinx
//
//  Engine-level graph storage abstraction. The journal/apply layer depends only
//  on this protocol; LadybugGraphStore is one adapter (an iOS adapter or an
//  in-memory fake can replace it). All methods are synchronous and are called
//  by GraphJournalService on its single serial queue, never on the main thread.
//
import Foundation

enum GraphStoreOpenResult: Sendable, Equatable {
    /// The backing storage already existed and opened.
    case existing
    /// The backing storage did not exist and was created empty.
    case created
}

struct GraphStoredNode: Sendable, Equatable {
    var kind: String
    var payload: String
}

struct GraphStoredEdge: Sendable, Equatable {
    var src: UUID
    var dst: UUID
    var type: String
    var payload: String
}

struct GraphStoreSnapshot: Sendable, Equatable {
    var nodes: [UUID: GraphStoredNode] = [:]
    var edges: [UUID: GraphStoredEdge] = [:]
}

protocol GraphStore: AnyObject, Sendable {
    /// Opens (creating schema/storage if needed). Throws if existing storage is unusable.
    func open() throws -> GraphStoreOpenResult
    func close()
    /// Destroys all stored data (including sidecar files) and leaves an empty, open store.
    func reset() throws
    /// Closes the store and deletes its files, leaving nothing behind (account wipe).
    /// Unlike `reset()` the store is NOT reopened. Default: just `close()`.
    func destroy() throws
    /// Applies mutations in order, atomically (all or nothing).
    /// Must be idempotent per mutation: upserts overwrite, deletes of missing entities are no-ops.
    /// Deleting a node removes its edges.
    func perform(_ mutations: [GraphMutation]) throws
    func snapshot() throws -> GraphStoreSnapshot

    // MARK: Read API (recall). Same threading rules as above; none of these write.

    /// Nodes whose normalized name or alias equals the normalized `query` (exact matches first),
    /// then those containing it. Normalization is `GraphIdentifiers.normalize`. At most `limit`.
    func findNodes(query: String, limit: Int) throws -> [GraphNodeRecord]
    /// Nodes and edges within `hops` (clamped to 1...2) of `node`, both edge directions,
    /// each node and edge reported once. Unknown node -> empty.
    func neighbors(of node: UUID, hops: Int) throws -> GraphNeighborhood
    /// Every node with its degree and relations: degree desc, then name, then id.
    func rankedNodes() throws -> [GraphRankedNode]
}

extension GraphStore {
    func destroy() throws {
        close()
    }
}
