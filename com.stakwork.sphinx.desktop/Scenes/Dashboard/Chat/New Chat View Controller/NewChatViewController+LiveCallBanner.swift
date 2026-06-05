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
    
    // MARK: - Polling lifecycle
    
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
        
        // Immediate first poll
        pollForActiveCall()
        
        // Repeating 15-second timer on .common run loop mode (fires during scroll)
        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            self?.pollForActiveCall()
        }
        RunLoop.main.add(timer, forMode: .common)
        liveCallPollingTimer = timer
    }
    
    func pollForActiveCall() {
        guard let roomName = liveCallRoomName,
              let callLink = liveCallLink else { return }
        
        API.sharedInstance.getCallParticipants(
            roomName: roomName,
            callback: { [weak self] participants in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if participants.isEmpty {
                        self.chatTopView.hideActiveCallBanner()
                        self.liveCallPollingTimer?.invalidate()
                        self.liveCallPollingTimer = nil
                    } else {
                        let isInCall = WindowsManager.sharedInstance.getLiveKitCallWindow() != nil
                        self.chatTopView.updateActiveCallBanner(
                            participants: participants,
                            callLink: callLink,
                            isAlreadyInCall: isInCall,
                            delegate: self
                        )
                    }
                }
            },
            errorCallback: { _ in }
        )
    }
    
    func stopLiveCallBannerPolling() {
        liveCallPollingTimer?.invalidate()
        liveCallPollingTimer = nil
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
