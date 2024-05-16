//
//  SphinxOnionManager+ChatExtension.swift
//  sphinx
//
//  Created by James Carucci on 12/4/23.
//  Copyright © 2023 sphinx. All rights reserved.
//

import Foundation
import CocoaMQTT
import SwiftyJSON

extension SphinxOnionManager{
    
    func getChatWithTribeOrContactPubkey(
        contactPubkey: String?,
        tribePubkey: String?
    ) -> Chat? {
        if let contact = UserContact.getContactWithDisregardStatus(pubkey: contactPubkey ?? ""), let oneOnOneChat = contact.getChat() {
            return oneOnOneChat
        } else if let tribeChat = Chat.getTribeChatWithOwnerPubkey(ownerPubkey: tribePubkey ?? "") {
            return tribeChat
        }
        return nil
    }
    
    func fetchOrCreateChatWithTribe(
        ownerPubkey: String,
        host: String?,
        completion: @escaping (Chat?,Bool) -> ()
    ) {
        // First try to fetch the chat from the database.
        if let chat = Chat.getTribeChatWithOwnerPubkey(ownerPubkey: ownerPubkey) {
            completion(chat,false)
        } else if let host = host {
            // If not found in the database, attempt to lookup and restore.
            GroupsManager.sharedInstance.lookupAndRestoreTribe(pubkey: ownerPubkey, host: host) { chat in
                completion(chat,true)
            }
        } else {
            completion(nil, false)
        }
    }

    
    func loadMediaToken(
        recipPubkey: String?,
        muid: String?
    ) -> String? {
        guard let seed = getAccountSeed(), let recipPubkey = recipPubkey, let muid = muid, let expiry = Calendar.current.date(byAdding: .year, value: 1, to: Date()) else {
            return nil
        }
        do {
            let mt = try makeMediaToken(
                seed: seed,
                uniqueTime: getTimeWithEntropy(),
                state: loadOnionStateAsData(),
                host: "memes.sphinx.chat",
                muid: muid,
                to: recipPubkey,
                expiry: UInt32(expiry.timeIntervalSince1970)
            )
            return mt
        } catch {
            return nil
        }
    }
    
    func formatMsg(
        content: String,
        type: UInt8,
        muid: String? = nil,
        recipPubkey: String? = nil,
        mediaKey: String? = nil,
        mediaType: String? = "file",
        threadUUID: String?,
        replyUUID: String?,
        invoiceString: String?,
        tribeKickMember: String? = nil
    ) -> (String?, String?)? {
        
        var msg: [String: Any] = ["content": content]
        var mt: String? = nil

        switch TransactionMessage.TransactionMessageType(rawValue: Int(type)) {
        case .message, .boost, .delete, .call, .groupLeave, .memberReject, .memberApprove,.groupDelete:
            break
        case .attachment, .directPayment, .purchase:
            mt = loadMediaToken(recipPubkey: recipPubkey, muid: muid)
            msg["mediaToken"] = mt
            msg["mediaKey"] = mediaKey
            msg["mediaType"] = mediaType
            
            if type == UInt8(TransactionMessage.TransactionMessageType.purchase.rawValue) {
                msg["content"] = ""
            }
            break
        case .invoice, .payment:
            msg["invoice"] = invoiceString
            break
        case .groupKick:
            if let member = tribeKickMember {
                msg["member"] = member
            } else {
                return nil
            }
            break
        default:
            return nil
        }
        
        replyUUID != nil ? (msg["replyUuid"] = replyUUID) : ()
        threadUUID != nil ? (msg["threadUuid"] = threadUUID) : ()
            
        guard let contentData = try? JSONSerialization.data(withJSONObject: msg), let contentJSONString = String(data: contentData, encoding: .utf8) else {
            return nil
        }
        
        return (contentJSONString, mt)
    }
    
