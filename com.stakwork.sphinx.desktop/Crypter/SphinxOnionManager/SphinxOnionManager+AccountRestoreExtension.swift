//
//  SphinxOnionManager+AccountRestore.swift
//  sphinx
//
//  Created by James Carucci on 3/20/24.
//  Copyright © 2024 sphinx. All rights reserved.
//

import Foundation
import CoreData
import ObjectMapper
import SwiftyJSON

class ChatsFetchParams {
    var restoreInProgress: Bool
    var itemsPerPage: Int
    var fetchStartIndex: Int
    var restoredItems: Int
    var restoredTribesPubKeys: [String] = []

    enum FetchDirection {
        case forward, backward
    }

    init(
        restoreInProgress: Bool,
        fetchStartIndex: Int,
        itemsPerPage: Int,
        restoredItems: Int
    ) {
        self.restoreInProgress = restoreInProgress
        self.fetchStartIndex = fetchStartIndex
        self.itemsPerPage = itemsPerPage
        self.restoredItems = restoredItems
        self.restoredTribesPubKeys = []
    }
    
    var debugDescription: String {
        return """
        restoreInProgress: \(restoreInProgress)
        fetchStartIndex: \(fetchStartIndex)
        itemsPerPage: \(itemsPerPage)
        """
    }
}

class MessageFetchParams {
    
    var itemsPerPage: Int
    var fetchStartIndex: Int
    var restoredItems: Int
    var stopIndex: Int
    var direction: FetchDirection

    enum FetchDirection {
        case forward, backward
    }

    init(
        fetchStartIndex: Int,
        itemsPerPage: Int,
        restoredItems: Int,
        stopIndex: Int,
        direction: FetchDirection
    ) {
        self.fetchStartIndex = fetchStartIndex
        self.itemsPerPage = itemsPerPage
        self.restoredItems = restoredItems
        self.stopIndex = stopIndex
        self.direction = direction
    }
    
    var debugDescription: String {
        return """
        fetchStartIndex: \(fetchStartIndex)
        itemsPerPage: \(itemsPerPage)
        stopIndex: \(stopIndex)
        """
    }
}

class MessagePerContactFetchParams {
    
    var itemsPerPage: Int
    var fetchStartIndex: Int
    var index: Int
    var direction: FetchDirection
    var chatPubkeys: [String]

    enum FetchDirection {
        case forward, backward
    }

    init(
        fetchStartIndex: Int,
        itemsPerPage: Int,
        index: Int,
        direction: FetchDirection,
        chatPubkeys: [String]
    ) {
        self.fetchStartIndex = fetchStartIndex
        self.itemsPerPage = itemsPerPage
        self.index = index
        self.direction = direction
        self.chatPubkeys = chatPubkeys
    }
    
    var debugDescription: String {
        return """
        fetchStartIndex: \(fetchStartIndex)
        itemsPerPage: \(itemsPerPage)
        index: \(index)
        chatPubkeys: \(chatPubkeys)
        """
    }
}

class MsgTotalCounts: Mappable {
    var totalMessageAvailableCount: Int?
    var okKeyMessageAvailableCount: Int?
    var firstMessageAvailableCount: Int?
    var totalMessageMaxIndex: Int?
    var okKeyMessageMaxIndex: Int?
    var firstMessageMaxIndex: Int?

    required init?(map: Map) {
    }

    func mapping(map: Map) {
        totalMessageAvailableCount  <- map["total"]
        okKeyMessageAvailableCount  <- map["ok_key"]
        firstMessageAvailableCount  <- map["first_for_each_scid"]
        totalMessageMaxIndex        <- map["total_highest_index"]
        okKeyMessageMaxIndex        <- map["ok_key_highest_index"]
        firstMessageMaxIndex        <- map["first_for_each_scid_highest_index"]
    }

    func hasOneValidCount() -> Bool {
        // Use an array to check for non-nil properties in a condensed form
        let properties = [totalMessageAvailableCount, okKeyMessageAvailableCount, firstMessageAvailableCount]
        return properties.contains(where: { $0 != nil })
    }
}

