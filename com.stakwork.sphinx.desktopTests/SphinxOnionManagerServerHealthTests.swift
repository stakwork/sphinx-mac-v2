//
//  SphinxOnionManagerServerHealthTests.swift
//  com.stakwork.sphinx.desktopTests
//
//  Server-status topic intercept, health store, staleness, and mixer error mapping.
//

import XCTest
@testable import com_stakwork_sphinx_desktop

final class SphinxOnionManagerServerHealthTests: XCTestCase {

    var manager: SphinxOnionManager!

    override func setUp() {
        super.setUp()
        SphinxOnionManager.resetSharedInstance()
        manager = SphinxOnionManager.sharedInstance
    }

    override func tearDown() {
        manager.onOnionHandleInvoked = nil
        manager.serverHealthNowMsOverride = nil
        manager.stopServerHealthStalenessTimer()
        SphinxOnionManager.resetSharedInstance()
        super.tearDown()
    }

    // MARK: - Exact-topic intercept

    func test_statusTopic_isInterceptedBeforeHandle() {
        var handleCalled = false
        manager.onOnionHandleInvoked = { _ in handleCalled = true }

        let payload = Data(#"{"cln_ok":true,"degraded":false,"reason":null,"ts":1}"#.utf8)
        let intercepted = manager.consumeServerStatusMessage(
            topic: SphinxrsHealth.serverStatusTopic(),
            payload: payload
        )

        XCTAssertTrue(intercepted, "exact status topic must be consumed before onion handle()")
        XCTAssertFalse(handleCalled, "status topic must never reach onion handle()")
    }

    func test_substringTopic_isNotIntercepted() {
        let substring = "prefix/\(SphinxrsHealth.serverStatusTopic())/suffix"
        XCTAssertFalse(manager.shouldInterceptServerStatus(topic: substring))
        XCTAssertFalse(
            manager.shouldInterceptServerStatus(
                topic: "not_\(SphinxrsHealth.serverStatusTopic())"
            )
        )
        XCTAssertTrue(
            manager.shouldInterceptServerStatus(
                topic: SphinxrsHealth.serverStatusTopic()
            )
        )

        var handleCalled = false
        manager.onOnionHandleInvoked = { _ in handleCalled = true }
        let consumed = manager.consumeServerStatusMessage(
            topic: substring,
            payload: Data(#"{"cln_ok":true,"degraded":false,"reason":null,"ts":1}"#.utf8)
        )
        XCTAssertFalse(consumed)
        XCTAssertFalse(handleCalled)
    }

    // MARK: - Store start Unknown

    func test_healthStore_startsUnknown() {
        XCTAssertEqual(manager.currentServerHealth, .unknown)
        XCTAssertNil(manager.lastServerStatus)
        XCTAssertEqual(manager.lastServerStatusSeenMs, 0)
    }

    // MARK: - Heartbeat restore + invalid JSON

    func test_healthyHeartbeat_restoresOk_afterDegraded() {
        let now: UInt64 = 1_000_000
        manager.serverHealthNowMsOverride = now

        let degraded = Data(#"{"cln_ok":false,"degraded":true,"reason":null,"ts":1000000}"#.utf8)
        manager.applyServerStatusPayload(degraded)
        XCTAssertEqual(manager.currentServerHealth, .degraded)

        manager.serverHealthNowMsOverride = now + 1_000
        let healthy = Data(#"{"cln_ok":true,"degraded":false,"reason":null,"ts":1001000}"#.utf8)
        manager.applyServerStatusPayload(healthy)
        XCTAssertEqual(manager.currentServerHealth, .ok)
        XCTAssertNil(SphinxrsHealth.localizedBannerCopy(for: .ok))
    }

    func test_invalidPayload_mapsToUnknown() {
        manager.applyServerStatusPayload(Data("not-json".utf8))
        XCTAssertEqual(manager.currentServerHealth, .unknown)
        XCTAssertNil(manager.lastServerStatus)
    }

    // MARK: - Staleness

    func test_staleness_transitionsToUnknown_afterNMissedIntervals() {
        let interval = SphinxrsHealth.defaultIntervalMs
        let n = UInt64(SphinxrsHealth.defaultMaxMissed)
        let now: UInt64 = 5_000_000
        manager.serverHealthNowMsOverride = now

        let healthy = Data(#"{"cln_ok":true,"degraded":false,"reason":null,"ts":5000000}"#.utf8)
        manager.applyServerStatusPayload(healthy)
        XCTAssertEqual(manager.currentServerHealth, .ok)

        // N-1 missed intervals still trusts the last sample.
        manager.serverHealthNowMsOverride = now + interval * (n - 1)
        manager.reevaluateServerHealth()
        XCTAssertEqual(manager.currentServerHealth, .ok)

        // Age > interval * N → Unknown, even if MQTT is still up.
        manager.isConnected = true
        manager.serverHealthNowMsOverride = now + interval * n + 1
        manager.reevaluateServerHealth()
        XCTAssertEqual(manager.currentServerHealth, .unknown)
        XCTAssertTrue(manager.isConnected)
    }

    func test_staleTs_doesNotFlashOk() {
        let now: UInt64 = 10_000_000
        manager.serverHealthNowMsOverride = now
        // Payload ts far in the past relative to now, even though cln_ok is true.
        let stale = Data(#"{"cln_ok":true,"degraded":false,"reason":null,"ts":1}"#.utf8)
        manager.applyServerStatusPayload(stale)
        XCTAssertEqual(manager.currentServerHealth, .unknown)
    }

    // MARK: - Error mapping

    func test_mappedErrorCopy_forKnownAndUnknownCodes() {
        XCTAssertEqual(
            SphinxrsHealth.parseMixerErrorCode(raw: "CLN_UNAVAILABLE"),
            .clnUnavailable
        )
        XCTAssertEqual(
            SphinxrsHealth.parseMixerErrorCode(raw: #"{"code":"CLN_TIMEOUT"}"#),
            .clnTimeout
        )
        XCTAssertEqual(
            SphinxrsHealth.parseMixerErrorCode(raw: "INSUFFICIENT_BALANCE"),
            .insufficientBalance
        )
        XCTAssertEqual(
            SphinxrsHealth.parseMixerErrorCode(raw: #"{"code":"INSUFFICIENT_BALANCE"}"#),
            .insufficientBalance
        )
        XCTAssertEqual(
            SphinxrsHealth.parseMixerErrorCode(raw: "SOMETHING_ELSE"),
            .unknown
        )
        XCTAssertEqual(
            SphinxrsHealth.parseMixerErrorCode(raw: ""),
            .unknown
        )

        XCTAssertEqual(
            SphinxrsHealth.localizedMessage(forCode: "CLN_UNAVAILABLE"),
            "mixer.error.cln.unavailable".localized
        )
        XCTAssertEqual(
            SphinxrsHealth.localizedMessage(forCode: "CLN_TIMEOUT"),
            "mixer.error.cln.timeout".localized
        )
        XCTAssertEqual(
            SphinxrsHealth.localizedMessage(forCode: "INSUFFICIENT_BALANCE"),
            "mixer.error.insufficient.balance".localized
        )
        XCTAssertEqual(
            SphinxrsHealth.localizedMessage(forCode: "NOPE"),
            "mixer.error.unknown".localized
        )
        XCTAssertEqual(
            SphinxrsHealth.localizedMessage(forCode: nil),
            "generic.error.message".localized
        )
    }

    func test_parseServerStatus_happyAndDegraded() throws {
        let ok = try SphinxrsHealth.parseServerStatus(
            payload: #"{"cln_ok":true,"degraded":false,"reason":null,"ts":42}"#
        )
        XCTAssertTrue(ok.clnOk)
        XCTAssertFalse(ok.degraded)
        XCTAssertNil(ok.reason)
        XCTAssertEqual(ok.ts, 42)

        let degraded = try SphinxrsHealth.parseServerStatus(
            payload: #"{"cln_ok":false,"degraded":true,"reason":"cln down","ts":99}"#
        )
        XCTAssertFalse(degraded.clnOk)
        XCTAssertTrue(degraded.degraded)
        XCTAssertEqual(degraded.reason, "cln down")
    }

    func test_bannerCopy_neverRendersReason() {
        XCTAssertEqual(
            SphinxrsHealth.localizedBannerCopy(for: .degraded),
            "server.health.banner.degraded".localized
        )
        XCTAssertEqual(
            SphinxrsHealth.localizedBannerCopy(for: .unknown),
            "server.health.banner.unknown".localized
        )
        XCTAssertNil(SphinxrsHealth.localizedBannerCopy(for: .ok))
    }
}