    func sendMessage(
        to recipContact: UserContact?,
        content: String,
        chat: Chat,
        provisionalMessage: TransactionMessage?,
        amount:Int = 0,
        shouldSendAsKeysend: Bool = false,
        msgType: UInt8 = 0,
        muid: String? = nil,
        recipPubkey: String? = nil,
        mediaKey: String? = nil,
        mediaType: String? = nil,
        threadUUID: String?,
        replyUUID: String?,
        invoiceString: String? = nil,
        tribeKickMember: String? = nil
    ) -> TransactionMessage? {
        
        guard let seed = getAccountSeed() else {
            return nil
        }
//        let sendAmount = chat.isConversation() ? amount : max(1, amount)  //send keysends to group
        
        guard let (contentJSONString, mediaToken) = formatMsg(
            content: content,
            type: msgType,
            muid: muid,
            recipPubkey: recipPubkey,
            mediaKey: mediaKey,
            mediaType: mediaType,
            threadUUID: threadUUID,
            replyUUID: replyUUID,
            invoiceString: invoiceString,
            tribeKickMember: tribeKickMember
        ) else {
            return nil
        }
        
        guard let selfContact = UserContact.getSelfContact(),
              let nickname = selfContact.nickname ?? chat.name,
              let recipPubkey = (recipContact?.publicKey ?? chat.ownerPubkey),
              let contentJSONString = contentJSONString else {
            return nil
        }
        
        let myImg = selfContact.avatarUrl ?? ""
        
        do {
            
            let isTribe = recipContact == nil
            let escrowAmountSats = max(Int(truncating: chat.escrowAmount ?? 3), tribeMinEscrowSats)
            let amtMsat = (isTribe && amount == 0) ? UInt64(((Int(truncating: (chat.pricePerMessage ?? 0)) + escrowAmountSats) * 1000)) : UInt64((amount * 1000))
            
            print("sendMessage args seed: \(seed), uniqueTime: \(getTimeWithEntropy()), to: \(recipPubkey), msgType: \(msgType), msgJson: \(contentJSONString), state: \(String(describing: loadOnionStateAsData())), myAlias: \(nickname), myImg: \(String(describing: myImg)), amtMsat: \(UInt64(amtMsat)), isTribe: \(String(describing: recipContact == nil))")
            
            let rr = try Sphinx.send(
                seed: seed,
                uniqueTime: getTimeWithEntropy(),
                to: recipPubkey,
                msgType: msgType,
                msgJson: contentJSONString,
                state: loadOnionStateAsData(),
                myAlias: nickname,
                myImg: myImg,
                amtMsat: amtMsat,
                isTribe: isTribe
            )
            
            let sentMessage = processNewOutgoingMessage(
                rr: rr,
                chat: chat,
                provisionalMessage: provisionalMessage,
                msgType: msgType,
                content: content,
                amount: amount,
                mediaKey: mediaKey,
                mediaToken: mediaToken,
                mediaType: mediaType,
                replyUUID: replyUUID,
                threadUUID: threadUUID,
                invoiceString: invoiceString
            )
            
            let tag = handleRunReturn(
                rr: rr,
                isMessageSend: true
            )
            
            if let tag = tag, let sentMessage = sentMessage {
                sentMessage.tag = tag
                
                // Invalidate existing timer for this tag if it exists
                messageTimers[tag]?.invalidate()
               
                // Create and store a new timer for the message
                messageTimers[tag] = Timer.scheduledTimer(timeInterval: 10.0,
                    target: self,
                    selector: #selector(handleMessageTimerTimeout(_:)),
                    userInfo: ["tag": tag],
                    repeats: false
                )
                
                assignReceiverId(localMsg: sentMessage)
            }
            return sentMessage
        } catch let error {
            print("error sending msg \(error.localizedDescription)")
            return nil
        }
    }
    
    @objc func handleMessageTimerTimeout(
        _ timer: Timer
    ) {
        if let userInfo = timer.userInfo as? [String: Any],
           let tag = userInfo["tag"] as? String,
           let cachedMessage = TransactionMessage.getMessageWith(tag: tag),
           cachedMessage.status != TransactionMessage.TransactionMessageStatus.received.rawValue
        {
            // Logic to handle timeout, now having access to the message tag
            print("Watchdog timer fired: Message with tag \(tag) sending timeout")
            // Invalidate timer
            cachedMessage.status = TransactionMessage.TransactionMessageStatus.failed.rawValue
            messageTimers.removeValue(forKey: tag)
        }
        timer.invalidate()
    }
    
