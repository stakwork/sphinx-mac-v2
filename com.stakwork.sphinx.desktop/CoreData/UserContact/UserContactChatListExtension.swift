//
//  UserContactChatListExtension.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 02/07/2020.
//  Copyright © 2020 Sphinx. All rights reserved.
//

import Cocoa
import CoreData

extension UserContact : ChatListCommonObject {
    public func isConversation() -> Bool {
        return true
    }
    
    public func isPublicGroup() -> Bool {
        return false
    }
    
    public func getContactStatus() -> Int? {
        return status
    }
    
    public func getInviteStatus() -> Int? {
        if let invite = invite {
            if (invite.isPendingPayment() && invite.isPaymentProcessed()) {
                return UserInvite.Status.ProcessingPayment.rawValue
            }
            return invite.status
        }
        return nil
    }
    
    public func getObjectId() -> String {
        return "user-\(self.id)"
    }
    
    public func isMuted() -> Bool {
        return conversation?.isMuted() ?? false
    }
    
    public func isSeen(ownerId: Int) -> Bool {
        return self.getChat()?.isSeen(ownerId: ownerId) ?? true
    }
    
    public func getContactChat(
        context: NSManagedObjectContext? = nil
    ) -> Chat? {
        if conversation == nil {
            setContactConversation(context: context)
        }
        return conversation
    }
    
    public func getChat() -> Chat? {
        if conversation == nil {
            setContactConversation()
        }
        return conversation
    }
    
    public func getContact() -> UserContact? {
        return self
    }
    
    public func getInvite() -> UserInvite? {
        return self.invite
    }
    
    public func isInvite() -> Bool {
        return self.invite != nil || self.sentInviteCode != nil
    }
    
    public func getObjectId() -> Int {
        return self.id
    }
    
    public func getOrderDate() -> Date? {
        return lastMessage?.date ?? createdAt ?? Date()
    }
    
    public func getName() -> String {
        return getUserName()
    }
    
    func getUserName(forceNickname: Bool = false) -> String {
        if isOwner && !forceNickname {
            return "name.you".localized
        }
        if let nn = nickname, nn != "" {
            return nn
        }
        return "name.unknown".localized
    }
    
    public func getPhotoUrl() -> String? {
        return avatarUrl
    }
    
    public func getCachedImage() -> NSImage? {
        if let url = getPhotoUrl(), let cachedImage = MediaLoader.getImageFromCachedUrl(url: url) {
            return cachedImage
        }
        return nil
    }
    
    public func getChatContacts() -> [UserContact] {
        return [self]
    }
    
    public func getColor() -> NSColor {
        let key = "\(self.id)-color"
        return NSColor.getColorFor(key: key)
    }
    
    public func deleteColor() {
        let key = "\(self.id)-color"
        NSColor.removeColorFor(key: key)
    }
    
    public func shouldShowSingleImage() -> Bool {
        return true
    }
    
    public func isGroupObject() -> Bool {
        return false
    }
    
    public func getUnseenMessagesCount(
        ownerId: Int
    ) -> Int {
        if self.isSeen(ownerId: ownerId) == true {
            return 0
        }
        return self.getChat()?.getReceivedUnseenMessagesCount() ?? 0
    }
}
