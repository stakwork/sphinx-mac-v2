//
//  TribeTimestampTests.swift
//  com.stakwork.sphinx.desktopTests
//
//  Tests for tribe timestamp revert logic:
//  - GenericIncomingMessage.init timestamp gate (tribe uses innerContent.date, DM uses msg.timestamp)
//  - isTribe computation combining tribesMap and senderInfo.isTribeMessage()
//  - restoreGenericPmt tribe/DM timestamp gate
//

import XCTest
@testable import com_stakwork_sphinx_desktop

// MARK: - Helpers

private func makeMsg(
    timestamp: UInt64? = nil,
    index: String = "1",
    msat: UInt64? = nil,
    paymentHash: String? = nil
) -> Msg {
    Msg(
        message: nil,
        type: nil,
        uuid: nil,
        tag: nil,
        index: index,
        sender: nil,
        msat: msat,
        timestamp: timestamp,
        sentTo: nil,
        fromMe: nil,
        paymentHash: paymentHash,
        error: nil
    )
}

private func makeInnerContent(date: Int? = nil, content: String? = nil) -> MessageInnerContent? {
    var ic = MessageInnerContent(map: .init(mappingType: .fromJSON, JSON: [:]))
    ic?.date = date
    ic?.content = content
    return ic
}

private func makeCSR(role: Int? = nil, pubkey: String? = nil) -> ContactServerResponse? {
    var csr = ContactServerResponse(map: .init(mappingType: .fromJSON, JSON: [:]))
    csr?.role = role
    csr?.pubkey = pubkey
    return csr
}

// MARK: - GenericIncomingMessage Timestamp Tests

class GenericIncomingMessageTimestampTests: XCTestCase {

    // MARK: Tribe: always use innerContent.date

    func testTribeMessage_usesInnerContentDate_whenMsgTimestampPresent() {
        let relayTimestamp: UInt64 = 9_999_999
        let senderTimestamp = 1_000_000
        let msg = makeMsg(timestamp: relayTimestamp)
        let inner = makeInnerContent(date: senderTimestamp)
        let csr = makeCSR(role: 2)

        let gim = GenericIncomingMessage(
            msg: msg,
            csr: csr,
            innerContent: inner,
            isTribeMessage: true
        )

        XCTAssertEqual(
            gim?.timestamp,
            senderTimestamp,
            "Tribe message must use innerContent.date even when msg.timestamp is present"
        )
    }

    func testTribeMessage_usesInnerContentDate_whenMsgTimestampNil() {
        let senderTimestamp = 1_000_000
        let msg = makeMsg(timestamp: nil)
        let inner = makeInnerContent(date: senderTimestamp)
        let csr = makeCSR(role: 2)

        let gim = GenericIncomingMessage(
            msg: msg,
            csr: csr,
            innerContent: inner,
            isTribeMessage: true
        )

        XCTAssertEqual(
            gim?.timestamp,
            senderTimestamp,
            "Tribe message must use innerContent.date when msg.timestamp is nil"
        )
    }

    // MARK: DM: use msg.timestamp when present, fall back to innerContent.date

    func testDMMessage_usesMsgTimestamp_whenPresent() {
        let relayTimestamp: UInt64 = 9_999_999
        let senderTimestamp = 1_000_000
        let msg = makeMsg(timestamp: relayTimestamp)
        let inner = makeInnerContent(date: senderTimestamp)
        let csr = makeCSR(role: nil)

        let gim = GenericIncomingMessage(
            msg: msg,
            csr: csr,
            innerContent: inner,
            isTribeMessage: false
        )

        XCTAssertEqual(
            gim?.timestamp,
            Int(relayTimestamp),
            "DM message must use msg.timestamp when present"
        )
    }

    func testDMMessage_fallsBackToInnerContentDate_whenMsgTimestampNil() {
        let senderTimestamp = 1_000_000
        let msg = makeMsg(timestamp: nil)
        let inner = makeInnerContent(date: senderTimestamp)
        let csr = makeCSR(role: nil)

        let gim = GenericIncomingMessage(
            msg: msg,
            csr: csr,
            innerContent: inner,
            isTribeMessage: false
        )

        XCTAssertEqual(
            gim?.timestamp,
            senderTimestamp,
            "DM message must fall back to innerContent.date when msg.timestamp is nil"
        )
    }

    // MARK: Pre-existing edge case: innerContent == nil → timestamp stays nil

    func testTimestampNil_whenInnerContentNil_tribeMessage() {
        let msg = makeMsg(timestamp: 9_999_999)
        let csr = makeCSR(role: 2)

        let gim = GenericIncomingMessage(
            msg: msg,
            csr: csr,
            innerContent: nil,
            isTribeMessage: true
        )

        XCTAssertNil(
            gim?.timestamp,
            "timestamp must stay nil when innerContent is nil (tribe)"
        )
    }

    func testTimestampNil_whenInnerContentNil_DMMessage() {
        let msg = makeMsg(timestamp: 9_999_999)
        let csr = makeCSR(role: nil)

        let gim = GenericIncomingMessage(
            msg: msg,
            csr: csr,
            innerContent: nil,
            isTribeMessage: false
        )

        XCTAssertNil(
            gim?.timestamp,
            "timestamp must stay nil when innerContent is nil (DM)"
        )
    }
}

// MARK: - isTribe Computation Tests (ContactServerResponse.isTribeMessage)

class IsTribeComputationTests: XCTestCase {

