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
import SFSafeSymbols
import SwiftUI
import SDWebImageSwiftUI

let adaptiveMin = 300.0
let toolbarPlacement: ToolbarItemPlacement = .primaryAction

extension CIImage {
    // helper to create a `CIImage` for both platforms
    convenience init(named name: String) {
        self.init(data: NSImage(named: name)!.tiffRepresentation!)!
    }
}

// keeps weak reference to NSWindow
class WindowAccess: ObservableObject {
    private weak var window: NSWindow?

    deinit {
        // reset changed properties
        DispatchQueue.main.async { [weak window] in
            window?.level = .normal
        }
    }

    @Published public var pinned: Bool = false {
        didSet {
            guard oldValue != pinned else { return }
            level = pinned ? .floating : .normal
        }
    }

    private var level: NSWindow.Level {
        get { window?.level ?? .normal }
        set {
            Task { @MainActor in
                window?.level = newValue
                objectWillChange.send()
            }
        }
    }

    public func set(window: NSWindow?) {
        self.window = window
        Task { @MainActor in
            objectWillChange.send()
        }
    }
}

struct RoomView: View {
    @EnvironmentObject var appCtx: AppContext
    @EnvironmentObject var roomCtx: RoomContext
    @EnvironmentObject var room: Room

    @State var isCameraPublishingBusy = false
    @State var isMicrophonePublishingBusy = false
    @State var isScreenSharePublishingBusy = false
    @State var isARCameraPublishingBusy = false

    @State private var screenPickerPresented = false
    @State private var publishOptionsPickerPresented = false
    @State private var isGearMenuPresented = false
    
    @State private var isParticipantsVideoMenuPresented: [String: Bool] = [:]
    @State private var isParticipantsAudioMenuPresented: [String: Bool] = [:]

    @State private var cameraPublishOptions = VideoPublishOptions()

    @ObservedObject private var windowAccess = WindowAccess()

    @State private var showConnectionTime = true
    @State private var canSwitchCameraPosition = false    
    
    let newMessageBubbleHelper = NewMessageBubbleHelper()
    
    private func toggleRecording() {
        guard let roomName = room.name else {
            return
        }
        roomCtx.isProcessingRecordRequest = true
        
        let urlAction = roomCtx.didStartRecording ? "stop" : "start"
        var isoStringWithMilliseconds: String? = nil
        
        if !roomCtx.didStartRecording {
            let currentDate = Date()
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            isoStringWithMilliseconds = isoFormatter.string(from: currentDate)
        }
        
        self.roomCtx.didStartRecording.toggle()
        
        self.newMessageBubbleHelper.showGenericMessageView(
            text: self.roomCtx.didStartRecording ? "Starting call recording. Please wait..." : "Stopping call recording. Please wait...",
            delay: 5,
            textColor: NSColor.white,
            backColor: NSColor.Sphinx.BadgeRed,
            backAlpha: 1.0
        )
        
        API.sharedInstance.toggleLiveKitRecording(
            room: roomName,
            now: isoStringWithMilliseconds,
            action: urlAction,
            callback: { success in
                if !success {
                    DispatchQueue.main.async {
                        self.roomCtx.didStartRecording.toggle()
                    }
                }
                DispatchQueue.main.async {
                    self.roomCtx.isProcessingRecordRequest = false
                }
            }
        )
    }
    
    private func stopRecording() {
        guard let roomName = room.name else {
            return
        }
        
        API.sharedInstance.toggleLiveKitRecording(
            room: roomName,
            now: nil,
            action: "stop",
            callback: { _ in }
        )
    }

    func messageView(_ message: ExampleRoomMessage) -> some View {
        let isMe = message.senderSid == room.localParticipant.sid

        return HStack {
            if isMe {
                Spacer()
            }

            Text(message.text)
                .padding(8)
                .background(Color(isMe ? NSColor.Sphinx.PrimaryGreen : NSColor.Sphinx.SecondaryText))
                .foregroundColor(Color.white)
                .cornerRadius(18)
            if !isMe {
                Spacer()
            }
        }.padding(.vertical, 5)
        .padding(.horizontal, 10)
    }

    func scrollToBottom(_ scrollView: ScrollViewProxy) {
        
    }
    
    func scrollToTop(_ scrollView: ScrollViewProxy) {
        guard let first = sortedParticipants().first else { return }
        withAnimation {
            scrollView.scrollTo(first.id)
        }
    }
    