///account restore related
extension SphinxOnionManager {
    
    func isMnemonic(code: String) -> Bool {
        let words = code.split(separator: " ").map { String($0).trim().lowercased() }
        let (error, _) = validateSeed(words: words)
        return error == nil
    }
    
    func syncContactsAndMessages(){
        setupSyncWith(callback: processMessageCountReceived)
    }
    
    func setupSyncWith(
        callback: @escaping () -> ()
    ) {
        guard let seed = getAccountSeed() else{
            return
        }
        
        totalMsgsCountCallback = callback
        
        do {
            let rr = try getMsgsCounts(
                seed: seed,
                uniqueTime: getTimeWithEntropy(),
                state: loadOnionStateAsData()
            )
            
            let _ = handleRunReturn(rr: rr)
        } catch {
            print("Error getting msgs count")
        }
    }
    
    func processMessageCountReceived() {
        if let msgTotalCounts = msgTotalCounts,
           msgTotalCounts.hasOneValidCount()
        {
            kickOffFullRestore()
        }
    }
    
    func kickOffFullRestore() {
        guard let msgTotalCounts = msgTotalCounts else {return}
        
        if let _ = msgTotalCounts.firstMessageAvailableCount {
            
            self.restoreFirstScidMessages()
        }
    }
    
    func doNextRestorePhase() {
        guard let _ = messageFetchParams else {
            startMessagesRestore()
            return
        }
        
        finishMessagesFetch(isRestore: true)
    }
    
    func restoreFirstScidMessages(
        startIndex: Int = 0
    ) {
        guard let seed = getAccountSeed() else{
            finishMessagesFetch(isRestore: true)
            return
        }
        
        chatsFetchParams = ChatsFetchParams(
            restoreInProgress: true,
            fetchStartIndex: startIndex,
            itemsPerPage: SphinxOnionManager.kContactsBatchSize,
            restoredItems: chatsFetchParams?.restoredItems ?? 0
        )
        
        firstSCIDMsgsCallback = handleFetchFirstScidMessages
        
        fetchFirstContactPerKey(
            seed: seed,
            lastMessageIndex: startIndex,
            msgCountLimit: SphinxOnionManager.kContactsBatchSize
        )
    }
    
    func fetchFirstContactPerKey(
        seed: String,
        lastMessageIndex: Int,
        msgCountLimit: Int
    ){
        do {
            let rr = try fetchFirstMsgsPerKey(
                seed: seed,
                uniqueTime: getTimeWithEntropy(),
                state: loadOnionStateAsData(),
                lastMsgIdx: UInt64(lastMessageIndex),
                limit: UInt32(msgCountLimit),
                reverse: false
            )
            
            let _ = handleRunReturn(rr: rr)
        } catch {}
    }
    
    func startMessagesRestore() {
        if let msgTotalCounts = self.msgTotalCounts,
           msgTotalCounts.totalMessageAvailableCount ?? 0 > 0 {
            
            let startIndex = (msgTotalCounts.totalMessageMaxIndex ?? 0)
            let lastMessageIndex = 0
            
            let safeSpread = max(0, startIndex - lastMessageIndex)
            let firstBatchSize = min(SphinxOnionManager.kMessageBatchSize, safeSpread) //either do max batch size or less if less is needed
            
            if (safeSpread <= 0) {
                finishMessagesFetch(isRestore: true)
                return
            }
            
            startAllMsgPerContactFetch(
                startIndex: startIndex,
                itemsPerPage: firstBatchSize,
                stopIndex: lastMessageIndex,
                reverse: true
            )
        } else {
            finishMessagesFetch(isRestore: true)
        }
    }
    
