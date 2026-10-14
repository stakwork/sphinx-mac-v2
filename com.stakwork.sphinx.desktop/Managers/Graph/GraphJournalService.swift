//
//  GraphJournalService.swift
//  sphinx
//
//  The Core Data journal (GraphJournalEntry) is the source of truth of the
//  personal knowledge graph; the GraphStore (Ladybug) is a rebuildable cache.
//
//  - `apply(_:)` is the ONLY write path: it appends journal rows (one Core Data
//    save per batch) and then applies the mutations derived from those same
//    operations to the store (one store transaction per batch).
//  - Operations are idempotent by (clientId, seq): a duplicate is a no-op.
//  - The journal is append-only. Nothing in this file deletes or truncates rows.
//
//  Threading: all store and journal work runs on ONE serial DispatchQueue.
//
import Foundation
@preconcurrency import CoreData

/// @unchecked Sendable: `store` and all Core Data work are only used from `queue`
/// (serial); the remaining properties are immutable.
final class GraphJournalService: @unchecked Sendable {

    private static let replayPageSize = 500

    private let container: NSPersistentContainer
    private let store: GraphStore
    private let clientIdProvider: GraphClientIdProviding
    private let queue: DispatchQueue

    init(
        container: NSPersistentContainer,
        store: GraphStore,
        clientIdProvider: GraphClientIdProviding,
        queue: DispatchQueue = DispatchQueue(label: "com.stakwork.sphinx.graph", qos: .utility)
    ) {
        self.container = container
        self.store = store
        self.clientIdProvider = clientIdProvider
        self.queue = queue
    }

    // MARK: Public API

    /// Opens the store. If it is missing (freshly created while the journal has rows)
    /// or fails to open, the cache is rebuilt from the journal.
    func start() async throws {
        try await onQueue { () throws -> Void in
            let openResult: GraphStoreOpenResult
            do {
                openResult = try self.store.open()
            } catch {
                // Store failed to open (corrupt/missing pieces): delete and rebuild.
                try self.rebuildOnQueue()
                return
            }
            if openResult == .created, try self.journalCount() > 0 {
                // File was missing: the fresh empty store is rebuilt from the journal.
                try self.replayJournal()
            }
        }
    }

