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
    
    func isPaidMessageRelated(
        type:UInt8
    )-> Bool{
        let intType = Int(type)
        
        return (
            intType == TransactionMessage.TransactionMessageType.purchase.rawValue ||
            intType == TransactionMessage.TransactionMessageType.purchaseAccept.rawValue ||
            intType == TransactionMessage.TransactionMessageType.purchaseDeny.rawValue
        )
    }
    
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
    
    func fetchTribeInfo(
        ownerPubkey: String,
        host: String?
    ) async -> ((String, JSON)?, Bool) {
        if (chatsFetchParams?.restoredTribesPubKeys ?? []).contains(ownerPubkey) {
            return (nil, false)
        }
        
        if deletedTribesPubKeys.contains(ownerPubkey) {
            return (nil, false)
        }
        
        chatsFetchParams?.restoredTribesPubKeys.append(ownerPubkey)
        
        if let host = host {
            if let tribeJson = await GroupsManager.sharedInstance.fetchTribeInfoAsync(pubkey: ownerPubkey, host: host) {
                return ((ownerPubkey, tribeJson), true)
            }
        }
        return (nil, false)
    }

    
    func loadMediaToken(
        recipPubkey: String?,
        muid: String?,
        price: Int? = nil
    ) -> String? {
        guard let seed = getAccountSeed(), let recipPubkey = recipPubkey, let muid = muid, let expiry = Calendar.current.date(byAdding: .year, value: 1, to: Date()) else {
            return nil
        }
        do {
            let hostname = "memes.sphinx.chat"
            var mt: String
            
            if (price == nil) {
                mt = try makeMediaToken(
                    seed: seed,
                    uniqueTime: getTimeWithEntropy(),
                    state: loadOnionStateAsData(),
                    host: hostname,
                    muid: muid,
                    to: recipPubkey,
                    expiry: UInt32(expiry.timeIntervalSince1970)
                )
            } else {
                mt = try makeMediaTokenWithPrice(
                    seed: seed,
                    uniqueTime: getTimeWithEntropy(),
                    state: loadOnionStateAsData(),
                    host: hostname,
                    muid: muid,
                    to: recipPubkey,
                    expiry: UInt32(expiry.timeIntervalSince1970),
                    price: UInt64((price!))
                )
            }
            return mt
        } catch {
            return nil
        }
    }
    
    func formatMsg(
        content: String,
        type: UInt8,
        muid: String? = nil,
        purchaseItemAmount: Int? = nil,
        recipPubkey: String? = nil,
        mediaKey: String? = nil,
        mediaType: String? = "file",
        mediaToken: String? = nil,
        threadUUID: String?,
        replyUUID: String?,
        invoiceString: String?,
        tribeKickMember: String? = nil,
        paidAttachmentMediaToken: String? = nil,
        isTribe: Bool,
        metaData: String? = nil
    ) -> (String?, String?)? {
        
        var msg: [String: Any] = ["content": content ]
        var mt: String? = nil
        
        if let metaData = metaData {
            msg["metadata"] = metaData
        }

        switch TransactionMessage.TransactionMessageType(rawValue: Int(type)) {
        case .message, .boost, .delete, .call, .groupLeave, .memberReject, .memberApprove,.groupDelete:
            break
        case .attachment, .directPayment, .purchaseAccept, .purchaseDeny:
            
            msg["mediaKey"] = mediaKey
            msg["mediaKeyForSelf"] = mediaKey
            msg["mediaType"] = mediaType
            
            if Int(type) == TransactionMessage.TransactionMessageType.purchaseAccept.rawValue ||
               Int(type) == TransactionMessage.TransactionMessageType.purchaseDeny.rawValue
            {
                ///reference mediaToken made by sender of encrypted message we are paying for
                mt = paidAttachmentMediaToken
            } else {
                ///create a media token corresponding to attachment (paid or unpaid)
                mt = loadMediaToken(recipPubkey: recipPubkey, muid: muid, price: purchaseItemAmount)
            }
            msg["mediaToken"] = mt ?? mediaToken
            
            if let _ = purchaseItemAmount {
                ///Remove content if it's a paid text message
                if mediaType == "sphinx/text" {
                    msg.removeValue(forKey: "content")
                }
                
                ///Remove mediaKey if it's a conversation, otherwise send it since tribe admin will custodial it
                if !isTribe {
                    msg.removeValue(forKey: "mediaKey")
                }
            }
            break
        case .purchase:
            if let paidAttachmentMediaToken = paidAttachmentMediaToken{
                mt = paidAttachmentMediaToken
                msg["mediaToken"] = mt ?? mediaToken
            }
            else{
                return nil
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
            
        guard let contentData = try? JSONSerialization.data(withJSONObject: msg, options: .prettyPrinted), let contentJSONString = String(data: contentData, encoding: .utf8) else {
            return nil
        }
        
        return (contentJSONString, mt)
    }
    
    func sendMessage(
        to recipContact: UserContact?,
        content: String,
        chat: Chat,
        provisionalMessage: TransactionMessage?,
        owner: UserContact? = nil,
        amount: Int = 0,
        purchaseAmount: Int? = nil,
        shouldSendAsKeysend: Bool = false,
        msgType: UInt8 = 0,
        muid: String? = nil,
        mediaKey: String? = nil,
        mediaType: String? = nil,
        threadUUID: String?,
        replyUUID: String?,
        invoiceString: String? = nil,
        tribeKickMember: String? = nil,
        paidAttachmentMediaToken: String? = nil,
        context: NSManagedObjectContext? = nil
    ) -> (TransactionMessage?, String?) {
        
        guard let seed = getAccountSeed() else {
            return (nil, "Account seed not found")
        }
        
        let isTribe = recipContact == nil
        
        guard let selfContact = owner ?? UserContact.getOwner(),
              let nickname = isTribe ? (chat.myAlias?.isNotEmpty == true ? chat.myAlias : selfContact.nickname)?.fixedAlias : (chat.myAlias?.isNotEmpty == true ? chat.myAlias : selfContact.nickname),
              let recipPubkey = recipContact?.publicKey ?? chat.ownerPubkey
        else {
            return (nil, "Owner not found")
        }
        
        let metaData = chat.getMetaDataJsonStringValue()
        
        guard let (contentJSONString, mediaToken) = formatMsg(
            content: content,
            type: msgType,
            muid: muid,
            purchaseItemAmount: purchaseAmount,
            recipPubkey: recipPubkey,
            mediaKey: mediaKey,
            mediaType: mediaType,
            threadUUID: threadUUID,
            replyUUID: replyUUID,
            invoiceString: invoiceString,
            tribeKickMember: tribeKickMember,
            paidAttachmentMediaToken: paidAttachmentMediaToken,
            isTribe: isTribe,
            metaData: metaData
        ) else {
            return (nil, "Msg json format issue")
        }
        
        guard let contentJSONString = contentJSONString else {
            return (nil, "Msg json format issue")
        }
        
        let myImg = (chat.myPhotoUrl?.isNotEmpty == true ? (chat.myPhotoUrl ?? "") : (selfContact.avatarUrl ?? ""))
        
        do {
            var amtMsat = tribeMinSats
            
            if isTribe && amount == 0 {
                let escrowAmountSats = Int(truncating: chat.escrowAmount ?? 0)
                let pricePerMessage = Int(truncating: chat.pricePerMessage ?? 0)
                amtMsat = max((escrowAmountSats + pricePerMessage), tribeMinSats)
            } else {
                amtMsat = amount
            }
            
            let rr = try Sphinx.send(
                seed: seed,
                uniqueTime: getTimeWithEntropy(),
                to: recipPubkey,
                msgType: msgType,
                msgJson: contentJSONString,
                state: loadOnionStateAsData(),
                myAlias: nickname,
                myImg: myImg,
                amtMsat: UInt64(amtMsat),
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
                mediaToken: mediaToken ?? paidAttachmentMediaToken,
                mediaType: mediaType,
                replyUUID: replyUUID,
                threadUUID: threadUUID,
                invoiceString: invoiceString,
                tag: tag,
                owner: owner ?? UserContact.getOwner(),
                context: context
            )
            
//            if let sentMessage = sentMessage {
//                assignReceiverId(localMsg: sentMessage)
//            }
            
            if let _ = metaData {
                chat.timezoneUpdated = false
            }
            
            (context ?? chat.managedObjectContext)?.saveContext()
            
            return (sentMessage, nil)
        } catch let error {
            print("error sending msg \(error.localizedDescription)")
            return (nil, "Send msg error \(error)")
        }
    }
    
    func isMessageLengthValid(
        text: String,
        sendingAttachment: Bool,
        threadUUID: String?,
        replyUUID: String?,
        metaDataString: String? = nil
    ) -> Bool {
        let contentBytes: Int = 18
        let attachmentBytes: Int = 389
        let replyBytes: Int = 84
        let threadBytes: Int = 84
        
        var bytes = text.byteSize() + contentBytes
        
        if sendingAttachment {
            bytes += attachmentBytes
        }
        
        if replyUUID != nil {
            bytes += replyBytes
        }
        
        if threadUUID != nil {
            bytes += threadBytes
        }
        
        if let metaDataBytes = metaDataString?.lengthOfBytes(using: .utf8) {
            let metaDataJsonBytes: Int = 15
            
            bytes += metaDataBytes + metaDataJsonBytes
        }
        
        return bytes <= 869
    }
    
//    func startSendTimeoutTimer(
//        for messageUUID: String,
//        msgType: UInt8
//    ) {
//        let excludedTypes = [
//            UInt8(TransactionMessage.TransactionMessageType.payment.rawValue),
//            UInt8(TransactionMessage.TransactionMessageType.directPayment.rawValue),
//            UInt8(TransactionMessage.TransactionMessageType.boost.rawValue),
//            UInt8(TransactionMessage.TransactionMessageType.keysend.rawValue),
//            UInt8(TransactionMessage.TransactionMessageType.delete.rawValue),
//        ]
//        
//        if excludedTypes.contains(msgType) {
//            return
//        }
//        
//        sendTimeoutTimers[messageUUID]?.invalidate() // Invalidate any existing timer for this UUID
//
//        let timer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] timer in
//            self?.handleSendTimeout(for: messageUUID)
//        }
//        
//        sendTimeoutTimers[messageUUID] = timer
//    }
//
//    func handleSendTimeout(for messageUUID: String) {
//        guard let message = TransactionMessage.getMessageWith(uuid: messageUUID) else { return }
//        
//        message.status = TransactionMessage.TransactionMessageStatus.failed.rawValue
//        message.managedObjectContext?.saveContext()
//        
//        sendTimeoutTimers[messageUUID] = nil // Remove the timer reference
//    }
//    
//    // Call this method when you receive Ongoing Message UUID
//    func receivedOMuuid(_ omuuid: String) {
//        sendTimeoutTimers[omuuid]?.invalidate()
//        sendTimeoutTimers[omuuid] = nil
//    }
    
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
        tag: String?,
        owner: UserContact?,
        context: NSManagedObjectContext? = nil
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
                mediaType: mediaType,
                context: context
            )
        }
        
        for msg in rr.msgs {
            
            if msgType == TransactionMessage.TransactionMessageType.delete.rawValue {
                guard let replyUUID = replyUUID, let messageToDelete = TransactionMessage.getMessageWith(
                    uuid: replyUUID,
                    context: context
                ) else {
                    return nil
                }
                messageToDelete.status = TransactionMessage.TransactionMessageStatus.deleted.rawValue
                messageToDelete.setAsLastMessage()
//                messageToDelete.managedObjectContext?.saveContext()
                
                return messageToDelete
            }
            
            if msgType == TransactionMessage.TransactionMessageType.memberApprove.rawValue {
                return nil
            }
            
            if let sentUUID = msg.uuid {
                
                let date = Date()
                
                let message  = provisionalMessage ?? TransactionMessage.createProvisionalMessage(
                    messageContent: content,
                    type: Int(msgType),
                    date: date,
                    chat: chat,
                    replyUUID: replyUUID,
                    threadUUID: threadUUID,
                    context: context
                )
                
                message?.tag = tag ?? msg.tag
                
                if msgType == TransactionMessage.TransactionMessageType.boost.rawValue {
                    message?.amount = NSDecimalNumber(value: amount / 1000)
                }
                
                if chat.isPublicGroup(), let owner = owner {
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
                
                if let paymentHash = rr.msgs.first?.paymentHash {
                    message?.paymentHash = paymentHash
                }
                
                message?.createdAt = date
                message?.updatedAt = date
                message?.uuid = sentUUID
                message?.id = provisionalMessage?.id ?? uniqueIntHashFromString(stringInput: UUID().uuidString)
                message?.setAsLastMessage()
                message?.muid = TransactionMessage.getMUIDFrom(mediaToken: mediaToken)
                
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
        mediaType: String?,
        context: NSManagedObjectContext? = nil
    ) -> TransactionMessage? {
        
        let paymentMsg = rr.msgs[0]
        var paymentMessage: TransactionMessage? = nil
        
        if let sentUUID = paymentMsg.uuid {
            let date = Date()
            paymentMessage = provisionalMessage ?? TransactionMessage.createProvisionalMessage(
                messageContent: content,
                type: Int(msgType),
                date: date,
                chat: chat,
                context: context
            )
            
            paymentMessage?.id = uniqueIntHashFromString(stringInput: UUID().uuidString)
            paymentMessage?.amount = NSDecimalNumber(value: amount / 1000)
            paymentMessage?.mediaKey = mediaKey
            paymentMessage?.mediaToken = mediaToken
            paymentMessage?.mediaType = mediaType
            paymentMessage?.createdAt = date
            paymentMessage?.updatedAt = date
            paymentMessage?.uuid = sentUUID
            paymentMessage?.tag = paymentMsg.tag
            paymentMessage?.paymentHash = paymentMsg.paymentHash
            paymentMessage?.setAsLastMessage()
//            paymentMessage?.managedObjectContext?.saveContext()
            
            return paymentMessage
        }
        return nil
    }
    
    func finalizeSentMessage(
        message: Msg,
        genericIncomingMessage: GenericIncomingMessage?,
        localMsg: TransactionMessage,
        existingMessagesUUIDMap: [String: TransactionMessage?],
        owner: UserContact? = nil
    ) -> TransactionMessage? {
        if let contentTimestamp = genericIncomingMessage?.timestamp {
            let date = timestampToDate(timestamp: UInt64(contentTimestamp))
            localMsg.date = date
            localMsg.updatedAt = Date()
        } else if let timestamp = message.timestamp {
            let date = timestampToDate(timestamp: timestamp) ?? Date()
            localMsg.date = date
            localMsg.updatedAt = Date()
        }
        
        if let type = message.type,
           type == TransactionMessage.TransactionMessageType.memberApprove.rawValue,
           let ruuid = localMsg.replyUUID,
           let messageWeAreReplying = existingMessagesUUIDMap[ruuid], let messageWeAreReplying = messageWeAreReplying
        {
            localMsg.senderAlias = messageWeAreReplying.senderAlias
        } else if let owner = UserContact.getOwner() {
            localMsg.senderAlias = owner.nickname
            localMsg.senderPic = owner.avatarUrl
        }
        
        if
            let msg = message.message,
            let innerContent = MessageInnerContent(JSONString: msg),
            let metadataString = innerContent.metadata,
            let metadataData = metadataString.data(using: .utf8)
        {
            do {
                if
                    let metadataDict = try JSONSerialization.jsonObject(with: metadataData, options: []) as? [String: Any],
                    let timezone = metadataDict["tz"] as? String
                {
                    if localMsg.chat?.isPublicGroup() == true {
                        localMsg.remoteTimezoneIdentifier = timezone
                    }
                }
            } catch {
                print("Error parsing metadata JSON: \(error)")
            }
        }
        
        localMsg.senderId = owner?.id ?? UserData.sharedInstance.getUserId(context: backgroundContext)
        
        return localMsg
    }
    
//    func assignReceiverId(localMsg: TransactionMessage) {
//        var receiverId :Int = -1
//        
//        if let contact = localMsg.chat?.getContact() {
//            receiverId = contact.id
//        } else if localMsg.type == TransactionMessage.TransactionMessageType.boost.rawValue,
//            let replyUUID = localMsg.replyUUID,
//            let replyMsg = TransactionMessage.getMessageWith(uuid: replyUUID)
//        {
//            receiverId = replyMsg.senderId
//        }
//        localMsg.receiverId = receiverId
//    }
    
    func isTribeMessage(
        senderPubkey: String
    ) -> Bool {
        
        var isTribe = false
        
        if let _ = Chat.getTribeChatWithOwnerPubkey(ownerPubkey: senderPubkey){
            isTribe = true
        }
        
        return isTribe
    }
    
    func processInvoicePaid(rr: RunReturn) {
        if let _ = rr.settleTopic, let _ = rr.settlePayload {
            let paymentHashes = rr.msgs.compactMap({ $0.paymentHash })
            for paymentHash in paymentHashes {
                NotificationCenter.default.post(
                    name: .sentInvoiceSettled,
                    object: nil,
                    userInfo: ["paymentHash": paymentHash]
                )
            }
        }
    }
    
    //MARK: processes updates from general purpose messages like plaintext and attachments
    func processGenericMessages(
        topic: String?,
        rr: RunReturn
    ) {
        if rr.msgs.isEmpty {
            return
        }
        
        let isRestoringContactsAndTribes = firstSCIDMsgsCallback != nil
        
        if isRestoringContactsAndTribes {
            return
        }
        
        ///Messages indexes
        let messageIndexes = rr.msgs.compactMap({
            if let index = $0.index, let indexInt = Int(index) {
                return indexInt
            }
            return nil
        })
        
        ///Messages UUIDs
        var messageUUIDs = rr.msgs.compactMap({
            return $0.uuid
        })
        
        ///Messages inner content Map
        let messagesInnerContentMap = Dictionary(uniqueKeysWithValues: rr.msgs.compactMap {
            if let message = $0.message,
               let index = $0.index,
               let indexInt = Int(index),
               let innerContent = MessageInnerContent(JSONString: message)
            {
                return (indexInt, innerContent)
            }
            return nil
        })

        ///Messages sender info Map
        let senderInfoMessagesMap = Dictionary(uniqueKeysWithValues: rr.msgs.compactMap {
            if let _ = $0.type,
               let sender = $0.sender,
               let index = $0.index,
               let indexInt = Int(index),
               let _ = $0.uuid,
               let _ = $0.date,
               let csr = ContactServerResponse(JSONString: sender)
            {
                return (indexInt, csr)
            }
            return nil
        })
        
        ///Tribes Map per public key
        let tribePubkeys = senderInfoMessagesMap.compactMap({ $0.value.pubkey })
        let tribes = Chat.getChatTribesFor(ownerPubkeys: tribePubkeys, context: backgroundContext)
        var tribesMap = Dictionary(uniqueKeysWithValues: tribes.compactMap {
            if let ownerPubkey = $0.ownerPubkey {
                return (ownerPubkey, $0)
            }
            return nil
        })
        
        ///Generic incoming messages Map
        let genericIncomingMessagesMap = Dictionary(uniqueKeysWithValues: rr.msgs.compactMap {
            if let index = $0.index, let indexInt = Int(index) {
                let senderInfo = senderInfoMessagesMap[indexInt]
                let innerContent = messagesInnerContentMap[indexInt]
                
                let tribe: Chat? = senderInfo?.pubkey.flatMap { tribesMap[$0] }
                
                var genericIncomingMessage = GenericIncomingMessage(
                    msg: $0,
                    csr: senderInfo,
                    innerContent: innerContent,
                    isTribeMessage: tribe != nil
                )
                
                if let fromMe = $0.fromMe, fromMe == true, let sentTo = $0.sentTo {
                    genericIncomingMessage.senderPubkey = sentTo
                } else {
                    genericIncomingMessage.senderPubkey = senderInfo?.pubkey
                }
                
                genericIncomingMessage.uuid = $0.uuid
                genericIncomingMessage.index = $0.index
                
                return (indexInt, genericIncomingMessage)
            }
            return nil
        })
        
        ///Contacts Map per public key
        let contactPubkeys = genericIncomingMessagesMap.values.compactMap({ $0.senderPubkey })
        let contacts = UserContact.getContactsWith(pubkeys: contactPubkeys, context: backgroundContext)
        let contactsMap = Dictionary(uniqueKeysWithValues: contacts.compactMap {
            $0.setContactConversation(context: backgroundContext)
            
            if let pubkey = $0.publicKey {
                return (pubkey, $0)
            }
            return nil
        })
        
        let originalUUIDs = genericIncomingMessagesMap.values.compactMap({
            return $0.originalUuid
        })
        messageUUIDs.append(contentsOf: originalUUIDs)
        
        let replyingUUIDs = genericIncomingMessagesMap.values.compactMap({
            return $0.replyUuid
        })
        messageUUIDs.append(contentsOf: replyingUUIDs)
        
        ///Existing messages
        let existingIdMessages = TransactionMessage.getMessagesWith(ids: messageIndexes, context: backgroundContext)
        var existingMessagesIdMap = Dictionary(uniqueKeysWithValues: existingIdMessages.map { ($0.id, $0) })
        
        let existingUUIDMessages = TransactionMessage.getMessagesWith(uuids: messageUUIDs, context: backgroundContext)
        var existingMessagesUUIDMap = Dictionary(uniqueKeysWithValues: existingUUIDMessages.compactMap{
            if let uuid = $0.uuid {
                return (uuid, $0)
            }
            return nil
        })
        
        let paymentHashes = rr.msgs.compactMap({
            return $0.paymentHash
        })
        let invoices = TransactionMessage.getInvoicesWith(paymentHashes: paymentHashes, context: backgroundContext)
        let invoicesByPaymentHashMap = Dictionary(uniqueKeysWithValues: invoices.compactMap{
            if let paymentHash = $0.paymentHash {
                return (paymentHash, $0)
            }
            return nil
        })
        
        let notAllowedTypes = [
            UInt8(TransactionMessage.TransactionMessageType.contactKey.rawValue),
            UInt8(TransactionMessage.TransactionMessageType.contactKeyConfirmation.rawValue),
            UInt8(TransactionMessage.TransactionMessageType.unknown.rawValue)
        ]
        //GET MESSAGES TO DELETE
        
        let owner = UserContact.getOwner(context: backgroundContext)
        
        for message in rr.msgs {
            guard let index = message.index, let indexInt = Int(index) else {
                continue
            }
            
            let existingMessages = existingMessagesIdMap[indexInt]
            let senderInfo = senderInfoMessagesMap[indexInt]
            let genericIncomingMsg = genericIncomingMessagesMap[indexInt]
            var newMessage: TransactionMessage? = nil
            
            let isPayment = message.type == nil && message.msat ?? 0 > 0 && message.message?.isNotEmpty == true
            
            if isPayment {
                restoreGenericPmt(
                    pmt: message,
                    innerContent: messagesInnerContentMap[indexInt],
                    existingMessage: existingMessagesIdMap[indexInt]
                )
                continue
            } else {
                if let messageType = message.type, notAllowedTypes.contains(messageType) {
                    continue
                }
            }
            
            if let fromMe = message.fromMe, fromMe == true {
                ///New sent message
                newMessage = processSentMessage(
                    message: message,
                    existingMessagesUUIDMap: existingMessagesUUIDMap,
                    existingMessage: existingMessages,
                    senderInfo: senderInfo,
                    genericIncomingMessage: genericIncomingMsg,
                    contact: contactsMap[genericIncomingMsg?.senderPubkey ?? ""],
                    tribe: tribesMap[senderInfo?.pubkey ?? ""],
                    owner: owner
                )
                
            } else if let uuid = message.uuid, existingMessagesUUIDMap[uuid] == nil {
                ///New Incoming message
                guard let type = message.type else {
                    continue
                }
                
                if isMessageWithText(type: type) {
                    newMessage = processIncomingMessagesAndAttachments(
                        message: message,
                        existingMessage: existingMessages,
                        senderInfo: senderInfo,
                        genericIncomingMessage: genericIncomingMsg,
                        contact: contactsMap[genericIncomingMsg?.senderPubkey ?? ""],
                        tribe: tribesMap[senderInfo?.pubkey ?? ""],
                        owner: owner
                    )
                }
                
                if isBoostOrPayment(type: type) {
                    let invoiceForPayment = (type == TransactionMessage.TransactionMessageType.payment.rawValue && message.paymentHash != nil) ? invoicesByPaymentHashMap[message.paymentHash!] : nil
                    
                    newMessage = processIncomingPaymentsAndBoosts(
                        message: message,
                        existingMessage: existingMessages,
                        invoiceForPayment: invoiceForPayment,
                        senderInfo: senderInfo,
                        genericIncomingMessage: genericIncomingMsg,
                        contact: contactsMap[genericIncomingMsg?.senderPubkey ?? ""],
                        tribe: tribesMap[senderInfo?.pubkey ?? ""],
                        owner: owner
                    )
                }
                
                if isDelete(type: type) {
                    newMessage = processIncomingDeletion(
                        message: message,
                        existingMessage: existingMessages,
                        messageToDelete: existingMessagesUUIDMap[genericIncomingMsg?.replyUuid ?? ""],
                        senderInfo: senderInfo,
                        genericIncomingMessage: genericIncomingMsg,
                        contact: contactsMap[genericIncomingMsg?.senderPubkey ?? ""],
                        tribe: tribesMap[senderInfo?.pubkey ?? ""],
                        owner: owner
                    )
                }
                
                if isGroupAction(type: type) {
                    newMessage = processIncomingGroupJoinMsg(
                        message: message,
                        existingMessage: existingMessages,
                        senderInfo: senderInfo,
                        innerContent: messagesInnerContentMap[indexInt],
                        genericIncomingMessage: genericIncomingMsg,
                        contact: contactsMap[genericIncomingMsg?.senderPubkey ?? ""],
                        tribe: tribesMap[senderInfo?.pubkey ?? ""],
                        owner: owner
                    )
                }
                
                if isInvoice(type: type) {
                    newMessage = processIncomingInvoice(
                        message: message,
                        existingMessage: existingMessages,
                        senderInfo: senderInfo,
                        genericIncomingMessage: genericIncomingMsg,
                        contact: contactsMap[genericIncomingMsg?.senderPubkey ?? ""],
                        tribe: tribesMap[senderInfo?.pubkey ?? ""],
                        owner: owner
                    )
                }
                
                if isPaidMessageRelated(type: type) {
                    newMessage = processIncomingPaidMessageEvent(
                        message: message,
                        existingMessage: existingMessages,
                        senderInfo: senderInfo,
                        genericIncomingMessage: genericIncomingMsg,
                        contact: contactsMap[genericIncomingMsg?.senderPubkey ?? ""],
                        tribe: tribesMap[senderInfo?.pubkey ?? ""],
                        owner: owner
                    )
                }
            }
            
            if let newMessage = newMessage {
                if !existingMessagesIdMap.keys.contains(newMessage.id) {
                    existingMessagesIdMap[newMessage.id] = newMessage
                }
                
                if let uuid = newMessage.uuid, !existingMessagesUUIDMap.keys.contains(uuid) {
                    existingMessagesUUIDMap[uuid] = newMessage
                }
                
                if let chat = newMessage.chat, let ownerPubKey = chat.ownerPubkey, chat.isPublicGroup(), !tribesMap.keys.contains(ownerPubKey) {
                    tribesMap[ownerPubKey] = chat
                }                
            }
            
            processIndexUpdate(message: message, cachedMessage: existingMessages)
        }
    }
    
    func restoreGenericPmt(
        pmt: Msg,
        innerContent: MessageInnerContent?,
        existingMessage: TransactionMessage?
    ) {
        guard let index = pmt.index,
              let indexInt = Int(index) else
        {
            return
        }
        
        let newMessage = existingMessage ?? TransactionMessage(context: backgroundContext)
        
        newMessage.id = indexInt
        
        if let amount = pmt.msat {
            newMessage.amount = NSDecimalNumber(value: amount / 1000)
            newMessage.amountMsat = NSDecimalNumber(value: amount)
        }
        
        newMessage.messageContent = innerContent?.content
        newMessage.paymentHash = pmt.paymentHash
        
        if let timestamp = pmt.timestamp {
            newMessage.date = timestampToDate(timestamp: timestamp)
        }
    }
    
    func updateIsPaidAllMessages() {
        let msgs = TransactionMessage.getAllPayment()
        for msg in msgs {
            msg.setPaymentInvoiceAsPaid()
        }
    }
    
    func processSentMessage(
        message: Msg,
        existingMessagesUUIDMap: [String: TransactionMessage?],
        existingMessage: TransactionMessage?,
        senderInfo: ContactServerResponse?,
        genericIncomingMessage: GenericIncomingMessage?,
        contact: UserContact?,
        tribe: Chat?,
        owner: UserContact? = nil
    ) -> TransactionMessage? {
        if let omuuid = genericIncomingMessage?.originalUuid, let newUUID = message.uuid,
           let originalMessage = existingMessagesUUIDMap[omuuid], let originalMessage = originalMessage
        {
            originalMessage.uuid = newUUID
            
            return finalizeSentMessage(
                message: message,
                genericIncomingMessage: genericIncomingMessage,
                localMsg: originalMessage,
                existingMessagesUUIDMap: existingMessagesUUIDMap,
                owner: owner
            )
        }
        
        if let uuid = message.uuid,
           let type = message.type,
           let genericIncomingMessage = genericIncomingMessage,
           existingMessagesUUIDMap[uuid] == nil
        {
            guard let localMsg = processGenericIncomingMessage(
                message: genericIncomingMessage,
                existingMessage: existingMessage,
                invoiceForPayment: nil,
                csr: senderInfo,
                contact: contact,
                tribe: tribe,
                owner: owner,
                date: Date(),
                type: Int(type),
                fromMe: true
            ) else {
                return nil
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
            
            return finalizeSentMessage(
                message: message,
                genericIncomingMessage: genericIncomingMessage,
                localMsg: localMsg,
                existingMessagesUUIDMap: existingMessagesUUIDMap,
                owner: owner
            )
        }
        
        return nil
    }
    
    func processIncomingMessagesAndAttachments(
        message: Msg,
        existingMessage: TransactionMessage?,
        senderInfo: ContactServerResponse?,
        genericIncomingMessage: GenericIncomingMessage?,
        contact: UserContact?,
        tribe: Chat?,
        owner: UserContact? = nil
    ) -> TransactionMessage? {
        guard let _ = message.index,
              let _ = message.uuid,
              let _ = message.sender,
              let date = message.date,
              let type = message.type,
              let _ = senderInfo,
              let genericIncomingMessage = genericIncomingMessage else
        {
            return nil
        }
        
        return processGenericIncomingMessage(
            message: genericIncomingMessage,
            existingMessage: existingMessage,
            invoiceForPayment: nil,
            csr: senderInfo,
            contact: contact,
            tribe: tribe,
            owner: owner,
            date: date,
            type: Int(type),
            fromMe: message.fromMe ?? false
        )
    }
    
    func processIncomingPaymentsAndBoosts(
        message: Msg,
        existingMessage: TransactionMessage?,
        invoiceForPayment: TransactionMessage?,
        senderInfo: ContactServerResponse?,
        genericIncomingMessage: GenericIncomingMessage?,
        contact: UserContact?,
        tribe: Chat?,
        owner: UserContact? = nil
    ) -> TransactionMessage? {
        
        guard let _ = message.index,
              let _ = message.uuid,
              let _ = message.sender,
              let date = message.date,
              let type = message.type,
              let _ = senderInfo,
              let genericIncomingMessage = genericIncomingMessage else
        {
            return nil
        }
        
        return processGenericIncomingMessage(
            message: genericIncomingMessage,
            existingMessage: existingMessage,
            invoiceForPayment: invoiceForPayment,
            csr: senderInfo,
            contact: contact,
            tribe: tribe,
            owner: owner,
            date: date,
            amount: Int(message.msat ?? 0),
            type: Int(type),
            fromMe: message.fromMe ?? false
        )
    }
    
    func processIncomingDeletion(
        message: Msg,
        existingMessage: TransactionMessage?,
        messageToDelete: TransactionMessage?,
        senderInfo: ContactServerResponse?,
        genericIncomingMessage: GenericIncomingMessage?,
        contact: UserContact?,
        tribe: Chat?,
        owner: UserContact? = nil
    ) -> TransactionMessage? {

        guard let date = message.date,
              let type = message.type,
              let _ = senderInfo,
              let genericIncomingMessage = genericIncomingMessage else
        {
            return nil
        }
    
        if let messageToDelete = messageToDelete {
            messageToDelete.status = TransactionMessage.TransactionMessageStatus.deleted.rawValue
        } else {
            return processGenericIncomingMessage(
                message: genericIncomingMessage,
                existingMessage: existingMessage,
                invoiceForPayment: nil,
                csr: senderInfo,
                contact: contact,
                tribe: tribe,
                owner: owner,
                date: date,
                type: Int(type),
                fromMe: message.fromMe ?? false
            )
        }
        
        return nil
    }
    
    func processIncomingGroupJoinMsg(
        message: Msg,
        existingMessage: TransactionMessage?,
        senderInfo: ContactServerResponse?,
        innerContent: MessageInnerContent?,
        genericIncomingMessage: GenericIncomingMessage?,
        contact: UserContact?,
        tribe: Chat?,
        owner: UserContact? = nil
    ) -> TransactionMessage? {
        ///Check for sender information
        guard let csr =  senderInfo,
              let _ = csr.pubkey else
        {
            return nil
        }
        
        if let chat = tribe {
            return restoreGroupJoinMsg(
                message: message,
                existingMessage: existingMessage,
                senderInfo: senderInfo,
                innerContent: innerContent,
                chat: chat,
                didCreateTribe: false
            )
        } else {
            print("Tribe not found")
        }
        
        return nil
    }
    
    func processIncomingPaidMessageEvent(
        message: Msg,
        existingMessage: TransactionMessage?,
        senderInfo: ContactServerResponse?,
        genericIncomingMessage: GenericIncomingMessage?,
        contact: UserContact?,
        tribe: Chat?,
        owner: UserContact? = nil
    ) -> TransactionMessage? {
        guard let type = message.type,
              let _ = message.sender,
              let _ = message.index,
              let _ = message.uuid,
              let date = message.date,
              let _ = senderInfo,
              let genericIncomingMessage = genericIncomingMessage else
        {
            return nil
        }
        
        guard let newMessage = processGenericIncomingMessage(
            message: genericIncomingMessage,
            existingMessage: existingMessage,
            invoiceForPayment: nil,
            csr: senderInfo,
            contact: contact,
            tribe: tribe,
            owner: owner,
            date: date,
            type: Int(type),
            fromMe: message.fromMe ?? false
        ) else {
            return nil
        }
        
        ///process purchase attempt
        if newMessage.type == TransactionMessage.TransactionMessageType.purchase.rawValue,
          let mediaToken = newMessage.mediaToken,
          let muid = TransactionMessage.getMUIDFrom(mediaToken: mediaToken),
          let encryptedAttachmentMessage = TransactionMessage.getAttachmentMessageWith(muid: muid, managedContext: self.backgroundContext),
          let purchaseMinAmount = encryptedAttachmentMessage.getAttachmentPrice(),
          let chat = newMessage.chat,
          let mediaKey = encryptedAttachmentMessage.mediaKey
        {
            if chat.isPublicGroup() {
                return nil
            }
            
            if Int(truncating: newMessage.amount ?? 0) + kRoutingOffset >= purchaseMinAmount {
                ///purchase of media received with sufficient amount
                let _ = sendMessage(
                    to: chat.getContact(),
                    content: "",
                    chat: chat,
                    provisionalMessage: nil,
                    owner: owner,
                    msgType: UInt8(TransactionMessage.TransactionMessageType.purchaseAccept.rawValue),
                    mediaKey: mediaKey,
                    threadUUID: nil,
                    replyUUID: nil,
                    paidAttachmentMediaToken: mediaToken,
                    context: backgroundContext
                )
            } else {
                ///purchase of media received but amount insufficient
                let _ = sendMessage(
                    to: chat.getContact(),
                    content: "",
                    chat: chat,
                    provisionalMessage: nil,
                    owner: owner,
                    amount: ((newMessage.amount as? Int) ?? 0) * 1000,
                    msgType: UInt8(TransactionMessage.TransactionMessageType.purchaseDeny.rawValue),
                    threadUUID: nil,
                    replyUUID: nil,
                    paidAttachmentMediaToken: mediaToken,
                    context: backgroundContext
                )
            }
            newMessage.muid = muid
            
            return newMessage
        }
        
        return nil
    }
    
    func processIncomingInvoice(
        message: Msg,
        existingMessage: TransactionMessage?,
        senderInfo: ContactServerResponse?,
        genericIncomingMessage: GenericIncomingMessage?,
        contact: UserContact?,
        tribe: Chat?,
        owner: UserContact? = nil
    ) -> TransactionMessage? {
        guard let type = message.type,
              let _ = message.sender,
              let _ = message.index,
              let _ = message.uuid,
              let date = message.date,
              let _ = senderInfo,
              let genericIncomingMessage = genericIncomingMessage else
        {
            return nil
        }
        
        if let invoice = genericIncomingMessage.invoice {
            
            let prd = PaymentRequestDecoder()
            prd.decodePaymentRequest(paymentRequest: invoice)
            
            if let expiry = prd.getExpirationDate(),
                let amount = prd.getAmount(),
                let paymentHash = try? paymentHashFromInvoice(bolt11: invoice)
            {
                if let newMessage = processGenericIncomingMessage(
                    message: genericIncomingMessage,
                    existingMessage: existingMessage,
                    invoiceForPayment: nil,
                    csr: senderInfo,
                    contact: contact,
                    tribe: tribe,
                    owner: owner,
                    date: date,
                    amount: amount * 1000,
                    type: Int(type),
                    fromMe: message.fromMe ?? false
                ) {
                    newMessage.messageContent = prd.getMemo()
                    newMessage.paymentHash = paymentHash
                    newMessage.expirationDate = expiry
                    newMessage.invoice = genericIncomingMessage.invoice
                    newMessage.amountMsat = NSDecimalNumber(value: Int(truncating: newMessage.amount ?? 0) * 1000)
                    newMessage.status = TransactionMessage.TransactionMessageStatus.pending.rawValue
                    
                    return newMessage
                }
            }
        }
        return nil
    }
    
    func processGenericIncomingMessage(
        message: GenericIncomingMessage,
        existingMessage: TransactionMessage?,
        invoiceForPayment: TransactionMessage?,
        csr: ContactServerResponse? = nil,
        contact: UserContact?,
        tribe: Chat?,
        owner: UserContact? = nil,
        date: Date,
        amount: Int = 0,
        type: Int? = nil,
        status: Int? = nil,
        fromMe: Bool = false
    ) -> TransactionMessage? {
        
        let content = message.content
        
        guard let indexString = message.index,
            let index = Int(indexString),
            let pubkey = message.senderPubkey,
            let uuid = message.uuid else
        {
            return nil
        }
        
        if let _ = existingMessage {
            return nil
        }
        
        var chat : Chat? = nil
        var senderId: Int? = nil
        var receiverId: Int? = nil
        
        if let contact = contact {
            if let oneOnOneChat = contact.conversation {
                chat = oneOnOneChat
            } else {
                chat = createChat(for: contact, with: date, context: backgroundContext)
            }
            
            let userid = UserData.sharedInstance.getUserId(context: backgroundContext)
            senderId = (fromMe == true) ? userid : contact.id
            receiverId = (fromMe == true) ? contact.id : userid
            
            if fromMe {
                if let owner = owner, let pubKey = owner.publicKey {
                    updateContactInfoFromMessage(
                        contact: owner,
                        alias: message.alias,
                        photoUrl: message.photoUrl,
                        pubkey: pubKey,
                        isOwner: true
                    )
                }
            } else {
                updateContactInfoFromMessage(
                    contact: contact,
                    alias: message.alias,
                    photoUrl: message.photoUrl,
                    pubkey: pubkey
                )
            }
            
        } else if let tribeChat = tribe {
            chat = tribeChat
            senderId = tribeChat.id
        }
        
        guard let chat = chat,
              let senderId = senderId else
        {
            return nil
        }
        
        let newMessage = TransactionMessage(context: backgroundContext)
        
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
        newMessage.receiverId = receiverId ?? -1
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
        newMessage.muid = TransactionMessage.getMUIDFrom(mediaToken: message.mediaToken)
        newMessage.paymentHash = message.paymentHash
        newMessage.tag = message.tag
        
        if let myAlias = chat.myAlias ?? owner?.nickname, chat.isPublicGroup() {
            newMessage.push = content?.contains("@\(myAlias) ") == true
        } else {
            newMessage.push = false
        }
        
        let msgAmount = message.amount ?? amount
        newMessage.amount = NSDecimalNumber(value: msgAmount / 1000)
        newMessage.amountMsat = NSDecimalNumber(value: msgAmount)
        
        if let invoiceForPayment = invoiceForPayment {
            invoiceForPayment.status = TransactionMessage.TransactionMessageStatus.confirmed.rawValue
        }

        if let timezone = message.tz {
            if chat.isGroup() {
                newMessage.remoteTimezoneIdentifier = timezone
            } else {
                if (!isV2Restore || chat.remoteTimezoneIdentifier == nil) && !fromMe {
                    chat.remoteTimezoneIdentifier = timezone
                }
            }
        }
                
        newMessage.setAsLastMessage()
        
        return newMessage
    }
    
    func createKeyExchangeMsgFrom(
        msg: Msg,
        existingContact: UserContact?,
        existingMessage: TransactionMessage?
    ) {
        guard let contact = existingContact else {
            return
        }
        
        guard let index = msg.index, let intIndex = Int(index), let msgType = msg.type else {
            return
        }
        
        let allowedTypes = [
            UInt8(TransactionMessage.TransactionMessageType.unknown.rawValue),
            UInt8(TransactionMessage.TransactionMessageType.contactKey.rawValue),
            UInt8(TransactionMessage.TransactionMessageType.contactKeyConfirmation.rawValue)
        ]
        
        if !allowedTypes.contains(msgType) {
            return
        }
        
        if let _ = existingMessage {
            return
        }
        
        let newMessage = TransactionMessage(context: backgroundContext)
        
        newMessage.id = intIndex
        newMessage.uuid = msg.uuid
        
        if let timestamp = msg.timestamp,
           let dateFromMessage = timestampToDate(timestamp: UInt64(timestamp))
        {
            newMessage.createdAt = dateFromMessage
            newMessage.updatedAt = dateFromMessage
            newMessage.date = dateFromMessage
        } else {
            let date = Date()
            newMessage.createdAt = date
            newMessage.updatedAt = date
            newMessage.date = date
        }
        
        newMessage.status = TransactionMessage.TransactionMessageStatus.confirmed.rawValue
        newMessage.type = Int(msgType)
        newMessage.encrypted = true
        newMessage.senderId = contact.id
        newMessage.push = false
        newMessage.chat = contact.getChat()
        newMessage.chat?.seen = false
        newMessage.messageContent = msg.message
    }
    
    func updateContactInfoFromMessage(
        contact: UserContact,
        alias: String?,
        photoUrl: String?,
        pubkey: String,
        isOwner: Bool = false
    ) {
        ///Avoid updating it again since it was already updated from most recent messahe
        if restoredContactInfoTracker.contains(pubkey) && isV2Restore {
            return
        }
        
        if isOwner && isV2Restore {
            ///Just update Owner during restore if  nickname or photo Url was not set during restore and last message has a valid one
            if (
                (contact.nickname == nil || contact.nickname?.isEmpty == true) &&
                alias != nil &&
                alias?.isEmpty == false
            ) {
                contact.nickname = alias
            }
            
            if (
                (contact.avatarUrl == nil || contact.avatarUrl?.isEmpty == true) &&
                photoUrl != nil &&
                photoUrl?.isEmpty == false
            ) {
                contact.avatarUrl = photoUrl
            }
        } else {
            if (alias != nil && alias?.isEmpty == false && contact.nickname != alias) {
                contact.nickname = alias
            }
            
            if (photoUrl != nil && photoUrl?.isEmpty == false && contact.avatarUrl != photoUrl) {
                contact.avatarUrl = photoUrl
            }
        }
        
        if isV2Restore {
            restoredContactInfoTracker.append(pubkey)
        }
    }
    
    func processIndexUpdate(
        message: Msg,
        cachedMessage: TransactionMessage?
    ) {
        if isMyMessageNeedingIndexUpdate(msg: message),
            let uuid = message.uuid,
            let cachedMessage = cachedMessage ?? TransactionMessage.getMessageWith(uuid: uuid, context: backgroundContext),
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
            if challenge.isBase64Encoded {
                let resultBase64 = try signBase64(
                    seed: seed,
                    idx: 0,
                    time: getTimeWithEntropy(),
                    network: network,
                    msg: challenge
                )
                return resultBase64
            }
            
            if let challengeData = challenge.nonBase64Data {
                let resultHex = try signBytes(
                    seed: seed,
                    idx: 0,
                    time: getTimeWithEntropy(),
                    network: network,
                    msg: challengeData
                )
                
                let resultBase64 = Data(hexString: resultHex)?
                    .base64EncodedString().urlSafe
                
                return resultBase64
            }
            
            return nil
        } catch {
            return nil
        }
    }
    
    func getSignedToken() -> String? {
        guard let seed = self.getAccountSeed() else {
            return nil
        }
        do {
            let idx: UInt64 = 0
            
            let token = try Sphinx.signedTimestamp(
                seed: seed,
                idx: idx,
                time: getTimeWithEntropy(),
                network: network
            )
            
            return token
        } catch {
            return nil
        }
    }
    
    func payAttachment(
        message: TransactionMessage,
        price: Int
    ){
        guard let chat = message.chat else{
            return
        }
         
        let _ = sendMessage(
            to: message.chat?.getContact(),
            content: "",
            chat: chat,
            provisionalMessage: nil,
            amount: price * 1000,
            msgType: UInt8(TransactionMessage.TransactionMessageType.purchase.rawValue),
            muid: message.muid,
            threadUUID: nil,
            replyUUID: message.uuid,
            paidAttachmentMediaToken: message.mediaToken
        )
    }
    

    func sendAttachment(
        file: NSDictionary,
        attachmentObject: AttachmentObject,
        chat: Chat?,
        provisionalMessage: TransactionMessage? = nil,
        replyingMessage: TransactionMessage? = nil,
        threadUUID: String? = nil
    ) -> (TransactionMessage?, String?) {
        
        guard let muid = file["muid"] as? String,
            let chat = chat,
            let mk = attachmentObject.mediaKey else
        {
            return (nil, "MUID or mediaKey not found")
        }
        
        let (_, mediaType) = attachmentObject.getFileAndMime()
        
        //Create JSON object and push through onion network
        var recipContact : UserContact? = nil
        
        if let contact = chat.getContact() {
            recipContact = contact
        }
        
        let type = (TransactionMessage.TransactionMessageType.attachment.rawValue)
        let purchaseAmt = (attachmentObject.price > 0) ? (attachmentObject.price) : nil
        
        let (sentMessage, errorMessage) = sendMessage(
            to: recipContact,
            content: attachmentObject.text ?? "",
            chat: chat,
            provisionalMessage: provisionalMessage,
            purchaseAmount: purchaseAmt,
            msgType: UInt8(type),
            muid: muid,
            mediaKey: mk,
            mediaType: mediaType,
            threadUUID: threadUUID,
            replyUUID: replyingMessage?.uuid
        )
        
        if let sentMessage = sentMessage {
            if (type == TransactionMessage.TransactionMessageType.attachment.rawValue) {
                AttachmentsManager.sharedInstance.cacheImageAndMediaData(message: sentMessage, attachmentObject: attachmentObject)
            } else if (type == TransactionMessage.TransactionMessageType.purchase.rawValue) {
                print(sentMessage)
            }
            
            return (sentMessage, nil)
        }
        
        return (nil, errorMessage ?? "generic.error.message".localized)
    }
    
    //MARK: Payments related
    func sendBoostReply(
        params: [String: AnyObject],
        chat: Chat,
        completion: @escaping (TransactionMessage?) -> ()
    ) {
        let pubkey = chat.getContact()?.publicKey ?? chat.ownerPubkey
        let routeHint = chat.getContact()?.routeHint
        
        guard let _ = params["reply_uuid"] as? String,
              let _ = params["text"] as? String,
              let pubkey = pubkey,
              let amount = params["amount"] as? Int else
        {
            completion(nil)
            return
        }
        
        if chat.isPublicGroup(), let _ = chat.ownerPubkey {
            ///If it's a tribe and I'm already in, then there's a route
            let message = self.finalizeSendBoostReply(
                params: params,
                chat: chat
            )
            completion(message)
            return
        }
        
        checkAndFetchRouteTo(
            publicKey: pubkey,
            routeHint: routeHint,
            amtMsat: amount
        ) { success in
            if success {
                let message = self.finalizeSendBoostReply(
                    params: params,
                    chat: chat
                )
                completion(message)
            } else {
                AlertHelper.showAlert(
                    title: "Routing Error",
                    message: "There was a routing error. Please try again."
                )
                completion(nil)
            }
        }
    }
    
    func sendFeedBoost(
        params: [String: AnyObject],
        chat: Chat,
        completion: @escaping (TransactionMessage?) -> ()
    ) {
        let pubkey = chat.getContact()?.publicKey ?? chat.ownerPubkey
        
        guard let _ = params["text"] as? String,
              let _ = pubkey,
              let _ = params["amount"] as? Int else
        {
            completion(nil)
            return
        }
        
        let message = self.finalizeSendBoostReply(
            params: params,
            chat: chat
        )
        completion(message)
    }
    
    func finalizeSendBoostReply(
        params: [String: AnyObject],
        chat: Chat
    ) -> TransactionMessage? {
        
        guard let text = params["text"] as? String,
            let amount = params["amount"] as? Int else
        {
            return nil
        }
        
        let (sentMessage, _) = self.sendMessage(
            to: chat.getContact(),
            content: text,
            chat: chat,
            provisionalMessage: nil,
            amount: amount,
            msgType: UInt8(TransactionMessage.TransactionMessageType.boost.rawValue),
            threadUUID: nil,
            replyUUID: params["reply_uuid"] as? String
        )
        
        return sentMessage
    }
    
    func sendDirectPaymentMessage(
        amount: Int,
        muid: String?,
        content: String?,
        chat: Chat,
        completion: @escaping (Bool, TransactionMessage?) -> ()
    ) {
        guard let contact = chat.getContact(),
              let pubkey = contact.publicKey else
        {
            return
        }
        
        checkAndFetchRouteTo(
            publicKey: pubkey,
            routeHint: contact.routeHint,
            amtMsat: amount
        ) { success in
            if(success){
                self.finalizeDirectPayment(
                    amount: amount,
                    muid: muid,
                    content: content,
                    chat: chat,
                    completion: { success, message in
                        completion(success, message)
                    }
                )
            } else {
                completion(false,nil)
            }
        }
    }
    
    func finalizeDirectPayment(
        amount: Int,
        muid: String?,
        content: String?,
        chat: Chat,
        completion: @escaping (Bool, TransactionMessage?) -> ()
    ){
        guard let contact = chat.getContact() else {
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
            mediaType: "image/png",
            threadUUID: nil,
            replyUUID: nil
        ).0 {
//            SphinxOnionManager.sharedInstance.assignReceiverId(localMsg: sentMessage)
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
    ) -> Bool {
        guard let seed = getAccountSeed() else{
            return false
        }
        
        guard let _ = mqtt else {
            return false
        }
        
        guard let recipPubkey = (recipContact?.publicKey ?? chat.ownerPubkey) else {
            return false
        }
        
        do {
            let rr = try Sphinx.read(
                seed: seed,
                uniqueTime: getTimeWithEntropy(),
                state: loadOnionStateAsData(),
                pubkey: recipPubkey,
                msgIdx: index
            )
            let _ = handleRunReturn(rr: rr)
            return true
        } catch {
            print("Error setting read level")
            return false
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
    
    func getMessagesStatusForPendingMessages() {
        let dispatchQueue = DispatchQueue.global(qos: .utility)
        dispatchQueue.async {
            let backgroundContext = self.backgroundContext
            
            backgroundContext.performAndWait {
                let messages = TransactionMessage.getAllNotConfirmed()
                
                if messages.isEmpty {
                    return
                }
                
                Task {
                    for i in stride(from: 0, to: messages.count, by: 200) {
                        let chunk = Array(messages[i..<min(i + 200, messages.count)])
                        
                        let tags = chunk.compactMap({ $0.tag })
                        
                        SphinxOnionManager.sharedInstance.getMessagesStatusFor(tags: tags)
                        
                        try? await Task.sleep(nanoseconds: 500_000_000)
                    }
                }
            }
            
            backgroundContext.saveContext()
        }
    }
    
    func getMessagesStatusFor(tags: [String]) {
        guard let seed = getAccountSeed() else{
            return
        }
        
        do {
            let rr = try Sphinx.getTags(
                seed: seed,
                uniqueTime: getTimeWithEntropy(),
                state: loadOnionStateAsData(),
                tags: tags,
                pubkey: nil
            )
            let _ = handleRunReturn(rr: rr)
        } catch {
            print("Error getting read level")
        }
    }
    
    @objc func getFetchRequestFor(
        chat: Chat,
        with items: Int
    ) -> NSFetchRequest<TransactionMessage> {
        return TransactionMessage.getChatMessagesFetchRequest(
            for: chat,
            with: items
        )
    }
    
    func getFetchMinIndex(
        fetchRequest: NSFetchRequest<TransactionMessage>,
        context: NSManagedObjectContext
    ) -> Int? {
        var objects: [TransactionMessage] = [TransactionMessage]()
        
        do {
            try objects = context.fetch(fetchRequest)
        } catch let error as NSError {
            print("Error: " + error.localizedDescription)
        }
        
        return objects.last?.id
    }
    
    func batchDeleteOldMessagesInBackground(
        forChat chat: Chat,
        keepingLatest count: Int = 100
    ) {
        DispatchQueue.global(qos: .utility).async {
            let backgroundContext = CoreDataManager.sharedManager.getBackgroundContext()
            
            backgroundContext.perform {
                do {
                    let fetchRequest = self.getFetchRequestFor(
                        chat: chat,
                        with: count
                    )
                    
                    if let thresholdId = self.getFetchMinIndex(fetchRequest: fetchRequest, context: backgroundContext) {
                        print("🔍 Will delete messages with id < \(thresholdId) from chat \(chat.id)")
                        
                        // Step 2: Create fetch request for messages to delete
                        let deleteRequest: NSFetchRequest<TransactionMessage> = TransactionMessage.fetchRequest()
                        deleteRequest.predicate = NSPredicate(format: "chat.id == %d AND id < %d", chat.id, thresholdId)
                        
                        // Step 3: Create batch delete request with the fetch request
                        let batchDelete = NSBatchDeleteRequest(fetchRequest: deleteRequest as! NSFetchRequest<NSFetchRequestResult>)
                        batchDelete.resultType = .resultTypeCount // Get count of deleted objects
                        
                        let result = try backgroundContext.execute(batchDelete) as? NSBatchDeleteResult
                        let deletedCount = result?.result as? Int ?? 0
                        
                        if deletedCount > 0 {
                            print("✅ Successfully deleted \(deletedCount) old messages from chat \(chat.id) in background")
                            
                            // Step 4: Save the context - this will automatically merge to parent contexts
                            try backgroundContext.save()
                            print("💾 Saved deletion changes to persistent store")
                        } else {
                            print("ℹ️ No messages were deleted from chat \(chat.id)")
                        }
                    }
                } catch {
                    print("❌ Background batch delete failed for chat \(chat.id): \(error)")
                }
            }
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
