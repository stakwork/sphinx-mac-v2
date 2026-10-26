//
//  SphinxOnionManagerHistorySyncTests.swift
//  com.stakwork.sphinx.desktopTests
//
//  History cursor over buffered chunk fragments, stale chunk buffers, and forward-only read levels.
//

import XCTest
import MessagePack
@testable import Sphinx

final class SphinxOnionManagerHistorySyncTests: XCTestCase {

    // MARK: - Batch page frame

    private func bigEndian(_ value: UInt64) -> Data {
        return Data(withUnsafeBytes(of: value.bigEndian) { Array($0) })
    }

    private func messageOnion(index: UInt64) -> Data {
        return Data(count: 1401) + bigEndian(index) + bigEndian(1_792_769_415) + bigEndian(7)
    }

    private func paymentOnion(index: UInt64) -> Data {
        return Data(count: 1366) + bigEndian(index) + bigEndian(1_792_769_415) + bigEndian(7) + bigEndian(21_000) + Data(count: 32)
    }

    private func batch(_ onions: [Data]) -> Data {
        return pack(.array(onions.map { .binary($0) }))
    }

    func test_batchPageIndexes_readsMessageAndPaymentOnions() {
        let payload = batch([messageOnion(index: 157829), paymentOnion(index: 157830), messageOnion(index: 157928)])

        XCTAssertEqual(SphinxOnionManager.batchPageIndexes(payload: payload), [157829, 157830, 157928])
    }

    func test_batchPageIndexes_emptyPage() {
        XCTAssertEqual(SphinxOnionManager.batchPageIndexes(payload: batch([])), [])
    }

    func test_batchPageIndexes_nilForPayloadNotFramedAsPage() {
        XCTAssertNil(SphinxOnionManager.batchPageIndexes(payload: Data("{\"error\":1}".utf8)))
        XCTAssertNil(SphinxOnionManager.batchPageIndexes(payload: batch([Data(count: 10)])))
        XCTAssertNil(SphinxOnionManager.batchPageIndexes(payload: batch([messageOnion(index: 1)]) + Data([0x01])))
    }

    // MARK: - History cursor

    func test_reachedIndex_pageOfOnlyBufferedFragmentsStillMovesCursor() {
        // Three long replies interleaved across 157829...157928: the core returns no msgs.
        let payload = batch((157829...157928).map { messageOnion(index: UInt64($0)) })
        let pageMax = SphinxOnionManager.batchPageIndexes(payload: payload)?.max()

        XCTAssertEqual(
            SphinxOnionManager.historyPageReachedIndex(messageIndexes: [], pageMaxIndex: pageMax),
            157928
        )
    }

    func test_reachedIndex_countsBufferedFragmentsAboveReturnedMessages() {
        XCTAssertEqual(
            SphinxOnionManager.historyPageReachedIndex(messageIndexes: ["157930", "157940"], pageMaxIndex: 158028),
            158028
        )
    }

    func test_reachedIndex_fallsBackToMessagesWhenFrameUnreadable() {
        XCTAssertEqual(
            SphinxOnionManager.historyPageReachedIndex(messageIndexes: ["12", nil, "15"], pageMaxIndex: nil),
            15
        )
    }

    func test_reachedIndex_emptyPageEndsFetch() {
        XCTAssertNil(SphinxOnionManager.historyPageReachedIndex(messageIndexes: [], pageMaxIndex: nil))
    }

    // MARK: - Stale chunk buffers

    private func chunkBuffer(firstReceived: UInt64) -> [UInt8] {
        let json = "{\"total_chunks\":50,\"original_msg_type\":0,\"received\":[],\"first_received_ts\":\(firstReceived),\"date\":null}"
        return Array(json.utf8)
    }

    func test_timedOutChunkBufferKeys_onlyStaleOrUnreadableChunkBuffers() {
        let now: UInt64 = 1_792_900_000
        let state: [String: [UInt8]] = [
            "chunkbuf_fresh": chunkBuffer(firstReceived: now - 60),
            "chunkbuf_edge": chunkBuffer(firstReceived: now - 300),
            "chunkbuf_stale": chunkBuffer(firstReceived: now - 2_520),
            "chunkbuf_garbage": [0xFF, 0x00],
            "contact_abc": chunkBuffer(firstReceived: 0),
        ]

        let keys = SphinxOnionManager.timedOutChunkBufferKeys(state: state, now: now)

        XCTAssertEqual(Set(keys), ["chunkbuf_stale", "chunkbuf_garbage"])
    }

    // MARK: - Read levels

    func test_readLevel_unknownUntilGetReadsReply() {
        XCTAssertFalse(SphinxOnionManager.readLevelMovesForward(index: 157828, pubkey: "tribe", serverReadLevels: nil))
    }

    func test_readLevel_neverMovesServerMarkerBack() {
        let levels: [String: UInt64] = ["tribe": 157990]

        XCTAssertFalse(SphinxOnionManager.readLevelMovesForward(index: 157820, pubkey: "tribe", serverReadLevels: levels))
        XCTAssertFalse(SphinxOnionManager.readLevelMovesForward(index: 157990, pubkey: "tribe", serverReadLevels: levels))
        XCTAssertTrue(SphinxOnionManager.readLevelMovesForward(index: 157991, pubkey: "tribe", serverReadLevels: levels))
    }

    func test_readLevel_chatWithoutServerMarker() {
        XCTAssertTrue(SphinxOnionManager.readLevelMovesForward(index: 5, pubkey: "new", serverReadLevels: ["tribe": 157990]))
    }
}
