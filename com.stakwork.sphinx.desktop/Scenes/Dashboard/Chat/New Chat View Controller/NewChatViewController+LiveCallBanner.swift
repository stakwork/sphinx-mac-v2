//
//  NewChatViewController+LiveCallBanner.swift
//  Sphinx
//
//  Polls for active LiveKit call participants and surfaces a persistent
//  banner below the tribe chat header.
//

import Cocoa

extension NewChatViewController: ActiveCallBannerDelegate {
    
    // MARK: - Polling lifecycle
    
    func startLiveCallBannerPolling() {
        // Only for public-group (tribe) chats, never for threads
        guard chat?.isPublicGroup() == true, !isThread else { return }
        guard let chatId = chat?.id else { return }
        
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
        
        // Repeating 15-second timer on .common run loop mode (so it fires during scroll)
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
                        // Call has ended – stop polling
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
        // chatTopView is an implicitly-unwrapped outlet; guard in case view is torn down
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
