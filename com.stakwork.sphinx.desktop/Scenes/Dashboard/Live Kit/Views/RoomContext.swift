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

import LiveKit
import SwiftUI

// This class contains the logic to control behavior of the whole app.
final class RoomContext: NSObject, ObservableObject {
    let jsonEncoder = JSONEncoder()
    let jsonDecoder = JSONDecoder()
    
    typealias OnConnected = () -> Void
    typealias OnCallEnded = () -> Void
    
    private var onConnected: OnConnected? = nil
    private var onCallEnded: OnCallEnded? = nil

    private let store: ValueStore<Preferences>

    // Used to show connection error dialog
    // private var didClose: Bool = false
    @Published var shouldShowDisconnectReason: Bool = false
    public var latestError: LiveKitError?

    public let room = Room()

    @Published var url: String = "" {
        didSet { store.value.url = url }
    }

    @Published var token: String = "" {
        didSet { store.value.token = token }
    }
    
    @Published var tribeImage: String? = nil

    @Published var e2eeKey: String = "" {
        didSet { store.value.e2eeKey = e2eeKey }
    }

    @Published var isE2eeEnabled: Bool = false {
        didSet {
            store.value.isE2eeEnabled = isE2eeEnabled
            // room.set(isE2eeEnabled: isE2eeEnabled)
        }
    }

    // RoomOptions
    @Published var simulcast: Bool = true {
        didSet { store.value.simulcast = simulcast }
    }

    @Published var adaptiveStream: Bool = false {
        didSet { store.value.adaptiveStream = adaptiveStream }
    }

    @Published var dynacast: Bool = false {
        didSet { store.value.dynacast = dynacast }
    }

    @Published var reportStats: Bool = false {
        didSet { store.value.reportStats = reportStats }
    }

    // ConnectOptions
    @Published var autoSubscribe: Bool = true {
        didSet { store.value.autoSubscribe = autoSubscribe }
    }

    @Published var focusParticipant: Participant?

    @Published var showMessagesView: Bool = false
    @Published var showParticipantsView: Bool = false
    @Published var messages: [ExampleRoomMessage] = []

    @Published var textFieldString: String = ""
    
    @State var didStartRecording = false

    var _connectTask: Task<Void, Error>?
    
    var colors: [String: Color] = [:]
    
    var controlsPanel: NSPanel? = nil

    public init(
        store: ValueStore<Preferences>
    ) {
        self.store = store
        
        super.init()
        
        room.add(delegate: self)

        url = store.value.url
        token = store.value.token
        isE2eeEnabled = store.value.isE2eeEnabled
        e2eeKey = store.value.e2eeKey
        simulcast = store.value.simulcast
        adaptiveStream = store.value.adaptiveStream
        dynacast = store.value.dynacast
        reportStats = store.value.reportStats
        autoSubscribe = store.value.autoSubscribe

        #if os(iOS)
            UIApplication.shared.isIdleTimerDisabled = true
        #endif
    }

    func cancelConnect() {
        _connectTask?.cancel()
    }

    @MainActor
    func connect(
        entry: ConnectionHistory? = nil,
        onConnected: OnConnected? = nil,
        onCallEnded: OnCallEnded? = nil
    ) async throws -> Room {
        
        self.onConnected = onConnected
        self.onCallEnded = onCallEnded
        
        if let entry {
            url = entry.url
            token = entry.token
            isE2eeEnabled = entry.e2ee
            e2eeKey = entry.e2eeKey
        }

        let connectOptions = ConnectOptions(
            autoSubscribe: autoSubscribe
        )

        var e2eeOptions: E2EEOptions? = nil
        if isE2eeEnabled {
            let keyProvider = BaseKeyProvider(isSharedKey: true)
            keyProvider.setKey(key: e2eeKey)
            e2eeOptions = E2EEOptions(keyProvider: keyProvider)
        }

        let roomOptions = RoomOptions(
            defaultCameraCaptureOptions: CameraCaptureOptions(
                dimensions: .h1080_169
            ),
            defaultScreenShareCaptureOptions: ScreenShareCaptureOptions(
                dimensions: .h1080_169,
                includeCurrentApplication: true
            ),
            defaultVideoPublishOptions: VideoPublishOptions(
                simulcast: simulcast
            ),
            adaptiveStream: true,
            dynacast: dynacast,
            // isE2eeEnabled: isE2eeEnabled,
            e2eeOptions: e2eeOptions,
            reportRemoteTrackStatistics: true
        )

        let connectTask = Task.detached { [weak self] in
            guard let self else { return }
            try await self.room.connect(url: self.url,
                                        token: self.token,
                                        connectOptions: connectOptions,
                                        roomOptions: roomOptions)
        }

        _connectTask = connectTask
        try await connectTask.value

        return room
    }

