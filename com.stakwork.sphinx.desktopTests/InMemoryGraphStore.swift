//
//  InMemoryGraphStore.swift
//  com.stakwork.sphinx.desktopTests
//
//  Fake GraphStore for journal tests. Mirrors the contract of the Ladybug adapter:
//  atomic batches, idempotent upserts, node delete removes incident edges.
//
import Foundation
@testable import Sphinx

final class InMemoryGraphStore: GraphStore, @unchecked Sendable {

    private let lock = NSLock()
    private var state = GraphStoreSnapshot()
    private var isOpen = false
    /// Next `open()` reports `.created` (as if the backing file was missing).
    private var created = true

    private(set) var performCalls = 0
    var failNextPerform = false

    func open() throws -> GraphStoreOpenResult {
        lock.lock(); defer { lock.unlock() }
        isOpen = true
        let result: GraphStoreOpenResult = created ? .created : .existing
        created = false
        return result
    }

    func close() {
        lock.lock(); defer { lock.unlock() }
        isOpen = false
    }

    /// Simulates the backing file disappearing.
    func simulateFileLoss() {
        lock.lock(); defer { lock.unlock() }
        state = GraphStoreSnapshot()
        created = true
        isOpen = false
    }

    func reset() throws {
        lock.lock(); defer { lock.unlock() }
        state = GraphStoreSnapshot()
        isOpen = true
        created = false
    }

    func perform(_ mutations: [GraphMutation]) throws {
        lock.lock(); defer { lock.unlock() }
        guard isOpen else { throw GraphJournalError.storeNotOpen }
        performCalls += 1
        if failNextPerform {
            failNextPerform = false
            throw GraphJournalError.storeNotOpen
        }
        var next = state
        for mutation in mutations {
            switch mutation {
            case let .upsertNode(id, kind, payload):
                next.nodes[id] = GraphStoredNode(kind: kind, payload: payload)
            case let .deleteNode(id):
                next.nodes[id] = nil
                next.edges = next.edges.filter { $0.value.src != id && $0.value.dst != id }
            case let .upsertEdge(id, src, dst, type, payload):
                next.edges[id] = nil
                if next.nodes[src] != nil, next.nodes[dst] != nil {
                    next.edges[id] = GraphStoredEdge(src: src, dst: dst, type: type, payload: payload)
                }
            case let .deleteEdge(id):
                next.edges[id] = nil
            }
        }
        state = next
    }

    func snapshot() throws -> GraphStoreSnapshot {
        lock.lock(); defer { lock.unlock() }
        return state
    }
}