    func startAllMsgPerContactFetch(
        startIndex: Int,
        itemsPerPage: Int,
        stopIndex: Int,
        reverse: Bool
    ) {
        guard let seed = getAccountSeed() else {
            finishMessagesFetch(isRestore: true)
            return
        }
        
        let chats = Chat.getAll()
        let contacts = UserContact.getPendingContacts()
        
        let allPubKeys = chats.compactMap({ $0.ownerPubkey }) + contacts.compactMap({ $0.publicKey })
        let chatPubKeys = Array(Set(allPubKeys))
        
        let currentIndex = 0
        
        if chatPubKeys.count > currentIndex {
            chatsFetchParams = nil
            
            messagePerContactFetchParams = MessagePerContactFetchParams(
                fetchStartIndex: startIndex,
                itemsPerPage: itemsPerPage,
                index: currentIndex,
                direction: .backward,
                chatPubkeys: chatPubKeys
            )
            
            firstSCIDMsgsCallback = nil
            onMessageRestoredCallback = handleFetchMessagesBatch
            
            fetchMessagePerContactBlock(
                seed: seed,
                lastMessageIndex: startIndex,
                msgCountLimit: itemsPerPage,
                publicKey: chatPubKeys[currentIndex],
                reverse: reverse
            )
        } else {
            finishMessagesFetch(isRestore: true)
        }
    }

    func startAllMsgBlockFetch(
        startIndex: Int,
        itemsPerPage: Int,
        stopIndex: Int,
        reverse: Bool
    ) {
        guard let seed = getAccountSeed() else {
            finishMessagesFetch(isRestore: reverse)
            return
        }
        
        chatsFetchParams = nil
        messageFetchParams = MessageFetchParams(
            fetchStartIndex: startIndex,
            itemsPerPage: itemsPerPage,
            restoredItems: 0,
            stopIndex: stopIndex,
            direction: reverse ? .backward : .forward
        )
        
        firstSCIDMsgsCallback = nil
        onMessageRestoredCallback = handleFetchMessagesBatch
        
        fetchMessageBlock(
            seed: seed,
            lastMessageIndex: startIndex,
            msgCountLimit: itemsPerPage,
            reverse: reverse
        )
    }
    
    func fetchMessageBlock(
        seed: String,
        lastMessageIndex: Int,
        msgCountLimit: Int,
        reverse: Bool
    ) {
        startWatchdogTimer()
        
        let safeLastMsgIndex = max(lastMessageIndex, 0)
        
        do {
            let rr = try fetchMsgsBatch(
                seed: seed,
                uniqueTime: getTimeWithEntropy(),
                state: loadOnionStateAsData(),
                lastMsgIdx: UInt64(safeLastMsgIndex),
                limit: UInt32(msgCountLimit),
                reverse: reverse
            )
            let _ = handleRunReturn(rr: rr)
        } catch let error {
            print(error)
        }
    }
    
    func startChatMsgBlockFetch(
        startIndex: Int,
        itemsPerPage: Int,
        stopIndex: Int,
        publicKey: String,
        callback: @escaping (Int) -> ()
    ) {
        guard let seed = getAccountSeed() else {
            return
        }
        
        firstSCIDMsgsCallback = nil
        onMessageRestoredCallback = nil
        
        restoringMsgsForPublicKey = publicKey
        onMessagePerPublicKeyRestoredCallback = callback
        
        fetchMessagePerContactBlock(
            seed: seed,
            lastMessageIndex: startIndex,
            msgCountLimit: itemsPerPage,
            publicKey: publicKey,
            reverse: true
        )
    }
    
    func fetchMessagePerContactBlock(
        seed: String,
        lastMessageIndex: Int,
        msgCountLimit: Int,
        publicKey: String,
        reverse: Bool
    ) {
        do {
            let rr = try fetchMsgsBatchPerContact(
                seed: seed,
                uniqueTime: getTimeWithEntropy(),
                state: loadOnionStateAsData(),
                lastMsgIdx: UInt64(lastMessageIndex),
                limit: UInt32(msgCountLimit),
                reverse: true,
                contact: publicKey
            )
            let _ = handleRunReturn(rr: rr)
        } catch let error {
            print(error)
        }
    }
}

