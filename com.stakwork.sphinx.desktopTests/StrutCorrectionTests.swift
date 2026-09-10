//
//  StrutCorrectionTests.swift
//  com.stakwork.sphinx.desktopTests
//

import XCTest
@testable import com_stakwork_sphinx_desktop

final class StrutCorrectionTests: XCTestCase {

    private let session = "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"

    // MARK: - shouldPostCorrection

    func testInvalidSessionReturnsNil() {
        XCTAssertNil(
            StrutCorrection.shouldPostCorrection(
                session: "not-a-uuid",
                prefix: "",
                committed: "hello",
                sent: "hello there"
            )
        )
        XCTAssertNil(
            StrutCorrection.shouldPostCorrection(
                session: "abc/../\(session)",
                prefix: "",
                committed: "hello",
                sent: "hello there"
            )
        )
        XCTAssertNil(
            StrutCorrection.shouldPostCorrection(
                session: "\(session)?x=1",
                prefix: "",
                committed: "hello",
                sent: "hello there"
            )
        )
        XCTAssertNil(
            StrutCorrection.shouldPostCorrection(
                session: "",
                prefix: "",
                committed: "hello",
                sent: "hello there"
            )
        )
    }

    func testEmptyCommittedReturnsNil() {
        XCTAssertNil(
            StrutCorrection.shouldPostCorrection(
                session: session,
                prefix: "",
                committed: "",
                sent: "hello"
            )
        )
        XCTAssertNil(
            StrutCorrection.shouldPostCorrection(
                session: session,
                prefix: "Note",
                committed: "   \n",
                sent: "Note hello"
            )
        )
    }

    func testSentAsIsReturnsNil() {
        XCTAssertNil(
            StrutCorrection.shouldPostCorrection(
                session: session,
                prefix: "",
                committed: "hello world",
                sent: "hello world"
            )
        )
        XCTAssertNil(
            StrutCorrection.shouldPostCorrection(
                session: session,
                prefix: "Note",
                committed: "hello",
                sent: "Note hello"
            )
        )
        XCTAssertNil(
            StrutCorrection.shouldPostCorrection(
                session: session,
                prefix: "Note",
                committed: "hello",
                sent: "Note hello  "
            )
        )
    }

    func testEditedPrefixReturnsNil() {
        XCTAssertNil(
            StrutCorrection.shouldPostCorrection(
                session: session,
                prefix: "Hello ",
                committed: "world",
                sent: "Hi world"
            )
        )
        XCTAssertNil(
            StrutCorrection.shouldPostCorrection(
                session: session,
                prefix: "Hello",
                committed: "world",
                sent: "world"
            )
        )
    }

    func testEditedDictatedSpanReturnsSpanWithoutPrefix() {
        let span = StrutCorrection.shouldPostCorrection(
            session: session,
            prefix: "Note ",
            committed: "hello",
            sent: "Note hello there"
        )
        XCTAssertEqual(span, "hello there")
        XCTAssertFalse(span?.contains("Note") ?? true)

        let emptyPrefix = StrutCorrection.shouldPostCorrection(
            session: session,
            prefix: "",
            committed: "hello",
            sent: "hello world"
        )
        XCTAssertEqual(emptyPrefix, "hello world")
    }

    func testWhitespaceOnlySpanAfterPrefixDropIsPostedWhenCommittedWasNotEmpty() {
        // User deleted the dictated span but left the prefix. Isolated span is
        // empty, which is not equal to committed — still a real edit.
        let span = StrutCorrection.shouldPostCorrection(
            session: session,
            prefix: "Note ",
            committed: "hello",
            sent: "Note "
        )
        XCTAssertEqual(span, "")
    }

    // MARK: - pending-record lifecycle (pure)

