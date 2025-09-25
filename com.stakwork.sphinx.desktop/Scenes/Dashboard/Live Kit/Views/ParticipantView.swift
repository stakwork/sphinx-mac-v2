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
    @EnvironmentObject var roomCtx: RoomContext

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
                Color(NSColor.Sphinx.HeaderBG)
                    .ignoresSafeArea()
                    .overlay(
                        participant.isSpeaking ?
                            RoundedRectangle(cornerRadius: 8).stroke(Color(NSColor.Sphinx.PrimaryBlue), lineWidth: 3.0)
                            : nil
                    )

                // VideoView for the Participant
                if let publication = participant.mainVideoPublication,
                   !publication.isMuted,
                   let track = publication.track as? VideoTrack,
                   appCtx.videoViewVisible
                {
                    ZStack(alignment: .center) {
                        SwiftUIVideoView(track,
                                         layoutMode: .fit,
                                         mirrorMode: appCtx.videoViewMirrored ? .mirror : .auto,
                                         renderMode: appCtx.preferSampleBufferRendering ? .sampleBuffer : .auto,
                                         pinchToZoomOptions: appCtx.videoViewPinchToZoomOptions,
                                         isDebugMode: false,
                                         isRendering: $isRendering)
                        .cornerRadius(8)
                        
                        if !isRendering {
                            ProgressView().progressViewStyle(CircularProgressViewStyle())
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        }
                    }.overlay(
                        participant.isSpeaking ?
                            RoundedRectangle(cornerRadius: 8).stroke(Color(NSColor.Sphinx.PrimaryBlue), lineWidth: 3.0)
                            : nil
                    )
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
                        .frame(width: 146.0, height: 146.0)
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
                    ZStack(alignment: .center) {
                        Circle()
                            .fill(roomCtx.getColorForParticipan(participantId: participant.sid?.stringValue) ?? Color(NSColor.random()))
                            .frame(maxWidth: 146.0, maxHeight: 146.0)

                        Text((participant.name ?? "Unknow").getInitialsFromName())
                            .font(Font(NSFont(name: "Roboto-Medium", size: 70.0)!))
                            .foregroundColor(Color.white)
                            .frame(width: 146.0, height: 130.0)
                            .padding(.top, 8.0)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
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
                                         layoutMode: .fit,
                                         mirrorMode: appCtx.videoViewMirrored ? .mirror : .auto)
                            .background(Color.black)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: min(geometry.size.width, geometry.size.height) * 0.3)
                            .cornerRadius(8)
                            .padding()
                    }

                    // Bottom user info bar
                    HStack(spacing: 4.0) {
                        ZStack(alignment: .center) {
                            if let publication = participant.firstAudioPublication,
                               !publication.isMuted
                            {
                                // is remote
                                if participant.isSpeaking {
                                    Circle()
                                        .fill(Color.white)
                                        .frame(maxWidth: 24.0, maxHeight: 24.0)
                                    Image(systemSymbol: .waveformCircleFill)
                                        .renderingMode(.template)
                                        .foregroundColor(Color(NSColor.Sphinx.PrimaryBlue))
                                        .font(.system(size: 24))
                                } else {
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
                                                    .foregroundColor(Color.white)
                                                    .font(.system(size: 14))
                                            } else if case .notAllowed = remotePub.subscriptionState {
                                                Image(systemSymbol: .exclamationmarkCircle)
                                                    .foregroundColor(Color(NSColor.Sphinx.BadgeRed))
                                                    .font(.system(size: 14))
                                            } else {
                                                Image(systemSymbol: .micSlashFill)
                                                    .foregroundColor(Color(NSColor.Sphinx.BadgeRed))
                                                    .font(.system(size: 14))
                                            }
                                        }
                                        .menuStyle(BorderlessButtonMenuStyle())
                                        .menuIndicator(.hidden)
                                        .fixedSize()
                                    } else {
                                        Image(systemSymbol: .micFill)
                                            .foregroundColor(Color.white)
                                            .font(.system(size: 14))
                                    }
                                }

                            } else {
                                Image(systemSymbol: .micSlashFill)
                                    .foregroundColor(Color(NSColor.Sphinx.BadgeRed))
                                    .font(.system(size: 14))
                            }
                        }.frame(width: 28.0, height: 28.0)
                        
                        if let name = participant.name, name.isNotEmpty {
                            Text(String(describing: name))
                                .font(Font(NSFont(name: "Roboto-Medium", size: 14.0)!))
                                .lineLimit(1)
                                .foregroundColor(Color.white)
                                .truncationMode(.tail)
                        } else if let identity = participant.identity {
                            Text(String(describing: identity))
                                .font(Font(NSFont(name: "Roboto-Medium", size: 14.0)!))
                                .lineLimit(1)
                                .foregroundColor(Color.white)
                                .truncationMode(.tail)
                        }
                        Spacer()

                    }
                    .padding(.leading, 10)
                    .padding(.bottom, 10)
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .frame(height: 30.0)
                }
            }
            .cornerRadius(8)
            .padding(EdgeInsets(top: 9, leading: 0, bottom: 0, trailing: 13))
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