    func processNewOutgoingMessage(
        rr: RunReturn,
        chat: Chat,
        provisionalMessage: TransactionMessage?,
        msgType: UInt8,
        content: String,
        amount: Int,
        mediaKey: String?,
        mediaToken: String?,
        mediaType: String?,
        replyUUID: String?,
        threadUUID: String?,
        invoiceString: String?
    ) -> TransactionMessage? {
        
        for msg in rr.msgs {
            if let sentUUID = msg.uuid, msgType != TransactionMessage.TransactionMessageType.delete.rawValue {
                let date = Date()
                let message  = provisionalMessage ?? TransactionMessage.createProvisionalMessage(
                    messageContent: content,
                    type: Int(msgType),
                    date: date,
                    chat: chat,
                    replyUUID: replyUUID,
                    threadUUID: threadUUID
                )
                
                if msgType == TransactionMessage.TransactionMessageType.boost.rawValue || 
                   msgType == TransactionMessage.TransactionMessageType.directPayment.rawValue
                {
                    message?.amount = NSDecimalNumber(value: amount)
                    message?.mediaKey = mediaKey
                    message?.mediaToken = mediaToken
                    message?.mediaType = mediaType
                } else if msgType == TransactionMessage.TransactionMessageType.purchase.rawValue || 
                          msgType == TransactionMessage.TransactionMessageType.attachment.rawValue
                {
                    message?.mediaKey = mediaKey
                    message?.mediaToken = mediaToken
                    message?.mediaType = mediaType
                } else if msgType == TransactionMessage.TransactionMessageType.invoice.rawValue {
                    guard let invoiceString = invoiceString else { return nil}
                    
                    let prd = PaymentRequestDecoder()
                    prd.decodePaymentRequest(paymentRequest: invoiceString)
                    
                    guard let paymentHash = try? paymentHashFromInvoice(bolt11: invoiceString),
                          let expiry = prd.getExpirationDate(),
                          let amount = prd.getAmount() else 
                    {
                        return nil
                    }
                    
                    message?.paymentHash = paymentHash
                    message?.invoice = invoiceString
                    message?.amount = NSDecimalNumber(value: amount)
                    message?.expirationDate = expiry
                }

                
                message?.createdAt = date
                message?.updatedAt = date
                message?.uuid = sentUUID
                message?.id = uniqueIntHashFromString(stringInput: UUID().uuidString)
                message?.setAsLastMessage()
                message?.managedObjectContext?.saveContext()
                return message
            } else if let replyUUID = replyUUID, msgType == TransactionMessage.TransactionMessageType.delete.rawValue, let messageToDelete = TransactionMessage.getMessageWith(uuid: replyUUID)
            {
                messageToDelete.status = TransactionMessage.TransactionMessageStatus.deleted.rawValue
                messageToDelete.setAsLastMessage()
                messageToDelete.managedObjectContext?.saveContext()
                return messageToDelete
            }
        }
        return nil
    }
    
    func finalizeSentMessage(
        localMsg: TransactionMessage,
        remoteMsg: Msg
    ){
        let remoteMessageAsGenericMessage = GenericIncomingMessage(msg: remoteMsg)
        
        if let contentTimestamp = remoteMessageAsGenericMessage.timestamp {
            let date = timestampToDate(timestamp: UInt64(contentTimestamp))
            localMsg.date = date
            localMsg.updatedAt = Date()
        } else if let timestamp = remoteMsg.timestamp {
            let date = timestampToDate(timestamp: timestamp) ?? Date()
            localMsg.date = date
            localMsg.updatedAt = Date()
        }
        
        if let type = remoteMsg.type,
           type == TransactionMessage.TransactionMessageType.memberApprove.rawValue,
           let ruuid = localMsg.replyUUID,
           let messageWeAreReplying = TransactionMessage.getMessageWith(uuid: ruuid)
        {
            localMsg.senderAlias = messageWeAreReplying.senderAlias
        } else if let owner = UserContact.getOwner() {
            localMsg.senderAlias = owner.nickname
            localMsg.senderPic = owner.avatarUrl
        }
        localMsg.senderId = UserData.sharedInstance.getUserId()
        assignReceiverId(localMsg: localMsg)
        localMsg.managedObjectContext?.saveContext()
    }
    
    func assignReceiverId(localMsg: TransactionMessage) {
        var receiverId :Int = -1
        
        if let contact = localMsg.chat?.getContact(){
            receiverId = contact.id
        } else if localMsg.type == 29,
            let replyUUID = localMsg.replyUUID,
            let replyMsg = TransactionMessage.getMessageWith(uuid: replyUUID)
        {
            receiverId = replyMsg.senderId
        }
        localMsg.receiverId = receiverId
    }
    
