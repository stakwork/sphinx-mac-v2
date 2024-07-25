//
//  SphinxOnionManager+ContactExtension.swift
//  sphinx
//
//  Created by James Carucci on 12/4/23.
//  Copyright © 2023 sphinx. All rights reserved.
//

import Foundation
import CocoaMQTT
import ObjectMapper
import SwiftyJSON

extension SphinxOnionManager {//contacts related
    
    //MARK: Contact Add helpers
    func parseContactInfoString(
        fullContactInfo: String
    ) -> (String, String, String)? {
        let components = fullContactInfo.split(separator: "_").map({String($0)})
        return (components.count >= 3) ? (components[0],components[1],components[2]) : nil
    }
    
    func deleteContactOrChatMsgsFor(
        contact: UserContact? = nil,
        chat: Chat? = nil
    ) -> Bool {
        guard let seed = getAccountSeed() else {
            return false
        }
        
        if let chat = chat ?? contact?.getChat(), (contact == nil || contact?.isConfirmed() == true) {
            
            let okKeyMessages = chat.getOkKeyMessages()
            let indexes = okKeyMessages.compactMap({ UInt64($0.id) })
            
            do {
                let rr = try Sphinx.deleteMsgs(
                    seed: seed,
                    uniqueTime: getTimeWithEntropy(),
                    state: loadOnionStateAsData(),
                    pubkey: nil,
                    msgIdxs: indexes
                )
                
                let _ = handleRunReturn(rr: rr)
            } catch {}
        }
        
        if let publicKey = contact?.publicKey ?? chat?.ownerPubkey {
            do {
                let rr = try Sphinx.deleteMsgs(
                    seed: seed,
                    uniqueTime: getTimeWithEntropy(),
                    state: loadOnionStateAsData(),
                    pubkey: publicKey,
                    msgIdxs: nil
                )
                
                let _ = handleRunReturn(rr: rr)
            } catch {}
        }
        
        return true
    }
    
    func makeFriendRequest(
        contactInfo: String,
        nickname: String? = nil,
        inviteCode: String? = nil
    ){
        guard let (recipientPubkey, recipLspPubkey, scid) = parseContactInfoString(fullContactInfo: contactInfo) else {
            return
        }
        if let existingContact = UserContact.getContactWithDisregardStatus(pubkey: recipientPubkey) {
            print("Error: Contact attempting to be created already exists: \(String(describing: existingContact.nickname))")
            return
        }
        
        guard let seed = getAccountSeed(),
              let selfContact = UserContact.getOwner() else
        {
            return
        }
        
        do {
            let _ = createNewContact(
                pubkey: recipientPubkey,
                nickname: nickname
            )
            
            let rr = try addContact(
                seed: seed,
                uniqueTime: getTimeWithEntropy(),
                state: loadOnionStateAsData(),
                toPubkey: recipientPubkey,
                routeHint: "\(recipLspPubkey)_\(scid)",
                myAlias: (selfContact.nickname ?? nickname) ?? "",
                myImg: selfContact.avatarUrl ?? "",
                amtMsat: 5000,
                inviteCode: inviteCode,
                theirAlias: nickname
            )
            
            let _ = handleRunReturn(rr: rr)
            
            print("INITIATED KEY EXCHANGE WITH RR:\(rr)")
            
        } catch {}
    }
    
    func retryAddingContact(
        contact: UserContact
    ){
        guard let pubkey = contact.publicKey, let routeHint = contact.routeHint else {
            return
        }
        
        guard let seed = getAccountSeed(),
              let selfContact = UserContact.getOwner() else
        {
            return
        }
        
        do {
            let rr = try addContact(
                seed: seed,
                uniqueTime: getTimeWithEntropy(),
                state: loadOnionStateAsData(),
                toPubkey: pubkey,
                routeHint: routeHint,
                myAlias: selfContact.nickname ?? "",
                myImg: selfContact.avatarUrl ?? "",
                amtMsat: 5000,
                inviteCode: nil,
                theirAlias: contact.nickname
            )
            
            let _ = handleRunReturn(rr: rr)
            
            print("INITIATED KEY EXCHANGE WITH RR:\(rr)")
            
        } catch {}
    }
    
