//
//  SphinxOnionManager+NotificationsExtension.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 16/05/2024.
//  Copyright © 2024 Tomas Timinskas. All rights reserved.
//

import Foundation
import AppKit

extension SphinxOnionManager {
    func sendNotification(message: TransactionMessage?) {
        guard let message = message else {
            return
        }
        
        setAppBadgeCount()
        
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            
            if message.isOutgoing() || message.shouldAvoidShowingBubble() {
                return
            }
            
            guard let chat = message.chat else {
                return
            }
            
            if chat.isMuted() {
                return
            }
            
            if chat.willNotifyOnlyMentions() && !message.push {
                return
            }
            
            if chat.willNotifyOnlyMentions() {
                if !message.containsMention() {
                    return
                }
            }
            
            if let tribePubKey = chat.ownerPubkey, recentlyJoinedTribePubKeys.contains(tribePubKey) {
                return
            }
            
            appDelegate.sendNotification(message: message)
        }
    }
    
    func setAppBadgeCount() {
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            appDelegate.setBadge(count: TransactionMessage.getReceivedUnseenMessagesCount())
        }
    }
}
