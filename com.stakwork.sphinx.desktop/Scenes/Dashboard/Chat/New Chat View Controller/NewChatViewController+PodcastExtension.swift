//
//  NewChatViewController+PodcastExtension.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 17/07/2023.
//  Copyright © 2023 Tomas Timinskas. All rights reserved.
//

import Cocoa

extension NewChatViewController {
    func addPodcastVC(
        deepLinkData: DeeplinkData? = nil
    ) {
        if isThread {
            return
        }
        
        guard let chat = chat else {
            return
        }
        
        guard let contentFeed = chat.contentFeed, contentFeed.isPodcast else {
            return
        }
        
        podcastPlayerVC = NewPodcastPlayerViewController.instantiate(
            chat: chat,
            delegate: self,
            deepLinkData: deepLinkData
        )
        
        guard let podcastPlayerVC = podcastPlayerVC else {
            return
        }
        
        WindowsManager.sharedInstance.showVCOnRightPanelWindow(
            with: "Podcast",
            identifier: "podcast-window",
            contentVC: podcastPlayerVC,
            shouldReplace: false,
            panelFixedWidth: true
        )
        
        chatTableDataSource?.updateFrame()
    }
}

extension NewChatViewController : PodcastPlayerViewDelegate {
    func shouldReloadEpisodesTable() {
        
    }
    
    func shouldShareClip(comment: PodcastComment) {
        let isAtBottom = isChatAtBottom()

        newChatViewModel.podcastComment = comment

        chatBottomView.configureReplyViewFor(
            podcastComment: comment,
            owner: self.owner,
            withDelegate: self
        )

        if isAtBottom {
            shouldScrollToBottom()
        }
    }
    
    func shouldSendBoost(
        message: String,
        amount: Int,
        animation: Bool
    ) -> TransactionMessage? {
        return nil
    }
    
    func shouldSyncPodcast() {
        
    }
}