    func isMessageTribeMessage(
        senderPubkey: String
    ) -> Bool {
        
        var isTribe = false
        
        if let _ = Chat.getTribeChatWithOwnerPubkey(ownerPubkey: senderPubkey){
            isTribe = true
        }
        
        return isTribe
    }
    
    //MARK: processes updates from general purpose messages like plaintext and attachments
    func processGenericMessages(rr: RunReturn) {
        
        let filteredMsgs = rr.msgs.filter({ $0.type != 11 && $0.type != 10 })
        
        if filteredMsgs.count <= 0 {return}
        
        for message in filteredMsgs {
            
            var genericIncomingMessage = GenericIncomingMessage(msg: message)
            
            if Int(message.type ?? 0) == TransactionMessage.TransactionMessageType.unknown.rawValue {
                ///Message to restore contact info
                
                if let sender = message.sender,
                   let csr =  ContactServerResponse(JSONString: sender),
                   let recipientPubkey = csr.pubkey,
                    UserContact.getContactWithDisregardStatus(pubkey: recipientPubkey) == nil
                {
                    let pendingContact = createNewContact(
                        pubkey: recipientPubkey,
                        nickname: genericIncomingMessage.alias ?? "Unknown",
                        photoUrl: genericIncomingMessage.photoUrl
                    )
                    
                    pendingContact?.status = UserContact.Status.Pending.rawValue
                }
                
                firstSCIDMsgsCallback?()
                
            } else if let omuuid = genericIncomingMessage.originalUuid,//update uuid if it's changing/
                      let newUUID = message.uuid,
                      let originalMessage = TransactionMessage.getMessageWith(uuid: omuuid)
            {
                originalMessage.uuid = newUUID
                
                if (originalMessage.status == (TransactionMessage.TransactionMessageStatus.deleted.rawValue)){
                    originalMessage.status = TransactionMessage.TransactionMessageStatus.deleted.rawValue
                }
                
                finalizeSentMessage(localMsg: originalMessage, remoteMsg: message)
           } else if let fromMe = message.fromMe,
                    fromMe == true,
                    let _ = message.sentTo,
                    let uuid = message.uuid,
                    TransactionMessage.getMessageWith(uuid: uuid) == nil,
                    let type = message.type,
                    let localMsg = processGenericIncomingMessage(
                        message: genericIncomingMessage,
                        date: Date(),
                        delaySave: true,
                        type: Int(type),
                        fromMe: true
                    )
            {
                localMsg.uuid = uuid
               
                if let genericMessageMsat = genericIncomingMessage.amount{
                    localMsg.amount = NSDecimalNumber(value:  genericMessageMsat/1000)
                    localMsg.amountMsat = NSDecimalNumber(value: Int(truncating: (genericMessageMsat) as NSNumber))
                }
                
                finalizeSentMessage(localMsg: localMsg, remoteMsg: message)
            } else if let uuid = message.uuid, TransactionMessage.getMessageWith(uuid: uuid) == nil { // guarantee it is a new message
                if let type = message.type,
                   let sender = message.sender,
                   let uuid = message.uuid,
                   let index = message.index,
                   let timestamp = message.timestamp,
                   let date = timestampToDate(timestamp: timestamp),
                   let csr = ContactServerResponse(JSONString: sender)
                {
                    if type == TransactionMessage.TransactionMessageType.message.rawValue
                        || type == TransactionMessage.TransactionMessageType.call.rawValue
                        || type == TransactionMessage.TransactionMessageType.attachment.rawValue
                    {
                        genericIncomingMessage.senderPubkey = csr.pubkey
                        genericIncomingMessage.uuid = uuid
                        genericIncomingMessage.index = index
                        let _ = processGenericIncomingMessage(
                            message: genericIncomingMessage,
                            date: date,
                            csr: csr,
                            type: Int(type)
                        )
                    } else if type == TransactionMessage.TransactionMessageType.boost.rawValue ||
                        type == TransactionMessage.TransactionMessageType.directPayment.rawValue ||
                        type == TransactionMessage.TransactionMessageType.payment.rawValue,
                        let index = message.index,
                        let uuid = message.uuid
                    {
                        let msats = message.msat ?? 0
                        genericIncomingMessage.senderPubkey = csr.pubkey
                        genericIncomingMessage.uuid = uuid
                        genericIncomingMessage.index = index
                        let _ = processIncomingPayment(
                            message: genericIncomingMessage,
                            date: date,
                            csr: csr,
                            amount: Int(msats/1000),
                            type: Int(type)
                        )
                    } else if type == TransactionMessage.TransactionMessageType.delete.rawValue {
                        processIncomingDeletion(message: genericIncomingMessage, date: date)
                    } else if isGroupAction(type: type), let tribePubkey = csr.pubkey {
                        ///Restoring tribe
                        fetchOrCreateChatWithTribe(
                            ownerPubkey: tribePubkey,
                            host: csr.host,
                            completion: { chat,didCreateTribe  in
                                if let chat = chat {
                                    let groupActionMessage = TransactionMessage(context: self.managedContext)
                                    groupActionMessage.uuid = uuid
                                    groupActionMessage.id = Int(index) ?? self.uniqueIntHashFromString(stringInput: UUID().uuidString)
                                    groupActionMessage.chat = chat
                                    groupActionMessage.type = Int(type)
                                    groupActionMessage.setAsLastMessage()
                                    groupActionMessage.senderAlias = csr.alias
                                    groupActionMessage.senderPic = csr.photoUrl
                                    groupActionMessage.createdAt = date
                                    groupActionMessage.date = date
                                    groupActionMessage.updatedAt = date
                                    groupActionMessage.seen = false
                                    chat.seen = false
                                
                                    if (didCreateTribe && csr.role != nil) {
                                        chat.isTribeICreated = csr.role == 0
                                    }
                                    if (type == TransactionMessage.TransactionMessageType.memberApprove.rawValue) {
                                        chat.status = Chat.ChatStatus.approved.rawValue
                                    }
                                    if (type == TransactionMessage.TransactionMessageType.memberReject.rawValue) {
                                        chat.status = Chat.ChatStatus.rejected.rawValue
                                    }
                                    self.finalizeNewMessage(index: groupActionMessage.id, newMessage: groupActionMessage)
                                }
                            }
                        )
                    } else if type == TransactionMessage.TransactionMessageType.invoice.rawValue,
                            let invoice = genericIncomingMessage.invoice
                    {
                        genericIncomingMessage.senderPubkey = csr.pubkey
                        genericIncomingMessage.uuid = uuid
                        genericIncomingMessage.index = index
                        
                        let prd = PaymentRequestDecoder()
                        prd.decodePaymentRequest(paymentRequest: invoice)
                        
                        if let expiry = prd.getExpirationDate(),
                            let amount = prd.getAmount(),
                            let paymentHash = try? paymentHashFromInvoice(bolt11: invoice),
                            let newMessage = processGenericIncomingMessage(
                                message: genericIncomingMessage,
                                date: date,
                                csr: csr,
                                amount: amount,
                                type: Int(type)
                            )
                        {
                            newMessage.paymentHash = paymentHash
                            newMessage.expirationDate = expiry
                            newMessage.invoice = genericIncomingMessage.invoice
                            newMessage.amountMsat = NSDecimalNumber(value: Int(truncating: newMessage.amount ?? 0) * 1000)
                            newMessage.status = TransactionMessage.TransactionMessageStatus.pending.rawValue
                            finalizeNewMessage(index: newMessage.id, newMessage: newMessage)
                        }
                        
                    }
                    print("handleRunReturn message: \(message)")
                }
            } else if isMyMessageNeedingIndexUpdate(msg: message),
                let uuid = message.uuid,
                let cachedMessage = TransactionMessage.getMessageWith(uuid: uuid),
                let indexString = message.index,
                let index = Int(indexString)
            { //updates index of sent message
                cachedMessage.id = index //sync self index
                cachedMessage.updatedAt = Date()
                finalizeNewMessage(index: index, newMessage: cachedMessage)
            }
            
            onMessageRestoredCallback?()
        }
    }
    