extension SphinxOnionManager {
    //MARK: Process all first scid messages
    func handleFetchFirstScidMessages(msgs: [Msg]) {
        guard let params = chatsFetchParams, let _ = msgTotalCounts?.firstMessageMaxIndex else {
            doNextRestorePhase()
            return
        }
        
        let maxRestoreIndex = msgs.max {
            let firstIndex = Int($0.index ?? "0") ?? -1
            let secondIndex = Int($1.index ?? "0") ?? -1
            return firstIndex < secondIndex
        }?.index
        
        ///Contacts Restore
        if let totalMsgCount = msgTotalCounts?.firstMessageAvailableCount {
            
            if let contactRestoreCallback = contactRestoreCallback, totalMsgCount > 0 {
                ///Contacts Restore progress
                params.restoredItems = params.restoredItems + msgs.count
                
                let restoredMsgsCount = min(params.restoredItems, totalMsgCount)
                let percentage = 2 + (Double(restoredMsgsCount) / Double(totalMsgCount)) * 18
                let pctInt = Int(percentage.rounded())
                contactRestoreCallback(pctInt)
            }
            
            if msgs.count <= 0 {
                doNextRestorePhase()
                return
            }
            
            if let scidMaxIndex = msgTotalCounts?.firstMessageMaxIndex,
                let maxRestoreIndex = maxRestoreIndex,
                let maxRestoredIndexInt = Int(maxRestoreIndex)
            {
                if maxRestoredIndexInt < scidMaxIndex {
                    ///Didn't restore max index yet. Proceed to next page
                    restoreFirstScidMessages(startIndex: maxRestoredIndexInt + 1)
                    return
                }
            }
        }
        
        doNextRestorePhase()
    }
    
    //MARK: Process all messages
    func handleFetchMessagesBatch(msgs: [Msg]) {
        if  let params = messageFetchParams, params.direction == .forward {
            handleFetchMessagesBatchInForward(msgs: msgs)
            return
        }
        
        guard let params = messagePerContactFetchParams else {
            finishMessagesFetch(isRestore: true)
            return
        }
        
        guard let _ = msgTotalCounts?.totalMessageMaxIndex else {
            finishMessagesFetch(isRestore: true)
            return
        }
        
        if params.index + 1 == params.chatPubkeys.count {
            finishMessagesFetch(isRestore: true)
            return
        }
        
        ///Messages Restore progress
        if let messageRestoreCallback = messageRestoreCallback {
            let chatsCount = params.chatPubkeys.count
            let percentage = 20 + (Double(params.index + 1) / Double(chatsCount)) * 80
            let pctInt = Int(percentage.rounded())
            messageRestoreCallback(pctInt)
        }
        
        guard let seed = getAccountSeed() else {
            finishMessagesFetch(isRestore: true)
            return
        }
        
        params.index = params.index + 1
        
        fetchMessagePerContactBlock(
            seed: seed,
            lastMessageIndex: params.fetchStartIndex,
            msgCountLimit: params.itemsPerPage,
            publicKey: params.chatPubkeys[params.index],
            reverse: params.direction == .backward
        )
    }
    
    func handleFetchMessagesBatchInForward(msgs: [Msg]) {
        guard let params = messageFetchParams else {
            finishMessagesFetch()
            return
        }
        
        let maxRestoreIndex = msgs.min {
            let firstIndex = Int($0.index ?? "0") ?? -1
            let secondIndex = Int($1.index ?? "0") ?? -1
            return firstIndex > secondIndex
        }?.index ?? "0"
        
        guard let maxRestoredIndexInt = Int(maxRestoreIndex) else {
            finishMessagesFetch()
            return
        }
        
        if msgs.count <= 0 {
            finishMessagesFetch()
            return
        }
        
        maxMessageIndex = maxRestoredIndexInt
        
        guard let seed = getAccountSeed() else {
            finishMessagesFetch()
            return
        }
        
        fetchMessageBlock(
            seed: seed,
            lastMessageIndex: maxRestoredIndexInt + 1,
            msgCountLimit: params.itemsPerPage,
            reverse: false
        )
    }
    
