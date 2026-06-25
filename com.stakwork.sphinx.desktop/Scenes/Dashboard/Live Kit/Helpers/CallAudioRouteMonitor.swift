//
//  CallAudioRouteMonitor.swift
//  Sphinx
//
//  Detects mid-call audio device removal and safely re-routes LiveKit's
//  AVAudioEngine to a valid fallback device, preventing SIGSEGV crashes
//  caused by the engine referencing a vanished device.
//

import LiveKit

/// Monitors audio device availability during an active LiveKit call.
/// When the currently-selected output or input device is removed, it
/// automatically re-routes to the system default (or first available device).
/// If no device is available at all, `onNoDeviceAvailable` is fired so the
/// call can be ended cleanly.
@MainActor
final class CallAudioRouteMonitor {

    /// Weak reference to AppContext so we can read/write selected devices.
    weak var appContext: AppContext?

    /// Called when no valid output device remains — the call should end cleanly.
    var onNoDeviceAvailable: (() -> Void)?

    // MARK: - Public entry point

    /// Should be called from AppContext's `onDeviceUpdate` closure whenever the
    /// device list changes. Checks both output and input devices.
    func handleDeviceUpdate(from audioManager: AudioManager) {
        handleOutputChange(audioManager)
        handleInputChange(audioManager)
    }

    // MARK: - Output device handling

    private func handleOutputChange(_ audioManager: AudioManager) {
        guard let appCtx = appContext else { return }
        let available = audioManager.outputDevices

        // Device still present — nothing to do.
        if available.contains(where: { $0.deviceId == appCtx.outputDevice.deviceId }) { return }

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

        appCtx.outputDevice = fallback
        AudioManager.shared.outputDevice = fallback
        appCtx.reloadAudioDevices()

        AppLogger.shared.log(
            level: .info,
            message: "[CallAudioRouteMonitor] Output re-route succeeded"
        )
    }

    // MARK: - Input device handling

    private func handleInputChange(_ audioManager: AudioManager) {
        guard let appCtx = appContext else { return }
        let available = audioManager.inputDevices

        // Device still present — nothing to do.
        if available.contains(where: { $0.deviceId == appCtx.inputDevice.deviceId }) { return }

        AppLogger.shared.log(
            level: .warning,
            message: "[CallAudioRouteMonitor] Input device removed: \(appCtx.inputDevice.name). Available: \(available.map(\.name))"
        )

        guard let fallback = resolveInputFallback(audioManager) else {
            AppLogger.shared.log(
                level: .error,
                message: "[CallAudioRouteMonitor] No input device available — microphone will be silent"
            )
            // Input-only loss is not fatal; we don't end the call but we log it.
            return
        }

        AppLogger.shared.log(
            level: .info,
            message: "[CallAudioRouteMonitor] Re-routing input to: \(fallback.name)"
        )

        appCtx.inputDevice = fallback
        AudioManager.shared.inputDevice = fallback
        appCtx.reloadAudioDevices()

        AppLogger.shared.log(
            level: .info,
            message: "[CallAudioRouteMonitor] Input re-route succeeded"
        )
    }

    // MARK: - Fallback resolution

    private func resolveOutputFallback(_ audioManager: AudioManager) -> AudioDevice? {
        let sysDefault = audioManager.defaultOutputDevice
        // 1. Prefer the current system default if it is in the available list.
        if audioManager.outputDevices.contains(where: { $0.deviceId == sysDefault.deviceId }) {
            return sysDefault
        }
        // 2. Fall back to the first available device.
        return audioManager.outputDevices.first
    }

    private func resolveInputFallback(_ audioManager: AudioManager) -> AudioDevice? {
        let sysDefault = audioManager.defaultInputDevice
        // 1. Prefer the current system default if it is in the available list.
        if audioManager.inputDevices.contains(where: { $0.deviceId == sysDefault.deviceId }) {
            return sysDefault
        }
        // 2. Fall back to the first available device.
        return audioManager.inputDevices.first
    }
}
