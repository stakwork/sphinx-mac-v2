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
    
    // Installs the banner stack into the VC's own view hierarchy, sitting directly
    // below chatTopView. Called once from setupChatTopView().
    func installActiveCallBannerIfNeeded() {
        let stack = chatTopView.liveCallBannerStack
        guard stack.superview == nil else { return }
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: chatTopView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: chatTopView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: chatTopView.bottomAnchor),
        ])
        // No fixed height — stack self-sizes via each row's intrinsicContentSize
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleCallWindowChange),
            name: .liveKitCallWindowDidChange, object: nil
        )
    }
    
    // MARK: - WebSocket-based banner lifecycle

    func startLiveCallBannerPolling() {
        guard chat?.isPublicGroup() == true, !isThread else { return }
        guard let chatId = chat?.id else { return }

        installActiveCallBannerIfNeeded()

        let callMessages = TransactionMessage.getRecentCallMessages(for: chatId)
        for callMessage in callMessages {
            guard let rawContent = callMessage.messageContent else { continue }

            let callLink: String
            if let parsed = VoIPRequestMessage.getFromString(rawContent)?.link, parsed.isCallLink {
                callLink = parsed
            } else if rawContent.isCallLink {
                callLink = rawContent
            } else {
                continue
            }

            guard let url = URL(string: callLink),
                  let roomName = url.pathComponents.last(where: { !$0.isEmpty && $0 != "/" }) else {
                continue
            }

            liveCallRooms[roomName] = callLink
            liveCallRoomDates[roomName] = callMessage.date ?? Date()

            if chatTableDataSource?.callParticipantsSocketManager == nil {
                chatTableDataSource?.callParticipantsSocketManager = CallParticipantsSocketManager()
                chatTableDataSource?.callParticipantsSocketManager?.delegate = chatTableDataSource
            }
            if chatTableDataSource?.subscribedRooms.contains(roomName) == false {
                chatTableDataSource?.subscribedRooms.insert(roomName)
                chatTableDataSource?.callParticipantsSocketManager?.subscribe(roomName: roomName)
            } else {
                // Already subscribed — force the server to re-emit current_participants
                chatTableDataSource?.callParticipantsSocketManager?.sendSubscribeTo(roomName: roomName)
            }
            chatTableDataSource?.bannerRooms.insert(roomName)
        }
    }

    func stopLiveCallBannerPolling() {
        chatTableDataSource?.unsubscribeAllRooms()
        chatTableDataSource?.bannerRooms.removeAll()
        liveCallRooms.removeAll()
        liveCallRoomDates.removeAll()
        if isViewLoaded {
            chatTopView?.hideAllCallBanners()
        }
        NotificationCenter.default.removeObserver(self, name: .liveKitCallWindowDidChange, object: nil)
    }
    
    // MARK: - ActiveCallBannerDelegate

    func didTapJoin(callLink: String) {
        WindowsManager.sharedInstance.closeActiveCallWindow()
        shouldStartCallWith(link: callLink, audioOnly: false, isHost: false)
    }
    
    // MARK: - Call window change notification
    
    @objc private func handleCallWindowChange() {
        refreshAllBanners()
        if WindowsManager.sharedInstance.getLiveKitCallWindow() != nil {
            for roomName in chatTableDataSource?.bannerRooms ?? [] {
                chatTableDataSource?.callParticipantsSocketManager?.sendSubscribeTo(roomName: roomName)
            }
        }
    }
    
    private func refreshAllBanners() {
        for roomName in liveCallRooms.keys {
            let participants = chatTableDataSource?.callParticipantsStore[roomName] ?? []
            shouldUpdateLiveCallBanner(roomName: roomName, participants: participants)
        }
    }

    func didTapOpen() {
        WindowsManager.sharedInstance.getLiveKitCallWindow()?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - NewChatTableDataSourceDelegate live call banner
extension NewChatViewController {
    func roomFinished(roomName: String) {
        chatTopView.hideCallBanner(roomName: roomName)
    }

    func newCallMessageReceived() {
        stopLiveCallBannerPolling()
        startLiveCallBannerPolling()
    }

    func shouldUpdateLiveCallBanner(roomName: String, participants: [BubbleMessageLayoutState.CallParticipantInfo]) {
        guard let callLink = liveCallRooms[roomName] else { return }
        if participants.isEmpty {
            chatTopView.hideCallBanner(roomName: roomName)
        } else {
            let activeRoomName = WindowsManager.sharedInstance.getLiveKitCallWindow()?.windowIdentifier?.liveKitRoomName
            let isAlreadyInCall = activeRoomName == roomName
            let messageDate = liveCallRoomDates[roomName] ?? .distantPast
            chatTopView.showCallBanner(
                roomName: roomName,
                participants: participants,
                callLink: callLink,
                messageDate: messageDate,
                isAlreadyInCall: isAlreadyInCall,
                delegate: self
            )
        }
    }
}
