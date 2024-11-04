//
//  LikeKitCallViewController.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 04/11/2024.
//  Copyright © 2024 Tomas Timinskas. All rights reserved.
//

import Cocoa
import LiveKit

class LikeKitCallViewController: NSViewController {
    
    lazy var room = Room(delegate: self)

    lazy var remoteVideoView: VideoView = {
        let videoView = VideoView()
        view.addSubview(videoView)
        // Additional initialization ...
        return videoView
    }()

    lazy var localVideoView: VideoView = {
        let videoView = VideoView()
        view.addSubview(videoView)
        // Additional initialization ...
        return videoView
    }()
    
    var url: String? = nil
    var audioOnly: Bool = true

    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.wantsLayer = true
        view.layer?.backgroundColor = .white

//        let url = "ws://your_host"
        let token = "your_jwt_token"
        
        guard let url = url else {
            return
        }

        Task {
            do {
                try await room.connect(url: url, token: token)
                // Connection successful...

                // Publishing camera & mic...
                try await room.localParticipant.setCamera(enabled: !audioOnly)
                try await room.localParticipant.setMicrophone(enabled: true)
            } catch {
                // Failed to connect
            }
        }
    }
}

extension LikeKitCallViewController: RoomDelegate {

    func room(_: Room, participant _: LocalParticipant, didPublishTrack publication: LocalTrackPublication) {
        guard let track = publication.track as? VideoTrack else { return }
        DispatchQueue.main.async {
            self.localVideoView.track = track
        }
    }

    func room(_: Room, participant _: RemoteParticipant, didSubscribeTrack publication: RemoteTrackPublication) {
        guard let track = publication.track as? VideoTrack else { return }
        DispatchQueue.main.async {
            self.remoteVideoView.track = track
        }
    }
}