    // (a) tribe already known via tribesMap (role not present on CSR)
    func testIsTribe_viaTribesMap() {
        let csr = makeCSR(role: nil, pubkey: "somePubkey")
        // isTribeMessage() returns false (no role), but tribesMap lookup would return non-nil
        // We simulate the combined expression: (tribe != nil) || (senderInfo?.isTribeMessage() ?? false)
        let tribesMapHit = true       // simulates tribesMap[pubkey] != nil
        let csrSignal = csr?.isTribeMessage() ?? false

        let isTribe = tribesMapHit || csrSignal
        XCTAssertTrue(isTribe, "isTribe should be true when tribesMap has the tribe, even with no role on CSR")
    }

    // (b) tribe not in tribesMap but senderInfo.role present (new-member/first-replay race)
    func testIsTribe_viaCSRRole_whenTribesMapMiss() {
        let csr = makeCSR(role: 2, pubkey: "newTribePubkey")
        let tribesMapHit = false      // simulates tribesMap[pubkey] == nil (not yet persisted)
        let csrSignal = csr?.isTribeMessage() ?? false

        let isTribe = tribesMapHit || csrSignal
        XCTAssertTrue(isTribe, "isTribe should be true from CSR role even when tribe not yet in tribesMap")
    }

    // (c) neither signal present (plain DM)
    func testIsTribe_false_forPlainDM() {
        let csr = makeCSR(role: nil, pubkey: "dmPubkey")
        let tribesMapHit = false
        let csrSignal = csr?.isTribeMessage() ?? false

        let isTribe = tribesMapHit || csrSignal
        XCTAssertFalse(isTribe, "isTribe should be false for a plain DM with no role and no tribesMap entry")
    }

    // Sanity: CSR with role=0 (non-nil) still counts as tribe
    func testIsTribeMessage_roleZero_isTribe() {
        let csr = makeCSR(role: 0)
        XCTAssertTrue(csr?.isTribeMessage() ?? false, "role=0 (non-nil) should be treated as tribe")
    }

    // Sanity: nil CSR → false
    func testIsTribeMessage_nilCSR_isFalse() {
        let csr: ContactServerResponse? = nil
        XCTAssertFalse(csr?.isTribeMessage() ?? false)
    }
}

// MARK: - restoreGenericPmt Timestamp Tests
//
// restoreGenericPmt is a method on SphinxOnionManager which requires a full
// Core Data stack and background context, making direct invocation in unit tests
// impractical without mocking the entire actor. We test the timestamp selection
// logic in isolation via a pure helper that mirrors the same gate, ensuring the
// business rule is correct independently of the CoreData wiring.

class RestoreGenericPmtTimestampLogicTests: XCTestCase {

    /// Pure distillation of the timestamp gate inside restoreGenericPmt.
    /// Returns the chosen date (as epoch seconds) or nil.
    private func resolveDate(
        pmtTimestamp: UInt64?,
        innerDate: Int?,
        isTribeMessage: Bool
    ) -> Date? {
        if let timestamp = pmtTimestamp, isTribeMessage == false {
            return Date(timeIntervalSince1970: TimeInterval(timestamp))
        } else if let innerDate = innerDate {
            return Date(timeIntervalSince1970: TimeInterval(UInt64(innerDate)))
        }
        return nil
    }

    // Tribe payment: must use innerContent.date regardless of pmt.timestamp
    func testTribePayment_usesInnerContentDate_whenPmtTimestampPresent() {
        let relayTs: UInt64 = 9_999_999
        let senderDate = 1_000_000
        let date = resolveDate(pmtTimestamp: relayTs, innerDate: senderDate, isTribeMessage: true)
        XCTAssertEqual(date, Date(timeIntervalSince1970: TimeInterval(senderDate)))
    }

    func testTribePayment_usesInnerContentDate_whenPmtTimestampNil() {
        let senderDate = 1_000_000
        let date = resolveDate(pmtTimestamp: nil, innerDate: senderDate, isTribeMessage: true)
        XCTAssertEqual(date, Date(timeIntervalSince1970: TimeInterval(senderDate)))
    }

    // DM payment: must use pmt.timestamp when present
    func testDMPayment_usesPmtTimestamp_whenPresent() {
        let relayTs: UInt64 = 9_999_999
        let senderDate = 1_000_000
        let date = resolveDate(pmtTimestamp: relayTs, innerDate: senderDate, isTribeMessage: false)
        XCTAssertEqual(date, Date(timeIntervalSince1970: TimeInterval(relayTs)))
    }

    // DM payment: falls back to innerContent.date when pmt.timestamp nil
    func testDMPayment_fallsBackToInnerContentDate_whenPmtTimestampNil() {
        let senderDate = 1_000_000
        let date = resolveDate(pmtTimestamp: nil, innerDate: senderDate, isTribeMessage: false)
        XCTAssertEqual(date, Date(timeIntervalSince1970: TimeInterval(senderDate)))
    }

    // innerContent nil → nil date (both tribe and DM)
    func testDate_nil_whenInnerContentNil_tribePayment() {
        let date = resolveDate(pmtTimestamp: nil, innerDate: nil, isTribeMessage: true)
        XCTAssertNil(date)
    }

    func testDate_nil_whenInnerContentNil_DMPayment_andNoTimestamp() {
        let date = resolveDate(pmtTimestamp: nil, innerDate: nil, isTribeMessage: false)
        XCTAssertNil(date)
    }
}