    func processGenericIncomingMessage(
        message: GenericIncomingMessage,
        date: Date,
        csr: ContactServerResponse?=nil ,
        amount: Int = 0,
        delaySave: Bool = false,
        type: Int? = nil,
        fromMe: Bool = false
    ) -> TransactionMessage? {
        let content = (type == TransactionMessage.TransactionMessageType.boost.rawValue) ? ("") : (message.content)
        guard let indexString = message.index,
            let index = Int(indexString),
            TransactionMessage.getMessageWith(id: index) == nil,
             //let content = content,
              //let amount = message.amount,
            let pubkey = message.senderPubkey,
            let uuid = message.uuid else
        {
            return nil
        }
        
        var chat : Chat? = nil
        var senderId: Int? = nil
        //var senderAlias : String? = nil
        var isTribe = false
        
        if let contact = UserContact.getContactWithDisregardStatus(pubkey: pubkey), let oneOnOneChat = contact.getChat() {
            chat = oneOnOneChat
            
            senderId = (fromMe == true) ? (UserData.sharedInstance.getUserId()) : contact.id
            
            var contactDidChange = false
            if (contact.nickname != message.alias && message.alias != nil) {
                contact.nickname = message.alias
                contactDidChange = true
            }
            if (contact.avatarUrl != message.photoUrl) {
                contact.avatarUrl = message.photoUrl
                contactDidChange = true
            }
            contactDidChange ? (contact.managedObjectContext?.saveContext()) :()
        } else if let tribeChat = Chat.getTribeChatWithOwnerPubkey(ownerPubkey: pubkey) {
            chat = tribeChat
            senderId = tribeChat.id
            isTribe = true
        }
        
        guard let chat = chat,
              let senderId = senderId else
        {
            return nil //error extracting proper chat data
        }
        
        let newMessage = TransactionMessage(context: managedContext)
        
        newMessage.id = index
        newMessage.uuid = uuid
        
        if let timestamp = message.timestamp,
           let dateFromMessage = timestampToDate(timestamp: UInt64(timestamp))
        {
            newMessage.createdAt = dateFromMessage
            newMessage.updatedAt = dateFromMessage
            newMessage.date = dateFromMessage
        } else {
            newMessage.createdAt = date
            newMessage.updatedAt = date
            newMessage.date = date
        }
        newMessage.status = TransactionMessage.TransactionMessageStatus.confirmed.rawValue
        newMessage.type = type ?? TransactionMessage.TransactionMessageType.message.rawValue
        newMessage.encrypted = true
        newMessage.senderId = senderId
        newMessage.receiverId = UserContact.getSelfContact()?.id ?? 0
        newMessage.push = false
        newMessage.chat = chat
        newMessage.seen = false
        newMessage.chat?.seen = false
        newMessage.messageContent = content
        newMessage.replyUUID = message.replyUuid
        newMessage.threadUUID = message.threadUuid
        newMessage.senderAlias = csr?.alias
        newMessage.senderPic = csr?.photoUrl
        newMessage.mediaKey = message.mediaKey
        newMessage.mediaType = message.mediaType
        newMessage.mediaToken = message.mediaToken
        newMessage.paymentHash = message.paymentHash
        
        if (type == TransactionMessage.TransactionMessageType.boost.rawValue && isTribe == true), let msgAmount = message.amount {
            newMessage.amount = NSDecimalNumber(value: msgAmount/1000)
            newMessage.amountMsat = NSDecimalNumber(value: msgAmount)
        } else {
            newMessage.amount = NSDecimalNumber(value: amount)
            newMessage.amountMsat = NSDecimalNumber(value: amount * 1000)
        }
        
        if type == TransactionMessage.TransactionMessageType.payment.rawValue,
           let ph = message.paymentHash,
           let _ = TransactionMessage.getInvoiceWith(paymentHash: ph)
        {
            newMessage.setPaymentInvoiceAsPaid()
        }
        
        if (delaySave == false) {
            finalizeNewMessage(index: index, newMessage: newMessage)
        }
        
        assignReceiverId(localMsg: newMessage)
        
        newMessage.setAsLastMessage()
        
        return newMessage
    }
    
