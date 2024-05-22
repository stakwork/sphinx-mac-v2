//
//  SphinxOnionManager+HandleStateExtension.swift
//  sphinx
//
//  Created by James Carucci on 12/19/23.
//  Copyright © 2023 sphinx. All rights reserved.
//

import Foundation
import MessagePack
import CocoaMQTT
import ObjectMapper
import SwiftyJSON


extension SphinxOnionManager {
    func handleRunReturn(
        rr: RunReturn,
        topic: String? = nil,
        completion: (([String:AnyObject]) ->())? = nil,
        isSendingMessage: Bool = false
    ) -> String? {
        
        if let topic = topic {
            print("V2 Received topic: \(topic)")
        }
        
        ///Update state mape
        updateStateMap(stateMap: rr.stateMp)
        
        ///Handling new tribe crated
        handleTribeCreation(newTribe: rr.newTribe)
        
        ///Handling owner contact
        handleOwnerContact(myContactInfo: rr.myContactInfo)
        
        ///Handling balance update
        handleBalanceUpdate(newBalance: rr.newBalance)
        
        ///Handling messages totals
        handleMessagesCount(msgsCounts: rr.msgsCounts)
        
        ///Handling tribes restore
        restoreTribesFrom(messages: rr.msgs)
        
        ///handling contacts restore
        restoreContactsFrom(messages: rr.msgs)
        
        ///Handling messages restore
        processKeyExchangeMessages(rr: rr)
        processGenericMessages(rr: rr)
        
        ///Handling tribe members
        handleTribeMembers(tribeMembers: rr.tribeMembers)
        
        ///Handling invoice paid status
        handleInvoiceSentStatus(sentStatus: rr.sentStatus)
        
        ///Handling settle status
        handleSettledStatus(settledStatus: rr.settledStatus)
        
        ///Handling error
        handleError(error: rr.error)
        
        ///Handling new invites
        handleNewInvite(newInvite: rr.newInvite, messages: rr.msgs)
        
        ///Handling incoming tags
        handleMessageStatusByTag(rr: rr)
        
        ///Handling read status
        handleReadStatus(rr: rr)

        ///Handling mute levels
        handleMuteLevels(rr: rr)
        
        ///Handling state to delete
        handleStateToDelete(stateToDelete: rr.stateToDelete)
        
        ///Handling restore callbacks
        handleRestoreCallbacks(topic: topic, messages: rr.msgs)
        
        ///Handling topics to publish on MQTT
        handleTopicsToPush(topics: rr.topics, payloads: rr.payloads)
        
        return getMessageTag(messages: rr.msgs, isSendingMessage: isSendingMessage)
    }
    
    func updateStateMap(stateMap: Data?) {
        if let stateMap = stateMap {
            let _ = storeOnionState(inc: stateMap.bytes)
        }
    }
    
    func handleTribeCreation(newTribe: String?) {
        if let newTribe = newTribe {
            if let createTribeCallback = createTribeCallback {
                createTribeCallback(newTribe)
            }
        }
    }
    
    func handleOwnerContact(myContactInfo: String?) {
        if let myContactInfo = myContactInfo {
            if let components = parseContactInfoString(
                fullContactInfo: myContactInfo
            ), UserContact.getContactWithDisregardStatus(pubkey: components.0) == nil {
                ///only add this if we don't already have a "self" contact
                let _ = createSelfContact(
                    scid: components.2,
                    serverPubkey: components.1,
                    myOkKey: components.0
                )
                
                managedContext.saveContext()
            }
        }
    }
    
