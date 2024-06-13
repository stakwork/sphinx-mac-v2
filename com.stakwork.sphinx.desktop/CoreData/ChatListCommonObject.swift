//
//  ChatListCommonObject.swift
//  com.stakwork.sphinx.desktop
//
//  Created by Tomas Timinskas on 11/05/2020.
//  Copyright © 2020 Sphinx. All rights reserved.
//

import Cocoa

public protocol ChatListCommonObject: AnyObject {
    
    func isPending() -> Bool
    func isConfirmed() -> Bool
    
    func isConversation() -> Bool
    func isPublicGroup() -> Bool
    
    func getContactStatus() -> Int?
    func getInviteStatus() -> Int?
    
    func getObjectId() -> String
    func getOrderDate() -> Date?
    func getName() -> String
    func getChatContacts() -> [UserContact]
    func getPhotoUrl() -> String?
    func getColor() -> NSColor
    func shouldShowSingleImage() -> Bool
    
    func isEncrypted() -> Bool
    func subscribedToContact() -> Bool
    func isMuted() -> Bool
    func isSeen(ownerId: Int) -> Bool
    func getUnseenMessagesCount(ownerId: Int) -> Int
    
    func getChat() -> Chat?
    func getContact() -> UserContact?
    func getInvite() -> UserInvite?
    func isInvite() -> Bool
    
    var lastMessage : TransactionMessage? { get set }
    var unseenMessagesCount: Int { get set }
    
}
