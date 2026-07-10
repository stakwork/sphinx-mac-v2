//
//  CallAudioRouteMonitor.swift
//  Sphinx
//
//  Detects mid-call audio device removal or route changes and safely re-routes
//  LiveKit's AVAudioEngine to a valid device, preventing SIGSEGV crashes caused
//  by the engine referencing a changed or vanished device.
//
//  Architecture notes
//  ------------------
//  • AudioManagerInterface / AudioContextInterface provide a dependency-injection
//    seam so the route-monitoring logic can be unit-tested without real CoreAudio
//    hardware.  Production code passes AudioManager.shared; tests supply mocks.
//  • isReconfiguring prevents synchronous re-entrancy: if applyOutputDevice's
//    write to audioManager.outputDevice somehow synchronously re-fires
//    handleDeviceUpdate (e.g. during teardown races), the second call is coalesced.
//  • pendingReconfiguration coalesces rapid update bursts into a single pass so
//    the AVAudioEngine is not thrashed by back-to-back CoreAudio callbacks.
//  • Changed-but-still-present device handling (AirPods-pause fix): previously the
//    monitor returned early when the selected device was still in the available list,
//    leaving an unhandled CoreAudio route-reconfiguration in-flight.  Now, when the
//    active route changes to a different present device, a controlled reroute is
//    performed immediately rather than letting the engine self-reconfigure mid-call.
//

import LiveKit

// MARK: - AudioManagerInterface

/// Abstraction over LiveKit's `AudioManager` for dependency injection / testing.
/// All members are expected to be accessed from the main actor.
/// Extension `AudioManager: AudioManagerInterface` below provides the real conformance.
public protocol AudioManagerInterface: AnyObject {
    var outputDevices: [AudioDevice] { get }
    var inputDevices: [AudioDevice] { get }
    var defaultOutputDevice: AudioDevice { get }
    var defaultInputDevice: AudioDevice { get }
    var outputDevice: AudioDevice { get set }
    var inputDevice: AudioDevice { get set }
}

extension AudioManager: AudioManagerInterface {}

// MARK: - AudioContextInterface

/// Minimal interface over `AppContext` consumed by `CallAudioRouteMonitor`.
/// Keeping this narrow makes mock implementations trivial in unit tests.
@MainActor
public protocol AudioContextInterface: AnyObject {
    var outputDevice: AudioDevice { get set }
    var inputDevice: AudioDevice { get set }
    func reloadAudioDevices()
}

// MARK: - CallAudioRouteMonitor

/// Monitors audio device availability during an active LiveKit call.
///
/// **Hardened behaviors added for the AirPods-pause crash fix:**
/// - A device that is *present but on a different active route* is now treated as
///   a reroute (not silently ignored).  This prevents the AVAudioEngine from
///   racing against an unhandled CoreAudio reconfiguration triggered by the
///   AirPods stem-press gesture.
/// - `isReconfiguring` prevents re-entrant calls from thrashing the engine when
///   writing `appCtx.outputDevice` (→ `didSet` → `AudioManager.shared`) fires
///   another `onDeviceUpdate` callback within the same call stack.
/// - `pendingReconfiguration` coalesces rapid bursts of callbacks into a single
///   reconfiguration pass — the second update is deferred and run exactly once
///   after the in-flight pass completes.
@MainActor
final class CallAudioRouteMonitor {

    // MARK: - Dependencies (injection seam)

    /// Weak reference to the context that tracks the active in-call devices.
    /// Type is `any AudioContextInterface` so tests can supply a lightweight mock
    /// instead of a full `AppContext`.
    weak var appContext: (any AudioContextInterface)?

    /// Audio manager used for device enumeration and active-device writes.
    /// Defaults to `AudioManager.shared`; override in tests with a `MockAudioManager`
    /// to avoid hitting real CoreAudio hardware.
    var audioManagerProvider: any AudioManagerInterface

    /// Called when no valid output device remains — caller should end the call cleanly.
    var onNoDeviceAvailable: (() -> Void)?

