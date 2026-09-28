/*
 * Copyright 2024 LiveKit
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import Combine
import LiveKit
import SwiftUI

// This class contains the logic to control behavior of the whole app.
@MainActor
final class AppContext: ObservableObject {
    private let store: ValueStore<Preferences>

    // Monitor that re-routes audio when the in-use device is removed or the active
    // route changes mid-call (e.g. AirPods stem-press triggers a CoreAudio reroute).
    // Typed as the narrow `CallAudioRouteMonitoring` protocol so tests can inject a
    // spy/mock and assert on `handleDeviceUpdate()` call counts without needing a
    // full `CallAudioRouteMonitor` + `AudioManagerInterface` stack.
    private let routeMonitor: any CallAudioRouteMonitoring

    // Debounces the burst of CoreAudio `onDeviceUpdate` callbacks fired during a
    // Bluetooth A2DP → SCO/HFP profile switch (5–15 callbacks within ~100–200ms).
    // Each callback previously spawned its own `Task { @MainActor }` that
    // independently called `handleDeviceUpdate()`; `CallAudioRouteMonitor`'s
    // `isReconfiguring` guard only coalesces *synchronous* re-entrancy, so it could
    // not stop multiple independently-queued Tasks from each reconfiguring the
    // audio engine (and re-triggering LiveKit's "call ended" cue). Cancelling and
    // rescheduling this Task handle on every callback collapses the whole burst
    // into a single `handleDeviceUpdate()` pass ~150ms after the last callback.
    //
    // `nonisolated(unsafe)` is required because:
    //  (a) `AppContext` is `@MainActor` but `deinit` is nonisolated in Swift 6, so
    //      an actor-isolated stored property cannot be touched from `deinit`; and
    //  (b) CoreAudio delivers `onDeviceUpdate` on a background thread, so the
    //      cancel/reschedule below also happens off the main actor.
    // The cancel + reschedule is a last-writer-wins operation on a Task handle,
    // which is safe without additional locking. Mirrors `RoomContext.disconnecting`.
    nonisolated(unsafe) private var deviceUpdateDebounceTask: Task<Void, Never>?

    @Published var videoViewVisible: Bool = true {
        didSet { store.value.videoViewVisible = videoViewVisible }
    }

    @Published var showInformationOverlay: Bool = false {
        didSet { store.value.showInformationOverlay = showInformationOverlay }
    }

    @Published var preferSampleBufferRendering: Bool = false {
        didSet { store.value.preferSampleBufferRendering = preferSampleBufferRendering }
    }

    @Published var videoViewMode: VideoView.LayoutMode = .fit {
        didSet { store.value.videoViewMode = videoViewMode }
    }

    @Published var videoViewMirrored: Bool = false {
        didSet { store.value.videoViewMirrored = videoViewMirrored }
    }

    @Published var videoViewPinchToZoomOptions: VideoView.PinchToZoomOptions = []

    @Published var connectionHistory: Set<ConnectionHistory> = [] {
        didSet { store.value.connectionHistory = connectionHistory }
    }

    @Published var outputDevice: AudioDevice = AudioManager.shared.defaultOutputDevice {
        didSet {
            // Guard prevents a re-entrancy loop:
            //   handleDeviceUpdate → applyOutputDevice writes appCtx.outputDevice
            //   → didSet fires → would write AudioManager.shared.outputDevice again
            //   → triggers another onDeviceUpdate callback → handleDeviceUpdate…
            guard outputDevice.deviceId != AudioManager.shared.outputDevice.deviceId else { return }
            AudioManager.shared.outputDevice = outputDevice
            reloadAudioDevices()
        }
    }
    
    @Published var realOutputDevice: AudioDevice = AudioManager.shared.defaultOutputDevice
    
    @Published var outputDeviceId: String = AudioManager.shared.defaultOutputDevice.deviceId {
        didSet {
            outputDevice = AudioManager.shared.outputDevices.first(where: { $0.deviceId == outputDeviceId }) ?? AudioManager.shared.defaultOutputDevice
        }
    }

    @Published var inputDevice: AudioDevice = AudioManager.shared.defaultInputDevice {
        didSet {
            // Same re-entrancy guard as outputDevice above.
            guard inputDevice.deviceId != AudioManager.shared.inputDevice.deviceId else { return }
            AudioManager.shared.inputDevice = inputDevice
            reloadAudioDevices()
        }
    }
    
    @Published var realInputDevice: AudioDevice = AudioManager.shared.defaultInputDevice
    
    @Published var inputDeviceId: String = AudioManager.shared.defaultInputDevice.deviceId {
        didSet {
            inputDevice = AudioManager.shared.inputDevices.first(where: { $0.deviceId == inputDeviceId }) ?? AudioManager.shared.defaultInputDevice
        }
    }
    #if os(iOS) || os(visionOS) || os(tvOS)
        @Published var preferSpeakerOutput: Bool = true {
            didSet { AudioManager.shared.isSpeakerOutputPreferred = preferSpeakerOutput }
        }
    #endif

    public init(store: ValueStore<Preferences>,
                audioManagerProvider: any AudioManagerInterface = AudioManager.shared,
                routeMonitorProvider: (any CallAudioRouteMonitoring)? = nil) {
        self.store = store
        self.routeMonitor = routeMonitorProvider ?? CallAudioRouteMonitor(audioManagerProvider: audioManagerProvider)

        videoViewVisible = store.value.videoViewVisible
        showInformationOverlay = store.value.showInformationOverlay
        preferSampleBufferRendering = store.value.preferSampleBufferRendering
        videoViewMode = store.value.videoViewMode
        videoViewMirrored = store.value.videoViewMirrored
        connectionHistory = store.value.connectionHistory

        AudioManager.shared.onDeviceUpdate = { [weak self] _ in
            // Cancel-and-reschedule debounce: collapses the whole Bluetooth SCO
            // callback burst into a single `handleDeviceUpdate()` pass, run
            // ~150ms after the last callback in the burst.
            //
            // Intentionally does NOT pre-sync `self.outputDevice`/`self.inputDevice`
            // to `AudioManager.shared`'s current values before calling
            // `handleDeviceUpdate()`. Doing so makes `handleOutputChange` always
            // observe `currentId == activeRouteId` (Case 1: no-op), silently
            // bypassing Case 2 (AirPods controlled reroute) and Case 3
            // (`onNoDeviceAvailable`). The route monitor reads live `AudioManager`
            // state itself, so no pre-sync is needed here.
            self?.deviceUpdateDebounceTask?.cancel()
            self?.deviceUpdateDebounceTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(150))
                guard let self, !Task.isCancelled else { return }
                self.routeMonitor.handleDeviceUpdate()
            }
        }

        routeMonitor.appContext = self
    }

    /// Attach a callback for when no audio output device is available mid-call.
    /// Pass `nil` to clear the callback (e.g., when the call is ending).
    func configureRouteMonitor(onNoDeviceAvailable: (() -> Void)?) {
        routeMonitor.onNoDeviceAvailable = onNoDeviceAvailable
    }
    
    deinit {
        deviceUpdateDebounceTask?.cancel()
        AudioManager.shared.onDeviceUpdate = nil
    }
    
    func syncWithSystemAudioDefaults() {
        let systemOutput = AudioManager.shared.defaultOutputDevice
        let systemInput = AudioManager.shared.defaultInputDevice

        outputDevice = systemOutput
        inputDevice = systemInput
        reloadAudioDevices()
    }

    func reloadAudioDevices() {
        //Audio Output device
        var defaultOutputDevice = outputDevice

        if defaultOutputDevice.name.isEmpty, let firstDevice = AudioManager.shared.outputDevices.first {
            defaultOutputDevice = firstDevice
        }

        let realOutputDevice = AudioManager.shared.outputDevices.first(where: {
            $0.deviceId == defaultOutputDevice.deviceId && $0.deviceId != "default"
        }) ?? AudioManager.shared.outputDevices.first(where: {
            $0.name == defaultOutputDevice.name && $0.deviceId != "default"
        }) ?? defaultOutputDevice

        self.realOutputDevice = realOutputDevice
        
        //Audio Input device
        var defaultInputDevice = inputDevice

        if defaultInputDevice.name.isEmpty, let firstDevice = AudioManager.shared.inputDevices.first {
            defaultInputDevice = firstDevice
        }

        let realInputDevice = AudioManager.shared.inputDevices.first(where: {
            $0.deviceId == defaultInputDevice.deviceId && $0.deviceId != "default"
        }) ?? AudioManager.shared.inputDevices.first(where: {
            $0.name == defaultInputDevice.name && $0.deviceId != "default"
        }) ?? defaultInputDevice

        self.realInputDevice = realInputDevice
    }
}

// MARK: - AppContext + AudioContextInterface

extension AppContext: AudioContextInterface {}