    func restoreContactsFrom(messages: [Msg]) {
        if messages.isEmpty {
            return
        }
        
        let allowedTypes = [
            UInt8(TransactionMessage.TransactionMessageType.unknown.rawValue),
            UInt8(TransactionMessage.TransactionMessageType.contactKey.rawValue),
            UInt8(TransactionMessage.TransactionMessageType.contactKeyConfirmation.rawValue)
        ]
        
        let filteredMsgs = messages.filter({ $0.type != nil && allowedTypes.contains($0.type!) })
        
        let messageIndexes = filteredMsgs.compactMap({
            if let index = $0.index, let indexInt = Int(index) {
                return indexInt
            }
            return nil
        })
        
        let existingIdMessages = TransactionMessage.getMessagesWith(ids: messageIndexes, context: backgroundContext)
        let existingMessagesIdMap = Dictionary(uniqueKeysWithValues: existingIdMessages.map { ($0.id, $0) })
        
        ///Messages sender info Map
        let senderInfoMessagesMap = Dictionary(uniqueKeysWithValues: filteredMsgs.compactMap {
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
        
        ///Contacts Map per public key
        let pubkeys = senderInfoMessagesMap.compactMap({ $0.value.pubkey })
        let contactsByPubKeys = UserContact.getContactsWith(pubkeys: pubkeys, context: backgroundContext)
        var contactsByPubKeyMap = Dictionary(uniqueKeysWithValues: contactsByPubKeys.compactMap {
            $0.setContactConversation(context: backgroundContext)
            
            if let pubkey = $0.publicKey {
                return (pubkey, $0)
            }
            return nil
        })
        
        let codes = senderInfoMessagesMap.compactMap({ $0.value.code })
        let contactsByInviteCode = UserContact.getContactsWithInviteCode(inviteCode: codes, managedContext: backgroundContext)
        var contactsByInviteCodeMap = Dictionary(uniqueKeysWithValues: contactsByInviteCode.compactMap {
            $0.setContactConversation(context: backgroundContext)
            
            if let code = $0.sentInviteCode {
                return (code, $0)
            }
            return nil
        })
        
        for message in filteredMsgs {
            
            guard let index = message.index, let indexInt = Int(index) else {
                continue
            }
            
            guard let csr =  senderInfoMessagesMap[indexInt],
                  let recipientPubkey = csr.pubkey else
            {
                continue
            }
            
            if (chatsFetchParams?.restoredTribesPubKeys ?? []).contains(recipientPubkey) {
                ///If is tribe message, then continue
                continue
            }
            
            let routeHint: String? = csr.routeHint
                
            let contact = contactsByPubKeyMap[recipientPubkey] ?? createNewContact(
                pubkey: recipientPubkey,
                routeHint: routeHint,
                nickname: csr.alias,
                photoUrl: csr.photoUrl,
                code: csr.code,
                date: message.date,
                context: backgroundContext
            )
            
            if !contactsByPubKeyMap.keys.contains(recipientPubkey) {
                contactsByPubKeyMap[recipientPubkey] = contact
            }
            
            if let inviteCode = csr.code, !contactsByInviteCodeMap.keys.contains(inviteCode) {
                contactsByInviteCodeMap[inviteCode] = contact
            }
            
            if contact.isOwner {
                continue
            }
            
            if let routeHint = routeHint {
                contact.routeHint = routeHint
            }
            
            let isConfirmed = csr.confirmed == true
            
            if contact.isPending() {
                contact.status = isConfirmed ? UserContact.Status.Confirmed.rawValue : UserContact.Status.Pending.rawValue
            }
            
            if contact.getChat() == nil && isConfirmed {
                let _ = createChat(for: contact, with: message.date, context: backgroundContext)
            }
            
            createKeyExchangeMsgFrom(
                msg: message,
                existingContact: contact,
                existingMessage: existingMessagesIdMap[indexInt]
            )
        }
    }
    
    func fetchMissingTribesFor(
        rr: RunReturn,
        topic: String?,
        completion: @escaping (RunReturn, [String: JSON], String?) -> ()
    ) {
        let messages = rr.msgs
        
        if messages.isEmpty {
            completion(rr, [:], topic)
            return
        }

        let allowedTypes = [
            UInt8(TransactionMessage.TransactionMessageType.groupJoin.rawValue),
            UInt8(TransactionMessage.TransactionMessageType.memberApprove.rawValue)
        ]
        
        let filteredMsgs = messages.filter({ $0.type != nil && allowedTypes.contains($0.type!) })
        
        if filteredMsgs.isEmpty {
            completion(rr, [:], topic)
            return
        }

        ///Messages sender info Map
        let senderInfoMessagesMap = Dictionary(uniqueKeysWithValues: filteredMsgs.compactMap {
            if let sender = $0.sender,
               let index = $0.index,
               let indexInt = Int(index),
               let csr = ContactServerResponse(JSONString: sender)
            {
                return (indexInt, csr)
            }
            return nil
        })
        
        ///Tribes Map per public key
        let pubkeys = senderInfoMessagesMap.compactMap({ $0.value.pubkey })
        let tribes = Chat.getChatTribesFor(ownerPubkeys: pubkeys, context: backgroundContext)
        let tribesMap = Dictionary(uniqueKeysWithValues: tribes.compactMap {
            if let ownerPubkey = $0.ownerPubkey {
                return (ownerPubkey, $0)
            }
            return nil
        })
        
        Task {
            // Process all tribes concurrently
            let resultsDict = await withTaskGroup(
                of: (String, JSON)?.self,
                returning: [String: JSON].self
            ) { group in
                // Add async tasks
                for message in filteredMsgs {
                    
                    guard let indx = message.index, let indexInt = Int(indx) else {
                        continue
                    }
                    
                    guard let csr = senderInfoMessagesMap[indexInt],
                          let tribePubkey = csr.pubkey else
                    {
                        continue
                    }
                    
                    if let _ = tribesMap[tribePubkey] {
                        continue
                    }
                    
                    group.addTask {
                        let ((tuple), didCreate) = await self.fetchTribeInfo(
                            ownerPubkey: tribePubkey,
                            host: csr.host
                        )
                        return didCreate ? tuple : nil
                    }
                    
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms delay
                }
                
                // Collect results
                var dict: [String: JSON] = [:]
                for await result in group {
                    if let (pubkey, json) = result {
                        dict[pubkey] = json
                    }
                }
                return dict
            }
            
            // Call completion on main queue
            await MainActor.run {
                completion(rr, resultsDict, topic)
            }
        }
    }
    
    func restoreTribesFrom(
        dictionary: [String: JSON],
        rr: RunReturn
    ) {
        let messages = rr.msgs
        
        if messages.isEmpty {
            return
        }

        let allowedTypes = [
            UInt8(TransactionMessage.TransactionMessageType.groupJoin.rawValue),
            UInt8(TransactionMessage.TransactionMessageType.memberApprove.rawValue)
        ]
        
        let filteredMsgs = messages.filter({ $0.type != nil && allowedTypes.contains($0.type!) })
        
        if filteredMsgs.isEmpty {
            return
        }
        
        ///Messages sender info Map
        let senderInfoMessagesMap = Dictionary(uniqueKeysWithValues: filteredMsgs.compactMap {
            if let sender = $0.sender,
               let index = $0.index,
               let indexInt = Int(index),
               let csr = ContactServerResponse(JSONString: sender)
            {
                return (indexInt, csr)
            }
            return nil
        })
        
        ///Tribes Map per public key
        let pubkeys = senderInfoMessagesMap.compactMap({ $0.value.pubkey })
        let tribes = Chat.getChatTribesFor(ownerPubkeys: pubkeys, context: backgroundContext)
        var tribesMap = Dictionary(uniqueKeysWithValues: tribes.compactMap {
            if let ownerPubkey = $0.ownerPubkey {
                return (ownerPubkey, $0)
            }
            return nil
        })
        
        for message in filteredMsgs {
            
            guard let indx = message.index, let indexInt = Int(indx) else {
                continue
            }
            
            ///Check for sender information
            guard let csr = senderInfoMessagesMap[indexInt],
                  let tribePubkey = csr.pubkey else
            {
                continue
            }
            
            if let chat = tribesMap[tribePubkey] {
                restoreTribeStateFrom(
                    message: message,
                    senderInfo: csr,
                    chat: chat,
                    didCreateTribe: false
                )
            } else if let tribeInfo = dictionary[tribePubkey] {
                
                let chat = Chat.insertChat(chat: tribeInfo, context: backgroundContext)
                chat?.status = (tribeInfo["private"].bool ?? false) ? Chat.ChatStatus.pending.rawValue : Chat.ChatStatus.approved.rawValue
                chat?.type = Chat.ChatType.publicGroup.rawValue
                
                guard let chat = chat else {
                    return
                }
                
                restoreTribeStateFrom(
                    message: message,
                    senderInfo: csr,
                    chat: chat,
                    didCreateTribe: true
                )
                
                if let ownerPubKey = chat.ownerPubkey, !tribesMap.keys.contains(ownerPubKey) {
                    tribesMap[ownerPubKey] = chat
                }
            }
        }
    }
    
    func restoreTribeStateFrom(
        message: Msg,
        senderInfo: ContactServerResponse?,
        chat: Chat,
        didCreateTribe: Bool
    ) {
        
        guard let type = message.type else {
            return
        }
        
        guard let csr =  senderInfo else {
            return
        }
        
        if (didCreateTribe && csr.role != nil) {
            chat.isTribeICreated = csr.role == 0 && message.fromMe == true
        }
        if (type == TransactionMessage.TransactionMessageType.memberApprove.rawValue || type == TransactionMessage.TransactionMessageType.groupJoin.rawValue) {
            chat.status = Chat.ChatStatus.approved.rawValue
        }
        if (type == TransactionMessage.TransactionMessageType.memberReject.rawValue) {
            chat.status = Chat.ChatStatus.rejected.rawValue
        }
    }
    
    func restoreGroupJoinMsg(
        message: Msg,
        existingMessage: TransactionMessage?,
        senderInfo: ContactServerResponse?,
        innerContent: MessageInnerContent?,
        chat: Chat,
        didCreateTribe: Bool
    ) -> TransactionMessage? {
        
        guard let uuid = message.uuid,
              let index = message.index,
              let timestamp = message.timestamp,
              let type = message.type,
              let date = timestampToDate(timestamp: timestamp) else
        {
            return nil
        }
        
        guard let csr =  senderInfo else {
            return nil
        }
        
        let groupActionMessage = existingMessage ?? TransactionMessage(context: backgroundContext)
        groupActionMessage.uuid = uuid
        groupActionMessage.id = Int(index) ?? uniqueIntHashFromString(stringInput: UUID().uuidString)
        groupActionMessage.chat = chat
        groupActionMessage.type = Int(type)
        
        let innerContentDate = message.getInnerContentDate()
        groupActionMessage.createdAt = innerContentDate ?? date
        groupActionMessage.date = innerContentDate ?? date
        groupActionMessage.updatedAt = innerContentDate ?? date
        
        groupActionMessage.setAsLastMessage()
        groupActionMessage.senderAlias = csr.alias
        groupActionMessage.senderPic = csr.photoUrl
        groupActionMessage.senderId = message.fromMe == true ? UserData.sharedInstance.getUserId(context: backgroundContext) : chat.id
        groupActionMessage.status = TransactionMessage.TransactionMessageStatus.confirmed.rawValue
        
        groupActionMessage.replyUUID = innerContent?.replyUuid
        
        chat.seen = false
        
        if (didCreateTribe && csr.role != nil) {
            chat.isTribeICreated = csr.role == 0 && message.fromMe == true
        }
        if (type == TransactionMessage.TransactionMessageType.memberApprove.rawValue || type == TransactionMessage.TransactionMessageType.groupJoin.rawValue) {
            chat.status = Chat.ChatStatus.approved.rawValue
        }
        if (type == TransactionMessage.TransactionMessageType.memberReject.rawValue) {
            chat.status = Chat.ChatStatus.rejected.rawValue
        }
        
        return groupActionMessage
    }

    func endWatchdogTime() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
    }
    
    func startWatchdogTimer() {
        watchdogTimer?.invalidate()
        
        watchdogTimer = Timer.scheduledTimer(
            timeInterval: 10.0,
            target: self,
            selector: #selector(watchdogTimerFired),
            userInfo: nil,
            repeats: false
        )
    }
    
    @objc func watchdogTimerFired() {
        onMessageRestoredCallback = nil
        firstSCIDMsgsCallback = nil
        totalMsgsCountCallback = nil
        
        messageFetchParams = nil
        chatsFetchParams = nil
        messagePerContactFetchParams = nil
        
        endWatchdogTime()
        resetFromRestore()
    }
    
    func finishMessagesFetch(
        isRestore: Bool = false
    ) {
        onMessageRestoredCallback = nil
        firstSCIDMsgsCallback = nil
        totalMsgsCountCallback = nil
        
        messageFetchParams = nil
        chatsFetchParams = nil
        messagePerContactFetchParams = nil
        
        restoredContactInfoTracker = []
        
        requestPings()
        endWatchdogTime()
        resetFromRestore()
        updateRoutingInfo()
        
        if isRestore, let maxIndex = TransactionMessage.getMaxIndex() {
            maxMessageIndex = maxIndex
        }
    }
    
    func attempFinishResotoration() {
        messageFetchParams = nil
        chatsFetchParams = nil
        messagePerContactFetchParams = nil
    }
    
    func requestPings() {
        guard let seed = getAccountSeed() else{
            return
        }
        readyForPing = true

        do {
            let rr = try Sphinx.fetchPings(
                seed: seed,
                uniqueTime: getTimeWithEntropy(),
                state: loadOnionStateAsData()
            )
            let _ = handleRunReturn(rr: rr)
        } catch {
            print("Error fetching pings")
        }
    }
    
    func resetFromRestore() {
        setLastMessagesOnChats()
        processDeletedRestoredMessages()
        updateIsPaidAllMessages()
        
        backgroundContext.saveContext()
        
        isV2InitialSetup = false
        contactRestoreCallback = nil
        messageRestoreCallback = nil
        
        if let hideRestoreCallback = hideRestoreCallback {
            hideRestoreCallback(false)
        }
        
        joinInitialTribe()
    }
    
    func setLastMessagesOnChats() {
        if !isV2Restore {
            return
        }
        
        for chat in Chat.getAll() {
            if let lastMessage = chat.getLastMessageToShow(includeContactKeyTypes: true) {
                if lastMessage.isKeyExchangeType() {
                    fixSeenStateForChatsWithNoMessages(
                        chat: chat,
                        message: lastMessage,
                        shouldSetLastMessage: false
                    )
                } else if lastMessage.isTribeInitialMessageType() && chat.messages?.count == 1 {
                    fixSeenStateForChatsWithNoMessages(
                        chat: chat,
                        message: lastMessage,
                        shouldSetLastMessage: true
                    )
                } else if lastMessage.isOutgoing() {
                    chat.setChatMessagesAsSeen()
                } else {
                    chat.lastMessage = lastMessage
                }
            }
        }
    }
    
    func fixSeenStateForChatsWithNoMessages(
        chat: Chat,
        message: TransactionMessage,
        shouldSetLastMessage: Bool
    ) {
        message.seen = true
        chat.seen = true
        
        chat.lastMessage = shouldSetLastMessage ? message : chat.lastMessage
        
        if let maxMessageIndex = TransactionMessage.getMaxIndex() {
            let _  = SphinxOnionManager.sharedInstance.setReadLevel(
                index: UInt64(maxMessageIndex),
                chat: chat,
                recipContact: chat.getContact()
            )
        }
    }
    
    func processDeletedRestoredMessages() {
        let deleteRequests = TransactionMessage.getMessageDeletionRequests()
        
        for deleteRequest in deleteRequests {
            if let replyUUID = deleteRequest.replyUUID,
               let messageToDelete = TransactionMessage.getMessageWith(uuid: replyUUID)
            {
                messageToDelete.status = TransactionMessage.TransactionMessageStatus.deleted.rawValue
            }
        }
    }
}
