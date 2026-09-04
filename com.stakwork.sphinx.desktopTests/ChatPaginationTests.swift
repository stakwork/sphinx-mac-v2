//
//  ChatPaginationTests.swift
//  com.stakwork.sphinx.desktopTests
//
//  Predicate construction, probe reduction, and pagination phase
//  transitions — no in-memory Core Data stack.
//

import XCTest
@testable import com_stakwork_sphinx_desktop

final class ChatPaginationTests: XCTestCase {

    private func message(id: Int, date: Date?) -> NSMutableDictionary {
        let object = NSMutableDictionary()
        object["id"] = id
        if let date {
            object["date"] = date
        }
        return object
    }

    // MARK: - Probe reduction (getFetchMinIndex)

    func testProbeReturnsSmallestRealIdAndMinNonNilDate() {
        let lastDate = Date(timeIntervalSince1970: 4_000)
        let earlierDate = Date(timeIntervalSince1970: 1_000)
        let laterDate = Date(timeIntervalSince1970: 3_000)

        // id-DESC order like the probe fetch: last object is not the oldest date.
        let rows: [(id: Int, date: Date?)] = [
            (id: 50, date: laterDate),
            (id: 40, date: lastDate),
            (id: -3, date: Date(timeIntervalSince1970: 0)),
            (id: 10, date: earlierDate),
            (id: -1, date: nil)
        ]

        let result = ChatPaginationProbe.minIdAndOldestDate(from: rows)
        XCTAssertEqual(result?.minId, 10)
        XCTAssertEqual(result?.oldestDate, earlierDate)
        XCTAssertNotEqual(result?.oldestDate, lastDate)
    }

    func testProbeIgnoresNegativeIdsWhenPickingMinId() {
        let rows: [(id: Int, date: Date?)] = [
            (id: 8, date: Date(timeIntervalSince1970: 2)),
            (id: -20, date: Date(timeIntervalSince1970: 1)),
            (id: 3, date: Date(timeIntervalSince1970: 5))
        ]
        let result = ChatPaginationProbe.minIdAndOldestDate(from: rows)
        XCTAssertEqual(result?.minId, 3)
        XCTAssertGreaterThan(result?.minId ?? -1, -1)
    }

    func testProbeAllNilDatesFallsBackToDistantPast() {
        let rows: [(id: Int, date: Date?)] = [
            (id: 9, date: nil),
            (id: 4, date: nil)
        ]
        let result = ChatPaginationProbe.minIdAndOldestDate(from: rows)
        XCTAssertEqual(result?.minId, 4)
        XCTAssertEqual(result?.oldestDate, Date.distantPast)
    }

    func testProbeEmptyOrOnlyProvisionalsReturnsNil() {
        XCTAssertNil(ChatPaginationProbe.minIdAndOldestDate(from: []))
        XCTAssertNil(ChatPaginationProbe.minIdAndOldestDate(from: [
            (id: -1, date: Date()),
            (id: -4, date: nil)
        ]))
    }

    // MARK: - Predicate construction

    func testPaginationPredicateDateGatesProvisionals() {
        let oldest = Date(timeIntervalSince1970: 1_000)
        let predicate = ChatPaginationPredicates.idWindowPredicate(
            lowerBound: 40,
            oldestDate: oldest
        )
        let format = predicate.predicateFormat
        XCTAssertTrue(format.contains("id >=") || format.contains("id>="))
        XCTAssertTrue(format.contains("id <") || format.contains("id<"))
        XCTAssertTrue(format.contains("date"))

        XCTAssertTrue(predicate.evaluate(with: message(id: 40, date: oldest)))
        XCTAssertTrue(predicate.evaluate(with: message(id: 99, date: oldest)))
        XCTAssertTrue(predicate.evaluate(with: message(
            id: -2,
            date: Date(timeIntervalSince1970: 1_001)
        )))
        XCTAssertFalse(predicate.evaluate(with: message(
            id: -2,
            date: Date(timeIntervalSince1970: 999)
        )))
        XCTAssertFalse(predicate.evaluate(with: message(id: 12, date: oldest)))
        XCTAssertFalse(predicate.evaluate(with: message(id: -2, date: nil)))
    }

