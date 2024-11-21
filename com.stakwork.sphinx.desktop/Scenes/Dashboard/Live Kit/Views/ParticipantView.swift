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
import SwiftyJSON
import SDWebImageSwiftUI

struct ParticipantView: View {
    @ObservedObject var participant: Participant
    @EnvironmentObject var appCtx: AppContext

    var videoViewMode: VideoView.LayoutMode = .fill
    var onTap: ((_ participant: Participant) -> Void)?

    @State private var isRendering: Bool = false
    
    @State private var retry: Bool = false
    
    func bgView(
        systemSymbol: SFSymbol,
        geometry: GeometryProxy
    ) -> some View {
        Image(systemSymbol: systemSymbol)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundColor(Color(NSColor.Sphinx.SecondaryText))
            .frame(width: min(geometry.size.width, geometry.size.height) * 0.3)
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )
    }

    var body: some View {
        GeometryReader { geometry in

            ZStack(alignment: .bottom) {
                // Background color
                Color(NSColor.Sphinx.HeaderBG).ignoresSafeArea()

                // VideoView for the Participant
                if let publication = participant.mainVideoPublication,
                   !publication.isMuted,
                   let track = publication.track as? VideoTrack,
                   appCtx.videoViewVisible
                {
                    ZStack(alignment: .topLeading) {
                        SwiftUIVideoView(track,
                                         layoutMode: videoViewMode,
                                         mirrorMode: appCtx.videoViewMirrored ? .mirror : .auto,
                                         renderMode: appCtx.preferSampleBufferRendering ? .sampleBuffer : .auto,
                                         pinchToZoomOptions: appCtx.videoViewPinchToZoomOptions,
                                         isDebugMode: appCtx.showInformationOverlay,
                                         isRendering: $isRendering)
                        
                        if !isRendering {
                            ProgressView().progressViewStyle(CircularProgressViewStyle())
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        }
                    }
                } else if let profilePictureUrl = participant.profilePictureUrl, let url = URL(string: profilePictureUrl) {
                    WebImage(url: url)
                        .onSuccess { _,_,_ in
                            print("success")
                        }
                        .onFailure { error in
                            self.retry = true
                        }
                        .resizable()
                        .scaledToFill()
                        .frame(
                            width: min(geometry.size.width, geometry.size.height) * 0.8,
                            height: min(geometry.size.width, geometry.size.height) * 0.8
                        )
                        .clipped()
                        .cornerRadius(min(geometry.size.width, geometry.size.height) * 0.4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(
                            Group {
                                if retry {
                                    bgView(systemSymbol: .videoSlashFill, geometry: geometry)
                                }
                            }
                        )
                } else {
                    if let publication = participant.mainVideoPublication as? RemoteTrackPublication,
                       case .notAllowed = publication.subscriptionState {
                        bgView(systemSymbol: .exclamationmarkCircle, geometry: geometry)
                    } else {
                        bgView(systemSymbol: .videoSlashFill, geometry: geometry)
                    }
                }

                if appCtx.showInformationOverlay {
                    VStack(alignment: .leading, spacing: 5) {
                        // Video stats
                        if let publication = participant.mainVideoPublication,
                           !publication.isMuted,
                           let track = publication.track as? VideoTrack
                        {
                            StatsView(track: track)
                        }
                        // Audio stats
                        if let publication = participant.firstAudioPublication,
                           !publication.isMuted,
                           let track = publication.track as? AudioTrack
                        {
                            StatsView(track: track)
                        }
                    }
                    .padding(8)
                    .frame(
                        minWidth: 0,
                        maxWidth: .infinity,
                        minHeight: 0,
                        maxHeight: .infinity,
                        alignment: .topLeading
                    )
                }

                VStack(alignment: .trailing, spacing: 0) {
                    // Show the sub-video view
                    if let subVideoTrack = participant.subVideoTrack {
                        SwiftUIVideoView(subVideoTrack,
                                         layoutMode: .fill,
                                         mirrorMode: appCtx.videoViewMirrored ? .mirror : .auto)
                            .background(Color.black)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: min(geometry.size.width, geometry.size.height) * 0.3)
                            .cornerRadius(8)
                            .padding()
                    }

                    // Bottom user info bar
                    HStack {
                        if let name = participant.name, name.isNotEmpty {
                            Text(String(describing: name))
                                .font(Font(NSFont(name: "Roboto-Regular", size: 16.0)!))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        } else if let identity = participant.identity {
                            Text(String(describing: identity))
                                .font(Font(NSFont(name: "Roboto-Regular", size: 16.0)!))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }

                        if let publication = participant.mainVideoPublication,
                           !publication.isMuted
                        {
                            // is remote
                            if let remotePub = publication as? RemoteTrackPublication {
                                Menu {
                                    if case .subscribed = remotePub.subscriptionState {
                                        Button {
                                            Task {
                                                try await remotePub.set(subscribed: false)
                                            }
                                        } label: {
                                            Text("Unsubscribe")
                                        }
                                    } else if case .unsubscribed = remotePub.subscriptionState {
                                        Button {
                                            Task {
                                                try await remotePub.set(subscribed: true)
                                            }
                                        } label: {
                                            Text("Subscribe")
                                        }
                                    }
                                } label: {
                                    if case .subscribed = remotePub.subscriptionState {
                                        Image(systemSymbol: .videoFill)
                                            .foregroundColor(Color(NSColor.Sphinx.PrimaryGreen))
                                    } else if case .notAllowed = remotePub.subscriptionState {
                                        Image(systemSymbol: .exclamationmarkCircle)
                                            .foregroundColor(Color(NSColor.Sphinx.BadgeRed))
                                    } else {
                                        Image(systemSymbol: .videoSlashFill)
                                    }
                                }
                                .menuStyle(BorderlessButtonMenuStyle(showsMenuIndicator: true))
                                .fixedSize()
                            } else {
                                // local
                                Image(systemSymbol: .videoFill)
                                    .foregroundColor(Color(NSColor.Sphinx.PrimaryGreen))
                            }

                        } else {
                            Image(systemSymbol: .videoSlashFill)
                                .foregroundColor(Color.white)
                        }

                        if let publication = participant.firstAudioPublication,
                           !publication.isMuted
                        {
                            // is remote
                            if let remotePub = publication as? RemoteTrackPublication {
                                Menu {
                                    if case .subscribed = remotePub.subscriptionState {
                                        Button {
                                            Task {
                                                try await remotePub.set(subscribed: false)
                                            }
                                        } label: {
                                            Text("Unsubscribe")
                                        }
                                    } else if case .unsubscribed = remotePub.subscriptionState {
                                        Button {
                                            Task {
                                                try await remotePub.set(subscribed: true)
                                            }
                                        } label: {
                                            Text("Subscribe")
                                        }
                                    }
                                } label: {
                                    if case .subscribed = remotePub.subscriptionState {
                                        Image(systemSymbol: .micFill)
                                            .foregroundColor(Color(NSColor.Sphinx.PrimaryGreen))
                                    } else if case .notAllowed = remotePub.subscriptionState {
                                        Image(systemSymbol: .exclamationmarkCircle)
                                            .foregroundColor(Color(NSColor.Sphinx.BadgeRed))
                                    } else {
                                        Image(systemSymbol: .micSlashFill)
                                    }
                                }
                                .menuStyle(BorderlessButtonMenuStyle(showsMenuIndicator: true))
                                .fixedSize()
                            } else {
                                // local
                                Image(systemSymbol: .micFill)
                                    .foregroundColor(Color(NSColor.Sphinx.PrimaryGreen))
                            }

                        } else {
                            Image(systemSymbol: .micSlashFill)
                                .foregroundColor(Color.white)
                        }

                        if participant.connectionQuality == .excellent {
                            Image(systemSymbol: .wifi)
                                .foregroundColor(Color(NSColor.Sphinx.PrimaryGreen))
                        } else if participant.connectionQuality == .good {
                            Image(systemSymbol: .wifi)
                                .foregroundColor(Color(NSColor.Sphinx.SphinxOrange))
                        } else if participant.connectionQuality == .poor {
                            Image(systemSymbol: .wifiExclamationmark)
                                .foregroundColor(Color(NSColor.Sphinx.BadgeRed))
                        }

                        if participant.firstTrackEncryptionType == .none {
                            Image(systemSymbol: .lockOpenFill)
                                .foregroundColor(Color(NSColor.Sphinx.BadgeRed))
                        } else {
                            Image(systemSymbol: .lockFill)
                                .foregroundColor(Color(NSColor.Sphinx.PrimaryGreen))
                        }

                    }.padding(5)
                        .frame(minWidth: 0, maxWidth: .infinity)
                        .background(Color.black.opacity(0.5))
                }
            }
            .cornerRadius(8)
            // Glow the border when the participant is speaking
            .overlay(
                participant.isSpeaking ?
                    RoundedRectangle(cornerRadius: 5)
                    .stroke(Color(NSColor.Sphinx.PrimaryBlue), lineWidth: 5.0)
                    : nil
            )
        }.gesture(TapGesture()
            .onEnded { _ in
                // Pass the tap event
                onTap?(participant)
            })
    }
}