    func handleBalanceUpdate(newBalance: UInt64?) {
        if let newBalance = newBalance {
            self.walletBalanceService.balance = newBalance
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01, execute: {
                NotificationCenter.default.post(
                    Notification(
                        name: .onBalanceDidChange,
                        object: nil,
                        userInfo: ["balance" : newBalance]
                    )
                )
            })
        } 
    }
    
    func handleTribeMembers(tribeMembers: String?) {
        if let tribeMembersString = tribeMembers,
           let jsonData = tribeMembersString.data(using: .utf8),
           let jsonDict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        {
            var confirmedMembers: [TribeMembersRRObject] = []
            var pendingMembers: [TribeMembersRRObject] = []
            
            // Parse confirmed members
            if let confirmedArray = jsonDict["confirmed"] as? [[String: Any]] {
                confirmedMembers = confirmedArray.compactMap { Mapper<TribeMembersRRObject>().map(JSONObject: $0) }
            }
            
            // Parse pending members (assuming a similar structure for actual pending members)
            if let pendingArray = jsonDict["pending"] as? [[String: Any]] {
                pendingMembers = pendingArray.compactMap { Mapper<TribeMembersRRObject>().map(JSONObject: $0) }
            }
            
            // Assuming 'stashedCallback' expects a dictionary with confirmed and pending members
            if let completion = tribeMembersCallback {
                completion(
                    [
                        "confirmedMembers": confirmedMembers as AnyObject,
                        "pendingMembers": pendingMembers as AnyObject
                    ]
                )
                tribeMembersCallback = nil
            }
        }
    }
    
    func handleInvoiceSentStatus(sentStatus: String?) {
        if let sentStatus = sentStatus {
            if let data = sentStatus.data(using: .utf8) {
                do {
                    if let dictionary = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any?] {
                        if let paymentHash = dictionary["payment_hash"] as? String, !paymentHash.isEmpty,
                           let preimage = dictionary["preimage"] as? String,
                           !preimage.isEmpty
                        {
                            NotificationCenter.default.post(
                                name: .invoiceIPaidSettled,
                                object: nil,
                                userInfo: dictionary as [AnyHashable: Any]
                            )
                        }
                    }
                } catch {
                    print("Error decoding JSON: \(error)")
                }
            }
            
            if let sentStatus = SentStatus(JSONString: sentStatus) {
                processInvitePurchaseAcks(sentStatus: sentStatus)
            }
        }
    }
    
    func handleSettledStatus(settledStatus: String?) {
        if let settledStatus = settledStatus {
            print("Settled Status: \(settledStatus.debugDescription)")
        }
    }
    
    func handleError(error: String?) {
        if let error = error {
            print("Run return object error: \(error)")
        }
    }
    
    func handleNewInvite(
        newInvite: String?,
        messages: [Msg]
    ) {
        guard let newInvite = newInvite else {
            return
        }
        
        if messages.count > 0, let tag = messages[0].tag {
            self.pendingInviteLookupByTag[tag] = newInvite
        }
    }
    
    func processInvitePurchaseAcks(sentStatus: SentStatus) {
        guard let tag = sentStatus.tag else{
            return
        }
        if pendingInviteLookupByTag.keys.contains(tag) {
            let inviteCode = sentStatus.status != "COMPLETE" ? (nil) : (pendingInviteLookupByTag[tag])
            
            inviteCreationCallback?(inviteCode)
            
            pendingInviteLookupByTag.removeValue(forKey: tag)
        }
        
    }
    
    func handleMessagesCount(msgsCounts: String?) {
        if let msgsTotalsJSON = msgsCounts,
           let msgTotals = MsgTotalCounts(JSONString: msgsTotalsJSON)
        {
            msgTotalCounts = msgTotals
            totalMsgsCountCallback?()
        }
    }
    
    func handleRestoreCallbacks(
        topic: String?,
        messages: [Msg]
    ) {
        ///Restore callbacks
        if messages.count > 0 || topic?.isMessagesFetchResponse == true {
            if let firstSCIDMsgsCallback = firstSCIDMsgsCallback {
                firstSCIDMsgsCallback(messages)
            } else if let onMessageRestoredCallback = onMessageRestoredCallback {
                onMessageRestoredCallback(messages)
            }
        }
    }
    
    func handleMessageStatusByTag(rr: RunReturn) {
        if let sentStatusJSON = rr.sentStatus,
           let sentStatus = SentStatus(JSONString: sentStatusJSON),
           let tag = sentStatus.tag,
           let cachedMessage = TransactionMessage.getMessageWith(tag: tag)
        {
            if (sentStatus.status == kCompleteStatus) {
                 cachedMessage.status = TransactionMessage.TransactionMessageStatus.received.rawValue
            } else if (sentStatus.status == kFailedStatus) {
                cachedMessage.status = TransactionMessage.TransactionMessageStatus.failed.rawValue
            }
        }
    }
    
    func handleTopicsToPush(topics: [String], payloads: [Data]) {
        DelayPerformedHelper.performAfterDelay(seconds: 0.5, completion: {
            for i in 0..<topics.count {
                
                let byteArray: [UInt8] = payloads.count > i ? [UInt8](payloads[i]) : [UInt8]()
                
                print("V2 Requested topic: \(topics[i])")
                
                self.mqtt?.publish(
                    CocoaMQTTMessage(
                        topic: topics[i],
                        payload: byteArray
                    )
                )
            }
        })
    }
    
    func deleteContactFromState(pubkey: String) {
        let contactDictKey = "c/" + pubkey

        var state = loadOnionState()

        if state[contactDictKey] != nil {
            state.removeValue(forKey: contactDictKey)
            saveUpdatedOnionState(state: state)
        } else {
            print("No contact found with the specified pubkey:", pubkey)
        }
    }
    
    private func saveUpdatedOnionState(state: [String: [UInt8]]) {
        for key in state.keys {
            if let value = state[key] {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        UserDefaults.standard.synchronize()
        updateMutationKeys(with: state.keys.sorted())
    }

    private func updateMutationKeys(with keys: [String]) {
        mutationKeys = keys
    }
    
    func getMessageTag(
        messages: [Msg],
        isSendingMessage: Bool
    ) -> String? {
        if isSendingMessage,
           messages.count > 0,
           let tag = messages[0].tag
        {
            return tag
        }
        return nil
    }

    var mutationKeys: [String] {
        get {
            if let onionState: String = UserDefaults.Keys.onionState.get() {
                return onionState.components(separatedBy: ",")
            }
            return []
        }
        set {
            UserDefaults.Keys.onionState.set(
                newValue.joined(separator: ",")
            )
        }
    }
    
    func loadOnionStateAsData() -> Data {
        let state = loadOnionState()
        
        var mpDic = [MessagePackValue:MessagePackValue]()

        for (key, value) in state {
            mpDic[MessagePackValue(key)] = MessagePackValue(Data(value))
        }
        
        let stateBytes = pack(
            MessagePackValue(mpDic)
        ).bytes
        
        return Data(stateBytes)
    }

    private func loadOnionState() -> [String: [UInt8]] {
        var state:[String: [UInt8]] = [:]
        
        for key in mutationKeys {
            if let value = UserDefaults.standard.object(forKey: key) as? [UInt8] {
                state[key] = value
            }
        }
        return state
    }
    

    func storeOnionState(inc: [UInt8]) -> [NSNumber] {
        let muts = try? unpack(Data(inc))
        
        guard let mutsDictionary = (muts?.value as? MessagePackValue)?.dictionaryValue else {
            return []
        }
        
        persist_muts(muts: mutsDictionary)

        return []
    }

    private func persist_muts(muts: [MessagePackValue: MessagePackValue]) {
        var keys: [String] = []
        
        for  mut in muts {
            if let key = mut.key.stringValue, let value = mut.value.dataValue?.bytes {
                keys.append(key)
                UserDefaults.standard.removeObject(forKey: key)
                UserDefaults.standard.synchronize()
                UserDefaults.standard.set(value, forKey: key)
                UserDefaults.standard.synchronize()
            }
        }
        
        keys.append(contentsOf: mutationKeys)
        mutationKeys = keys
    }
    
    func handleStateToDelete(stateToDelete:[String]){
        for key in stateToDelete {
            UserDefaults.standard.removeObject(forKey: key)
            UserDefaults.standard.synchronize()
        }
    }

}

extension SphinxOnionManager {
    func timestampToDate(
        timestamp: UInt64
    ) -> Date? {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
        return date
    }
    
    func timestampToInt(
        timestamp: UInt64
    ) -> Int? {
        let dateInSeconds = Double(timestamp) / 1000.0
        return Int(dateInSeconds)
    }


    func isGroupAction(
        type: UInt8
    ) -> Bool {
        let intType = Int(type)
        return intType == TransactionMessage.TransactionMessageType.groupJoin.rawValue ||
                intType == TransactionMessage.TransactionMessageType.groupLeave.rawValue ||
                intType == TransactionMessage.TransactionMessageType.groupKick.rawValue ||
                intType == TransactionMessage.TransactionMessageType.groupDelete.rawValue ||
                intType == TransactionMessage.TransactionMessageType.memberRequest.rawValue ||
                intType == TransactionMessage.TransactionMessageType.memberApprove.rawValue ||
                intType == TransactionMessage.TransactionMessageType.memberReject.rawValue
    }
        

    func isMyMessageNeedingIndexUpdate(msg: Msg) -> Bool {
        if let _ = msg.uuid,
           let _ = msg.index {
            return true
        }
        return false
    }
}


struct ContactServerResponse: Mappable {
    var pubkey: String?
    var alias: String?
    var host:String?
    var photoUrl: String?
    var person: String?
    var code: String?
    var role: Int?
    var fullContactInfo: String?
    var recipientAlias: String?
    var confirmed: Bool?

    init?(map: Map) {}

    mutating func mapping(map: Map) {
        pubkey          <- map["pubkey"]
        alias           <- map["alias"]
        photoUrl        <- map["photo_url"]
        person          <- map["person"]
        code            <- map["code"]
        host            <- map["host"]
        role            <- map["role"]
        fullContactInfo <- map["fullContactInfo"]
        recipientAlias  <- map["recipientAlias"]
        confirmed       <- map["confirmed"]
    }
    
    func isTribeMessage() -> Bool {
        if let _ = role {
            return true
        }
        return false
    }
}

struct MessageInnerContent: Mappable {
    var content: String?
    var replyUuid: String? = nil
    var threadUuid: String? = nil
    var mediaKey: String? = nil
    var mediaToken: String? = nil
    var mediaType: String? = nil
    var muid: String? = nil
    var originalUuid: String? = nil
    var date: Int? = nil
    var invoice: String? = nil
    var paymentHash: String? = nil
    var amount: Int? = nil
    var fullContactInfo: String? = nil
    var recipientAlias: String? = nil

    init?(map: Map) {}
    
    mutating func mapping(map: Map) {
        content         <- map["content"]
        replyUuid       <- map["replyUuid"]
        threadUuid      <- map["threadUuid"]
        mediaToken      <- map["mediaToken"]
        mediaType       <- map["mediaType"]
        mediaKey        <- map["mediaKey"]
        muid            <- map["muid"]
        date            <- map["date"]
        originalUuid    <- map["originalUuid"]
        invoice         <- map["invoice"]
        paymentHash     <- map["paymentHash"]
        amount          <- map["amount"]
        fullContactInfo <- map["fullContactInfo"]
        recipientAlias  <- map["recipientAlias"]
    }
    
}


struct GenericIncomingMessage: Mappable {
    var content: String?
    var amount: Int?
    var senderPubkey: String? = nil
    var uuid: String? = nil
    var originalUuid: String? = nil
    var index: String? = nil
    var replyUuid: String? = nil
    var threadUuid: String? = nil
    var mediaKey: String? = nil
    var mediaToken: String? = nil
    var mediaType: String? = nil
    var muid: String? = nil
    var timestamp: Int? = nil
    var invoice: String? = nil
    var paymentHash: String? = nil
    var alias: String? = nil
    var fullContactInfo: String? = nil
    var photoUrl: String? = nil

    init?(map: Map) {}
    
    init(msg: Msg){
        
        if let fromMe = msg.fromMe, fromMe == true, let sentTo = msg.sentTo {
            self.senderPubkey = sentTo
        } else if let sender = msg.sender, let csr = ContactServerResponse(JSONString: sender) {
            self.senderPubkey = csr.pubkey
            self.photoUrl = csr.photoUrl
            self.alias = csr.alias
        }
        
        var innerContentAmount : UInt64? = nil
        
        if let message = msg.message,
           let innerContent = MessageInnerContent(JSONString: message)
        {
            self.content = innerContent.content
            self.replyUuid = innerContent.replyUuid
            self.threadUuid = innerContent.threadUuid
            self.mediaKey = innerContent.mediaKey
            self.mediaToken = innerContent.mediaToken
            self.mediaType = innerContent.mediaType
            self.muid = innerContent.muid
            self.originalUuid = innerContent.originalUuid
            self.invoice = innerContent.invoice
            self.paymentHash = innerContent.paymentHash
            
            innerContentAmount = UInt64(innerContent.amount ?? 0)
            
            if msg.type == 33 {
                self.alias = innerContent.recipientAlias
                self.fullContactInfo = innerContent.fullContactInfo
            }
            
            let isTribe = SphinxOnionManager.sharedInstance.isMessageTribeMessage(senderPubkey: self.senderPubkey ?? "")
            
            if let timestamp = msg.timestamp,
               isTribe == false
            {
                self.timestamp = Int(timestamp)
            } else {
                self.timestamp = innerContent.date
            }
        }
        
        if let invoice = self.invoice {
            let prd = PaymentRequestDecoder()
            prd.decodePaymentRequest(paymentRequest: invoice)
            
            let amount = prd.getAmount() ?? 0
            self.amount = amount * 1000 // convert to msat
        } else {
            self.amount = (msg.fromMe == true) ? Int((innerContentAmount) ?? 0) : Int((msg.msat ?? innerContentAmount) ?? 0)
        }
        
        self.uuid = msg.uuid
        self.index = msg.index
    }

    mutating func mapping(map: Map) {
        content    <- map["content"]
        amount     <- map["amount"]
        replyUuid  <- map["replyUuid"]
        threadUuid <- map["threadUuid"]
        mediaToken <- map["mediaToken"]
        mediaType  <- map["mediaType"]
        mediaKey   <- map["mediaKey"]
        muid       <- map["muid"]
        
    }
    
}

struct TribeMembersRRObject: Mappable {
    var pubkey: String? = nil
    var routeHint: String? = nil
    var alias: String? = nil
    var contactKey: String? = nil
    var is_owner: Bool = false
    var status: String? = nil

    init?(map: Map) {}

    mutating func mapping(map: Map) {
        pubkey       <- map["pubkey"]
        alias        <- map["alias"]
        routeHint    <- map["route_hint"]
        contactKey   <- map["contact_key"]
    }
    
}


class SentStatus: Mappable {
    var tag: String?
    var status: String?
    var preimage: String?
    var paymentHash: String?

    required init?(map: Map) {
    }

    func mapping(map: Map) {
        tag         <- map["tag"]
        status      <- map["status"]
        preimage    <- map["preimage"]
        paymentHash <- map["payment_hash"]
    }
}