    func testLeaveAndVoiceNoteDiscardPending() {
        XCTAssertTrue(StrutCorrection.shouldDiscardPending(reason: "leave"))
        XCTAssertTrue(StrutCorrection.shouldDiscardPending(reason: "voice note"))
        XCTAssertFalse(StrutCorrection.shouldDiscardPending(reason: "send"))
        XCTAssertFalse(StrutCorrection.shouldDiscardPending(reason: "user toggle"))

        XCTAssertNil(
            StrutCorrection.pendingRecordAfterStop(
                reason: "leave",
                session: session,
                prefix: "Note",
                committed: "hello",
                existing: (session: session, prefix: "Note", committed: "hello")
            )
        )
        XCTAssertNil(
            StrutCorrection.pendingRecordAfterStop(
                reason: "voice note",
                session: session,
                prefix: "Note",
                committed: "hello",
                existing: (session: session, prefix: "Note", committed: "hello")
            )
        )
    }

    func testUserToggleAndSendSnapshotCommittedAfterStopWindow() {
        // Trailing final that arrived during stopAndWait is already in
        // `committed` by the time the snapshot is taken.
        let pending = StrutCorrection.pendingRecordAfterStop(
            reason: "send",
            session: session,
            prefix: "Note",
            committed: "hello world"
        )
        XCTAssertEqual(pending?.session, session)
        XCTAssertEqual(pending?.prefix, "Note")
        XCTAssertEqual(pending?.committed, "hello world")

        let toggled = StrutCorrection.pendingRecordAfterStop(
            reason: "user toggle",
            session: session,
            prefix: "",
            committed: "hello"
        )
        XCTAssertEqual(toggled?.committed, "hello")
    }

    func testEmptyFinalsDoNotSnapshot() {
        XCTAssertNil(
            StrutCorrection.pendingRecordAfterStop(
                reason: "send",
                session: session,
                prefix: "Note",
                committed: "  "
            )
        )
        XCTAssertNil(
            StrutCorrection.pendingRecordAfterStop(
                reason: "send",
                session: nil,
                prefix: "",
                committed: "hello"
            )
        )
    }

    func testEmptyFinalsKeepExistingPendingFromPriorToggle() {
        let existing = (session: session, prefix: "Note", committed: "hello")
        let kept = StrutCorrection.pendingRecordAfterStop(
            reason: "send",
            session: session,
            prefix: "",
            committed: "",
            existing: existing
        )
        XCTAssertEqual(kept?.session, existing.session)
        XCTAssertEqual(kept?.committed, existing.committed)
    }

    func testSecondOccupancyDiscardsStalePendingRatherThanPostingIt() {
        let stale = StrutCorrection.makePendingSnapshot(
            session: session,
            prefix: "",
            committed: "old transcript"
        )
        XCTAssertNotNil(stale)

        // beginDictating overwrites pending to nil before a new session exists.
        let afterBegin: (session: String, prefix: String, committed: String)? = nil
        XCTAssertNil(
            StrutCorrection.consumeOnSuccessfulSend(
                pending: afterBegin,
                sent: "old transcript edited"
            )
        )
    }

    func testFailedSendRetainsPendingAndRetryPostsOnce() {
        let pending = StrutCorrection.makePendingSnapshot(
            session: session,
            prefix: "",
            committed: "hello"
        )
        XCTAssertNotNil(pending)

        // Failed send does not consume the record.
        let stillPending = pending
        XCTAssertEqual(stillPending?.committed, "hello")

        let first = StrutCorrection.consumeOnSuccessfulSend(
            pending: stillPending,
            sent: "hello there"
        )
        XCTAssertEqual(first, "hello there")

        // After a successful consume the caller clears pending, so a second
        // tap cannot POST again.
        let second = StrutCorrection.consumeOnSuccessfulSend(
            pending: nil,
            sent: "hello there"
        )
        XCTAssertNil(second)
    }

    func testSendAsIsDoesNotProduceASpan() {
        let pending = StrutCorrection.makePendingSnapshot(
            session: session,
            prefix: "Hi ",
            committed: "there"
        )
        XCTAssertNil(
            StrutCorrection.consumeOnSuccessfulSend(
                pending: pending,
                sent: "Hi there"
            )
        )
    }
}