    func participantView(_ participant: Participant) -> some View {
        return VStack {
            Rectangle()
                .fill(Color.clear)
                .frame(height: 1)
                .frame(maxWidth: .infinity)
            
            HStack(spacing: 8) {
                if let profilePictureUrl = participant.profilePictureUrl, let url = URL(string: profilePictureUrl) {
                    WebImage(url: url)
                        .onSuccess { _,_,_ in
                            print("success")
                        }
                        .onFailure { error in
                            print("error")
                        }
                        .resizable()
                        .scaledToFill()
                        .frame(width: 32.0, height: 32.0)
                        .clipped()
                        .cornerRadius(16.0)
                } else {
                    ZStack(alignment: .center) {
                        Circle()
                            .fill(roomCtx.getColorForParticipan(participantId: participant.sid?.stringValue) ?? Color(NSColor.random()))
                            .frame(maxWidth: 32.0, maxHeight: 32.0)

                        Text((participant.name ?? "Unknow").getInitialsFromName())
                            .font(Font(NSFont(name: "Roboto-Medium", size: 14.0)!))
                            .foregroundColor(Color.white)
                            .frame(width: 32.0, height: 32.0)

                    }
                }
                
                Text((participant.name ?? "Unknow"))
                    .padding(.leading, 8)
                    .font(Font(NSFont(name: "Roboto-Regular", size: 15.0)!))
                    .foregroundColor(Color(NSColor.Sphinx.Text))
                
                Spacer()
                
                ZStack(alignment: .center) {
                    if let publication = participant.mainVideoPublication,
                       !publication.isMuted,
                       appCtx.videoViewVisible
                    {
                        if let publication = participant.mainVideoPublication,
                           !publication.isMuted
                        {
                            if let remotePub = publication as? RemoteTrackPublication {
                                
                                Button(action: {
                                    isParticipantsVideoMenuPresented[participant.id] = true
                                }) {
                                    if case .subscribed = remotePub.subscriptionState {
                                        Image(systemSymbol: .videoFill)
                                            .foregroundColor(Color(NSColor.Sphinx.Text))
                                            .font(.system(size: 15))
                                            .frame(width: 32.0, height: 32.0)
                                    } else if case .notAllowed = remotePub.subscriptionState {
                                        Image(systemSymbol: .exclamationmarkCircle)
                                            .foregroundColor(Color(NSColor.Sphinx.BadgeRed))
                                            .font(.system(size: 15))
                                            .frame(width: 32.0, height: 32.0)
                                    } else {
                                        Image(systemSymbol: .videoSlashFill)
                                            .foregroundColor(Color(NSColor.Sphinx.Text))
                                            .font(.system(size: 15))
                                            .frame(width: 32.0, height: 32.0)
                                    }
                                }
                                .buttonStyle(.borderless)
                                .background(
                                    Color(NSColor.Sphinx.MainBottomIcons)
                                        .opacity(0.2)
                                        .cornerRadius(8.0)
                                )
                                .popover(isPresented: Binding(
                                    get: { isParticipantsVideoMenuPresented[participant.id] ?? false },
                                    set: { isParticipantsVideoMenuPresented[participant.id] = $0 }
                                )) {
                                    VStack(spacing: 16) {
                                        if case .subscribed = remotePub.subscriptionState {
                                            Button {
                                                Task {
                                                    try await remotePub.set(subscribed: false)
                                                    isParticipantsVideoMenuPresented[participant.id] = false
                                                }
                                            } label: {
                                                Text("Unsubscribe")
                                            }
                                        } else if case .unsubscribed = remotePub.subscriptionState {
                                            Button {
                                                Task {
                                                    try await remotePub.set(subscribed: true)
                                                    isParticipantsVideoMenuPresented[participant.id] = false
                                                }
                                            } label: {
                                                Text("Subscribe")
                                            }
                                        }
                                    }
                                    .padding()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                                .frame(width: 32, height: 32)
                                .onHover { isHover in
                                    if isHover {
                                        NSCursor.pointingHand.set()
                                    } else {
                                        NSCursor.arrow.set()
                                    }
                                }
                            } else {
                                Image(systemSymbol: .videoFill)
                                    .foregroundColor(Color(NSColor.Sphinx.Text))
                                    .font(.system(size: 15))
                            }

                        } else {
                            Image(systemSymbol: .videoFill)
                                .foregroundColor(Color.white)
                                .font(.system(size: 15))
                        }
                    }
                }.frame(width: 32.0, height: 32.0)
                
                ZStack(alignment: .center) {
                    @State var isAudioMenuPresented = false
                    
                    if let publication = participant.firstAudioPublication,
                       !publication.isMuted
                    {
                        if let remotePub = publication as? RemoteTrackPublication {
                            Button(action: {
                                isParticipantsAudioMenuPresented[participant.id] = true
                            }) {
                                if case .subscribed = remotePub.subscriptionState {
                                    Image(systemSymbol: .micFill)
                                        .foregroundColor(Color.white)
                                        .font(.system(size: 17))
                                        .frame(width: 32.0, height: 32.0)
                                } else if case .notAllowed = remotePub.subscriptionState {
                                    Image(systemSymbol: .exclamationmarkCircle)
                                        .foregroundColor(Color(NSColor.Sphinx.BadgeRed))
                                        .font(.system(size: 17))
                                        .frame(width: 32.0, height: 32.0)
                                } else {
                                    Image(systemSymbol: .micSlashFill)
                                        .foregroundColor(Color(NSColor.Sphinx.BadgeRed))
                                        .font(.system(size: 17))
                                        .frame(width: 32.0, height: 32.0)
                                }
                            }
                            .buttonStyle(.borderless)
                            .background(
                                Color(NSColor.Sphinx.MainBottomIcons)
                                    .opacity(0.2)
                                    .cornerRadius(8.0)
                            )
                            .popover(isPresented: Binding(
                                get: { isParticipantsAudioMenuPresented[participant.id] ?? false },
                                set: { isParticipantsAudioMenuPresented[participant.id] = $0 }
                            )) {
                                VStack(spacing: 16) {
                                    if case .subscribed = remotePub.subscriptionState {
                                        Button {
                                            Task {
                                                try await remotePub.set(subscribed: false)
                                                isParticipantsAudioMenuPresented[participant.id] = false
                                            }
                                        } label: {
                                            Text("Unsubscribe")
                                        }
                                    } else if case .unsubscribed = remotePub.subscriptionState {
                                        Button {
                                            Task {
                                                try await remotePub.set(subscribed: true)
                                                isParticipantsAudioMenuPresented[participant.id] = false
                                            }
                                        } label: {
                                            Text("Subscribe")
                                        }
                                    }
                                }
                                .padding()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                            .frame(width: 32, height: 32)
                            .onHover { isHover in
                                if isHover {
                                    NSCursor.pointingHand.set()
                                } else {
                                    NSCursor.arrow.set()
                                }
                            }
                        } else {
                            Image(systemSymbol: .micFill)
                                .foregroundColor(Color.white)
                                .font(.system(size: 17))
                        }

                    } else {
                        Image(systemSymbol: .micSlashFill)
                            .foregroundColor(Color(NSColor.Sphinx.BadgeRed))
                            .font(.system(size: 17))
                    }
                }.frame(width: 32.0, height: 32.0)
            }
            .frame(height: 62)
            .frame(minWidth: 0, maxWidth: .infinity)
            
            Rectangle()
                .fill(Color.black.opacity(0.35))
                .frame(height: 1)
                .frame(maxWidth: .infinity)
        }
    }
    
    func participantsView(geometry: GeometryProxy) -> some View {
        ZStack {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text(room.participantCount == 1 ? ("\(room.participantCount)  Participant") : ("\(room.participantCount)  Participants"))
                        .foregroundColor(Color(NSColor.Sphinx.Text))
                        .font(Font(NSFont(name: "Roboto-Bold", size: 18.0)!))
                    Spacer()
                    Button {
                        roomCtx.showParticipantsView.toggle()
                    } label: {
                        Image(systemSymbol: .xmark)
                            .font(.system(size: 18))
                            .foregroundColor(Color(NSColor.Sphinx.PlaceholderText))
                    }
                    .buttonStyle(.borderless)
                    .onHover { isHover in
                        if isHover {
                            NSCursor.pointingHand.set()
                        } else {
                            NSCursor.arrow.set()
                        }
                    }
                }.frame(
                    minWidth: 0,
                    maxWidth: .infinity
                ).frame(
                    height: 76
                )
                .padding(.trailing, 23)
                .padding(.leading, 30)
                
                ScrollViewReader { scrollView in
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(sortedParticipants()) { participant in
                                participantView(participant)
                            }
                        }
                    }
                    .onAppear(perform: {
                        scrollToTop(scrollView)
                    })
                    .onChange(of: room.participantCount, perform: { _ in
                        scrollToTop(scrollView)
                    })
                    .frame(
                        minWidth: 0,
                        maxWidth: .infinity,
                        minHeight: 0,
                        maxHeight: .infinity,
                        alignment: .leading
                    )
                }
                .padding(.trailing, 23)
                .padding(.leading, 30)
            }
            .frame(
                minWidth: 0,
                maxWidth: .infinity,
                minHeight: 0,
                maxHeight: .infinity,
                alignment: .leading
            )
            .background(Color(NSColor.Sphinx.HeaderBG))
            .cornerRadius(8)
        }
        .padding(.top, 9)
        .padding(.trailing, 16)
        .frame(
            width: 360
        )
    }

    func sortedParticipants() -> [Participant] {
        room.allParticipants.values.sorted { p1, p2 in
            if p1 is LocalParticipant { return true }
            if p2 is LocalParticipant { return false }
            return (p1.joinedAt ?? Date()) < (p2.joinedAt ?? Date())
        }
    }

    func content(geometry: GeometryProxy) -> some View {
        VStack {
            if case .connecting = room.connectionState {
                Text("Connecting...")
                    .multilineTextAlignment(.center)
                    .font(Font(NSFont(name: "Roboto-Medium", size: 14.0)!))
                    .foregroundColor(.white)
                    .padding()
            }
            
            HorVStack(axis: geometry.isTall ? .vertical : .horizontal, spacing: 0) {
                Group {
                    if let focusParticipant = roomCtx.focusParticipant {
                        ZStack(alignment: .bottomTrailing) {
                            ParticipantView(participant: focusParticipant,
                                            videoViewMode: appCtx.videoViewMode)
                            { _ in
                                roomCtx.focusParticipant = nil
                            }
                        }
                        
                    } else {
                        // Array([room.allParticipants.values, room.allParticipants.values].joined())
                        ParticipantLayout(sortedParticipants(), spacing: 0) { participant in
                            ParticipantView(participant: participant,
                                            videoViewMode: appCtx.videoViewMode)
                            { participant in
                                roomCtx.focusParticipant = participant
                            }
                        }
                    }
                }
                .frame(
                    minWidth: 0,
                    maxWidth: .infinity,
                    minHeight: 0,
                    maxHeight: .infinity
                )
                
                // Show participants view if enabled
                if roomCtx.showParticipantsView {
                    participantsView(geometry: geometry)
                }
            }
        }.padding(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 3))
    }
    
    func bottomBar() -> some View {
        ZStack {
            HStack(spacing: 12.0) {
                if let tribeImg = roomCtx.tribeImage, let url = URL(string: tribeImg) {
                    WebImage(url: url)
                        .onSuccess { _,_,_ in
                            print("success")
                        }
                        .onFailure { error in
                            print("failure")
                        }
                        .resizable()
                        .scaledToFill()
                        .frame(height: 40.0)
                        .frame(width: 40.0)
                        .cornerRadius(8.0)
                        .clipped()
                }
                
                HStack(spacing: 0.0) {
                    Text(room.name ?? "Room")
                        .font(Font(NSFont(name: "Roboto-Regular", size: 14.0)!))
                        .foregroundColor(Color(NSColor.Sphinx.MainBottomIcons))
                        .padding(.horizontal, 13)
                    
                    Button(action: {
                        Task {
                            let room = "\(API.sharedInstance.kVideoCallServer)/rooms/\(room.name ?? "Room")"
                            ClipboardHelper.copyToClipboard(text: room, message: "call.link.copied.clipboard".localized)
                        }
                    },
                    label: {
                        Image("itemDetailsCopy")
                            .renderingMode(.template)
                            .frame(height: 16.0)
                            .frame(width: 16.0)
                            .padding(.trailing, 13)
                            .foregroundColor(Color(NSColor.Sphinx.MainBottomIcons))
                    })
                    .background(Color.clear)
                    .buttonStyle(PlainButtonStyle())
                    .onHover { isHover in
                        if isHover {
                            NSCursor.pointingHand.set()
                        } else {
                            NSCursor.arrow.set()
                        }
                    }
                }
                .frame(height: 40.0)
                .background(
                    Color(NSColor.Sphinx.MainBottomIcons)
                        .opacity(0.1)
                        .cornerRadius(8.0)
                )
                
//                Picker("", selection: $appCtx.videoViewMode) {
//                    Text("Fit").tag(VideoView.LayoutMode.fit)
//                    Text("Fill").tag(VideoView.LayoutMode.fill)
//                }
//                .pickerStyle(SegmentedPickerStyle())
//                .frame(width: 150.0)
                
                Spacer()
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            
            HStack {
                Spacer()
                
                Group {
                    let isCameraEnabled = room.localParticipant.isCameraEnabled()
                    let isMicrophoneEnabled = room.localParticipant.isMicrophoneEnabled()
                    let isScreenShareEnabled = room.localParticipant.isScreenShareEnabled()
                    
                    // Toggle microphone enabled
                    Button {
                        Task {
                            isMicrophonePublishingBusy = true
                            defer { Task { @MainActor in isMicrophonePublishingBusy = false } }
                            try await room.localParticipant.setMicrophone(enabled: !isMicrophoneEnabled)
                        }
                    } label: {
                        Image(systemSymbol: isMicrophoneEnabled ? .micFill : .micSlashFill)
                            .renderingMode(.template)
                            .foregroundColor(isMicrophoneEnabled ? Color.white : Color(NSColor(hex: "#FF6F6F")))
                            .font(.system(size: 18))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .disabled(isMicrophonePublishingBusy)
                    .frame(height: 40.0)
                    .frame(width: 40.0)
                    .background(
                        Color(isMicrophoneEnabled ? NSColor.Sphinx.MainBottomIcons : NSColor.Sphinx.BadgeRed)
                            .opacity(isMicrophoneEnabled ? 0.1 : 0.2)
                            .cornerRadius(8.0)
                    )
                    .contentShape(Rectangle())
                    .buttonStyle(.borderless)
                    .onHover { isHover in
                        if isHover {
                            NSCursor.pointingHand.set()
                        } else {
                            NSCursor.arrow.set()
                        }
                    }

                    // Toggle Video enabled
                    Group {
                        Button(action: {
                           if isCameraEnabled {
                               Task {
                                   isCameraPublishingBusy = true
                                   defer { Task { @MainActor in isCameraPublishingBusy = false } }
                                   try await room.localParticipant.setCamera(enabled: false)
                               }
                           } else {
                               publishOptionsPickerPresented = true
                           }
                        },
                        label: {
                            Image(systemSymbol: isCameraEnabled ? .videoFill : .videoSlashFill)
                               .renderingMode(.template)
                               .foregroundColor(isCameraEnabled ? Color.white : Color(NSColor(hex: "#FF6F6F")))
                               .font(.system(size: 16))
                               .frame(maxWidth: .infinity, maxHeight: .infinity)
                        })
                        // disable while publishing/un-publishing
                        .disabled(isCameraPublishingBusy)
                    }
                    .popover(isPresented: $publishOptionsPickerPresented) {
                        PublishOptionsView(publishOptions: cameraPublishOptions) { captureOptions, publishOptions in
                            publishOptionsPickerPresented = false
                            isCameraPublishingBusy = true
                            cameraPublishOptions = publishOptions
                            Task {
                                defer { Task { @MainActor in isCameraPublishingBusy = false } }
                                try await room.localParticipant.setCamera(enabled: true,
                                                                          captureOptions: captureOptions,
                                                                          publishOptions: publishOptions)
                            }
                        }
                        .padding()
                    }
                    .frame(height: 40.0)
                    .frame(width: 40.0)
                    .background(
                        Color(isCameraEnabled ? NSColor.Sphinx.MainBottomIcons : NSColor.Sphinx.BadgeRed)
                            .opacity(isCameraEnabled ? 0.1 : 0.2)
                            .cornerRadius(8.0)
                    )
                    .contentShape(Rectangle())
                    .buttonStyle(.borderless)
                    .onHover { isHover in
                        if isHover {
                            NSCursor.pointingHand.set()
                        } else {
                            NSCursor.arrow.set()
                        }
                    }
                    
                    // Toggle recording
                    Button {
                        Task { @MainActor in
                            if roomCtx.isProcessingRecordRequest {
                                return
                            }
                            if (room.isRecording && roomCtx.didStartRecording) || !room.isRecording {
                                toggleRecording()
                            }
                        }
                    } label: {
                        Image(systemSymbol: room.isRecording && roomCtx.didStartRecording ? .stopCircle : .recordCircle)
                            .renderingMode(.template)
                            .foregroundColor(room.isRecording ? Color(NSColor(hex: "#FF6F6F")) : Color.white)
                            .font(.system(size: 25))
                            .opacity(roomCtx.shouldAnimate ? 0.4 : 1.0)
                            .frame(height: 40.0)
                            .frame(width: 40.0)
                    }
                    .frame(height: 40.0)
                    .frame(width: 40.0)
                    .background(
                        Color(NSColor.Sphinx.MainBottomIcons)
                            .opacity(0.1)
                            .cornerRadius(8.0)
                    )
                    .contentShape(Rectangle())
                    .buttonStyle(.borderless)
                    .onHover { isHover in
                        if isHover && ((room.isRecording && roomCtx.didStartRecording) || !room.isRecording) {
                            NSCursor.pointingHand.set()
                        } else {
                            NSCursor.arrow.set()
                        }
                    }

                    // Toggle Share Screen enabled
                    Button(action: {
                       if #available(macOS 12.3, *) {
                           if isScreenShareEnabled {
                               // Turn off screen share
                               Task {
                                   isScreenSharePublishingBusy = true
                                   defer { Task { @MainActor in isScreenSharePublishingBusy = false } }
                                   try await roomCtx.setScreenShareMacOS(isEnabled: false)
                               }
                           } else {
                               screenPickerPresented = true
                           }
                       }
                   },
                   label: {
                       Image(systemSymbol: .rectangleFillOnRectangleFill)
                           .renderingMode(.template)
                           .foregroundColor(isScreenShareEnabled ? Color(NSColor.Sphinx.PrimaryGreen) : Color.white)
                           .font(.system(size: 16))
                           .frame(maxWidth: .infinity, maxHeight: .infinity)
                   }).popover(isPresented: $screenPickerPresented) {
                        if #available(macOS 12.3, *) {
                            ScreenShareSourcePickerView { source in
                                Task {
                                    isScreenSharePublishingBusy = true
                                    defer { Task { @MainActor in isScreenSharePublishingBusy = false } }
                                    try await roomCtx.setScreenShareMacOS(isEnabled: true, screenShareSource: source)
                                }
                                screenPickerPresented = false
                            }.padding()
                        }
                   }
                   .disabled(isScreenSharePublishingBusy)
                   .frame(height: 40.0)
                   .frame(width: 40.0)
                   .background(
                       Color(NSColor.Sphinx.MainBottomIcons)
                           .opacity(0.1)
                           .cornerRadius(8.0)
                   )
                   .contentShape(Rectangle())
                   .buttonStyle(.borderless)
                   .onHover { isHover in
                       if isHover {
                           NSCursor.pointingHand.set()
                       } else {
                           NSCursor.arrow.set()
                       }
                   }
                }.padding(5)

                // Disconnect
                Button(action: {
                   Task {
                       if roomCtx.didStartRecording && room.isRecording {
                           stopRecording()
                       }
                       await roomCtx.disconnect()
                   }
                },
                label: {
                   Image(systemSymbol: .phoneDownFill)
                       .renderingMode(.template)
                       .foregroundColor(Color.white)
                       .font(.system(size: 23))
                       .frame(maxWidth: .infinity, maxHeight: .infinity)
                })
                .frame(height: 40.0)
                .frame(width: 64.0)
                .background(
                    Color(NSColor.Sphinx.BadgeRed)
                        .cornerRadius(8.0)
                )
                .contentShape(Rectangle())
                .buttonStyle(.borderless)
                .onHover { isHover in
                    if isHover {
                        NSCursor.pointingHand.set()
                    } else {
                        NSCursor.arrow.set()
                    }
                }
                
                Spacer()
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            
            HStack(spacing: 13.0) {
                Spacer()
                
                HStack(spacing: 4.0) {
                    Button(action: {
                        Task {
                            roomCtx.showParticipantsView.toggle()
                        }
                    },
                    label: {
                        Image(systemSymbol: .person2Fill)
                            .renderingMode(.template)
                            .foregroundColor(Color.white)
                            .font(.system(size: 18))
                    })
                    .background(Color.clear)
                    .contentShape(Rectangle())
                    .buttonStyle(PlainButtonStyle())
                    .padding(.leading, 8.0)
                    .onHover { isHover in
                        if isHover {
                            NSCursor.pointingHand.set()
                        } else {
                            NSCursor.arrow.set()
                        }
                    }
                    if room.allParticipants.count > 0 {
                        Text("\(room.allParticipants.count)")
                            .font(Font(NSFont(name: "Roboto-Regular", size: 14.0)!))
                            .foregroundColor(Color.white)
                            .padding(.trailing, 8)
                    }
                }
                .frame(height: 40.0)
                .background(
                    roomCtx.showParticipantsView ?
                    Color(NSColor(hex: "#5078F2"))
                        .opacity(0.75)
                        .cornerRadius(8.0)
                    : Color(NSColor.Sphinx.MainBottomIcons)
                        .opacity(0.1)
                        .cornerRadius(8.0)
                )
                
                Button(action: {
                    isGearMenuPresented.toggle()
                }) {
                    Image(systemSymbol: .gear)
                        .renderingMode(.template)
                        .foregroundColor(Color.white)
                        .font(.system(size: 18))
                        .frame(width: 40.0, height: 40.0)
                }
                .buttonStyle(PlainButtonStyle())
                .background(
                    Color(NSColor.Sphinx.MainBottomIcons)
                        .opacity(0.1)
                        .cornerRadius(8.0)
                )
                .contentShape(Rectangle())
                .popover(isPresented: $isGearMenuPresented) {
                    VStack(alignment: .leading, spacing: 16) {
                        Button {
                            let room = "\(API.sharedInstance.kVideoCallServer)/rooms/\(room.name ?? "Room")"
                            if let url = URL(string: room) {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            Text("Open in Browser")
                        }

                        Divider()

                        Toggle("Show info overlay", isOn: $appCtx.showInformationOverlay)

                        Group {
                            Toggle("VideoView visible", isOn: $appCtx.videoViewVisible)
                            Toggle("VideoView flip", isOn: $appCtx.videoViewMirrored)
                            Toggle("VideoView renderMode: .sampleBuffer", isOn: $appCtx.preferSampleBufferRendering)
                            Divider()
                        }

                        Group {
                            Picker("Output device", selection: $appCtx.outputDeviceId) {
                                ForEach(AudioManager.shared.outputDevices) { device in
                                    Text(device.isDefault ? "System default (\(appCtx.realOutputDevice.name))" : "\(device.name)").tag(device.deviceId)
                                }
                            }
                            Picker("Input device", selection: $appCtx.inputDeviceId) {
                                ForEach(AudioManager.shared.inputDevices) { device in
                                    Text(device.isDefault ? "System default (\(appCtx.realInputDevice.name))" : "\(device.name)").tag(device.deviceId)
                                }
                            }
                        }

                        Group {
                            Divider()
                            
                            Button {
                                Task {
                                    await room.localParticipant.unpublishAll()
                                }
                            } label: {
                                Text("Unpublish all")
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 80.0)
        .padding(.horizontal, 16.0)
        
    }
    
    func optionsButton() -> some View {
        Group {
            
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(NSColor.Sphinx.Body)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                VStack(spacing: 0) {
                    
                    Spacer().frame(height: 45.0)
                    
                    content(geometry: geometry)
                    
                    bottomBar()
                }
                .background(Color.black.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            Task { @MainActor in
                canSwitchCameraPosition = try await CameraCapturer.canSwitchPosition()
            }
            Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { _ in
                Task { @MainActor in
                    withAnimation {
                        showConnectionTime = false
                    }
                }
            }
            appCtx.reloadAudioDevices()
        }.onChange(of: room.isRecording) { newValue in
            self.newMessageBubbleHelper.showGenericMessageView(
                text: newValue ? "Recording in progress.\nPlease be aware this call is being recorded." : "Recording ended.\nThis call is no longer being recorded.",
                delay: 5,
                textColor: NSColor.white,
                backColor: NSColor.Sphinx.BadgeRed,
                backAlpha: 1.0
            )
            
            self.roomCtx.shouldAnimate = newValue
            
            if newValue {
                roomCtx.startAnimation()
            } else {
                roomCtx.stopAnimation()
                roomCtx.didStartRecording = false
            }
        }
    }
}

struct ParticipantLayout<Content: View>: View {
    let views: [AnyView]
    let spacing: CGFloat

    init<Data: RandomAccessCollection>(
        _ data: Data,
        id: KeyPath<Data.Element, Data.Element> = \.self,
        spacing: CGFloat,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.spacing = spacing
        views = data.map { AnyView(content($0[keyPath: id])) }
    }

    func computeColumn(with geometry: GeometryProxy) -> (x: Int, y: Int) {
        let sqr = Double(views.count).squareRoot()
        let r: [Int] = [Int(sqr.rounded()), Int(sqr.rounded(.up))]
        let c = geometry.isTall ? r : r.reversed()
        return (x: c[0], y: c[1])
    }

    func grid(axis: Axis, geometry: GeometryProxy) -> some View {
        ScrollView([axis == .vertical ? .vertical : .horizontal]) {
            HorVGrid(axis: axis, columns: [GridItem(.flexible())], spacing: spacing) {
                ForEach(0 ..< views.count, id: \.self) { i in
                    views[i]
                        .aspectRatio(1, contentMode: .fill)
                }
            }
            .padding(axis == .horizontal ? [.leading, .trailing] : [.top, .bottom],
                     max(0, ((axis == .horizontal ? geometry.size.width : geometry.size.height)
                             - ((axis == .horizontal ? geometry.size.height : geometry.size.width) * CGFloat(views.count)) - (spacing * CGFloat(views.count - 1))) / 2))
        }
    }

    var body: some View {
        GeometryReader { geometry in
            if views.isEmpty {
                EmptyView()
            } else if geometry.size.width <= 300 {
                grid(axis: .vertical, geometry: geometry)
            } else if geometry.size.height <= 300 {
                grid(axis: .horizontal, geometry: geometry)
            } else {
                let verticalWhenTall: Axis = geometry.isTall ? .vertical : .horizontal
                let horizontalWhenTall: Axis = geometry.isTall ? .horizontal : .vertical

                switch views.count {
                // simply return first view
                case 1: views[0]
                case 3: HorVStack(axis: verticalWhenTall, spacing: spacing) {
                        views[0]
                        HorVStack(axis: horizontalWhenTall, spacing: spacing) {
                            views[1]
                            views[2]
                        }
                    }
                case 5: HorVStack(axis: verticalWhenTall, spacing: spacing) {
                        views[0]
                        if geometry.isTall {
                            HStack(spacing: spacing) {
                                views[1]
                                views[2]
                            }
                            HStack(spacing: spacing) {
                                views[3]
                                views[4]
                            }
                        } else {
                            VStack(spacing: spacing) {
                                views[1]
                                views[3]
                            }
                            VStack(spacing: spacing) {
                                views[2]
                                views[4]
                            }
                        }
                    }
                    case 6:
                        if geometry.isTall {
                            VStack {
                                HStack {
                                    views[0]
                                    views[1]
                                }
                                HStack {
                                    views[2]
                                    views[3]
                                }
                                HStack {
                                    views[4]
                                    views[5]
                                }
                            }
                        } else {
                            VStack {
                                HStack {
                                    views[0]
                                    views[1]
                                    views[2]
                                }
                                HStack {
                                    views[3]
                                    views[4]
                                    views[5]
                                }
                            }
                        }
                default:
                    let c = computeColumn(with: geometry)
                    VStack(spacing: spacing) {
                        ForEach(0 ... (c.y - 1), id: \.self) { y in
                            HStack(spacing: spacing) {
                                ForEach(0 ... (c.x - 1), id: \.self) { x in
                                    let index = (y * c.x) + x
                                    if index < views.count {
                                        views[index]
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct HorVStack<Content: View>: View {
    let axis: Axis
    let horizontalAlignment: SwiftUI.HorizontalAlignment
    let verticalAlignment: SwiftUI.VerticalAlignment
    let spacing: CGFloat?
    let content: () -> Content

    init(axis: Axis = .horizontal,
         horizontalAlignment: SwiftUI.HorizontalAlignment = .center,
         verticalAlignment: SwiftUI.VerticalAlignment = .center,
         spacing: CGFloat? = nil,
         @ViewBuilder content: @escaping () -> Content)
    {
        self.axis = axis
        self.horizontalAlignment = horizontalAlignment
        self.verticalAlignment = verticalAlignment
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        Group {
            if axis == .vertical {
                VStack(alignment: horizontalAlignment, spacing: spacing, content: content)
            } else {
                HStack(alignment: verticalAlignment, spacing: spacing, content: content)
            }
        }
    }
}

struct HorVGrid<Content: View>: View {
    let axis: Axis
    let spacing: CGFloat?
    let content: () -> Content
    let columns: [GridItem]

    init(axis: Axis = .horizontal,
         columns: [GridItem],
         spacing: CGFloat? = nil,
         @ViewBuilder content: @escaping () -> Content)
    {
        self.axis = axis
        self.spacing = spacing
        self.columns = columns
        self.content = content
    }

    var body: some View {
        Group {
            if axis == .vertical {
                LazyVGrid(columns: columns, spacing: spacing, content: content)
            } else {
                LazyHGrid(rows: columns, spacing: spacing, content: content)
            }
        }
    }
}

extension GeometryProxy {
    public var isTall: Bool {
        size.height > size.width
    }

    var isWide: Bool {
        size.width > size.height
    }
}
