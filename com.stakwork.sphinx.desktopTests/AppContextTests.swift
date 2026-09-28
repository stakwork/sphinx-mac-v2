//
//  AppContextTests.swift
//  com.stakwork.sphinx.desktopTests
//
//  Regression test for the Bluetooth SCO callback-burst debounce fix.
//
//  `AppContext.onDeviceUpdate` previously spawned one `Task { @MainActor }` per
//  CoreAudio callback, and `CallAudioRouteMonitor`'s `isReconfiguring` guard only
//  coalesces *synchronous* re-entrancy — it cannot stop multiple independently
//  queued Tasks from each running their own `handleDeviceUpdate()` pass. This test
//  validates the actual fix (Task-level cancel-and-reschedule debounce) at the
//  layer where it lives: `AppContext`, not `CallAudioRouteMonitor`.
//

import XCTest
@testable import com_stakwork_sphinx_desktop
import LiveKit
import KeychainAccess

// MARK: - MockCallAudioRouteMonitor

/// Spy conforming to `CallAudioRouteMonitoring`, injected into `AppContext` so the
/// test can count `handleDeviceUpdate()` invocations without touching real
/// CoreAudio hardware or a full `CallAudioRouteMonitor` + `AudioManagerInterface`
/// stack.
@MainActor
final class MockCallAudioRouteMonitor: CallAudioRouteMonitoring {
    var appContext: (any AudioContextInterface)?
    var onNoDeviceAvailable: (() -> Void)?

    private(set) var handleDeviceUpdateCallCount = 0

    func handleDeviceUpdate() {
        handleDeviceUpdateCallCount += 1
    }
}

// MARK: - AppContextTests

@available(macOS 13.0, *)
final class AppContextTests: XCTestCase {

    /// Fires `AudioManager.shared.onDeviceUpdate` N=10 times in rapid succession
    /// (simulating the Bluetooth A2DP → SCO/HFP callback burst) and asserts the
    /// whole burst collapses into a single `handleDeviceUpdate()` pass after the
    /// 150ms debounce settles.
    @MainActor
    func test_rapidOnDeviceUpdateBurst_debouncesToSingleHandleDeviceUpdateCall() async {
        let mockMonitor = MockCallAudioRouteMonitor()
        let store = ValueStore<Preferences>(store: Keychain(), key: "AppContextTests.\(UUID().uuidString)", default: Preferences())

        let appCtx = AppContext(store: store, routeMonitorProvider: mockMonitor)
        _ = appCtx // silence unused-var warning if AppContext isn't otherwise referenced below

        // Fire the burst: N=10 callbacks in rapid succession, all within a single
        // main-actor pass, mirroring the ~5-15 CoreAudio callbacks over ~100-200ms
        // seen during a real Bluetooth SCO profile switch.
        guard let onDeviceUpdate = AudioManager.shared.onDeviceUpdate else {
            XCTFail("AppContext must install AudioManager.shared.onDeviceUpdate")
            return
        }
        for _ in 0..<10 {
            onDeviceUpdate(AudioManager.shared)
            await Task.yield()
        }

        // Allow the 150ms debounce window to fire and settle.
        try? await Task.sleep(for: .milliseconds(250))

        XCTAssertEqual(
            mockMonitor.handleDeviceUpdateCallCount, 1,
            "A burst of rapid onDeviceUpdate callbacks must debounce into exactly one handleDeviceUpdate() pass"
        )
    }

    /// Confirms that callbacks separated by more than the debounce window (150ms)
    /// are NOT coalesced — each should produce its own `handleDeviceUpdate()` pass,
    /// preserving responsiveness to genuinely distinct device-change events.
    @MainActor
    func test_wellSeparatedOnDeviceUpdateCalls_eachProduceOwnHandleDeviceUpdateCall() async {
        let mockMonitor = MockCallAudioRouteMonitor()
        let store = ValueStore<Preferences>(store: Keychain(), key: "AppContextTests.\(UUID().uuidString)", default: Preferences())

        let appCtx = AppContext(store: store, routeMonitorProvider: mockMonitor)
        _ = appCtx

        guard let onDeviceUpdate = AudioManager.shared.onDeviceUpdate else {
            XCTFail("AppContext must install AudioManager.shared.onDeviceUpdate")
            return
        }

        onDeviceUpdate(AudioManager.shared)
        try? await Task.sleep(for: .milliseconds(250))

        onDeviceUpdate(AudioManager.shared)
        try? await Task.sleep(for: .milliseconds(250))

        XCTAssertEqual(
            mockMonitor.handleDeviceUpdateCallCount, 2,
            "Callbacks separated by more than the debounce window must each produce their own handleDeviceUpdate() pass"
        )
    }
}
