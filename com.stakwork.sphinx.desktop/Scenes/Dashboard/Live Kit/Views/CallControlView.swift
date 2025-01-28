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
            HStack(spacing: 8) {
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

                    // Toggle messages view (chat example)
//                    Button(action: {
//                        withAnimation {
//                            roomCtx.showMessagesView.toggle()
//                        }
//                    },
//                    label: {
//                        Image(systemSymbol: .messageFill)
//                            .renderingMode(.template)
//                            .foregroundColor(roomCtx.showMessagesView ? Color(NSColor.Sphinx.PrimaryGreen) : Color.white)
//                    }).buttonStyle(.borderless)
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
            }.frame(maxWidth: .infinity, maxHeight: .infinity)

        }
        .frame(height: 80.0)
        .padding(.horizontal, 16.0)
        .background(
            Color(NSColor.black)
                .cornerRadius(8.0)
        )
    }
}

//#Preview {
//    let roomCtx = RoomContext(store: sync)
//    ShareControlView()
//        .environmentObject(roomCtx)
//        .environmentObject(roomCtx.room)
//}