    func disconnect() async {
        await room.disconnect()
    }

    func sendMessage() {
        // Make sure the message is not empty
        guard !textFieldString.isEmpty else { return }

        let roomMessage = ExampleRoomMessage(messageId: UUID().uuidString,
                                             senderSid: room.localParticipant.sid,
                                             senderIdentity: room.localParticipant.identity,
                                             text: textFieldString)
        textFieldString = ""
        messages.append(roomMessage)

        Task.detached { [weak self] in
            guard let self else { return }
            do {
                let json = try self.jsonEncoder.encode(roomMessage)
                try await self.room.localParticipant.publish(data: json)
            } catch {
                print("Failed to encode data \(error)")
            }
        }
    }

    #if os(macOS)
        weak var screenShareTrack: LocalTrackPublication?

        @available(macOS 12.3, *)
        func setScreenShareMacOS(isEnabled: Bool, screenShareSource: MacOSScreenCaptureSource? = nil) async throws {
            if isEnabled, let screenShareSource {
                let track = LocalVideoTrack.createMacOSScreenShareTrack(source: screenShareSource, options: ScreenShareCaptureOptions(includeCurrentApplication: true))
                let options = VideoPublishOptions(preferredCodec: VideoCodec.h264)
                screenShareTrack = try await room.localParticipant.publish(videoTrack: track, options: options)
            }

            if !isEnabled, let screenShareTrack {
                try await room.localParticipant.unpublish(publication: screenShareTrack)
            }
        }
    #endif

    #if os(visionOS) && compiler(>=6.0)
        weak var arCameraTrack: LocalTrackPublication?

        func setARCamera(isEnabled: Bool) async throws {
            if #available(visionOS 2.0, *) {
                if isEnabled {
                    let track = LocalVideoTrack.createARCameraTrack()
                    arCameraTrack = try await room.localParticipant.publish(videoTrack: track)
                }
            }

            if !isEnabled, let arCameraTrack {
                try await room.localParticipant.unpublish(publication: arCameraTrack)
                self.arCameraTrack = nil
            }
        }
    #endif
}

extension RoomContext: RoomDelegate {
    func room(_: Room, track publication: TrackPublication, didUpdateE2EEState e2eeState: E2EEState) {
        print("Did update e2eeState = [\(String(describing: e2eeState))] for publication \(publication.sid)")
    }

    func room(_ room: Room, didUpdateConnectionState connectionState: ConnectionState, from oldValue: ConnectionState) {
        print("Did update connectionState \(oldValue) -> \(connectionState)")

        if case .disconnected = connectionState {
            if let error = room.disconnectError {
                if error.type == .cancelled {
                    onCallEnded?()
                } else {
                    latestError = room.disconnectError

                    Task.detached { @MainActor [weak self] in
                        guard let self else { return }
                        self.shouldShowDisconnectReason = true
                        // Reset state
                        self.focusParticipant = nil
                        self.showMessagesView = false
                        self.textFieldString = ""
                        self.messages.removeAll()
                        // self.objectWillChange.send()
                    }
                }
            } else {
                onCallEnded?()
            }
        }
        
        if case .connected = connectionState {
            onConnected?()
        }
    }

    func room(_: Room, participantDidDisconnect participant: RemoteParticipant) {
        Task.detached { @MainActor [weak self] in
            guard let self else { return }
            if let focusParticipant = self.focusParticipant, focusParticipant.identity == participant.identity {
                self.focusParticipant = nil
            }
        }
    }

    func room(_: Room, participant _: RemoteParticipant?, didReceiveData data: Data, forTopic _: String) {
        do {
            let roomMessage = try jsonDecoder.decode(ExampleRoomMessage.self, from: data)
            // Update UI from main queue
            Task.detached { @MainActor [weak self] in
                guard let self else { return }

                withAnimation {
                    // Add messages to the @Published messages property
                    // which will trigger the UI to update
                    self.messages.append(roomMessage)
                    // Show the messages view when new messages arrive
                    self.showMessagesView = true
                }
            }

        } catch {
            print("Failed to decode data \(error)")
        }
    }