    //MARK: Processes key exchange messages (friend requests) between contacts
    func processKeyExchangeMessages(rr: RunReturn) {
        if rr.msgs.isEmpty {
            return
        }
        
        print("MSG COUNT: \(rr.msgs.count)")
        
        let allowedTypes = [
            UInt8(TransactionMessage.TransactionMessageType.contactKey.rawValue),
            UInt8(TransactionMessage.TransactionMessageType.contactKeyConfirmation.rawValue)
        ]
        
        for msg in rr.msgs.filter({ $0.type != nil && allowedTypes.contains($0.type!) }) {
            
            print("KEY EXCHANGE MSG of Type \(String(describing: msg.type)) RECEIVED:\(msg)")
            
            if let sender = msg.sender,
               let csr = ContactServerResponse(JSONString: sender),
               let senderPubkey = csr.pubkey
            {
                let routeHint: String? = msg.message?.toMessageInnerContent()?.getRouteHint()
                
                if let contact = UserContact.getContactWithDisregardStatus(pubkey: senderPubkey) {
                    if contact.isOwner {
                        continue
                    }
                    
                    if let routeHint = csr.routeHint {
                        contact.routeHint = routeHint
                    }
                    contact.status = UserContact.Status.Confirmed.rawValue
                    
                    updateContactInfoFromMessage(
                        contact: contact,
                        alias: csr.alias,
                        photoUrl: csr.photoUrl,
                        pubkey: senderPubkey
                    )
                    
                    ///Create chat for contact and save
                    if contact.getChat() == nil {
                        let _ = createChat(for: contact, with: msg.date)
                    }
                    
                    continue
                }
                
                let newContactRequest = createNewContact(
                    pubkey: senderPubkey,
                    routeHint: routeHint,
                    nickname: csr.alias,
                    photoUrl: csr.photoUrl,
                    code: csr.code,
                    status: UserContact.Status.Confirmed.rawValue,
                    date: msg.date
                )
                
                ///Create chat for contacts and save
                if newContactRequest.getChat() == nil {
                    let _ = createChat(for: newContactRequest, with: msg.date)
                }
                
                createKeyExchangeMsgFrom(msg: msg)
            }
        }
        
        managedContext.saveContext()
        
    }
    
    //MARK: END Contact Add helpers
    
    
    //MARK: CoreData Helpers:
    func createSelfContact(
        scid: String,
        serverPubkey: String,
        myOkKey: String
    ) -> UserContact {
        let contact = UserContact(context: managedContext)
        contact.scid = scid
        contact.isOwner = true
        contact.index = 0
        contact.id = 0
        contact.publicKey = myOkKey
        contact.routeHint = "\(serverPubkey)_\(scid)"
        contact.status = UserContact.Status.Confirmed.rawValue
        contact.createdAt = Date()
        contact.fromGroup = false
        contact.privatePhoto = false
        contact.tipAmount = 0
        return contact
    }
    
    func createNewContact(
        pubkey: String,
        routeHint: String? = nil,
        nickname: String? = nil,
        photoUrl: String? = nil,
        code: String? = nil,
        status: Int? = nil,
        date: Date? = nil
    ) -> UserContact {
        let contact = UserContact.getContactWithInviteCode(inviteCode: code ?? "") ?? UserContact(context: managedContext)
        contact.id = uniqueIntHashFromString(stringInput: UUID().uuidString)
        contact.publicKey = pubkey
        contact.routeHint = routeHint
        contact.isOwner = false
        contact.nickname = nickname
        contact.createdAt = date ?? Date()
        contact.fromGroup = false
        contact.privatePhoto = false
        contact.tipAmount = 0
        contact.avatarUrl = photoUrl
        contact.status = status ?? UserContact.Status.Pending.rawValue
        
        return contact
    }
    
    func findChatForNotification(child: String) -> Chat? {
        guard let seed = getAccountSeed() else {
            return nil
        }
        do {
            let pubkey = try contactPubkeyByEncryptedChild(
                seed: seed,
                state: loadOnionStateAsData(),
                child: child
            )
            let chat = Chat.getTribeChatWithOwnerPubkey(ownerPubkey: pubkey) ?? UserContact.getContactWithDisregardStatus(pubkey: pubkey)?.getChat()
            return chat
        } catch {
            return nil
        }
    }
    
    func createChat(
        for contact: UserContact,
        with date: Date? = nil
    ) -> Chat? {
        let contactID = NSNumber(value: contact.id)
        
        if let _ = Chat.getAll().filter({$0.contactIds.contains(contactID)}).first {
            return nil //don't make duplicates
        }
        
        if contact.isOwner {
            return nil
        }
        
        let selfContactId =  0
        let chat = Chat(context: managedContext)
        let contactIDArray = [contactID,NSNumber(value: selfContactId)]
        chat.id = contact.id
        chat.type = Chat.ChatType.conversation.rawValue
        chat.status = Chat.ChatStatus.approved.rawValue
        chat.seen = false
        chat.muted = false
        chat.unlisted = false
        chat.privateTribe = false
        chat.notify = Chat.NotificationLevel.SeeAll.rawValue
        chat.contactIds = contactIDArray
        chat.name = contact.nickname
        chat.photoUrl = contact.avatarUrl
        chat.createdAt = date ?? Date()
        
        return chat
    }
    
    func requiresManualRouting(
        publicKey: String,
        routeHint: String? = nil
    ) -> Bool {
        guard let myLSPPubkey = UserContact.getOwner()?.routeHint?.split(separator: "_")[0] else {
            return true
        }
        
        if let routeHint = routeHint, routeHint.split(separator: "_").count > 0 {
            let routeHintLSPPubkey = routeHint.split(separator: "_")[0]
            return myLSPPubkey != routeHintLSPPubkey
        }
        
        guard let contact = publicKey.isExistingContactPubkey().1 else {
            ///requires routing if it's not a contact in our db
            return true
        }
        
        guard let contactLSPPubkey = contact.routeHint?.split(separator: "_")[0] else {
            return true
        }
        
        ///require routing if we're not on the same LSP
        return myLSPPubkey != contactLSPPubkey
    }
}