    func testMinIndexWithoutOldestDateDoesNotAddUnboundedNegativeIds() {
        let predicate = ChatPaginationPredicates.idWindowPredicate(
            lowerBound: 40,
            oldestDate: nil
        )
        let format = predicate.predicateFormat.lowercased()
        XCTAssertFalse(format.contains("id < 0") || format.contains("id <0"))
        XCTAssertTrue(predicate.evaluate(with: message(id: 40, date: nil)))
        XCTAssertFalse(predicate.evaluate(with: message(id: -1, date: nil)))
        XCTAssertFalse(predicate.evaluate(with: message(id: 0, date: nil)))
    }

    func testAdditionalPredicateNilWhenNoMinOrPin() {
        XCTAssertNil(
            ChatPaginationPredicates.additionalIdPredicate(
                minIndex: nil,
                oldestDate: nil,
                pinnedMessageId: nil
            )
        )
    }

    func testPinnedLowerBoundIsMaxZeroPinnedMinus200() {
        XCTAssertEqual(
            ChatPaginationPredicates.pinnedProbeLowerBound(pinnedMessageId: 500),
            300
        )
        XCTAssertEqual(
            ChatPaginationPredicates.pinnedProbeLowerBound(pinnedMessageId: 50),
            0
        )
        XCTAssertEqual(
            ChatPaginationPredicates.pinnedProbeLowerBound(pinnedMessageId: 0),
            0
        )
    }

    func testPinnedPredicateDateGatesProvisionals() {
        let oldest = Date(timeIntervalSince1970: 2_000)
        let extra = ChatPaginationPredicates.additionalIdPredicate(
            minIndex: 999,
            oldestDate: oldest,
            pinnedMessageId: 250
        )
        XCTAssertNotNil(extra)
        let lower = ChatPaginationPredicates.pinnedProbeLowerBound(pinnedMessageId: 250)
        XCTAssertEqual(lower, 50)
        XCTAssertTrue(extra!.evaluate(with: message(id: 50, date: oldest)))
        XCTAssertTrue(extra!.evaluate(with: message(
            id: -4,
            date: Date(timeIntervalSince1970: 2_000)
        )))
        XCTAssertFalse(extra!.evaluate(with: message(
            id: -4,
            date: Date(timeIntervalSince1970: 1)
        )))
        XCTAssertFalse(extra!.evaluate(with: message(id: 10, date: oldest)))
    }

    func testPageFetchLimitOnlyWhenNoMinAndNoPin() {
        XCTAssertEqual(
            ChatPaginationPredicates.pageFetchLimit(
                limit: 100,
                pinnedMessageId: nil,
                minIndex: nil
            ),
            100
        )
        XCTAssertNil(
            ChatPaginationPredicates.pageFetchLimit(
                limit: 100,
                pinnedMessageId: nil,
                minIndex: 10
            )
        )
        XCTAssertNil(
            ChatPaginationPredicates.pageFetchLimit(
                limit: 100,
                pinnedMessageId: 20,
                minIndex: nil
            )
        )
    }

    func testPaginationProbeFetchLimitEqualsItems() {
        XCTAssertEqual(
            ChatPaginationPredicates.paginationProbeFetchLimit(items: 150),
            150
        )
    }

    func testMinMessageIndexPredicateRequiresRealIds() {
        let chat = NSObject()
        let predicate = ChatPaginationPredicates.minMessageIndexPredicate(chat: chat)
        let format = predicate.predicateFormat
        XCTAssertTrue(format.contains("id >=") || format.contains("id>="))
        XCTAssertFalse(format.contains("id < 0") || format.contains("id <0"))
    }

    func testRealIdProbePredicateExcludesNegativeIds() {
        let chat = NSObject()
        let predicate = ChatPaginationPredicates.realIdProbePredicate(
            chat: chat,
            typesToExclude: [29],
            boostType: 29
        )
        let format = predicate.predicateFormat
        XCTAssertTrue(format.contains("id >=") || format.contains("id>="))
        XCTAssertFalse(format.contains("id < 0") || format.contains("id <0"))
    }

    // MARK: - Phase transitions

    func testBeginLoadThreadNeverEntersLoading() {
        var state = ChatPaginationState()
        XCTAssertEqual(state.beginLoad(isThread: true, hasChat: true), .skippedThread)
        XCTAssertEqual(state.phase, .idle)
    }

    func testBeginLoadNoChatStaysIdle() {
        var state = ChatPaginationState()
        XCTAssertEqual(state.beginLoad(isThread: false, hasChat: false), .skippedNoChat)
        XCTAssertEqual(state.phase, .idle)
    }

