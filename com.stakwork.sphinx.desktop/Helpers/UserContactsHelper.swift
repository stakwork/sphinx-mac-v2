//
//  UserContactsHelper.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 05/07/2023.
//  Copyright © 2023 Tomas Timinskas. All rights reserved.
//

import Foundation
import SwiftyJSON

class UserContactsHelper {
    
    public static func insertObjects(
        contacts: [JSON],
        chats: [JSON],
        subscriptions: [JSON],
        invites: [JSON]
    ) {
        CoreDataManager.sharedManager.persistentContainer.viewContext.performAndWait({
            self.insertContacts(contacts: contacts)
            self.insertChats(chats: chats)
            self.insertSubscriptions(subscriptions: subscriptions)
            self.insertInvites(invites: invites)
        })
        
        CoreDataManager.sharedManager.saveContext()
    }

    public static func insertContacts(
        contacts: [JSON]
    ) {
        if contacts.count > 0 {
            for contact: JSON in contacts {
                if let id = contact.getJSONId(), contact["deleted"].boolValue || contact["from_group"].boolValue {
                    if let contact = UserContact.getContactWith(id: id) {
                        CoreDataManager.sharedManager.deleteContactObjectsFor(contact)
                    }
                } else {
                    let _ = UserContact.insertContact(contact: contact)
                }
            }
        }
    }
    
    public static func insertContact(
        contact: JSON,
        pin: String? = nil
    ) -> UserContact? {
        let c = UserContact.insertContact(contact: contact)
        c?.pin = pin
        return c
    }
    
    public static func insertInvites(
        invites: [JSON]
    ) {
        if invites.count > 0 {
            
            for invite: JSON in invites {
                let _ = UserInvite.insertInvite(invite: invite)
            }
        }
    }
    
    public static func insertChats(
        chats: [JSON]
    ) {
        if chats.count > 0 {
            for chat: JSON in chats {
                if let id = chat.getJSONId(), chat["deleted"].boolValue {
                    if let chat = Chat.getChatWith(id: id) {
                        CoreDataManager.sharedManager.deleteChatObjectsFor(chat)
                    }
                } else {
                    if let chat = Chat.insertChat(chat: chat) {
                        if chat.seen {
                            chat.setChatMessagesAsSeen(shouldSync: false, shouldSave: false)
                        }
                    }
                }
            }
        }
    }
    
    public static func insertSubscriptions(
        subscriptions: [JSON]
    ) {
        if subscriptions.count > 0 {
            for subscription: JSON in subscriptions {
                let _ = Subscription.insertSubscription(subscription: subscription)
            }
        }
    }
    
    public static func createV2Contact(
        nickname: String,
        pubKey: String,
        routeHint: String,
        photoUrl: String? = nil,
        contactKey: String? = nil,
        callback: @escaping (Bool, UserContact?) -> ()
    ){
        let contactInfo = pubKey + "_" + routeHint
        
        SphinxOnionManager.sharedInstance.makeFriendRequest(
            contactInfo: contactInfo,
            nickname: nickname
        )
        
        var maxTicks = 20
        
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            if let successfulContact = UserContact.getContactWithDisregardStatus(pubkey: pubKey) {
                callback(true, successfulContact)
                timer.invalidate()
            } else if (maxTicks >= 0) {
                maxTicks -= 1
            } else {
                callback(false, nil)
                timer.invalidate()
            }
        }
    }
}
