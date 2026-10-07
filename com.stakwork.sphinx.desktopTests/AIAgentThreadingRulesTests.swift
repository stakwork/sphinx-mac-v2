//
//  AIAgentThreadingRulesTests.swift
//  com.stakwork.sphinx.desktopTests
//
//  Unit tests for AIAgentThreadingRules — pure functions over plain value
//  types, so no Core Data stack is needed.
//

import XCTest
@testable import com_stakwork_sphinx_desktop

final class AIAgentThreadingRulesTests: XCTestCase {

    // MARK: - wireValues

    func test_wireValues_caseA_noThreadNoReply() {
        let result = AIAgentThreadingRules.wireValues(threadUUID: nil, replyTo: nil)
        XCTAssertNil(result.thread)
        XCTAssertNil(result.reply)
    }

    func test_wireValues_caseE_threadOnly() {
        let result = AIAgentThreadingRules.wireValues(threadUUID: "thread-1", replyTo: nil)
        XCTAssertEqual(result.thread, "thread-1")
        XCTAssertNil(result.reply)
    }

    func test_wireValues_caseB_replyNoThread_usesReplyThreadUUID() {
        let replyTo = AgentMessageRef(
            uuid: "R1", threadUUID: "T1", replyUUID: nil, chatId: 1
        )
        let result = AIAgentThreadingRules.wireValues(threadUUID: nil, replyTo: replyTo)
        XCTAssertEqual(result.thread, "T1")
        XCTAssertEqual(result.reply, "R1")
    }

    func test_wireValues_caseD_replyWithExplicitThread_explicitWins() {
        let replyTo = AgentMessageRef(
            uuid: "R1", threadUUID: "T1", replyUUID: nil, chatId: 1
        )
        let result = AIAgentThreadingRules.wireValues(threadUUID: "T2", replyTo: replyTo)
        XCTAssertEqual(result.thread, "T2")
        XCTAssertEqual(result.reply, "R1")
    }

    func test_wireValues_replyUUIDFallback_whenNoThreadUUID() {
        // R has a replyUUID but no threadUUID -> wire thread falls back to R.replyUUID
        let replyTo = AgentMessageRef(
            uuid: "R1", threadUUID: nil, replyUUID: "ReplyChainUUID", chatId: 1
        )
        let result = AIAgentThreadingRules.wireValues(threadUUID: nil, replyTo: replyTo)
        XCTAssertEqual(result.thread, "ReplyChainUUID")
        XCTAssertEqual(result.reply, "R1")
    }

    func test_wireValues_fallbackToUUID_whenNoThreadOrReplyUUID() {
        let replyTo = AgentMessageRef(
            uuid: "R1", threadUUID: nil, replyUUID: nil, chatId: 1
        )
        let result = AIAgentThreadingRules.wireValues(threadUUID: nil, replyTo: replyTo)
        XCTAssertEqual(result.thread, "R1")
        XCTAssertEqual(result.reply, "R1")
    }

    func test_wireValues_oneOnOneReply_stillYieldsNonNilThread() {
        // Intentional: 1:1 replies still produce a non-nil wire thread,
        // matching the composer's own behaviour.
        let replyTo = AgentMessageRef(
            uuid: "R1", threadUUID: nil, replyUUID: nil, chatId: 42
        )
        let result = AIAgentThreadingRules.wireValues(threadUUID: nil, replyTo: replyTo)
        XCTAssertNotNil(result.thread)
        XCTAssertEqual(result.thread, "R1")
    }

    // MARK: - validateReplyTarget

    func test_validateReplyTarget_notFound() {
        let result = AIAgentThreadingRules.validateReplyTarget(nil, chatId: 1)
        XCTAssertEqual(result, .refused("message not found"))
    }

    func test_validateReplyTarget_nilUUID_pending() {
        let ref = AgentMessageRef(uuid: nil, threadUUID: nil, replyUUID: nil, chatId: 1)
        let result = AIAgentThreadingRules.validateReplyTarget(ref, chatId: 1)
        XCTAssertFalse(result.isOK)
    }

