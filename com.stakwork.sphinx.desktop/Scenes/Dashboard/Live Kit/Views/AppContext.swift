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
    private let routeMonitor: CallAudioRouteMonitor

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
                audioManagerProvider: any AudioManagerInterface = AudioManager.shared) {
        self.store = store
        self.routeMonitor = CallAudioRouteMonitor(audioManagerProvider: audioManagerProvider)

        videoViewVisible = store.value.videoViewVisible
        showInformationOverlay = store.value.showInformationOverlay
        preferSampleBufferRendering = store.value.preferSampleBufferRendering
        videoViewMode = store.value.videoViewMode
        videoViewMirrored = store.value.videoViewMirrored
        connectionHistory = store.value.connectionHistory

        AudioManager.shared.onDeviceUpdate = { [weak self] audioManager in
            // Capture stable value IDs across the actor boundary (AudioDevice is
            // a value type so this is safe; we re-look up the live objects on the
            // main actor so the monitor always sees the freshest state).
            let outputId = audioManager.outputDevice.deviceId
            let inputId  = audioManager.inputDevice.deviceId
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Sync AppContext's published devices with what AudioManager reports
                // *before* invoking the route monitor, so the monitor operates on
                // up-to-date state.
                if self.outputDevice.deviceId != outputId {
                    self.outputDevice = AudioManager.shared.outputDevices.first(where: { $0.deviceId == outputId })
                        ?? AudioManager.shared.defaultOutputDevice
                }
                if self.inputDevice.deviceId != inputId {
                    self.inputDevice = AudioManager.shared.inputDevices.first(where: { $0.deviceId == inputId })
                        ?? AudioManager.shared.defaultInputDevice
                }
                // Use AudioManager.shared directly rather than the closure parameter
                // to avoid sending a non-Sendable value across the actor boundary.
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