    func updateIsPaidAllMessages() {
        let msgs = TransactionMessage.getAll().filter({$0.type == TransactionMessage.TransactionMessageType.payment.rawValue})
        for msg in msgs{
            if let ph = msg.paymentHash,
               let _ = TransactionMessage.getInvoiceWith(paymentHash: ph){
                msg.setPaymentInvoiceAsPaid()
            }
        }
    }
    
    func finalizeNewMessage(index: Int, newMessage: TransactionMessage) {
        managedContext.saveContext()
        UserData.sharedInstance.setLastMessageIndex(index: index)
    }
    
    func processIncomingPayment(
        message: GenericIncomingMessage,
        date: Date,
        csr: ContactServerResponse? = nil,
        amount: Int,
        type: Int
    ){
        let _ = processGenericIncomingMessage(
            message: message,
            date: date,
            csr: csr,
            amount: amount,
            type: type
        )
    }
    
    func processIncomingDeletion(message: GenericIncomingMessage, date: Date){
        if let messageToDeleteUUID = message.replyUuid,
           let messageToDelete = TransactionMessage.getMessageWith(uuid: messageToDeleteUUID) {
            messageToDelete.status = TransactionMessage.TransactionMessageStatus.deleted.rawValue
            if let context = messageToDelete.managedObjectContext {
                context.saveContext()
            }
        }
    }
    