    // MARK: - Re-entrancy / coalescing guards

    /// `true` while a device reconfiguration pass is in progress.
    /// A re-entrant call to `handleDeviceUpdate()` during the pass sets
    /// `pendingReconfiguration` and returns without recursing.
    private var isReconfiguring = false

    /// Set to `true` when an update arrives while `isReconfiguring` is `true`.
    /// After the current pass finishes, exactly one follow-up pass is run.
    private var pendingReconfiguration = false

    // MARK: - Init

    init(audioManagerProvider: any AudioManagerInterface = AudioManager.shared) {
        self.audioManagerProvider = audioManagerProvider
    }

    // MARK: - Public entry point

    /// Call from `AppContext.onDeviceUpdate` whenever the device list changes.
    /// Checks both output and input devices and performs controlled reroutes as needed.
    func handleDeviceUpdate() {
        guard !isReconfiguring else {
            // Coalesce: record that another pass is needed but do not re-enter.
            pendingReconfiguration = true
            AppLogger.shared.log(
                level: .info,
                message: "[CallAudioRouteMonitor] Device update coalesced — reconfiguration already in progress"
            )
            return
        }

        isReconfiguring = true
        handleOutputChange(audioManagerProvider)
        handleInputChange(audioManagerProvider)
        isReconfiguring = false

        if pendingReconfiguration {
            pendingReconfiguration = false
            AppLogger.shared.log(
                level: .info,
                message: "[CallAudioRouteMonitor] Running coalesced pending reconfiguration"
            )
            // Tail call — isReconfiguring is now false so this will run normally.
            handleDeviceUpdate()
        }
    }

    // MARK: - Output device handling

    private func handleOutputChange(_ audioManager: any AudioManagerInterface) {
        guard let appCtx = appContext else { return }
        let available = audioManager.outputDevices
        let currentId = appCtx.outputDevice.deviceId
        let activeRouteId = audioManager.outputDevice.deviceId

        let isCurrentDevicePresent = available.contains(where: { $0.deviceId == currentId })
        let isActiveRoutePresent   = available.contains(where: { $0.deviceId == activeRouteId })

        // ── Case 1: device present AND is already the active route — nothing to do.
        if isCurrentDevicePresent && currentId == activeRouteId {
            return
        }

        // ── Case 2: route changed but both devices are still present.
        // (AirPods pause: CoreAudio switches the active output without removing
        //  the device from the available list.)  Perform a controlled reroute to
        // the current active route device instead of letting the engine self-reconfigure.
        if isCurrentDevicePresent && isActiveRoutePresent && currentId != activeRouteId {
            guard let routeDevice = available.first(where: { $0.deviceId == activeRouteId }) else { return }
            AppLogger.shared.log(
                level: .info,
                message: "[CallAudioRouteMonitor] Output route changed (device present): '\(appCtx.outputDevice.name)' → '\(routeDevice.name)'"
            )
            applyOutputDevice(routeDevice, appCtx: appCtx, audioManager: audioManager)
            return
        }

        // ── Case 3: device was removed (or no longer available as an active route).
        AppLogger.shared.log(
            level: .warning,
            message: "[CallAudioRouteMonitor] Output device removed: \(appCtx.outputDevice.name). Available: \(available.map(\.name))"
        )

        guard let fallback = resolveOutputFallback(audioManager) else {
            AppLogger.shared.log(
                level: .error,
                message: "[CallAudioRouteMonitor] No output device available — ending call"
            )
            onNoDeviceAvailable?()
            return
        }

        AppLogger.shared.log(
            level: .info,
            message: "[CallAudioRouteMonitor] Re-routing output to: \(fallback.name)"
        )
        applyOutputDevice(fallback, appCtx: appCtx, audioManager: audioManager)
        AppLogger.shared.log(
            level: .info,
            message: "[CallAudioRouteMonitor] Output re-route succeeded"
        )
    }

    // MARK: - Input device handling