struct StatsView: View {
    private let track: Track
    @ObservedObject private var observer: TrackDelegateObserver

    init(track: Track) {
        self.track = track
        observer = TrackDelegateObserver(track: track)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 5) {
            VStack(alignment: .leading, spacing: 5) {
                if track is VideoTrack {
                    HStack(spacing: 3) {
                        Image(systemSymbol: .videoFill)
                        Text("Video").fontWeight(.bold)
                        if let dimensions = observer.dimensions {
                            Text("\(dimensions.width)×\(dimensions.height)")
                        }
                    }
                } else if track is AudioTrack {
                    HStack(spacing: 3) {
                        Image(systemSymbol: .micFill)
                        Text("Audio").fontWeight(.bold)
                    }
                } else {
                    Text("Unknown").fontWeight(.bold)
                }

                // if let trackStats = viewModel.statistics {
                ForEach(observer.allStatisticts, id: \.self) { trackStats in
                    ForEach(trackStats.outboundRtpStream.sortedByRidIndex()) { stream in

                        HStack(spacing: 3) {
                            Image(systemSymbol: .arrowUp)

                            if let codec = trackStats.codec.first(where: { $0.id == stream.codecId }) {
                                Text(codec.mimeType ?? "?")
                            }

                            if let rid = stream.rid, !rid.isEmpty {
                                Text(rid.uppercased())
                            }

                            Text(stream.formattedBps())

                            if let reason = stream.qualityLimitationReason, reason != QualityLimitationReason.none {
                                Image(systemSymbol: .exclamationmarkTriangleFill)
                                Text(reason.rawValue.capitalized)
                            }
                        }
                    }
                    ForEach(trackStats.inboundRtpStream) { stream in

                        HStack(spacing: 3) {
                            Image(systemSymbol: .arrowDown)

                            if let codec = trackStats.codec.first(where: { $0.id == stream.codecId }) {
                                Text(codec.mimeType ?? "?")
                            }

                            Text(stream.formattedBps())
                        }
                    }
                }
            }
            .font(.system(size: 10))
            .foregroundColor(Color.white)
            .padding(5)
            .background(Color.black.opacity(0.5))
            .cornerRadius(8)
        }
    }
}