    func signChallenge(challenge: String) -> String? {
        guard let seed = self.getAccountSeed() else {
            return nil
        }
        do {
            guard let challengeData = Data(base64Encoded: challenge) else {
                return nil
            }
            
            let resultHex = try signBytes(
                seed: seed,
                idx: 0,
                time: getTimeWithEntropy(),
                network: network,
                msg: challengeData
            )
            
            // Convert the hex string to binary data
            if let resultData = Data(hexString: resultHex) {
                let base64URLString = resultData.base64EncodedString(options: .init(rawValue: 0))
                    .replacingOccurrences(of: "/", with: "_")
                    .replacingOccurrences(of: "+", with: "-")
                
                return base64URLString
            } else {
                // Handle the case where hex to data conversion failed
                return nil
            }
        } catch {
            return nil
        }
    }
    

    func sendAttachment(
        file: NSDictionary,
        attachmentObject: AttachmentObject,
        chat: Chat?,
        provisionalMessage: TransactionMessage? = nil,
        replyingMessage: TransactionMessage? = nil,
        threadUUID: String? = nil
    ) -> TransactionMessage? {
        
        guard let muid = file["muid"] as? String,
            let chat = chat,
            let mk = attachmentObject.mediaKey,
            let destinationPubkey = getDestinationPubkey(for: chat) else
        {
            return nil
        }
        
        let (_, mediaType) = attachmentObject.getFileAndMime()
        
        //Create JSON object and push through onion network
        var recipContact : UserContact? = nil
        
        if let contact = chat.getContact() {
            recipContact = contact
        }
        
        let type = (attachmentObject.paidMessage != nil) ? (TransactionMessage.TransactionMessageType.purchase.rawValue) : (TransactionMessage.TransactionMessageType.attachment.rawValue)
        
        if let sentMessage = sendMessage(
            to: recipContact,
            content: attachmentObject.text ?? "",
            chat: chat,
            provisionalMessage: provisionalMessage,
            msgType: UInt8(type),
            muid: muid,
            recipPubkey: destinationPubkey,
            mediaKey: mk,
            mediaType: mediaType,
            threadUUID:threadUUID,
            replyUUID: replyingMessage?.uuid
        ){
            if (type == TransactionMessage.TransactionMessageType.attachment.rawValue) {
                AttachmentsManager.sharedInstance.cacheImageAndMediaData(message: sentMessage, attachmentObject: attachmentObject)
            } else if (type == TransactionMessage.TransactionMessageType.purchase.rawValue) {
                print(sentMessage)
            }
            
            return sentMessage
        }
        
        return nil
    }
    
    //MARK: Payments related
    func sendBoostReply(
        params: [String: AnyObject],
        chat:Chat
    ) -> TransactionMessage? {
        let contact = chat.getContact()
        
        guard let replyUUID = params["reply_uuid"] as? String,
        let text = params["text"] as? String,
        let amount = params["amount"] as? Int else{
            return nil
        }
        if let sentMessage = self.sendMessage(
            to: contact,
            content: text,
            chat: chat,
            provisionalMessage: nil,
            amount: amount,
            msgType: UInt8(TransactionMessage.TransactionMessageType.boost.rawValue),
            threadUUID: nil,
            replyUUID: replyUUID
        ){
            print(sentMessage)
            return sentMessage
        }
        return nil
    }
    