    func room(_: Room, participant _: Participant, trackPublication _: TrackPublication, didReceiveTranscriptionSegments segments: [TranscriptionSegment]) {
        print("didReceiveTranscriptionSegments: \(segments.map { "(\($0.id): \($0.text), \($0.firstReceivedTime)-\($0.lastReceivedTime), \($0.isFinal))" }.joined(separator: ", "))")
    }

    func room(_: Room, trackPublication _: TrackPublication, didUpdateE2EEState state: E2EEState) {
        print("didUpdateE2EEState: \(state)")
    }
    
    func room(_ room: Room, didUpdateIsRecording isRecording: Bool) {
        print("didUpdateIsRecording: \(isRecording)")
    }
}

extension RoomContext {
    func getColorForParticipan(participantId: String?) -> Color? {
        guard let participantId = participantId else {
            return nil
        }
        if let color = colors[participantId] {
            return color
        }
        let randomColor = Color(NSColor.random())
        colors[participantId] = randomColor
        return randomColor
    }
}

struct ExampleRoomMessage: Identifiable, Equatable, Hashable, Codable {
    // Identifiable protocol needs param named id
    var id: String {
        messageId
    }

    // message id
    let messageId: String

    let senderSid: Participant.Sid?
    let senderIdentity: Participant.Identity?
    let text: String

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.messageId == rhs.messageId
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(messageId)
    }
}

extension RoomContext: NSWindowDelegate {
    func windowDidBecomeKey(_ notification: Notification) {
        hideCallControlWindow()
    }
    
    func windowDidResignKey(_ notification: Notification) {
        if self.room.connectionState == .connected {
            presentCallControlWindow()
        }
    }
    
    func presentCallControlWindow() {
        let mainScreen = NSScreen.main
        let position = CGPoint(x: (mainScreen?.frame.size.width ?? 200) / 2 - 135, y: 15)
        
        let shareControlView = CallControlView()
            .environmentObject(self)
            .environmentObject(self.room)
        
        let hostingController = NSHostingController(rootView: shareControlView)
        
        showControlsPanel(
            with: "",
            size: CGSize(width: 270, height: 80),
            minSize: CGSize(width: 270, height: 80),
            position: position,
            identifier: "share-panel",
            backgroundColor: NSColor.clear,
            contentVC: hostingController
        )
    }
    
    func showControlsPanel(
        with title: String,
        size: CGSize,
        minSize: CGSize? = nil,
        centeredIn w: NSWindow? = nil,
        position: CGPoint? = nil,
        identifier: String? = nil,
        chatIdentifier: Int? = nil,
        backgroundColor: NSColor? = nil,
        contentVC: NSViewController
    ) {
        controlsPanel = NSPanel(
            contentRect: .init(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        
        controlsPanel?.title = title
        controlsPanel?.minSize = minSize ?? size
        controlsPanel?.isMovableByWindowBackground = false
        controlsPanel?.contentViewController = contentVC
        controlsPanel?.makeKeyAndOrderFront(nil)
        controlsPanel?.isReleasedWhenClosed = false
        controlsPanel?.backgroundColor = backgroundColor ?? NSColor.Sphinx.Body
        controlsPanel?.isOpaque = false
        controlsPanel?.toolbarStyle = .unifiedCompact
        controlsPanel?.titlebarAppearsTransparent = true
        controlsPanel?.styleMask = [.nonactivatingPanel, .borderless]
        controlsPanel?.level = .mainMenu
        controlsPanel?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        if let w = w {
            let position = CGPoint(x: w.frame.origin.x + (w.frame.width - size.width) / 2, y: w.frame.origin.y + (w.frame.height - size.height) / 2)
            controlsPanel?.setFrame(.init(origin: position, size: size), display: true)
        } else if let position = position {
            controlsPanel?.setFrame(.init(origin: position, size: size), display: true)
        } else {
            controlsPanel?.center()
        }
    }
    
    func hideCallControlWindow() {
        DispatchQueue.main.async {
            self.controlsPanel?.close()
        }
    }
}
