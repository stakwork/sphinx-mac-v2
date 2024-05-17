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

extension SphinxOnionManager{//contacts related
    
    //MARK: Contact Add helpers
    func parseContactInfoString(
        fullContactInfo: String
    ) -> (String, String, String)? {
        let components = fullContactInfo.split(separator: "_").map({String($0)})
        return (components.count >= 3) ? (components[0],components[1],components[2]) : nil
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
              let selfContact = UserContact.getSelfContact() else
        {
            return
        }
        
        do {
            let _ = createNewContact(
                pubkey: recipientPubkey,
                nickname: nickname
            )
            
            var hexCode : String? = nil
            
            if let inviteCode = inviteCode {
                hexCode = try codeFromInvite(inviteQr: inviteCode)
            }
            
            let rr = try addContact(
                seed: seed,
                uniqueTime: getTimeWithEntropy(),
                state: loadOnionStateAsData(),
                toPubkey: recipientPubkey,
                routeHint: "\(recipLspPubkey)_\(scid)",
                myAlias: (selfContact.nickname ?? nickname) ?? "",
                myImg: selfContact.avatarUrl ?? "",
                amtMsat: 1000,
                inviteCode: hexCode,
                theirAlias: nickname
            )
            
            let _ = handleRunReturn(rr: rr)
            
            print("INITIATED KEY EXCHANGE WITH RR:\(rr)")
            
        } catch {}
    }
    
    //MARK: Processes key exchange messages (friend requests) between contacts
    func processKeyExchangeMessages(rr: RunReturn) {
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
                print(sender)
                
                let type = msg.type ?? 255
                
                if type == TransactionMessage.TransactionMessageType.contactKeyConfirmation.rawValue, 
                    let pubkey = csr.pubkey /// incoming key exchange confirmation
                {
                    /// if contact exists it's a key exchange response from them or it exists already
                    let keyExchangeContact = UserContact.getContactWithDisregardStatus(pubkey: senderPubkey) ?? createNewContact(pubkey: pubkey)
                    
                    guard let keyExchangeContact = keyExchangeContact else {
                        return
                    }
                    
                    keyExchangeContact.nickname = csr.alias
                    keyExchangeContact.avatarUrl = csr.photoUrl
                    keyExchangeContact.status = UserContact.Status.Confirmed.rawValue
                    
                    if keyExchangeContact.getChat() == nil {
                        createChat(for: keyExchangeContact)
                    }
                    
                    CoreDataManager.sharedManager.saveContext()
                    
                } else if type == TransactionMessage.TransactionMessageType.contactKey.rawValue, /// incoming key exchange request
                        UserContact.getContactWithDisregardStatus(pubkey: senderPubkey) == nil, ///don't respond to requests if already exists
                        let newContactRequest = createNewContact(
                            pubkey: senderPubkey,
                            nickname: csr.alias,
                            photoUrl: csr.photoUrl,
                            person: csr.person,
                            code: csr.code
                        )
                {
                    ///new contact from a key exchange message
                    newContactRequest.status = UserContact.Status.Confirmed.rawValue
                    createChat(for: newContactRequest)
                    managedContext.saveContext()
                }
            }
        }
        
    }
    
    //MARK: END Contact Add helpers
    
    
    //MARK: CoreData Helpers:
    func createSelfContact(
        scid: String,
        serverPubkey: String,
        myOkKey: String
    ){
        self.pendingContact = UserContact(context: managedContext)
        self.pendingContact?.scid = scid
        self.pendingContact?.isOwner = true
        self.pendingContact?.index = 0
        self.pendingContact?.id = 0
        self.pendingContact?.publicKey = myOkKey
        self.pendingContact?.routeHint = "\(serverPubkey)_\(scid)"
        self.pendingContact?.status = UserContact.Status.Confirmed.rawValue
        self.pendingContact?.createdAt = Date()
        self.pendingContact?.fromGroup = false
        self.pendingContact?.privatePhoto = false
        self.pendingContact?.tipAmount = 0
        managedContext.saveContext()
    }
    
    func createNewContact(
        pubkey: String,
        nickname: String? = nil,
        photoUrl: String? = nil,
        person: String? = nil,
        code: String? = nil
    ) -> UserContact? {
        let contact = UserContact.getContactWithInvitCode(inviteCode: code ?? "") ?? UserContact(context: managedContext)
        contact.id = uniqueIntHashFromString(stringInput: UUID().uuidString)
        contact.publicKey = pubkey//
        contact.isOwner = false//
        contact.nickname = nickname
        contact.createdAt = Date()
        contact.status = UserContact.Status.Pending.rawValue
        contact.createdAt = Date()
        contact.createdAt = Date()
        contact.fromGroup = false
        contact.privatePhoto = false
        contact.tipAmount = 0
        contact.avatarUrl = photoUrl
        
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
    
    func createChat(for contact: UserContact) {
        let contactID = NSNumber(value: contact.id)
        
        if let _ = Chat.getAll().filter({$0.contactIds.contains(contactID)}).first{
            return //don't make duplicates
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
        chat.createdAt = Date()
    }
    //MARK: END CoreData Helpers
}


//MARK: Helper Structs & Functions:

// Parsing Helper Struct
struct SphinxOnionBrokerResponse: Mappable {
    var scid: String?
    var serverPubkey: String?
    var myPubkey: String?

    init?(map: Map) {}

    mutating func mapping(map: Map) {
        scid <- map["scid"]
        serverPubkey <- map["server_pubkey"]
    }
}

enum SphinxMsgError: Error {
    case encodingError
    case credentialsError //can't get access to my Private Keys/other data!
    case contactDataError // not enough data about contact!
}


