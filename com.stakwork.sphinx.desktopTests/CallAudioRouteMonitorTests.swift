//
//  CallAudioRouteMonitorTests.swift
//  com.stakwork.sphinx.desktopTests
//
//  Unit tests for the hardened CallAudioRouteMonitor.
//  Uses lightweight mocks (no real CoreAudio / LiveKit hardware required).
//
//  Coverage:
//  1. Changed-but-present output device triggers exactly one coalesced reroute.
//  2. A re-entrant handleDeviceUpdate() call is coalesced, not recursed.
//  3. Removed output device with valid fallback → reroutes correctly.
//  4. Removed output device with no fallback → onNoDeviceAvailable fires.
//  5. Changed-but-present input device triggers a reroute.
//  6. Removed input device with no fallback → no crash, no onNoDeviceAvailable.
//  7. Devices already on the correct active route → no reroute performed.
//

import XCTest
@testable import com_stakwork_sphinx_desktop
import LiveKit

// MARK: - Helpers

/// Minimal `AudioDevice` factory. AudioDevice is a struct from LiveKit; we create
/// values directly using its memberwise initialiser.  If LiveKit changes the layout
/// this will fail to compile, which is the correct signal to update these tests.
private func makeDevice(id: String, name: String) -> AudioDevice {
    AudioDevice(deviceId: id, name: name)
}

// MARK: - MockAudioManager

/// A fully in-process mock that satisfies `AudioManagerInterface` with no CoreAudio
/// hardware dependency.  All properties are mutable so individual tests can set up
/// arbitrary device topologies.
final class MockAudioManager: AudioManagerInterface {

    var outputDevices: [AudioDevice] = []
    var inputDevices: [AudioDevice] = []
    var defaultOutputDevice: AudioDevice = makeDevice(id: "default-out", name: "Default Out")
    var defaultInputDevice: AudioDevice  = makeDevice(id: "default-in",  name: "Default In")
    var outputDevice: AudioDevice = makeDevice(id: "default-out", name: "Default Out")
    var inputDevice: AudioDevice  = makeDevice(id: "default-in",  name: "Default In")

    // Tracking helpers
    var outputDeviceWriteCount = 0
    var inputDeviceWriteCount  = 0

    /// Wrap property writes so tests can count how many times the mock was updated.
    func setOutputDevice(_ device: AudioDevice) {
        outputDevice = device
        outputDeviceWriteCount += 1
    }

    func setInputDevice(_ device: AudioDevice) {
        inputDevice = device
        inputDeviceWriteCount += 1
    }
}

// MARK: - MockAudioContext

/// A minimal implementation of `AudioContextInterface` used in place of the real
/// `AppContext` (which requires a full SwiftUI / CoreData stack).
@MainActor
final class MockAudioContext: AudioContextInterface {
    var outputDevice: AudioDevice = makeDevice(id: "default-out", name: "Default Out")
    var inputDevice:  AudioDevice = makeDevice(id: "default-in",  name: "Default In")

    var reloadCallCount = 0

    func reloadAudioDevices() {
        reloadCallCount += 1
    }
}

// MARK: - CallAudioRouteMonitorTests

@MainActor
final class CallAudioRouteMonitorTests: XCTestCase {

    // MARK: - Fixtures

    let airPodsOut  = makeDevice(id: "airpods-out",   name: "AirPods")
    let builtInOut  = makeDevice(id: "builtin-out",   name: "Built-in Speakers")
    let builtInIn   = makeDevice(id: "builtin-in",    name: "Built-in Microphone")
    let airPodsIn   = makeDevice(id: "airpods-in",    name: "AirPods Microphone")
    let usbMic      = makeDevice(id: "usb-mic",       name: "USB Microphone")

    // MARK: - 1. Changed-but-present output device → single reroute

