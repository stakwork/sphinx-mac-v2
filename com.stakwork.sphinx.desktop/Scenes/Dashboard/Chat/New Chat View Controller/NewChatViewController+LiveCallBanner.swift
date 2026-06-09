//
//  NewChatViewController+LiveCallBanner.swift
//  Sphinx
//
//  Polls for active LiveKit call participants and surfaces a persistent
//  banner directly below the tribe chat header (chatTopView).
//

import Cocoa

extension NewChatViewController: ActiveCallBannerDelegate {
    
    // MARK: - Banner installation
    
    // Installs the banner view into the VC's own view hierarchy, sitting directly
    // below chatTopView. Called once from setupChatTopView().
    func installActiveCallBannerIfNeeded() {
        let banner = chatTopView.activeCallBannerView
        guard banner.superview == nil else { return }
        
        view.addSubview(banner)
        
        NSLayoutConstraint.activate([
            banner.leadingAnchor.constraint(equalTo: chatTopView.leadingAnchor),
            banner.trailingAnchor.constraint(equalTo: chatTopView.trailingAnchor),
            banner.topAnchor.constraint(equalTo: chatTopView.bottomAnchor),
            banner.heightAnchor.constraint(equalToConstant: ActiveCallBannerView.kHeight),
        ])
    }
    
    // MARK: - WebSocket-based banner lifecycle

    func startLiveCallBannerPolling() {
        guard chat?.isPublicGroup() == true, !isThread else { return }
        guard let chatId = chat?.id else { return }

        installActiveCallBannerIfNeeded()

        // Find the most recent call message and extract the actual call link URL.
        // messageContent is stored as "call::{json}" — parse via VoIPRequestMessage.
        // Fall back to using rawContent directly if it's already a bare call link.
        guard let callMessage = TransactionMessage.getMostRecentCallMessage(for: chatId),
              let rawContent = callMessage.messageContent else {
            return
        }

        let callLink: String
        if let parsed = VoIPRequestMessage.getFromString(rawContent)?.link, parsed.isCallLink {
            callLink = parsed
        } else if rawContent.isCallLink {
            callLink = rawContent
        } else {
            return
        }

        // Extract room name from URL (last non-empty path component)
        guard let url = URL(string: callLink),
              let roomName = url.pathComponents.last(where: { !$0.isEmpty && $0 != "/" }) else {
            return
        }

        liveCallRoomName = roomName
        liveCallLink = callLink

        // Subscribe for banner-level updates via the shared socket manager on the data source
        // (covers the case where the call cell hasn't rendered yet)
        if chatTableDataSource?.callParticipantsSocketManager == nil {
            chatTableDataSource?.callParticipantsSocketManager = CallParticipantsSocketManager()
            chatTableDataSource?.callParticipantsSocketManager?.delegate = chatTableDataSource
        }
        if chatTableDataSource?.subscribedRooms.contains(roomName) == false {
            chatTableDataSource?.subscribedRooms.insert(roomName)
            chatTableDataSource?.callParticipantsSocketManager?.subscribe(roomName: roomName)
        }
        chatTableDataSource?.messageIdToRoomName[-1] = roomName  // sentinel for banner-only subscriptions
    }

    func stopLiveCallBannerPolling() {
        chatTableDataSource?.unsubscribeAllRooms()
        if isViewLoaded {
            chatTopView?.hideActiveCallBanner()
        }
    }
    
    // MARK: - ActiveCallBannerDelegate

    func didTapJoin(callLink: String) {
        shouldStartCallWith(link: callLink, audioOnly: false, isHost: false)
    }

    func didTapOpen() {
        WindowsManager.sharedInstance.getLiveKitCallWindow()?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - NewChatTableDataSourceDelegate live call banner
extension NewChatViewController {
    func roomFinished(roomName: String) {
        guard roomName == liveCallRoomName else { return }
        chatTopView.hideActiveCallBanner()
    }

    func newCallMessageReceived() {
        stopLiveCallBannerPolling()
        startLiveCallBannerPolling()
    }

    func shouldUpdateLiveCallBanner(roomName: String, participants: [BubbleMessageLayoutState.CallParticipantInfo]) {
        guard roomName == liveCallRoomName, let callLink = liveCallLink else { return }
        if participants.isEmpty {
            chatTopView.hideActiveCallBanner()
        } else {
            let isAlreadyInCall = WindowsManager.sharedInstance.getLiveKitCallWindow() != nil
            chatTopView.updateActiveCallBanner(
                participants: participants,
                callLink: callLink,
                isAlreadyInCall: isAlreadyInCall,
                delegate: self
            )
        }
    }
}
