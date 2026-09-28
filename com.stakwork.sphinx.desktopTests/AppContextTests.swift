//
//  AppContextTests.swift
//  com.stakwork.sphinx.desktopTests
//
//  Regression test for the Bluetooth SCO callback-burst fix.
//
//  `AppContext.onDeviceUpdate` used to spawn one independent
//  `Task { @MainActor }` per CoreAudio callback, each calling
//  `handleDeviceUpdate()` on its own. `CallAudioRouteMonitor`'s
//  `isReconfiguring`/`pendingReconfiguration` guard only coalesces
//  *synchronous* re-entrancy within a single call stack — it cannot stop
//  multiple independently-queued Tasks already scheduled on the main actor.
//  During a Bluetooth A2DP→SCO/HFP profile switch, 5–15 such callbacks fire
//  within ~200ms, each reconfiguring the LiveKit audio pipeline and
//  triggering a "call ended" voice cue.
//
//  This test validates the fix at the correct layer: it exercises
//  `AppContext`'s `AudioManager.shared.onDeviceUpdate` closure directly (via
//  a injected `CallAudioRouteMonitoring` spy), firing it N times in rapid
//  succession, and asserts the debounce collapses the burst into exactly one
//  `handleDeviceUpdate()` invocation. Testing `CallAudioRouteMonitor.
//  handleDeviceUpdate()` directly (as `CallAudioRouteMonitorTests` does)
//  bypasses this Task-level coalescing entirely and cannot validate it.
//

import XCTest
@testable import com_stakwork_sphinx_desktop
import LiveKit
import KeychainAccess

// MARK: - MockRouteMonitor

/// Spy conforming to `CallAudioRouteMonitoring`, injected into `AppContext` in
/// place of the real `CallAudioRouteMonitor` so this test can count
/// `handleDeviceUpdate()` invocations without depending on the monitor's own
/// (separately tested) internal reconfiguration logic.
@MainActor
final class MockRouteMonitor: CallAudioRouteMonitoring {
    var appContext: (any AudioContextInterface)?
    var onNoDeviceAvailable: (() -> Void)?

    private(set) var handleDeviceUpdateCallCount = 0

    func handleDeviceUpdate() {
        handleDeviceUpdateCallCount += 1
    }
}

// MARK: - AppContextTests

@available(macOS 13.0, *)
@MainActor
final class AppContextTests: XCTestCase {

    /// In-memory keychain-store-free `ValueStore` fixture. Uses a throwaway
    /// key so this never touches (or collides with) the real app's stored
    /// preferences.
    private func makeStore() -> ValueStore<Preferences> {
        ValueStore<Preferences>(
            store: Keychain(service: "com.stakwork.sphinx.desktopTests.AppContextTests"),
            key: "app-context-tests-preferences-\(UUID().uuidString)",
            default: Preferences()
        )
    }

    /// Fires `AudioManager.shared.onDeviceUpdate` N=10 times in rapid
    /// succession (well within the 150ms debounce window) and asserts that
    /// only a single `handleDeviceUpdate()` pass results once the debounce
    /// settles — validating the Task-level coalescing fix rather than
    /// `CallAudioRouteMonitor`'s internal synchronous guard.
    func test_rapidOnDeviceUpdateBurst_collapsesToSingleHandleDeviceUpdateCall() async {
        let monitor = MockRouteMonitor()
        let appContext = AppContext(
            store: makeStore(),
            routeMonitor: monitor
        )
        _ = appContext // silence "unused" warning; kept alive for the closure's [weak self]

        guard let onDeviceUpdate = AudioManager.shared.onDeviceUpdate else {
            XCTFail("AppContext.init must install AudioManager.shared.onDeviceUpdate")
            return
        }

        // Fire the burst: simulates 10 CoreAudio callbacks arriving during a
        // Bluetooth A2DP→SCO/HFP profile switch, all within a few milliseconds.
        for _ in 0..<10 {
            onDeviceUpdate(AudioManager.shared)
        }

        // Allow the 150ms debounce to fire and settle.
        try? await Task.sleep(for: .milliseconds(250))

        XCTAssertEqual(
            monitor.handleDeviceUpdateCallCount, 1,
            "A burst of 10 rapid onDeviceUpdate callbacks must collapse into exactly one handleDeviceUpdate() pass"
        )
    }

    /// Sanity check: bursts separated by more than the debounce window each
    /// produce their own pass (i.e. the debounce does not over-coalesce
    /// distinct, well-separated device changes).
    func test_wellSeparatedDeviceUpdates_eachProduceOwnHandleDeviceUpdateCall() async {
        let monitor = MockRouteMonitor()
        let appContext = AppContext(
            store: makeStore(),
            routeMonitor: monitor
        )
        _ = appContext

        guard let onDeviceUpdate = AudioManager.shared.onDeviceUpdate else {
            XCTFail("AppContext.init must install AudioManager.shared.onDeviceUpdate")
            return
        }

        onDeviceUpdate(AudioManager.shared)
        try? await Task.sleep(for: .milliseconds(250))

        onDeviceUpdate(AudioManager.shared)
        try? await Task.sleep(for: .milliseconds(250))

        XCTAssertEqual(
            monitor.handleDeviceUpdateCallCount, 2,
            "Device updates separated by more than the debounce window must each produce their own pass"
        )
    }
}
