//
//  ChatPagination.swift
//  Sphinx
//
//  Explicit pagination phase machine, real-id probe reduction, and
//  predicate helpers for chat history paging.
//

import Foundation

enum PaginationPhase: Equatable, Sendable {
    case idle
    case loading
    case exhausted
}

struct ChatPaginationState: Equatable, Sendable {
    var phase: PaginationPhase = .idle
    var pendingScrollRestore: Bool = false
    var didAutoPageOnFirstLoad: Bool = false
    var fetchMinIndex: Int = 0
    var fetchOldestDate: Date? = nil

    var allItemsLoaded: Bool { phase == .exhausted }

    enum BeginLoadResult: Equatable {
        case started
        case skippedThread
        case skippedNotIdle
        case skippedNoChat
    }

    mutating func resetForChatSwitch() {
        phase = .idle
        didAutoPageOnFirstLoad = false
        fetchMinIndex = 0
        fetchOldestDate = nil
        pendingScrollRestore = false
    }

    mutating func beginLoad(isThread: Bool, hasChat: Bool) -> BeginLoadResult {
        if isThread {
            return .skippedThread
        }
        if phase != .idle {
            return .skippedNotIdle
        }
        if !hasChat {
            return .skippedNoChat
        }
        phase = .loading
        return .started
    }

    mutating func abortToIdle() {
        phase = .idle
    }

    mutating func completePage(exhausted: Bool) {
        pendingScrollRestore = true
        phase = exhausted ? .exhausted : .idle
    }

    mutating func consumePendingScrollRestore() {
        pendingScrollRestore = false
    }

    /// At most one first-load auto-fill per chat. Never while a page is
    /// in-flight or waiting for scroll restore.
    mutating func consumeAutoFillIfNeeded(
        wasFirstLoad: Bool,
        documentYOffset: Double
    ) -> Bool {
        guard wasFirstLoad else { return false }
        guard phase != .loading else { return false }
        guard !pendingScrollRestore else { return false }
        guard phase != .exhausted else { return false }
        guard !didAutoPageOnFirstLoad else { return false }
        guard documentYOffset <= 40 else { return false }
        didAutoPageOnFirstLoad = true
        return true
    }

    /// Short local probes exhaust only for Mac agent chats (local-only).
    /// Network-backed chats must still hit the network.
    static func shouldExhaustAfterLocalProbe(
        isAgent: Bool,
        probeCount: Int,
        requestedItems: Int
    ) -> Bool {
        isAgent && probeCount < requestedItems
    }
}

enum ChatPaginationProbe {
    /// `minId` is the smallest real (`id >= 0`) id. `oldestDate` is the
    /// minimum non-nil date among those real rows — not `objects.last?.date`.
    static func minIdAndOldestDate(
        from rows: [(id: Int, date: Date?)]
    ) -> (minId: Int, oldestDate: Date)? {
        let realRows = rows.filter { $0.id >= 0 }
        guard let minId = realRows.map(\.id).min() else {
            return nil
        }
        let oldestDate = realRows.compactMap(\.date).min() ?? Date.distantPast
        return (minId, oldestDate)
    }
}

enum ChatPaginationPredicates {
    static func additionalIdPredicate(
        minIndex: Int?,
        oldestDate: Date?,
        pinnedMessageId: Int?
    ) -> NSPredicate? {
        if let pinnedMessageId {
            let lowerBound = pinnedProbeLowerBound(pinnedMessageId: pinnedMessageId)
            return idWindowPredicate(lowerBound: lowerBound, oldestDate: oldestDate)
        }
        if let minIndex {
            return idWindowPredicate(lowerBound: minIndex, oldestDate: oldestDate)
        }
        return nil
    }

    static func idWindowPredicate(
        lowerBound: Int,
        oldestDate: Date?
    ) -> NSPredicate {
        if let oldestDate {
            return NSPredicate(
                format: "id >= %d OR (id < 0 AND date >= %@)",
                lowerBound,
                oldestDate as NSDate
            )
        }
        return NSPredicate(format: "id >= %d", lowerBound)
    }

    static func realIdProbePredicate(
        chat: NSObject,
        typesToExclude: [Int],
        boostType: Int
    ) -> NSPredicate {
        NSPredicate(
            format: "chat == %@ AND id >= 0 AND (NOT (type IN %@) OR (type == %d AND replyUUID == nil))",
            argumentArray: [chat, typesToExclude, boostType]
        )
    }

    static func pinnedProbeLowerBound(pinnedMessageId: Int) -> Int {
        max(0, pinnedMessageId - 200)
    }

    static func pageFetchLimit(
        limit: Int?,
        pinnedMessageId: Int?,
        minIndex: Int?
    ) -> Int? {
        if let limit, pinnedMessageId == nil, minIndex == nil {
            return limit
        }
        return nil
    }

    static func paginationProbeFetchLimit(items: Int) -> Int {
        items
    }

    static func minMessageIndexPredicate(chat: NSObject) -> NSPredicate {
        NSPredicate(format: "chat == %@ AND id >= 0", chat)
    }
}