    func sendDirectPaymentMessage(
        params: [String: Any],
        chat: Chat,
        completion: @escaping (Bool, TransactionMessage?) -> ()
    ){
        let muid = params["muid"] as? String
        
        guard let contact = chat.getContact(), let amount = params["amount"] as? Int else {
            return
        }
        
        if let sentMessage = self.sendMessage(
            to: contact, 
            content: "",
            chat: chat,
            provisionalMessage: nil,
            amount: amount,
            msgType: UInt8(TransactionMessage.TransactionMessageType.directPayment.rawValue),
            muid: muid,
            threadUUID: nil,
            replyUUID: nil
        ) {
            SphinxOnionManager.sharedInstance.assignReceiverId(localMsg: sentMessage)
            sentMessage.managedObjectContext?.saveContext()
            completion(true, sentMessage)
        } else {
            completion(false, nil)
        }
    }
    
    func sendDeleteRequest(
        message: TransactionMessage
    ){
        guard let chat = message.chat else{
            return
        }
        let contact = chat.getContact()
        let pubkey = getDestinationPubkey(for: chat)
        
        let _ = sendMessage(
            to: contact,
            content: "",
            chat: chat,
            provisionalMessage: nil,
            msgType: UInt8(TransactionMessage.TransactionMessageType.delete.rawValue),
            recipPubkey: pubkey,
            threadUUID: nil,
            replyUUID: message.uuid
        )
    }
    
    func getDestinationPubkey(for chat: Chat) -> String? {
        return chat.getContact()?.publicKey ?? chat.ownerPubkey ?? nil
    }
    
    func toggleChatSound(
        chatId: Int,
        muted: Bool,
        completion: @escaping (Chat?) -> ()
    ) {
        guard let chat = Chat.getChatWith(id: chatId) else{
            return
        }

        let level = muted ? Chat.NotificationLevel.MuteChat.rawValue : Chat.NotificationLevel.SeeAll.rawValue

        setMuteLevel(muteLevel: UInt8(level), chat: chat, recipContact: chat.getContact())
        chat.notify = level
        chat.managedObjectContext?.saveContext()
        completion(chat)
    }
    
    func setMuteLevel(
        muteLevel: UInt8,
        chat: Chat,
        recipContact: UserContact?
    ) {
        guard let seed = getAccountSeed() else{
            return
        }
        guard let recipPubkey = (recipContact?.publicKey ?? chat.ownerPubkey) else { return  }
        
        do {
            let rr = try Sphinx.mute(
                seed: seed,
                uniqueTime: getTimeWithEntropy(),
                state: loadOnionStateAsData(),
                pubkey: recipPubkey,
                muteLevel: muteLevel
            )
            
            let _ = handleRunReturn(rr: rr)
        } catch {
            print("Error setting mute level")
        }
    }
    
    func getMuteLevels() {
        guard let seed = getAccountSeed() else{
            return
        }
        do {
            let rr = try  Sphinx.getMutes(
                seed: seed,
                uniqueTime: getTimeWithEntropy(),
                state: loadOnionStateAsData()
            )
            let _ = handleRunReturn(rr: rr)
        } catch {
            print("Error getting mute level")
        }
    }
    
    func setReadLevel(
        index: UInt64,
        chat: Chat,
        recipContact: UserContact?
    ) {
        guard let seed = getAccountSeed() else{
            return
        }
        guard let recipPubkey = (recipContact?.publicKey ?? chat.ownerPubkey) else { return  }
        
        do {
            let rr = try Sphinx.read(
                seed: seed,
                uniqueTime: getTimeWithEntropy(),
                state: loadOnionStateAsData(),
                pubkey: recipPubkey,
                msgIdx: index
            )
            
            let _ = handleRunReturn(rr: rr)
        } catch {
            print("Error setting read level")
        }
    }
    
    func getReads() {
        guard let seed = getAccountSeed() else{
            return
        }
        do {
            let rr = try Sphinx.getReads(
                seed: seed,
                uniqueTime: getTimeWithEntropy(),
                state: loadOnionStateAsData()
            )
            let _ = handleRunReturn(rr: rr)
        } catch {
            print("Error getting read level")
        }
    }

}


extension Data {
    init?(hexString: String) {
        let cleanHex = hexString.replacingOccurrences(of: " ", with: "")
        var data = Data(capacity: cleanHex.count / 2)

        var index = cleanHex.startIndex
        while index < cleanHex.endIndex {
            let byteString = cleanHex[index ..< cleanHex.index(index, offsetBy: 2)]
            if let byte = UInt8(byteString, radix: 16) {
                data.append(byte)
            } else {
                return nil
            }
            index = cleanHex.index(index, offsetBy: 2)
        }

        self = data
    }
}