    func test_validateReplyTarget_deleted() {
        let ref = AgentMessageRef(
            uuid: "R1", threadUUID: nil, replyUUID: nil, chatId: 1, isDeleted: true
        )
        let result = AIAgentThreadingRules.validateReplyTarget(ref, chatId: 1)
        XCTAssertFalse(result.isOK)
    }

    func test_validateReplyTarget_otherChat() {
        let ref = AgentMessageRef(uuid: "R1", threadUUID: nil, replyUUID: nil, chatId: 2)
        let result = AIAgentThreadingRules.validateReplyTarget(ref, chatId: 1)
        XCTAssertFalse(result.isOK)
    }

    func test_validateReplyTarget_valid() {
        let ref = AgentMessageRef(uuid: "R1", threadUUID: nil, replyUUID: nil, chatId: 1)
        let result = AIAgentThreadingRules.validateReplyTarget(ref, chatId: 1)
        XCTAssertTrue(result.isOK)
    }

    // MARK: - validateThreadRoot

    func test_validateThreadRoot_rejectedInOneOnOne() {
        let ref = AgentMessageRef(uuid: "Root1", threadUUID: nil, replyUUID: nil, chatId: 1)
        let result = AIAgentThreadingRules.validateThreadRoot(ref, chatId: 1, isTribe: false)
        XCTAssertFalse(result.isOK)
    }

    func test_validateThreadRoot_notFound() {
        let result = AIAgentThreadingRules.validateThreadRoot(nil, chatId: 1, isTribe: true)
        XCTAssertFalse(result.isOK)
    }

    func test_validateThreadRoot_deleted() {
        let ref = AgentMessageRef(
            uuid: "Root1", threadUUID: nil, replyUUID: nil, chatId: 1, isDeleted: true
        )
        let result = AIAgentThreadingRules.validateThreadRoot(ref, chatId: 1, isTribe: true)
        XCTAssertFalse(result.isOK)
    }

    func test_validateThreadRoot_otherChat() {
        let ref = AgentMessageRef(uuid: "Root1", threadUUID: nil, replyUUID: nil, chatId: 2)
        let result = AIAgentThreadingRules.validateThreadRoot(ref, chatId: 1, isTribe: true)
        XCTAssertFalse(result.isOK)
    }

    func test_validateThreadRoot_memberAsRoot_rejected() {
        // threadUUID != nil && threadUUID != uuid => this message is itself
        // a thread member, not a root.
        let ref = AgentMessageRef(uuid: "Member1", threadUUID: "Root1", replyUUID: nil, chatId: 1)
        let result = AIAgentThreadingRules.validateThreadRoot(ref, chatId: 1, isTribe: true)
        XCTAssertFalse(result.isOK)
    }

    func test_validateThreadRoot_validRoot_zeroOrOneReplies_stillAccepted() {
        // Reply count is NOT checked here.
        let ref = AgentMessageRef(uuid: "Root1", threadUUID: nil, replyUUID: nil, chatId: 1)
        let result = AIAgentThreadingRules.validateThreadRoot(ref, chatId: 1, isTribe: true)
        XCTAssertTrue(result.isOK)
    }

    func test_validateThreadRoot_rootThatPointsToItself_accepted() {
        // threadUUID == uuid is allowed (root pointing at itself is not a
        // "member" case).
        let ref = AgentMessageRef(uuid: "Root1", threadUUID: "Root1", replyUUID: nil, chatId: 1)
        let result = AIAgentThreadingRules.validateThreadRoot(ref, chatId: 1, isTribe: true)
        XCTAssertTrue(result.isOK)
    }

    // MARK: - validateThreadReplyConsistency

    func test_validateThreadReplyConsistency_mismatch_rejected() {
        // R is in T1, thread = T2
        let replyTo = AgentMessageRef(uuid: "R1", threadUUID: "T1", replyUUID: nil, chatId: 1)
        let result = AIAgentThreadingRules.validateThreadReplyConsistency(
            threadUUID: "T2", replyTo: replyTo
        )
        XCTAssertFalse(result.isOK)
    }