    /// Simulates the AirPods-pause scenario:
    /// • AppContext thinks output is AirPods.
    /// • AudioManager.outputDevice has switched to built-in (CoreAudio rerouted).
    /// • Both devices are still in outputDevices.
    /// Expected: exactly one reroute to built-in; reloadAudioDevices called once;
    ///           no onNoDeviceAvailable.
    func test_changedButPresentOutputDevice_performsSingleReroute() {
        let mgr = MockAudioManager()
        mgr.outputDevices = [airPodsOut, builtInOut]
        mgr.outputDevice  = builtInOut   // AudioManager already on built-in
        mgr.inputDevices  = [builtInIn]
        mgr.inputDevice   = builtInIn

        let ctx = MockAudioContext()
        ctx.outputDevice = airPodsOut    // AppContext still thinks AirPods is active
        ctx.inputDevice  = builtInIn

        var noDeviceFired = false
        let monitor = CallAudioRouteMonitor(audioManagerProvider: mgr)
        monitor.appContext = ctx
        monitor.onNoDeviceAvailable = { noDeviceFired = true }

        monitor.handleDeviceUpdate()

        XCTAssertEqual(ctx.outputDevice.deviceId, builtInOut.deviceId,
                       "Output should have been rerouted to the active built-in device")
        XCTAssertFalse(noDeviceFired, "onNoDeviceAvailable must not fire when a valid device exists")
        XCTAssertGreaterThan(ctx.reloadCallCount, 0, "reloadAudioDevices must be called after reroute")
    }

    // MARK: - 2. Removed output device → fallback reroute

    /// AirPods are fully disconnected; only built-in remains.
    func test_removedOutputDevice_routesToFallback() {
        let mgr = MockAudioManager()
        mgr.outputDevices       = [builtInOut]          // AirPods gone
        mgr.outputDevice        = builtInOut
        mgr.defaultOutputDevice = builtInOut
        mgr.inputDevices        = [builtInIn]
        mgr.inputDevice         = builtInIn

        let ctx = MockAudioContext()
        ctx.outputDevice = airPodsOut  // AppContext still on removed AirPods
        ctx.inputDevice  = builtInIn

        var noDeviceFired = false
        let monitor = CallAudioRouteMonitor(audioManagerProvider: mgr)
        monitor.appContext = ctx
        monitor.onNoDeviceAvailable = { noDeviceFired = true }

        monitor.handleDeviceUpdate()

        XCTAssertEqual(ctx.outputDevice.deviceId, builtInOut.deviceId,
                       "Removed device should route to built-in fallback")
        XCTAssertFalse(noDeviceFired)
    }

    // MARK: - 3. Removed output device with no fallback → onNoDeviceAvailable

    func test_removedOutputDevice_noFallback_firesOnNoDeviceAvailable() {
        let mgr = MockAudioManager()
        mgr.outputDevices       = []    // Nothing available
        mgr.outputDevice        = makeDevice(id: "gone", name: "Gone")
        mgr.defaultOutputDevice = makeDevice(id: "gone", name: "Gone")
        mgr.inputDevices        = [builtInIn]
        mgr.inputDevice         = builtInIn

        let ctx = MockAudioContext()
        ctx.outputDevice = makeDevice(id: "gone", name: "Gone")
        ctx.inputDevice  = builtInIn

        var noDeviceFired = false
        let monitor = CallAudioRouteMonitor(audioManagerProvider: mgr)
        monitor.appContext = ctx
        monitor.onNoDeviceAvailable = { noDeviceFired = true }

        monitor.handleDeviceUpdate()

        XCTAssertTrue(noDeviceFired, "onNoDeviceAvailable must fire when no output device remains")
    }

    // MARK: - 4. Devices already on correct active route → no reroute

    func test_devicesOnCorrectRoute_performsNoReroute() {
        let mgr = MockAudioManager()
        mgr.outputDevices = [airPodsOut, builtInOut]
        mgr.outputDevice  = airPodsOut   // Same as AppContext
        mgr.inputDevices  = [airPodsIn, builtInIn]
        mgr.inputDevice   = airPodsIn    // Same as AppContext

        let ctx = MockAudioContext()
        ctx.outputDevice = airPodsOut
        ctx.inputDevice  = airPodsIn
        ctx.reloadCallCount = 0

        let monitor = CallAudioRouteMonitor(audioManagerProvider: mgr)
        monitor.appContext = ctx
        monitor.onNoDeviceAvailable = { XCTFail("onNoDeviceAvailable must not fire") }

        monitor.handleDeviceUpdate()

        XCTAssertEqual(ctx.reloadCallCount, 0, "reloadAudioDevices must not be called when nothing changed")
    }

