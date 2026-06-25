//
//  RoomContextView.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 06/11/2024.
//  Copyright © 2024 Tomas Timinskas. All rights reserved.
//

import SwiftUI
import LiveKit
import KeychainAccess
import AVFoundation

@MainActor let sync = ValueStore<Preferences>(store: Keychain(),
                                              key: "preferences",
                                              default: Preferences())

struct RoomSwitchView: View {
    @EnvironmentObject var appCtx: AppContext
    @EnvironmentObject var roomCtx: RoomContext
    @EnvironmentObject var room: Room
    
    var shouldStartRecording: Bool = true
    
    init(
        shouldStartRecording: Bool = false
    ) {
        self.shouldStartRecording = shouldStartRecording
    }

    var shouldShowRoomView: Bool {
        true
    }

    func computeTitle() -> String {
        if shouldShowRoomView {
            var elements: [String] = []
            if let roomName = room.name {
                elements.append(roomName)
            }
            if let localParticipantName = room.localParticipant.name {
                elements.append(localParticipantName)
            }
            return elements.joined(separator: " ")
        }

        return "LiveKit"
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if shouldShowRoomView {
                RoomView(shouldStartRecording: self.shouldStartRecording)
            } else {
                ConnectView()
            }
        }
    }
}

// Attaches RoomContext and Room to the environment
struct RoomContextView: View {
    @EnvironmentObject var appCtx: AppContext
    @EnvironmentObject var roomCtx: RoomContext
    
    var audioOnly: Bool = true
    var shouldStartRecording: Bool = true
    
    typealias OnCallEnded = () -> Void
    private var onCallEnded: OnCallEnded? = nil
    
    init(
        audioOnly: Bool,
        shouldStartRecording: Bool = false,
        onCallEnded: OnCallEnded? = nil
    ) {
        self.audioOnly = audioOnly
        self.shouldStartRecording = shouldStartRecording
        self.onCallEnded = onCallEnded
    }
    
    var body: some View {
        RoomSwitchView(shouldStartRecording: self.shouldStartRecording)
            .ignoresSafeArea()
            .environmentObject(roomCtx)
            .environmentObject(roomCtx.room)
            .environment(\.colorScheme, .dark)
            .foregroundColor(Color.white)
            .onDisappear {
                print("\(String(describing: type(of: self))) onDisappear")
                // Clear the route monitor callback before disconnecting so that
                // any late-firing device-removal event doesn't operate on a
                // torn-down audio engine context.
                appCtx.configureRouteMonitor(onNoDeviceAvailable: nil)
                Task {
                    await roomCtx.disconnect()
                }
            }
            .onAppear() {
                appCtx.syncWithSystemAudioDefaults()
                Task {
                    if !roomCtx.token.isEmpty {
                        do {
                            let room = try await roomCtx.connect(
                                onConnected: {
                                    self.enableMic()
                                    if !self.audioOnly {
                                        self.enableCamera()
                                    }
                                },
                                onCallEnded: {
                                    self.onCallEnded?()
                                }
                            )
                            appCtx.connectionHistory.update(room: room, e2ee: false, e2eeKey: "")
                            // Wire the route monitor: if all audio output devices vanish
                            // mid-call, end the call cleanly instead of crashing.
                            appCtx.configureRouteMonitor {
                                Task { @MainActor in
                                    AlertHelper.showAlert(
                                        title: "Audio Device Lost",
                                        message: "All audio output devices were removed. The call has ended."
                                    )
                                    appCtx.configureRouteMonitor(onNoDeviceAvailable: nil)
                                    await roomCtx.disconnect()
                                    self.onCallEnded?()
                                }
                            }
                        } catch {
                            print("LiveKit connect failed: \(error)")
                            Task { @MainActor in
                                AlertHelper.showAlert(
                                    title: "error.joining.call.title".localized,
                                    message: "Failed to connect to room"
                                )
                            }
                            self.onCallEnded?()
                        }
                    }
                }
            }
            .onOpenURL(perform: { url in

                guard let urlComponent = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
                guard let host = url.host else { return }

                let secureValue = urlComponent.queryItems?.first(where: { $0.name == "secure" })?.value?.lowercased()
                let secure = ["true", "1"].contains { $0 == secureValue }

                let tokenValue = urlComponent.queryItems?.first(where: { $0.name == "token" })?.value ?? ""

                let e2ee = ["true", "1"].contains { $0 == secureValue }
                let e2eeKey = urlComponent.queryItems?.first(where: { $0.name == "e2eeKey" })?.value ?? ""

                var builder = URLComponents()
                builder.scheme = secure ? "wss" : "ws"
                builder.host = host
                builder.port = url.port

                guard let builtUrl = builder.url?.absoluteString else { return }

                print("built URL: \(builtUrl), token: \(tokenValue)")

                Task { @MainActor in
                    roomCtx.url = builtUrl
                    roomCtx.token = tokenValue
                    roomCtx.isE2eeEnabled = e2ee
                    roomCtx.e2eeKey = e2eeKey
                    if !roomCtx.token.isEmpty {
                        do {
                            let room = try await roomCtx.connect()
                            appCtx.connectionHistory.update(room: room, e2ee: e2ee, e2eeKey: e2eeKey)
                        } catch {
                            print("LiveKit connect failed: \(error)")
                            AlertHelper.showAlert(
                                title: "error.joining.call.title".localized,
                                message: "Failed to connect to room"
                            )
                            self.onCallEnded?()
                        }
                    }
                }
            })
    }
    
    func enableMic() {
        AudioRecorderHelper.requestMicrophonePermission { granted in
            if granted {
                Task {
                    do {
                        try await self.roomCtx.room.localParticipant.setMicrophone(enabled: true)
                    } catch {
                        await MainActor.run {
                            AlertHelper.showAlert(
                                title: "error.enabling.microphone.title".localized,
                                message: "\(error.localizedDescription). You can try enabling it using the microphone button."
                            )
                        }
                    }
                }
            } else {
                Task { @MainActor in
                    AlertHelper.showTwoOptionsAlert(
                        title: "Microphone Access Required",
                        message: "Please enable microphone access in System Settings → Privacy & Security → Microphone.",
                        confirm: {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                        },
                        confirmLabel: "Open Settings"
                    )
                }
            }
        }
    }
    
    func enableCamera() {
        Task {
            let captureOptions = CameraCaptureOptions(
                device: AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
                dimensions: .h1080_169
            )
            
            let maxFPS: Int = 30

            let publishOptions = VideoPublishOptions(
                name: nil,
                encoding: VideoEncoding(maxBitrate: VideoParameters.presetH1080_169.encoding.maxBitrate, maxFps: maxFPS),
                screenShareEncoding: nil,
                simulcast: true,
                simulcastLayers: [],
                screenShareSimulcastLayers: [],
                preferredCodec: VideoCodec.vp8,
                preferredBackupCodec: nil
            )
            
            try await roomCtx.room.localParticipant.setCamera(
                enabled: true,
                captureOptions: captureOptions,
                publishOptions: publishOptions
            )
        }
    }
}