    func testBeginLoadWhenNotIdleIsSkipped() {
        var state = ChatPaginationState()
        state.phase = .loading
        XCTAssertEqual(state.beginLoad(isThread: false, hasChat: true), .skippedNotIdle)
        state.phase = .exhausted
        XCTAssertEqual(state.beginLoad(isThread: false, hasChat: true), .skippedNotIdle)
    }

    func testNoPubkeyAndFailedLookupAbortToIdle() {
        var state = ChatPaginationState()
        XCTAssertEqual(state.beginLoad(isThread: false, hasChat: true), .started)
        XCTAssertEqual(state.phase, .loading)
        state.abortToIdle()
        XCTAssertEqual(state.phase, .idle)
        XCTAssertFalse(state.pendingScrollRestore)
    }

    func testShortNetworkPageExhaustsWithScrollRestore() {
        var state = ChatPaginationState()
        _ = state.beginLoad(isThread: false, hasChat: true)
        state.completePage(exhausted: true)
        XCTAssertEqual(state.phase, .exhausted)
        XCTAssertTrue(state.pendingScrollRestore)
        XCTAssertTrue(state.allItemsLoaded)
    }

    func testFullNetworkPageReturnsIdleWithScrollRestore() {
        var state = ChatPaginationState()
        _ = state.beginLoad(isThread: false, hasChat: true)
        state.completePage(exhausted: false)
        XCTAssertEqual(state.phase, .idle)
        XCTAssertTrue(state.pendingScrollRestore)
        XCTAssertFalse(state.allItemsLoaded)
    }

    func testShortLocalProbeDoesNotExhaustOnNetworkPath() {
        XCTAssertFalse(
            ChatPaginationState.shouldExhaustAfterLocalProbe(
                isAgent: false,
                probeCount: 3,
                requestedItems: 100
            )
        )
    }

    func testAgentShortProbeExhausts() {
        XCTAssertTrue(
            ChatPaginationState.shouldExhaustAfterLocalProbe(
                isAgent: true,
                probeCount: 3,
                requestedItems: 100
            )
        )
        XCTAssertFalse(
            ChatPaginationState.shouldExhaustAfterLocalProbe(
                isAgent: true,
                probeCount: 100,
                requestedItems: 100
            )
        )
    }

    func testFirstLoadSnapshotDoesNotAutoFillWhileLoadingOrPendingRestore() {
        var loading = ChatPaginationState()
        loading.phase = .loading
        XCTAssertFalse(
            loading.consumeAutoFillIfNeeded(wasFirstLoad: true, documentYOffset: 0)
        )

        var restoring = ChatPaginationState()
        restoring.pendingScrollRestore = true
        XCTAssertFalse(
            restoring.consumeAutoFillIfNeeded(wasFirstLoad: true, documentYOffset: 0)
        )
    }

    func testFirstLoadAutoFillIsOneShot() {
        var state = ChatPaginationState()
        XCTAssertTrue(
            state.consumeAutoFillIfNeeded(wasFirstLoad: true, documentYOffset: 10)
        )
        XCTAssertTrue(state.didAutoPageOnFirstLoad)
        XCTAssertFalse(
            state.consumeAutoFillIfNeeded(wasFirstLoad: true, documentYOffset: 10)
        )
    }

    func testAutoFillSkippedWhenNotAtTopOrNotFirstLoad() {
        var state = ChatPaginationState()
        XCTAssertFalse(
            state.consumeAutoFillIfNeeded(wasFirstLoad: true, documentYOffset: 80)
        )
        XCTAssertFalse(
            state.consumeAutoFillIfNeeded(wasFirstLoad: false, documentYOffset: 0)
        )
    }

    func testChatSwitchResetsPhaseAndWindow() {
        var state = ChatPaginationState()
        _ = state.beginLoad(isThread: false, hasChat: true)
        state.completePage(exhausted: true)
        state.fetchMinIndex = 42
        state.fetchOldestDate = Date()
        state.didAutoPageOnFirstLoad = true

        state.resetForChatSwitch()

        XCTAssertEqual(state.phase, .idle)
        XCTAssertFalse(state.didAutoPageOnFirstLoad)
        XCTAssertEqual(state.fetchMinIndex, 0)
        XCTAssertNil(state.fetchOldestDate)
        XCTAssertFalse(state.pendingScrollRestore)
        XCTAssertFalse(state.allItemsLoaded)
    }
}