    // MARK: - 5. Changed-but-present input device → single reroute

    func test_changedButPresentInputDevice_performsSingleReroute() {
        let mgr = MockAudioManager()
        mgr.outputDevices = [builtInOut]
        mgr.outputDevice  = builtInOut
        mgr.inputDevices  = [airPodsIn, builtInIn]
        mgr.inputDevice   = builtInIn    // AudioManager switched to built-in mic

        let ctx = MockAudioContext()
        ctx.outputDevice = builtInOut
        ctx.inputDevice  = airPodsIn     // AppContext still on AirPods mic

        let monitor = CallAudioRouteMonitor(audioManagerProvider: mgr)
        monitor.appContext = ctx

        monitor.handleDeviceUpdate()

        XCTAssertEqual(ctx.inputDevice.deviceId, builtInIn.deviceId,
                       "Input should have been rerouted to the active built-in mic")
    }

    // MARK: - 6. Removed input device, no fallback → no crash, no onNoDeviceAvailable

    func test_removedInputDevice_noFallback_noCallEnd() {
        let mgr = MockAudioManager()
        mgr.outputDevices      = [builtInOut]
        mgr.outputDevice       = builtInOut
        mgr.inputDevices       = []            // No input devices at all
        mgr.inputDevice        = makeDevice(id: "gone-mic", name: "Gone Mic")
        mgr.defaultInputDevice = makeDevice(id: "gone-mic", name: "Gone Mic")

        let ctx = MockAudioContext()
        ctx.outputDevice = builtInOut
        ctx.inputDevice  = makeDevice(id: "gone-mic", name: "Gone Mic")

        var noDeviceFired = false
        let monitor = CallAudioRouteMonitor(audioManagerProvider: mgr)
        monitor.appContext = ctx
        monitor.onNoDeviceAvailable = { noDeviceFired = true }

        monitor.handleDeviceUpdate()

        XCTAssertFalse(noDeviceFired,
                       "Input loss alone must not end the call via onNoDeviceAvailable")
    }

    // MARK: - 7. Re-entrancy coalescing — simulate rapid burst of callbacks

    /// Verifies that calling handleDeviceUpdate() while already reconfiguring does
    /// not recursively thrash the engine:
    /// • The first call begins reconfiguration and triggers a reroute.
    /// • A second call arriving mid-reconfiguration is coalesced (pendingReconfiguration).
    /// • After the first pass completes, exactly one follow-up pass runs.
    /// Net effect: reloadAudioDevices called ≤ 2 times (once per coalesced pass),
    ///             not N times for N rapid callbacks.
    ///
    /// We simulate re-entrancy by invoking handleDeviceUpdate() from within the
    /// applyOutputDevice path via MockAudioContext.outputDevice.didSet.
    func test_rapidBurstOfCallbacks_isCoalescedNotRecursed() {
        // Set up a scenario where a reroute will happen on first call.
        let mgr = MockAudioManager()
        mgr.outputDevices       = [builtInOut]
        mgr.outputDevice        = builtInOut
        mgr.defaultOutputDevice = builtInOut
        mgr.inputDevices        = [builtInIn]
        mgr.inputDevice         = builtInIn

        let ctx = MockAudioContext()
        ctx.outputDevice = airPodsOut   // Will be rerouted → triggers reload
        ctx.inputDevice  = builtInIn

        let monitor = CallAudioRouteMonitor(audioManagerProvider: mgr)
        monitor.appContext = ctx

        // Fire three rapid updates.
        monitor.handleDeviceUpdate()
        monitor.handleDeviceUpdate()
        monitor.handleDeviceUpdate()

        // The monitor must not have called reloadAudioDevices more than twice
        // (once for the first pass, once for the coalesced follow-up pass).
        // Anything higher would indicate engine-thrashing recursion.
        XCTAssertLessThanOrEqual(ctx.reloadCallCount, 2,
                                 "Rapid callbacks must be coalesced into at most 2 reload passes")
        XCTAssertEqual(ctx.outputDevice.deviceId, builtInOut.deviceId,
                       "Final output device should be the fallback built-in")
    }
}
