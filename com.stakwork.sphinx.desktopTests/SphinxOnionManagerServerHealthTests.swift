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
        // Staleness timer is real; keep it from firing during grace assertions.
        manager.serverHealthStalenessInterval = 3_600
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
            topic: serverStatusTopic(),
            payload: payload
        )

        XCTAssertTrue(intercepted, "exact status topic must be consumed before onion handle()")
        XCTAssertFalse(handleCalled, "status topic must never reach onion handle()")
    }

    func test_substringTopic_isNotIntercepted() {
        let substring = "prefix/\(serverStatusTopic())/suffix"
        XCTAssertFalse(manager.shouldInterceptServerStatus(topic: substring))
        XCTAssertFalse(
            manager.shouldInterceptServerStatus(
                topic: "not_\(serverStatusTopic())"
            )
        )
        XCTAssertTrue(
            manager.shouldInterceptServerStatus(
                topic: serverStatusTopic()
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
        XCTAssertNil(manager.serverHealthTrackingStartedAtMs)
        XCTAssertFalse(manager.hasReceivedServerStatus)
        XCTAssertFalse(manager.isServerHealthBannerVisible)
    }

    func test_unknown_staysHidden_whenTrackingNotStarted_evenWithLargeNow() {
        manager.serverHealthNowMsOverride = UInt64.max
        XCTAssertNil(manager.serverHealthTrackingStartedAtMs)
        XCTAssertFalse(
            manager.isServerHealthBannerVisible,
            "nil startedAt must stay hidden; a UInt64 zero sentinel would look expired"
        )
    }

    func test_launchGrace_hidesUnknown_duringHold() {
        let start: UInt64 = 8_000_000
        manager.serverHealthNowMsOverride = start
        manager.startServerHealthStalenessTimer()

        manager.serverHealthNowMsOverride = start + 1_000
        XCTAssertEqual(manager.serverHealthTrackingStartedAtMs, start)
        XCTAssertFalse(manager.hasReceivedServerStatus)
        XCTAssertEqual(manager.currentServerHealth, .unknown)
        XCTAssertFalse(manager.isServerHealthBannerVisible)
    }

    func test_launchGrace_showsUnknown_afterHold_andElapsedPosts() {
        let start: UInt64 = 8_000_000
        manager.serverHealthNowMsOverride = start
        manager.startServerHealthStalenessTimer()

        manager.serverHealthNowMsOverride = start + ServerHealthPresentation.launchGraceMs
        XCTAssertEqual(manager.currentServerHealth, .unknown)
        XCTAssertFalse(manager.hasReceivedServerStatus)
        XCTAssertTrue(manager.isServerHealthBannerVisible)

        let posted = expectation(description: "grace elapsed posts onServerHealthChanged")
        let token = NotificationCenter.default.addObserver(
            forName: .onServerHealthChanged,
            object: nil,
            queue: nil
        ) { _ in
            posted.fulfill()
        }
        manager.handleServerHealthLaunchGraceElapsed()
        wait(for: [posted], timeout: 1)
        NotificationCenter.default.removeObserver(token)
        XCTAssertEqual(manager.currentServerHealth, .unknown)
        XCTAssertNil(manager.serverHealthLaunchGraceTimer)
    }

    func test_degraded_insideHold_showsImmediately() {
        let start: UInt64 = 9_000_000
        manager.serverHealthNowMsOverride = start
        manager.startServerHealthStalenessTimer()

        manager.serverHealthNowMsOverride = start + 1_000
        let degraded = Data(#"{"cln_ok":false,"degraded":true,"reason":null,"ts":9001000}"#.utf8)
        manager.applyServerStatusPayload(degraded)

        XCTAssertEqual(manager.currentServerHealth, .degraded)
        XCTAssertTrue(manager.hasReceivedServerStatus)
        XCTAssertNil(manager.serverHealthLaunchGraceTimer)
        XCTAssertTrue(manager.isServerHealthBannerVisible)
        XCTAssertEqual(manager.serverHealthTrackingStartedAtMs, start)
    }

    func test_unknownAfterHealthy_insideHold_showsImmediately() {
        let start: UInt64 = 12_000_000
        let interval = ServerHealthPresentation.defaultIntervalMs
        let missed = UInt64(ServerHealthPresentation.defaultMaxMissed)
        let healthyAt = start - interval * missed - 30_000

        manager.serverHealthNowMsOverride = healthyAt
        let healthy = Data(#"{"cln_ok":true,"degraded":false,"reason":null,"ts":1}"#.utf8)
        manager.applyServerStatusPayload(healthy)
        XCTAssertTrue(manager.hasReceivedServerStatus)

        manager.serverHealthNowMsOverride = start
        manager.startServerHealthStalenessTimer()
        manager.serverHealthNowMsOverride = start + 1_000
        manager.reevaluateServerHealth()

        XCTAssertEqual(manager.currentServerHealth, .unknown)
        XCTAssertTrue(manager.hasReceivedServerStatus)
        XCTAssertEqual(manager.serverHealthTrackingStartedAtMs, start)
        XCTAssertTrue(manager.isServerHealthBannerVisible)
    }

    func test_stopTimer_clearsGrace_andRearmHidesUnknown() {
        let start: UInt64 = 4_000_000
        manager.serverHealthNowMsOverride = start
        manager.startServerHealthStalenessTimer()
        let degraded = Data(#"{"cln_ok":false,"degraded":true,"reason":null,"ts":4000000}"#.utf8)
        manager.applyServerStatusPayload(degraded)
        XCTAssertTrue(manager.isServerHealthBannerVisible)

        manager.stopServerHealthStalenessTimer()
        XCTAssertFalse(manager.hasReceivedServerStatus)
        XCTAssertNil(manager.serverHealthTrackingStartedAtMs)
        XCTAssertFalse(manager.isServerHealthBannerVisible)

        let rearm: UInt64 = 7_000_000
        manager.serverHealthNowMsOverride = rearm
        manager.startServerHealthStalenessTimer()
        manager.serverHealthNowMsOverride = rearm + 1_000
        XCTAssertEqual(manager.serverHealthTrackingStartedAtMs, rearm)
        XCTAssertFalse(manager.hasReceivedServerStatus)
        XCTAssertFalse(manager.isServerHealthBannerVisible)
    }

    func test_repeatStart_doesNotResetGraceWindow() {
        let start: UInt64 = 6_000_000
        manager.serverHealthNowMsOverride = start
        manager.startServerHealthStalenessTimer()
        XCTAssertNotNil(manager.serverHealthStalenessTimer)
        XCTAssertEqual(manager.serverHealthTrackingStartedAtMs, start)

        manager.serverHealthNowMsOverride = start + 5_000
        manager.startServerHealthStalenessTimer()
        XCTAssertEqual(manager.serverHealthTrackingStartedAtMs, start)

        manager.serverHealthNowMsOverride = start + 1_000
        XCTAssertFalse(manager.isServerHealthBannerVisible)
    }

    func test_parseFailure_insideHold_showsUnknownImmediately() {
        let start: UInt64 = 3_000_000
        manager.serverHealthNowMsOverride = start
        manager.startServerHealthStalenessTimer()

        let posted = expectation(description: "parse failure posts onServerHealthChanged")
        let token = NotificationCenter.default.addObserver(
            forName: .onServerHealthChanged,
            object: nil,
            queue: nil
        ) { _ in
            posted.fulfill()
        }

        manager.serverHealthNowMsOverride = start + 1_000
        manager.applyServerStatusPayload(Data("not-json".utf8))

        wait(for: [posted], timeout: 1)
        NotificationCenter.default.removeObserver(token)
        XCTAssertEqual(manager.currentServerHealth, .unknown)
        XCTAssertTrue(manager.hasReceivedServerStatus)
        XCTAssertNil(manager.serverHealthLaunchGraceTimer)
        XCTAssertTrue(manager.isServerHealthBannerVisible)
    }

    func test_clockMovedBackward_staysHidden() {
        let start: UInt64 = 11_000_000
        manager.serverHealthNowMsOverride = start
        manager.startServerHealthStalenessTimer()
        manager.serverHealthNowMsOverride = start - 1
        XCTAssertFalse(manager.isServerHealthBannerVisible)
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
        XCTAssertNil(ServerHealthPresentation.localizedBannerCopy(for: .ok))
    }

    func test_invalidPayload_mapsToUnknown() {
        let now: UInt64 = 2_000_000
        manager.serverHealthNowMsOverride = now
        let healthy = Data(#"{"cln_ok":true,"degraded":false,"reason":null,"ts":2000000}"#.utf8)
        manager.applyServerStatusPayload(healthy)
        XCTAssertNotNil(manager.lastServerStatus)
        XCTAssertEqual(manager.lastServerStatusSeenMs, now)

        manager.applyServerStatusPayload(Data("not-json".utf8))
        XCTAssertEqual(manager.currentServerHealth, .unknown)
        XCTAssertNil(manager.lastServerStatus)
        XCTAssertEqual(manager.lastServerStatusSeenMs, 0)
    }

    // MARK: - Staleness

    func test_staleness_transitionsToUnknown_afterNMissedIntervals() {
        let interval = ServerHealthPresentation.defaultIntervalMs
        let n = UInt64(ServerHealthPresentation.defaultMaxMissed)
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
            parseMixerErrorCode(raw: "CLN_UNAVAILABLE"),
            .clnUnavailable
        )
        XCTAssertEqual(
            parseMixerErrorCode(raw: #"{"code":"CLN_TIMEOUT"}"#),
            .clnTimeout
        )
        XCTAssertEqual(
            parseMixerErrorCode(raw: "INSUFFICIENT_BALANCE"),
            .insufficientBalance
        )
        XCTAssertEqual(
            parseMixerErrorCode(raw: #"{"code":"INSUFFICIENT_BALANCE"}"#),
            .insufficientBalance
        )
        XCTAssertEqual(
            parseMixerErrorCode(raw: "SOMETHING_ELSE"),
            .unknown
        )
        XCTAssertEqual(
            parseMixerErrorCode(raw: ""),
            .unknown
        )

        XCTAssertEqual(
            ServerHealthPresentation.localizedMessage(forCode: "CLN_UNAVAILABLE"),
            "mixer.error.cln.unavailable".localized
        )
        XCTAssertEqual(
            ServerHealthPresentation.localizedMessage(forCode: "CLN_TIMEOUT"),
            "mixer.error.cln.timeout".localized
        )
        XCTAssertEqual(
            ServerHealthPresentation.localizedMessage(forCode: "INSUFFICIENT_BALANCE"),
            "mixer.error.insufficient.balance".localized
        )
        XCTAssertEqual(
            ServerHealthPresentation.localizedMessage(forCode: "NOPE"),
            "mixer.error.unknown".localized
        )
        XCTAssertEqual(
            ServerHealthPresentation.localizedMessage(forCode: nil),
            "generic.error.message".localized
        )
    }

    func test_parseServerStatus_happyAndDegraded() throws {
        let ok = try parseServerStatus(
            payload: #"{"cln_ok":true,"degraded":false,"reason":null,"ts":42}"#
        )
        XCTAssertTrue(ok.clnOk)
        XCTAssertFalse(ok.degraded)
        XCTAssertNil(ok.reason)
        XCTAssertEqual(ok.ts, 42)

        let degraded = try parseServerStatus(
            payload: #"{"cln_ok":false,"degraded":true,"reason":"cln down","ts":99}"#
        )
        XCTAssertFalse(degraded.clnOk)
        XCTAssertTrue(degraded.degraded)
        XCTAssertEqual(degraded.reason, "cln down")
    }

    func test_bannerCopy_neverRendersReason() {
        XCTAssertEqual(
            ServerHealthPresentation.localizedBannerCopy(for: .degraded),
            "server.health.banner.degraded".localized
        )
        XCTAssertEqual(
            ServerHealthPresentation.localizedBannerCopy(for: .unknown),
            "server.health.banner.unknown".localized
        )
        XCTAssertNil(ServerHealthPresentation.localizedBannerCopy(for: .ok))
    }
}
