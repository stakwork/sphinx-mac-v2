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
        inviteCode: String? = nil,
        completion: (([String:AnyObject]) ->())? = nil,
        isSendingMessage: Bool = false,
        skipSettleTopic: Bool = false,
        skipAsyncTopic: Bool = false
    ) -> String? {
        
        if let topic = topic {
            print("V2 Received topic: \(topic)")
        }
        
        ///If re-processing delayed RR Object then all inside this IF has been run already. Then skip
        if !skipSettleTopic && !skipAsyncTopic {
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
            
            ///Handling tribes restore before messages restore
            restoreTribesFrom(
                rr: rr,
                topic: topic
            ) { [weak self] rr, topic in
                
                ///handling contacts restore
                self?.restoreContactsFrom(messages: rr.msgs)
                
                ///Handling key exchange msgs restore
                self?.processKeyExchangeMessages(rr: rr)
                
                ///Handling invoice paid
                self?.processInvoicePaid(rr: rr)
                
                ///Handling generic msgs restore
                self?.processGenericMessages(rr: rr)
                
                ///Handling messages statused
                self?.handleMessagesStatus(tags: rr.tags)
                
                ///Handling incoming tags
                self?.handleMessageStatusByTag(rr: rr)
                
                ///Handling read status
                self?.handleReadStatus(rr: rr)
                
                ///Handling ping done
                self?.handlePingDone(msgs: rr.msgs)
                
                ///Handling restore callbacks
                self?.handleRestoreCallbacks(topic: topic, messages: rr.msgs)
            }
            
            ///Handling settle status
            handleSettledStatus(settledStatus: rr.settledStatus)
            
            ///Handling async tag
            handleAsyncTag(asyncTag: rr.asyncpayTag)
            
            ///Handling pings
            handlePing(ping: rr.ping)

            ///Handling mute levels
            handleMuteLevels(rr: rr)
            
            ///Handling invoice paid status
            handleInvoiceSentStatus(sentStatus: rr.sentStatus)
            
            ///Handling error
            handleError(error: rr.error)
            
            ///Handling new invites
            handleNewInvite(newInvite: rr.newInvite, messages: rr.msgs)
            
            ///Handling tribe members
            handleTribeMembers(tribeMembers: rr.tribeMembers)
            
            ///Handling state to delete
            handleStateToDelete(stateToDelete: rr.stateToDelete)
            
            ///Handling Payment History
            handlePaymentsHistory(payments: rr.payments)
            
            ///Handling topics subscription
            handleTopicsToSubscribe(topics: rr.subscriptionTopics)
        }
            
        //Publishing to topics
        ///Handling settle topics to publish
        if !skipSettleTopic && handleTopicToPush(
            topic: rr.settleTopic,
            payload: rr.settlePayload
        ) {
            let lastKey = delayedRRObjects.keys.max() ?? 0
            delayedRRObjects[lastKey + 1] = rr
            
            startDelayedRRTimeoutTimer(for: lastKey + 1)
            return nil
        }
        
        ///Handling register topics to publish
        handleRegisterTopic(
            rr: rr,
            skipAsyncTopic: skipAsyncTopic
        ) { [weak self] rr, skipAsyncTopic in
            guard let self = self else {
                return
            }
            ///Handling async pay topics to publish
            if !skipAsyncTopic && self.handleTopicToPush(
                topic: rr.asyncpayTopic,
                payload: rr.asyncpayPayload
            ) {
                let lastKey = self.delayedRRObjects.keys.min() ?? 0
                self.delayedRRObjects[lastKey - 1] = rr
                
                self.startDelayedRRTimeoutTimer(for: lastKey - 1)
                return
            }
            
            ///Handling topics to publish on MQTT
            self.handleTopicsToPush(topics: rr.topics, payloads: rr.payloads)
        }
        
        return getMessageTag(messages: rr.msgs, isSendingMessage: isSendingMessage)
    }
    
    func updateStateMap(stateMap: Data?) {
        if let stateMap = stateMap {
            let _ = storeOnionState(inc: stateMap.bytes)
        }
    }
    
    func handlePaymentsHistory(payments: String?) {
        if let payments = payments, payments != "[]" {
            if let paymentsHistoryCallback = paymentsHistoryCallback {
                paymentsHistoryCallback(payments, nil)
                
                self.paymentsHistoryCallback = nil
            }
        }
    }
    
    func handleTribeCreation(newTribe: String?) {
        if let newTribe = newTribe {
            if let createTribeCallback = createTribeCallback {
                createTribeCallback(newTribe)
                self.createTribeCallback = nil
            }
        }
    }
    
    func handleOwnerContact(myContactInfo: String?) {
        if let myContactInfo = myContactInfo {
            backgroundContext.perform { [weak self] in
                guard let self = self else {
                    return
                }
                if let components = self.parseContactInfoString(
                    fullContactInfo: myContactInfo
                ), UserContact.getContactWithDisregardStatus(
                    pubkey: components.0,
                    managedContext: self.backgroundContext
                ) == nil {
                    ///only add this if we don't already have a "self" contact
                    let _ = self.createSelfContact(
                        scid: components.2,
                        serverPubkey: components.1,
                        myOkKey: components.0,
                        context: self.backgroundContext
                    )
                    
                    self.backgroundContext.saveContext()
                }
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
            if let data = settledStatus.data(using: .utf8) {
                do {
                    if let dictionary = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any?] {
                        if let htlcId = dictionary["htlc_id"] as? String, let settleStatus = dictionary["status"] as? String, settleStatus == SphinxOnionManager.kCompleteStatus {
                            
                            if let RRObject = delayedRRObjects.filter({
                                return $0.value.msgs.filter({ $0.index == htlcId }).first != nil
                            }).first {
                                
                                delayedRRObjects.removeValue(forKey: RRObject.key)
                                
                                let _ = handleRunReturn(
                                    rr: RRObject.value,
                                    skipSettleTopic: true
                                )
                            }
                        }
                    }
                } catch {
                    print("Error decoding JSON: \(error)")
                }
            }
        }
    }
    
    func handleAsyncTag(asyncTag: String?) {
        if let asyncTag = asyncTag {
            if let RRObject = delayedRRObjects.filter({
                return $0.value.msgs.filter({ $0.tag == asyncTag }).first != nil
            }).first {
                
                delayedRRObjects.removeValue(forKey: RRObject.key)
                
                let _ = handleRunReturn(
                    rr: RRObject.value,
                    skipSettleTopic: true,
                    skipAsyncTopic: true
                )
            }
        }
    }
    
    func handlePing(ping: String?) {
        if let ping = ping {
            if let (paymentHash, timestamp, tag) = ping.pingComponents {
                if paymentHash != "_" {
                    pingsMap[paymentHash] = timestamp
                }
                
                if let tag = tag {
                    pingsMap[tag] = timestamp
                }
            }
        }
    }
    
    func handlePingDone(
        msgs: [Msg]
    ) {
        if msgs.isEmpty {
            return
        }
        
        guard let seed = getAccountSeed() else {
            return
        }
        
        for paymentHash in msgs.filter({ $0.paymentHash != nil && $0.paymentHash?.isEmpty == false }).compactMap({ $0.paymentHash! }) {
            if let timestamp = pingsMap[paymentHash], let intTimestamp = UInt64(timestamp) {
                do {
                    let rr = try Sphinx.pingDone(
                        seed: seed,
                        uniqueTime: getTimeWithEntropy(),
                        state: loadOnionStateAsData(),
                        pingTs: intTimestamp
                    )
                    let _ = handleRunReturn(rr: rr)
                    removeFromPingsMapWith(paymentHash)
                } catch {
                    print("Error calling ping done")
                }
            }
        }
    }
    
    func startDelayedRRTimeoutTimer(
        for key: Int
    ) {
        delayedRRTimers[key]?.invalidate()

        let timer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] timer in
            self?.handleDelayedRRTimeout(for: key)
        }
        
        delayedRRTimers[key] = timer
    }

    func handleDelayedRRTimeout(
        for key: Int
    ) {
        guard let object = delayedRRObjects[key] else {
            return
        }
        
        delayedRRObjects.removeValue(forKey: key)
        
        if key < 0 {
            let _ = handleRunReturn(
                rr: object,
                skipSettleTopic: true,
                skipAsyncTopic: true
            )
        }
    }
    
    func handleError(error: String?) {
        if let error = error {
            print("Run return object error: \(error)")
            
            if error.contains("async pay not found") {
                for tag in pingsMap.keys {
                    if error.contains(tag) {
                        guard let seed = getAccountSeed() else {
                            return
                        }
                        
                        if let timestamp = pingsMap[tag], let intTimestamp = UInt64(timestamp) {
                            do {
                                let rr = try Sphinx.pingDone(
                                    seed: seed,
                                    uniqueTime: getTimeWithEntropy(),
                                    state: loadOnionStateAsData(),
                                    pingTs: intTimestamp
                                )
                                let _ = handleRunReturn(rr: rr)
                                removeFromPingsMapWith(tag)
                            } catch {
                                print("Error calling ping done")
                            }
                            
                        }
                    }
                }
            }
        }
    }
    
    func removeFromPingsMapWith(_ key: String) {
        if let value = pingsMap[key] {
            for (key, _) in pingsMap.filter({ $0.value == value }) {
                pingsMap.removeValue(forKey: key)
            }
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
        if topic?.isMessagesFetchResponse == true {
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
           let tag = sentStatus.tag
        {
            backgroundContext.perform { [weak self] in
                guard let self = self else {
                    return
                }
                if let cachedMessage = TransactionMessage.getMessageWith(tag: tag, context: self.backgroundContext) {
                    if (sentStatus.status == SphinxOnionManager.kCompleteStatus) {
                        cachedMessage.status = TransactionMessage.TransactionMessageStatus.received.rawValue
                    } else if (sentStatus.status == SphinxOnionManager.kFailedStatus) {
                        cachedMessage.status = TransactionMessage.TransactionMessageStatus.failed.rawValue
                    }
                    
//                    if let uuid = cachedMessage.uuid {
//                        self.receivedOMuuid(uuid)
//                    }
                    
                    if cachedMessage.paymentHash == nil {
                        cachedMessage.paymentHash = sentStatus.paymentHash
                    }
                    
                    self.backgroundContext.saveContext()
                } else {
                    self.onPaymentStatusReceivedFor(
                        tag: tag,
                        status: sentStatus.status ?? SphinxOnionManager.kFailedStatus
                    )
                }
            }
        }
    }
    
    func handleTopicsToPush(topics: [String], payloads: [Data]) {
        DelayPerformedHelper.performAfterDelay(seconds: 0.5, completion: {
            for i in 0..<topics.count {
                let _ = self.handleTopicToPush(
                    topic: topics[i],
                    payload: payloads[i]
                )
            }
        })
    }
    
    func handleTopicToPush(
        topic: String?,
        payload: Data?
    ) -> Bool {
        if let topic = topic, let payload = payload {
            let byteArray: [UInt8] = [UInt8](payload)
            
            self.mqtt?.publish(
                CocoaMQTTMessage(
                    topic: topic,
                    payload: byteArray
                )
            )
            return true
        }
        return false
    }
    
    func handleRegisterTopic(
        rr: RunReturn,
        skipAsyncTopic: Bool,
        callback: @escaping (RunReturn, Bool) -> ()
    ) {
        if let topic = rr.registerTopic, let payload = rr.registerPayload {
            let byteArray: [UInt8] = [UInt8](payload)
            
            self.mqtt?.publish(
                CocoaMQTTMessage(
                    topic: topic,
                    payload: byteArray
                )
            )
            
            DelayPerformedHelper.performAfterDelay(seconds: 0.25, completion: {
                callback(rr, skipAsyncTopic)
            })
            
        } else {
            callback(rr, skipAsyncTopic)
        }
    }
    
    func handleTopicsToSubscribe(topics: [String]) {
        for topic in topics {
            self.mqtt.subscribe([
                (topic, CocoaMQTTQoS.qos1)
            ])
        }
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
        if isSendingMessage, messages.count > 0,
           let tag = messages[0].tag
        {
            return tag
        }
        return nil
    }
    
    func handleMessagesStatus(tags: String?) {
        if let tags = tags {
            if let data = tags.data(using: .utf8) {
                do {
                    if let array = try JSON(data: data).array {
                        var dictionary: [String: MessageStatusMap] = [:]

                        for message in array {
                            if let dictionaryObject = message.dictionaryObject, let messageStatus = MessageStatusMap(JSON: dictionaryObject) {
                                if let tag = messageStatus.tag {
                                    dictionary[tag] = messageStatus
                                }
                            }
                        }

                        let tags = array.compactMap({ $0["tag"].stringValue }).filter({ $0.isNotEmpty })
                        
                        if tags.isEmpty {
                            return
                        }

                        backgroundContext.perform { [weak self] in
                            guard let self = self else {
                                return
                            }
                            
                            var chatIds: [Int] = []
                            
                            for message in TransactionMessage.getMessagesWith(tags: tags, context: self.backgroundContext) {
                                if let messageStatus = dictionary[message.tag ?? ""] {
                                    if messageStatus.isReceived() {
                                        if message.isInvoice() {
                                            if message.status == TransactionMessage.TransactionMessageStatus.pending.rawValue {
                                                ///Just set invoice as received if pending. Otherwise it might be confirmed/paid and revert to received when this happens
                                                message.status = TransactionMessage.TransactionMessageStatus.received.rawValue
                                            }
                                        } else {
                                            message.status = TransactionMessage.TransactionMessageStatus.received.rawValue
                                        }
                                    } else if messageStatus.isFailed() {
                                        message.status = TransactionMessage.TransactionMessageStatus.failed.rawValue
                                    }
                                }
                                
                                if let chatId = message.chat?.id, !chatIds.contains(chatId) {
                                    chatIds.append(chatId)
                                }
                            }
                            
                            self.backgroundContext.saveContext()
                            
                            if !chatIds.isEmpty {
                                let userInfo: [String: [Int]] = ["chat-ids" : chatIds]
                                NotificationCenter.default.post(name: .shouldReloadChatLists, object: nil, userInfo: userInfo)
                            }
                        }
                    }
                } catch {
                    print("Error decoding JSON: \(error)")
                }
            }
        }
    }

}