    func test_validateThreadReplyConsistency_replyIsRoot_accepted() {
        let replyTo = AgentMessageRef(uuid: "T1", threadUUID: nil, replyUUID: nil, chatId: 1)
        let result = AIAgentThreadingRules.validateThreadReplyConsistency(
            threadUUID: "T1", replyTo: replyTo
        )
        XCTAssertTrue(result.isOK)
    }

    func test_validateThreadReplyConsistency_replyIsMember_accepted() {
        let replyTo = AgentMessageRef(uuid: "R1", threadUUID: "T1", replyUUID: nil, chatId: 1)
        let result = AIAgentThreadingRules.validateThreadReplyConsistency(
            threadUUID: "T1", replyTo: replyTo
        )
        XCTAssertTrue(result.isOK)
    }

    // MARK: - threadRootUUIDs

    func test_threadRootUUIDs_oneReply_doesNotMakeRoot() {
        let rows = [
            AgentThreadRow(uuid: "M1", threadUUID: "Root1", date: Date())
        ]
        let roots = AIAgentThreadingRules.threadRootUUIDs(replies: rows, isTribe: true)
        XCTAssertTrue(roots.isEmpty)
    }

    func test_threadRootUUIDs_twoReplies_makesRoot() {
        let now = Date()
        let rows = [
            AgentThreadRow(uuid: "M1", threadUUID: "Root1", date: now),
            AgentThreadRow(uuid: "M2", threadUUID: "Root1", date: now.addingTimeInterval(60))
        ]
        let roots = AIAgentThreadingRules.threadRootUUIDs(replies: rows, isTribe: true)
        XCTAssertEqual(roots, Set(["Root1"]))
    }

    func test_threadRootUUIDs_nonTribe_empty_evenWithTwoPlusReplies() {
        let now = Date()
        let rows = [
            AgentThreadRow(uuid: "M1", threadUUID: "Root1", date: now),
            AgentThreadRow(uuid: "M2", threadUUID: "Root1", date: now.addingTimeInterval(60))
        ]
        let roots = AIAgentThreadingRules.threadRootUUIDs(replies: rows, isTribe: false)
        XCTAssertTrue(roots.isEmpty)
    }

    // MARK: - groupThreads

    func test_groupThreads_threshold_excludesSingleReplyGroups() {
        let now = Date()
        let rows = [
            AgentThreadRow(uuid: "M1", threadUUID: "RootA", date: now),
            AgentThreadRow(uuid: "M2", threadUUID: "RootB", date: now),
            AgentThreadRow(uuid: "M3", threadUUID: "RootB", date: now.addingTimeInterval(30))
        ]
        let grouped = AIAgentThreadingRules.groupThreads(rows: rows)
        XCTAssertEqual(grouped.count, 1)
        XCTAssertEqual(grouped.first?.rootUUID, "RootB")
        XCTAssertEqual(grouped.first?.replyCount, 2)
    }

    func test_groupThreads_sortedNewestActivityFirst() {
        let now = Date()
        let rows = [
            AgentThreadRow(uuid: "M1", threadUUID: "RootA", date: now),
            AgentThreadRow(uuid: "M2", threadUUID: "RootA", date: now.addingTimeInterval(10)),
            AgentThreadRow(uuid: "M3", threadUUID: "RootB", date: now.addingTimeInterval(100)),
            AgentThreadRow(uuid: "M4", threadUUID: "RootB", date: now.addingTimeInterval(200))
        ]
        let grouped = AIAgentThreadingRules.groupThreads(rows: rows)
        XCTAssertEqual(grouped.map { $0.rootUUID }, ["RootB", "RootA"])
    }

