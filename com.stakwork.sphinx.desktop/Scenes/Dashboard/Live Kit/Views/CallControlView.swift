//
//  ShareControlView.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 28/01/2025.
//  Copyright © 2025 Tomas Timinskas. All rights reserved.
//

import SwiftUI
import LiveKit
import SDWebImageSwiftUI

struct CallControlView: View {
    @EnvironmentObject var roomCtx: RoomContext
    @EnvironmentObject var room: Room
    
    @State var isCameraPublishingBusy = false
    @State var isMicrophonePublishingBusy = false
    @State var isScreenSharePublishingBusy = false
    @State var isARCameraPublishingBusy = false

    @State private var screenPickerPresented = false
    @State private var publishOptionsPickerPresented = false
    @State private var isGearMenuPresented = false
    
    @State private var cameraPublishOptions = VideoPublishOptions()
    
    @State private var onHover = false
    
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
        
        DispatchQueue.main.async {
            self.roomCtx.didStartRecording.toggle()
        }
        
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
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    if onHover {
                        Text("drag_handle")
                            .font(Font(NSFont(name: "MaterialIcons-Regular", size: 25.0)!))
                            .foregroundColor(Color(NSColor.Sphinx.MainBottomIcons))
                            .frame(width: 100.0, height: 32.0)
                            .padding(.top, 15)
                    }
                }
                .frame(height: 20)
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                
                HStack(spacing: 8) {
                    controlButtonsGroup
                    disconnectButton
                }
                .frame(width: 300, height: 80)
                .padding(.horizontal, 16.0)
                .background(
                    onHover ? Color.clear.cornerRadius(8.0) : Color.black.opacity(0.9).cornerRadius(8.0)
                )
            }
        }
        .frame(width: 332, height: 100)
        .background(
            onHover ? Color.black.opacity(0.9).cornerRadius(8.0) : Color.clear.cornerRadius(8.0)
        )
        .onHover { hovering in
            onHover = hovering
        }
        .onChange(of: room.isRecording) { newValue in
            self.roomCtx.shouldAnimate = newValue
            
            if newValue {
                roomCtx.startAnimation()
            } else {
                roomCtx.stopAnimation()
                roomCtx.didStartRecording = false
            }
        }
        // Move popovers to the main view level - this prevents recreation
        .popover(isPresented: $publishOptionsPickerPresented) {
            cameraOptionsPopover
        }
        .popover(isPresented: $screenPickerPresented) {
            screenSharePopover
        }
    }

    // MARK: - Extracted Views

    @ViewBuilder
    private var controlButtonsGroup: some View {
        Group {
            microphoneButton
            cameraButton
            recordingButton
            screenShareButton
        }
        .padding(5)
    }

    @ViewBuilder
    private var microphoneButton: some View {
        let isMicrophoneEnabled = room.localParticipant.isMicrophoneEnabled()
        
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
        .frame(width: 40.0, height: 40.0)
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
    }

    @ViewBuilder
    private var cameraButton: some View {
        let isCameraEnabled = room.localParticipant.isCameraEnabled()
        
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
        }, label: {
            Image(systemSymbol: isCameraEnabled ? .videoFill : .videoSlashFill)
               .renderingMode(.template)
               .foregroundColor(isCameraEnabled ? Color.white : Color(NSColor(hex: "#FF6F6F")))
               .font(.system(size: 16))
               .frame(maxWidth: .infinity, maxHeight: .infinity)
        })
        .disabled(isCameraPublishingBusy)
        // Remove .popover from here - moved to main view
        .frame(width: 40.0, height: 40.0)
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
    }

    @ViewBuilder
    private var recordingButton: some View {
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
                .onAppear {
                    if room.isRecording {
                        roomCtx.startAnimation()
                    }
                }
                .frame(width: 40.0, height: 40.0)
        }
        .frame(width: 40.0, height: 40.0)
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
    }

    @ViewBuilder
    private var screenShareButton: some View {
        let isScreenShareEnabled = room.localParticipant.isScreenShareEnabled()
        
        Button(action: {
           if #available(macOS 12.3, *) {
               if isScreenShareEnabled {
                   Task {
                       isScreenSharePublishingBusy = true
                       defer { Task { @MainActor in isScreenSharePublishingBusy = false } }
                       try await roomCtx.setScreenShareMacOS(isEnabled: false)
                   }
               } else {
                   screenPickerPresented = true
               }
           }
        }, label: {
            Image(systemSymbol: .rectangleFillOnRectangleFill)
                .renderingMode(.template)
                .foregroundColor(isScreenShareEnabled ? Color(NSColor.Sphinx.PrimaryGreen) : Color.white)
                .font(.system(size: 16))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        })
        .disabled(isScreenSharePublishingBusy)
        // Remove .popover from here - moved to main view
        .frame(width: 40.0, height: 40.0)
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
    }

    @ViewBuilder
    private var disconnectButton: some View {
        Button(action: {
           Task {
               if roomCtx.didStartRecording && room.isRecording {
                   stopRecording()
               }
               await roomCtx.disconnect()
           }
        }, label: {
           Image(systemSymbol: .phoneDownFill)
               .renderingMode(.template)
               .foregroundColor(Color.white)
               .font(.system(size: 23))
               .frame(maxWidth: .infinity, maxHeight: .infinity)
        })
        .frame(width: 64.0, height: 40.0)
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
    }

    // MARK: - Popover Content

    @ViewBuilder
    private var cameraOptionsPopover: some View {
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
        .background(Color(NSColor.controlBackgroundColor)) // Stable background
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let popoverWindow = NSApp.windows.first(where: { $0.className.contains("Popover") }) {
                    popoverWindow.makeKey()
                    popoverWindow.orderFrontRegardless()
                }
            }
        }
    }

    @ViewBuilder
    private var screenSharePopover: some View {
        if #available(macOS 12.3, *) {
            ScreenShareSourcePickerView { source in
                Task {
                    isScreenSharePublishingBusy = true
                    defer { Task { @MainActor in isScreenSharePublishingBusy = false } }
                    try await roomCtx.setScreenShareMacOS(isEnabled: true, screenShareSource: source)
                }
                screenPickerPresented = false
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor)) // Stable background
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if let popoverWindow = NSApp.windows.first(where: { $0.className.contains("Popover") }) {
                        popoverWindow.makeKey()
                        popoverWindow.orderFrontRegardless()
                    }
                }
            }
        }
    }
}

//#Preview {
//    let roomCtx = RoomContext(store: sync)
//    CallControlView()
//        .environmentObject(roomCtx)
//        .environmentObject(roomCtx.room)
//}
