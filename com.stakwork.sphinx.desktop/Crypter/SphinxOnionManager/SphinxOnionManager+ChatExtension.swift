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

extension SphinxOnionManager {
    
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
        index: Int,
        completion: @escaping (Chat?, Bool, Int) -> ()
    ) {
        if (chatsFetchParams?.restoredTribesPubKeys ?? []).contains(ownerPubkey) {
            ///Tribe restore in progress
            completion(nil, false, index)
            return
        }
        
        if (messageFetchParams?.restoredTribesPubKeys ?? []).contains(ownerPubkey) {
            if let chat = Chat.getTribeChatWithOwnerPubkey(ownerPubkey: ownerPubkey) {
                completion(chat, false, index)
            } else {
                completion(nil, false, index)
            }
            return
        }
        
        if deletedTribesPubKeys.contains(ownerPubkey) {
            ///Tribe deleted
            completion(nil, false, index)
            return
        }
        
        chatsFetchParams?.restoredTribesPubKeys.append(ownerPubkey)
        messageFetchParams?.restoredTribesPubKeys.append(ownerPubkey)
        
        if let chat = Chat.getTribeChatWithOwnerPubkey(ownerPubkey: ownerPubkey) {
            ///Tribe restore found, no need to restore
            completion(chat, false, index)
        } else if let host = host {
            ///Tribe not found in the database, attempt to lookup and restore.
            GroupsManager.sharedInstance.lookupAndRestoreTribe(pubkey: ownerPubkey, host: host) { chat in
                completion(chat, chat != nil, index)
            }
        } else {
            completion(nil, false, index)
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
        
        var msg: [String: Any] = ["content": content ]
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
        
        guard let selfContact = UserContact.getSelfContact(),
              let nickname = selfContact.nickname ?? chat.name,
              let recipPubkey = recipContact?.publicKey ?? chat.ownerPubkey
        else {
            return nil
        }

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
        
        guard let contentJSONString = contentJSONString else {
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
            
            let tag = handleRunReturn(
                rr: rr,
                isSendingMessage: true
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
                invoiceString: invoiceString,
                tag: tag
            )
            
            if let sentMessage = sentMessage {
                assignReceiverId(localMsg: sentMessage)
            }
            
            return sentMessage
        } catch let error {
            print("error sending msg \(error.localizedDescription)")
            return nil
        }
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
        invoiceString: String?,
        tag: String?
    ) -> TransactionMessage? {
        
        if rr.msgs.count > 1 && msgType == TransactionMessage.TransactionMessageType.directPayment.rawValue {
            return processNewOutgoingPayment(
                rr: rr,
                chat: chat,
                provisionalMessage: provisionalMessage,
                msgType: msgType,
                content: content,
                amount: amount,
                mediaKey: mediaKey,
                mediaToken: mediaToken,
                mediaType: mediaType
            )
        }
        
        for msg in rr.msgs {
            
            if msgType == TransactionMessage.TransactionMessageType.delete.rawValue, let replyUUID = replyUUID {
                guard let messageToDelete = TransactionMessage.getMessageWith(uuid: replyUUID) else {
                    return nil
                }
                messageToDelete.status = TransactionMessage.TransactionMessageStatus.deleted.rawValue
                messageToDelete.setAsLastMessage()
                messageToDelete.managedObjectContext?.saveContext()
                
                return messageToDelete
            }
            
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
                
                message?.tag = tag ?? msg.tag
                
                if msgType == TransactionMessage.TransactionMessageType.boost.rawValue {
                    message?.amount = NSDecimalNumber(value: amount)
                }
                
                if chat.isPublicGroup(), let owner = UserContact.getOwner() {
                    message?.senderAlias = owner.nickname
                    message?.senderPic = owner.avatarUrl
                }
                
                if msgType == TransactionMessage.TransactionMessageType.purchase.rawValue || msgType == TransactionMessage.TransactionMessageType.attachment.rawValue {
                    message?.mediaKey = mediaKey
                    message?.mediaToken = mediaToken
                    message?.mediaType = mediaType
                }
                
                if msgType == TransactionMessage.TransactionMessageType.invoice.rawValue {
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
                message?.id = -uniqueIntHashFromString(stringInput: UUID().uuidString)
                message?.setAsLastMessage()
                message?.managedObjectContext?.saveContext()
                
                return message
            }
        }
        return nil
    }
    
    func processNewOutgoingPayment(
        rr: RunReturn,
        chat: Chat,
        provisionalMessage: TransactionMessage?,
        msgType: UInt8,
        content: String,
        amount: Int,
        mediaKey: String?,
        mediaToken: String?,
        mediaType: String?
    ) -> TransactionMessage? {
        
        let paymentMsg = rr.msgs[0]
        let paymentStatusMsg = rr.msgs[1]
        
        var paymentMessage: TransactionMessage? = nil
        
        if let sentUUID = paymentMsg.uuid {
            let date = Date()
            paymentMessage = provisionalMessage ?? TransactionMessage.createProvisionalMessage(
                messageContent: content,
                type: Int(msgType),
                date: date,
                chat: chat
            )
            
            paymentMessage?.id = -uniqueIntHashFromString(stringInput: UUID().uuidString)
            paymentMessage?.amount = NSDecimalNumber(value: amount)
            paymentMessage?.mediaKey = mediaKey
            paymentMessage?.mediaToken = mediaToken
            paymentMessage?.mediaType = mediaType
            paymentMessage?.createdAt = date
            paymentMessage?.updatedAt = date
            paymentMessage?.uuid = sentUUID
            paymentMessage?.tag = paymentStatusMsg.tag
            paymentMessage?.setAsLastMessage()
            paymentMessage?.managedObjectContext?.saveContext()
            
            return paymentMessage
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
    
    func isTribeMessage(
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
        if rr.msgs.isEmpty {
            return
        }
        
        let isRestoringContactsAndTribes = firstSCIDMsgsCallback != nil
        
        if isRestoringContactsAndTribes {
            return
        }
        
        let notAllowedTypes = [
            UInt8(TransactionMessage.TransactionMessageType.contactKey.rawValue),
            UInt8(TransactionMessage.TransactionMessageType.contactKeyConfirmation.rawValue),
            UInt8(TransactionMessage.TransactionMessageType.unknown.rawValue)
        ]
        
        let filteredMsgs = rr.msgs.filter({ $0.type != nil && !notAllowedTypes.contains($0.type!) })
        
        if filteredMsgs.isEmpty {
            return
        }
        
        for message in filteredMsgs {
            
            if let fromMe = message.fromMe, fromMe == true {
                
                ///New sent message
                processSentMessage(
                    message: message
                )
                
            } else if let uuid = message.uuid, TransactionMessage.getMessageWith(uuid: uuid) == nil {
                
                ///New Incoming message
                guard let type = message.type else {
                    continue
                }
                
                if isMessageCallOrAttachment(type: type) {
                    processIncomingMessagesAndAttachments(
                        message: message,
                        shouldSendPush: filteredMsgs.count < 10
                    )
                }
                
                if isBoostOrPayment(type: type) {
                    processIncomingPaymentsAndBoosts(
                        message: message,
                        shouldSendPush: filteredMsgs.count < 10
                    )
                }
                
                if isDelete(type: type) {
                    processIncomingDeletion(
                        message: message
                    )
                }
                
                if isGroupAction(type: type) {
                    processIncomingGroupJoinMsg(
                        message: message,
                        shouldSendPush: filteredMsgs.count < 10
                    )
                }
                
                if isInvoice(type: type) {
                    processIncomingInvoice(
                        message: message,
                        shouldSendPush: filteredMsgs.count < 10
                    )
                }
            }
            
            processIndexUpdate(message: message)
        }
        
        managedContext.saveContext()
    }
    
    func updateIsPaidAllMessages() {
        let msgs = TransactionMessage.getAllPayment()
        for msg in msgs {
            msg.setPaymentInvoiceAsPaid()
        }
    }
    
    func processSentMessage(
        message: Msg
    ) {
        let genericIncomingMessage = GenericIncomingMessage(msg: message)
        
        if let omuuid = genericIncomingMessage.originalUuid, let newUUID = message.uuid,
           let originalMessage = TransactionMessage.getMessageWith(uuid: omuuid)
        {
            originalMessage.uuid = newUUID
            
            if (originalMessage.status == (TransactionMessage.TransactionMessageStatus.deleted.rawValue)){
                originalMessage.status = TransactionMessage.TransactionMessageStatus.deleted.rawValue
            }
            
            finalizeSentMessage(localMsg: originalMessage, remoteMsg: message)
        }
        
        if let uuid = message.uuid,
           let type = message.type,
           TransactionMessage.getMessageWith(uuid: uuid) == nil
        {
            guard let localMsg = processGenericIncomingMessage(
                message: genericIncomingMessage,
                date: Date(),
                delaySave: true,
                type: Int(type),
                fromMe: true
            ) else {
                return
            }
            
            localMsg.uuid = uuid
            
            if let invoice = genericIncomingMessage.invoice {
                
                let prd = PaymentRequestDecoder()
                prd.decodePaymentRequest(paymentRequest: invoice)
                
                if let expiry = prd.getExpirationDate(),
                   let paymentHash = try? Sphinx.paymentHashFromInvoice(bolt11: invoice)
                {
                    localMsg.messageContent = prd.getMemo()
                    localMsg.paymentHash = paymentHash
                    localMsg.expirationDate = expiry
                    localMsg.invoice = genericIncomingMessage.invoice
                    localMsg.status = TransactionMessage.TransactionMessageStatus.pending.rawValue
                }
            }
           
            if let genericMessageMsat = genericIncomingMessage.amount {
                localMsg.amount = NSDecimalNumber(value:  genericMessageMsat/1000)
                localMsg.amountMsat = NSDecimalNumber(value: Int(truncating: (genericMessageMsat) as NSNumber))
            }
            
            finalizeSentMessage(localMsg: localMsg, remoteMsg: message)
        }
    }
    
    func processIncomingMessagesAndAttachments(
        message: Msg,
        shouldSendPush: Bool
    ) {
        guard let index = message.index,
              let uuid = message.uuid,
              let sender = message.sender,
              let date = message.date,
              let type = message.type,
              let csr = ContactServerResponse(JSONString: sender) else
        {
            return
        }
        
        var genericIncomingMessage = GenericIncomingMessage(msg: message)
        genericIncomingMessage.senderPubkey = csr.pubkey
        genericIncomingMessage.uuid = uuid
        genericIncomingMessage.index = index
        
        let msg = processGenericIncomingMessage(
            message: genericIncomingMessage,
            date: date,
            csr: csr,
            type: Int(type),
            fromMe: message.fromMe ?? false
        )
        
        if shouldSendPush {
            sendNotification(message: msg)
        }
    }
    
    func processIncomingPaymentsAndBoosts(
        message: Msg,
        shouldSendPush: Bool
    ) {
        guard let index = message.index,
              let uuid = message.uuid,
              let sender = message.sender,
              let date = message.date,
              let type = message.type,
              let csr = ContactServerResponse(JSONString: sender) else
        {
            return
        }
        
        let msats = message.msat ?? 0
        
        var genericIncomingMessage = GenericIncomingMessage(msg: message)
        genericIncomingMessage.senderPubkey = csr.pubkey
        genericIncomingMessage.uuid = uuid
        genericIncomingMessage.index = index
        
        let paymentMsg = processGenericIncomingMessage(
            message: genericIncomingMessage,
            date: date,
            csr: csr,
            amount: Int(msats/1000),
            type: Int(type),
            fromMe: message.fromMe ?? false
        )
        
        if shouldSendPush {
            sendNotification(message: paymentMsg)
        }
    }
    
    func processIncomingDeletion(message: Msg){
        let genericIncomingMessage = GenericIncomingMessage(msg: message)
        
        if let messageToDeleteUUID = genericIncomingMessage.replyUuid {
            if let messageToDelete = TransactionMessage.getMessageWith(uuid: messageToDeleteUUID) {
                messageToDelete.status = TransactionMessage.TransactionMessageStatus.deleted.rawValue
                
                messageToDelete.managedObjectContext?.saveContext()
            } else {
                guard let sender = message.sender,
                      let date = message.date,
                      let type = message.type,
                      let csr = ContactServerResponse(JSONString: sender) else
                {
                    return
                }
                
                guard let msg = processGenericIncomingMessage(
                    message: genericIncomingMessage,
                    date: date,
                    csr: csr,
                    type: Int(type),
                    fromMe: message.fromMe ?? false
                ) else {
                    return
                }
                
                msg.managedObjectContext?.saveContext()
            }
        }
    }
    
    func processIncomingGroupJoinMsg(
        message: Msg,
        shouldSendPush: Bool
    ) {
        ///Check for sender information
        guard let sender = message.sender,
              let csr =  ContactServerResponse(JSONString: sender),
              let tribePubkey = csr.pubkey else
        {
            return
        }
        
        if let chat = Chat.getTribeChatWithOwnerPubkey(ownerPubkey: tribePubkey) {
            restoreGroupJoinMsg(
                message: message,
                chat: chat,
                didCreateTribe: false,
                shouldSendPush: shouldSendPush
            )
        } else {
            fetchOrCreateChatWithTribe(
                ownerPubkey: tribePubkey,
                host: csr.host,
                index: 0,
                completion: { [weak self] chat, didCreateTribe, ind in
                    guard let self = self else {
                        return
                    }
                    
                    if let chat = chat {
                        self.restoreGroupJoinMsg(
                            message: message,
                            chat: chat,
                            didCreateTribe: didCreateTribe,
                            shouldSendPush: shouldSendPush
                        )
                    }
                }
            )
        }
    }
    
    func processIncomingInvoice(
        message: Msg,
        shouldSendPush: Bool
    ) {
        guard let type = message.type,
              let sender = message.sender,
              let index = message.index,
              let uuid = message.uuid,
              let date = message.date,
              let csr = ContactServerResponse(JSONString: sender) else
        {
            return
        }
        
        var genericIncomingMessage = GenericIncomingMessage(msg: message)
        
        if let invoice = genericIncomingMessage.invoice {
            genericIncomingMessage.senderPubkey = csr.pubkey
            genericIncomingMessage.uuid = uuid
            genericIncomingMessage.index = index
            
            let prd = PaymentRequestDecoder()
            prd.decodePaymentRequest(paymentRequest: invoice)
            
            if let expiry = prd.getExpirationDate(),
                let amount = prd.getAmount(),
               let paymentHash = try? Sphinx.paymentHashFromInvoice(bolt11: invoice)
            {
                
                guard let newMessage = processGenericIncomingMessage(
                    message: genericIncomingMessage,
                    date: date,
                    csr: csr,
                    amount: amount,
                    type: Int(type),
                    fromMe: message.fromMe ?? false
                ) else {
                    return
                }
                
                newMessage.messageContent = prd.getMemo()
                newMessage.paymentHash = paymentHash
                newMessage.expirationDate = expiry
                newMessage.invoice = genericIncomingMessage.invoice
                newMessage.amountMsat = NSDecimalNumber(value: Int(truncating: newMessage.amount ?? 0) * 1000)
                newMessage.status = TransactionMessage.TransactionMessageStatus.pending.rawValue
                
                if shouldSendPush {
                    sendNotification(message: newMessage)
                }
            }
        }
    }
    
    func processGenericIncomingMessage(
        message: GenericIncomingMessage,
        date: Date,
        csr: ContactServerResponse? = nil,
        amount: Int = 0,
        delaySave: Bool = false,
        type: Int? = nil,
        status: Int? = nil,
        fromMe: Bool = false
    ) -> TransactionMessage? {
        
        let content = (type == TransactionMessage.TransactionMessageType.boost.rawValue) ? ("") : (message.content)
        
        guard let indexString = message.index,
            let index = Int(indexString),
            let pubkey = message.senderPubkey,
            let uuid = message.uuid else
        {
            return nil
        }
        
        if let paymentHash = message.paymentHash {
            if let _ = TransactionMessage.getInvoiceWith(paymentHash: paymentHash), type == TransactionMessage.TransactionMessageType.invoice.rawValue {
                return nil
            }
            
            if let _ = TransactionMessage.getInvoicePaymentWith(paymentHash: paymentHash), type == TransactionMessage.TransactionMessageType.payment.rawValue {
                return nil
            }
        }
        
        if let _ = TransactionMessage.getMessageWith(id: index) {
            return nil
        }
        
        var chat : Chat? = nil
        var senderId: Int? = nil
        
        var isTribe = false
        
        if let contact = UserContact.getContactWithDisregardStatus(pubkey: pubkey) {
            
            if let oneOnOneChat = contact.getChat() {
                chat = oneOnOneChat
            } else {
                chat = createChat(for: contact, with: date)
            }
            
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
            return nil
        }
        
        let newMessage = TransactionMessage.getMessageInstanceWith(
            id: Int(index),
            context: managedContext
        )
        
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
        
        newMessage.status = status ?? TransactionMessage.TransactionMessageStatus.confirmed.rawValue
        newMessage.type = type ?? TransactionMessage.TransactionMessageType.message.rawValue
        newMessage.encrypted = true
        newMessage.senderId = senderId
        newMessage.receiverId = UserContact.getSelfContact()?.id ?? 0
        newMessage.push = false
        newMessage.chat = chat
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
            managedContext.saveContext()
        }
        
        assignReceiverId(localMsg: newMessage)
        
        newMessage.setAsLastMessage()
        
        return newMessage
    }
    
    func processIndexUpdate(message: Msg) {
        if isMyMessageNeedingIndexUpdate(msg: message),
            let uuid = message.uuid,
            let cachedMessage = TransactionMessage.getMessageWith(uuid: uuid),
            let indexString = message.index,
            let index = Int(indexString)
        {
            cachedMessage.id = index //sync self index
            cachedMessage.updatedAt = Date()
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
            let mk = attachmentObject.mediaKey else
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
        let mediaType = params["media_type"] as? String
        let content = params["text"] as? String
        
        guard let contact = chat.getContact(), let amount = params["amount"] as? Int else {
            return
        }
        
        if let sentMessage = self.sendMessage(
            to: contact, 
            content: content ?? "",
            chat: chat,
            provisionalMessage: nil,
            amount: amount,
            msgType: UInt8(TransactionMessage.TransactionMessageType.directPayment.rawValue),
            muid: muid,
            mediaType: mediaType,
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
        
        let _ = sendMessage(
            to: contact,
            content: "",
            chat: chat,
            provisionalMessage: nil,
            msgType: UInt8(TransactionMessage.TransactionMessageType.delete.rawValue),
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
        
        guard let _ = mqtt else {
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

extension Msg {
    func getInnerContentDate() -> Date? {
        if let msg = self.message,
           let innerContent = MessageInnerContent(JSONString: msg),
           let innerContentDate = innerContent.date,
           let date = self.timestampToDate(timestamp: UInt64(innerContentDate))
        {
            return date
        }
        return nil
    }
    
    func timestampToDate(
        timestamp: UInt64
    ) -> Date? {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
        return date
    }
    
    var date: Date? {
        get {
            if let timestamp = self.timestamp {
                return self.timestampToDate(timestamp: UInt64(timestamp))
            }
            return nil
        }
    }
}