    func test_groupThreads_limitAppliedByCaller() {
        let now = Date()
        var rows: [AgentThreadRow] = []
        for i in 0..<10 {
            let root = "Root\(i)"
            rows.append(AgentThreadRow(uuid: "M\(i)a", threadUUID: root, date: now.addingTimeInterval(Double(i))))
            rows.append(AgentThreadRow(uuid: "M\(i)b", threadUUID: root, date: now.addingTimeInterval(Double(i) + 0.5)))
        }
        let grouped = AIAgentThreadingRules.groupThreads(rows: rows)
        XCTAssertEqual(grouped.count, 10)
        let limited = Array(grouped.prefix(3))
        XCTAssertEqual(limited.count, 3)
        // newest first
        XCTAssertEqual(limited.first?.rootUUID, "Root9")
    }

    // MARK: - formatLine

    func test_formatLine_uuidPending_whenNil() {
        let line = AIAgentThreadingRules.formatLine(
            isOwner: false,
            isTribe: false,
            senderAlias: nil,
            resolvedContactName: "Bob",
            date: Date(),
            uuid: nil,
            threadUUID: nil,
            replyUUID: nil,
            isThreadRoot: false,
            threadReplyCount: 0,
            isInThread: false,
            content: "hello"
        )
        XCTAssertTrue(line.contains("uuid=pending"))
    }

    func test_formatLine_inThreadMarker() {
        let line = AIAgentThreadingRules.formatLine(
            isOwner: false,
            isTribe: true,
            senderAlias: "alice",
            resolvedContactName: nil,
            date: Date(),
            uuid: "M1",
            threadUUID: "Root1",
            replyUUID: nil,
            isThreadRoot: false,
            threadReplyCount: 0,
            isInThread: true,
            content: "hello"
        )
        XCTAssertTrue(line.contains("[IN THREAD]"))
    }

    func test_formatLine_threadRootMarker_withCount() {
        let line = AIAgentThreadingRules.formatLine(
            isOwner: false,
            isTribe: true,
            senderAlias: "alice",
            resolvedContactName: nil,
            date: Date(),
            uuid: "Root1",
            threadUUID: nil,
            replyUUID: nil,
            isThreadRoot: true,
            threadReplyCount: 3,
            isInThread: false,
            content: "hello"
        )
        XCTAssertTrue(line.contains("[THREAD ROOT, 3 replies]"))
    }

    func test_formatLine_oneOnOne_usesResolvedContactName_notRawInput() {
        let line = AIAgentThreadingRules.formatLine(
            isOwner: false,
            isTribe: false,
            senderAlias: "irrelevant-alias",
            resolvedContactName: "Bob Resolved",
            date: Date(),
            uuid: "M1",
            threadUUID: nil,
            replyUUID: nil,
            isThreadRoot: false,
            threadReplyCount: 0,
            isInThread: false,
            content: "hello"
        )
        XCTAssertTrue(line.hasPrefix("[Bob Resolved]"))
        XCTAssertFalse(line.contains("irrelevant-alias"))
    }

    func test_formatLine_tribeNoAlias_showsUnknown_notTribeName() {
        let line = AIAgentThreadingRules.formatLine(
            isOwner: false,
            isTribe: true,
            senderAlias: nil,
            resolvedContactName: "SomeTribeName",
            date: Date(),
            uuid: "M1",
            threadUUID: nil,
            replyUUID: nil,
            isThreadRoot: false,
            threadReplyCount: 0,
            isInThread: false,
            content: "hello"
        )
        XCTAssertTrue(line.hasPrefix("[Unknown]"))
        XCTAssertFalse(line.contains("SomeTribeName"))
    }

    func test_formatLine_owner_showsMe() {
        let line = AIAgentThreadingRules.formatLine(
            isOwner: true,
            isTribe: true,
            senderAlias: "owner-alias",
            resolvedContactName: nil,
            date: Date(),
            uuid: "M1",
            threadUUID: nil,
            replyUUID: nil,
            isThreadRoot: false,
            threadReplyCount: 0,
            isInThread: false,
            content: "hello"
        )
        XCTAssertTrue(line.hasPrefix("[Me]"))
    }
}