    private func handleInputChange(_ audioManager: any AudioManagerInterface) {
        guard let appCtx = appContext else { return }
        let available = audioManager.inputDevices
        let currentId = appCtx.inputDevice.deviceId
        let activeRouteId = audioManager.inputDevice.deviceId

        let isCurrentDevicePresent = available.contains(where: { $0.deviceId == currentId })
        let isActiveRoutePresent   = available.contains(where: { $0.deviceId == activeRouteId })

        // ── Case 1: device present AND is already the active route — nothing to do.
        if isCurrentDevicePresent && currentId == activeRouteId {
            return
        }

        // ── Case 2: route changed but both devices are still present.
        if isCurrentDevicePresent && isActiveRoutePresent && currentId != activeRouteId {
            guard let routeDevice = available.first(where: { $0.deviceId == activeRouteId }) else { return }
            AppLogger.shared.log(
                level: .info,
                message: "[CallAudioRouteMonitor] Input route changed (device present): '\(appCtx.inputDevice.name)' → '\(routeDevice.name)'"
            )
            applyInputDevice(routeDevice, appCtx: appCtx, audioManager: audioManager)
            return
        }

        // ── Case 3: device was removed.
        AppLogger.shared.log(
            level: .warning,
            message: "[CallAudioRouteMonitor] Input device removed: \(appCtx.inputDevice.name). Available: \(available.map(\.name))"
        )

        guard let fallback = resolveInputFallback(audioManager) else {
            AppLogger.shared.log(
                level: .error,
                message: "[CallAudioRouteMonitor] No input device available — microphone will be silent"
            )
            // Input-only loss is not fatal; log but do not end the call.
            return
        }

        AppLogger.shared.log(
            level: .info,
            message: "[CallAudioRouteMonitor] Re-routing input to: \(fallback.name)"
        )
        applyInputDevice(fallback, appCtx: appCtx, audioManager: audioManager)
        AppLogger.shared.log(
            level: .info,
            message: "[CallAudioRouteMonitor] Input re-route succeeded"
        )
    }

    // MARK: - Apply helpers

    /// Sets the output device on both the audio context and the audio manager.
    /// The guard on `audioManager.outputDevice.deviceId` avoids a redundant write
    /// that would trigger an unnecessary CoreAudio reconfiguration.
    private func applyOutputDevice(
        _ device: AudioDevice,
        appCtx: any AudioContextInterface,
        audioManager: any AudioManagerInterface
    ) {
        appCtx.outputDevice = device
        if audioManager.outputDevice.deviceId != device.deviceId {
            audioManager.outputDevice = device
        }
        appCtx.reloadAudioDevices()
    }

    /// Sets the input device on both the audio context and the audio manager.
    private func applyInputDevice(
        _ device: AudioDevice,
        appCtx: any AudioContextInterface,
        audioManager: any AudioManagerInterface
    ) {
        appCtx.inputDevice = device
        if audioManager.inputDevice.deviceId != device.deviceId {
            audioManager.inputDevice = device
        }
        appCtx.reloadAudioDevices()
    }

    // MARK: - Fallback resolution

    private func resolveOutputFallback(_ audioManager: any AudioManagerInterface) -> AudioDevice? {
        let sysDefault = audioManager.defaultOutputDevice
        // 1. Prefer the current system default if it is in the available list.
        if audioManager.outputDevices.contains(where: { $0.deviceId == sysDefault.deviceId }) {
            return sysDefault
        }
        // 2. Fall back to the first available device.
        return audioManager.outputDevices.first
    }

    private func resolveInputFallback(_ audioManager: any AudioManagerInterface) -> AudioDevice? {
        let sysDefault = audioManager.defaultInputDevice
        // 1. Prefer the current system default if it is in the available list.
        if audioManager.inputDevices.contains(where: { $0.deviceId == sysDefault.deviceId }) {
            return sysDefault
        }
        // 2. Fall back to the first available device.
        return audioManager.inputDevices.first
    }
}