    func close() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.store.close()
                continuation.resume()
            }
        }
    }

    /// Write path. Appends journal rows then updates the store from the same operations.
    @discardableResult
    func apply(_ operation: GraphOperation) async throws -> GraphApplyResult {
        let results = try await apply([operation])
        return results[0]
    }

    @discardableResult
    func apply(_ operations: [GraphOperation]) async throws -> [GraphApplyResult] {
        try await onQueue { try self.applyOnQueue(operations) }
    }

    /// Drops the cache and rebuilds it from the journal. The journal is untouched.
    func rebuild() async throws {
        try await onQueue { try self.rebuildOnQueue() }
    }

    func storeSnapshot() async throws -> GraphStoreSnapshot {
        try await onQueue { try self.store.snapshot() }
    }

    // MARK: Queue plumbing

    private func onQueue<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try work() })
            }
        }
    }

    // MARK: apply

    private struct Key: Hashable {
        let clientId: String
        let seq: Int64
    }

    private func applyOnQueue(_ operations: [GraphOperation]) throws -> [GraphApplyResult] {
        precondition(!Thread.isMainThread, "Graph work must not run on the main thread")
        guard !operations.isEmpty else { return [] }

        // Derive store mutations first: an invalid payload rejects the whole batch
        // before anything is written.
        let derived = try operations.map {
            try GraphMutation(opType: $0.opType, entityId: $0.entityId, payload: $0.payload)
        }

        // `let`, not `var`: a mutable var read inside performAndWait's closure
        // trips Swift 6 strict concurrency ("captured var in concurrently-
        // executing code") even though the closure runs synchronously here.
        let localClientId: String = try operations.contains(where: { $0.clientId == nil })
            ? clientIdProvider.clientId()
            : ""
        let context = container.newBackgroundContext()

        var results: [GraphApplyResult] = []
        var mutations: [GraphMutation] = []

        try context.performAndWait {
            var nextSeq: [String: Int64] = [:]   // highest seq known per client
            var batchKeys = Set<Key>()

            for (index, operation) in operations.enumerated() {
                let clientId = operation.clientId ?? localClientId
                guard !clientId.isEmpty else { throw GraphJournalError.emptyClientId }

                let seq: Int64
                if let explicit = operation.seq {
                    seq = explicit
                    let alreadyJournaled = try self.journalContains(clientId: clientId, seq: seq, in: context)
                    if alreadyJournaled || batchKeys.contains(Key(clientId: clientId, seq: seq)) {
                        results.append(.duplicate(clientId: clientId, seq: seq))
                        continue
                    }
                    let known = try nextSeq[clientId] ?? self.maxSeq(clientId: clientId, in: context)
                    nextSeq[clientId] = max(known, seq)
                } else {
                    let known = try nextSeq[clientId] ?? self.maxSeq(clientId: clientId, in: context)
                    seq = known + 1
                    nextSeq[clientId] = seq
                }

                batchKeys.insert(Key(clientId: clientId, seq: seq))

                let row = GraphJournalEntry(context: context)
                row.clientId = clientId
                row.seq = seq
                row.timestamp = operation.timestamp
                row.opType = operation.opType.rawValue
                row.entityId = operation.entityId
                row.payload = operation.payload
                row.schemaVersion = operation.schemaVersion

                mutations.append(derived[index])
                results.append(.applied(clientId: clientId, seq: seq))
            }

            if context.hasChanges {
                try context.save()
            }
        }

        guard !mutations.isEmpty else { return results }

        do {
            try store.perform(mutations)
        } catch {
            // The journal already holds the rows, so the cache can be rebuilt from it.
            try rebuildOnQueue()
        }
        return results
    }

    private func journalContains(clientId: String, seq: Int64, in context: NSManagedObjectContext) throws -> Bool {
        let request = GraphJournalEntry.fetchRequest()
        request.predicate = NSPredicate(format: "clientId == %@ AND seq == %lld", clientId, seq)
        return try context.count(for: request) > 0
    }

    private func maxSeq(clientId: String, in context: NSManagedObjectContext) throws -> Int64 {
        let request = GraphJournalEntry.fetchRequest()
        request.predicate = NSPredicate(format: "clientId == %@", clientId)
        request.sortDescriptors = [NSSortDescriptor(key: "seq", ascending: false)]
        request.fetchLimit = 1
        return try context.fetch(request).first?.seq ?? 0
    }

    private func journalCount() throws -> Int {
        let context = container.newBackgroundContext()
        return try context.performAndWait {
            try context.count(for: GraphJournalEntry.fetchRequest())
        }
    }

    // MARK: rebuild

    private func rebuildOnQueue() throws {
        precondition(!Thread.isMainThread, "Graph work must not run on the main thread")
        try store.reset()
        try replayJournal()
    }

    /// Replays the journal into the store ONLY.
    ///
    /// This is deliberately not a second write path: it never creates or modifies
    /// journal rows (read-only fetches), it only re-derives the same GraphMutations
    /// that `apply` derived when each row was first written, so the cache converges
    /// to the state the journal describes. All journal writes go through `apply`.
    ///
    /// Order: timestamp, then clientId, then seq. Timestamps give a global timeline
    /// across clients; (clientId, seq) makes ties deterministic. Rows are processed
    /// in pages of `replayPageSize`, one store transaction per page.
    private func replayJournal() throws {
        let context = container.newBackgroundContext()
        var offset = 0

        while true {
            let mutations: [GraphMutation] = try context.performAndWait {
                let request = GraphJournalEntry.fetchRequest()
                request.sortDescriptors = [
                    NSSortDescriptor(key: "timestamp", ascending: true),
                    NSSortDescriptor(key: "clientId", ascending: true),
                    NSSortDescriptor(key: "seq", ascending: true)
                ]
                request.fetchLimit = GraphJournalService.replayPageSize
                request.fetchOffset = offset
                let rows = try context.fetch(request)
                let page = try rows.map { row -> GraphMutation in
                    guard let opType = row.operationType else {
                        throw GraphJournalError.unknownOpType(row.opType)
                    }
                    return try GraphMutation(opType: opType, entityId: row.entityId, payload: row.payload)
                }
                offset += rows.count
                context.reset()
                return page
            }

            if mutations.isEmpty { break }
            try store.perform(mutations)
            if mutations.count < GraphJournalService.replayPageSize { break }
        }
    }
}
