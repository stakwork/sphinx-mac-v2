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

    enum FetchDirection {
        case forward, backward
    }

    init(
        fetchStartIndex: Int,
        itemsPerPage: Int,
        restoredItems: Int,
        stopIndex: Int
    ) {
        self.fetchStartIndex = fetchStartIndex
        self.itemsPerPage = itemsPerPage
        self.restoredItems = restoredItems
        self.stopIndex = stopIndex
    }
    
    var debugDescription: String {
        return """
        fetchStartIndex: \(fetchStartIndex)
        itemsPerPage: \(itemsPerPage)
        stopIndex: \(stopIndex)
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
        let (error, _) = CrypterManager.sharedInstance.validateSeed(words: words)
        return error == nil
    }
    
    func syncContactsAndMessages(
        contactRestoreCallback: RestoreProgressCallback?,
        messageRestoreCallback: RestoreProgressCallback?,
        hideRestoreViewCallback: (()->())?
    ){
        self.contactRestoreCallback = contactRestoreCallback
        self.messageRestoreCallback = messageRestoreCallback
        self.hideRestoreCallback = hideRestoreViewCallback
        
        setupSyncWith(callback: processMessageCountReceived)
    }
    
    @objc func processMessageCountReceived() {
        if let msgTotalCounts = self.msgTotalCounts,
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
        guard let _ = messageFetchParams else{
            startMessagesRestore()
            return
        }
        
        finishRestoration()
    }
    
    
    func restoreFirstScidMessages(
        startIndex: Int = 0
    ) {
        guard let seed = getAccountSeed() else{
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
    
    func startMessagesRestore() {
        if let msgTotalCounts = self.msgTotalCounts,
           msgTotalCounts.totalMessageAvailableCount ?? 0 > 0 {
            
            let startIndex = (msgTotalCounts.totalMessageMaxIndex ?? 0)
            let lastMessageIndex = TransactionMessage.getMaxIndex() ?? 0
            
            let safeSpread = max(0, startIndex - lastMessageIndex)
            let firstBatchSize = min(SphinxOnionManager.kMessageBatchSize, safeSpread) //either do max batch size or less if less is needed
            
            if (safeSpread <= 0) {
                finishRestoration()
                return
            }
            
            startAllMsgBlockFetch(
                startIndex: startIndex,
                itemsPerPage: firstBatchSize,
                stopIndex: lastMessageIndex
            )
        }
    }

    func startAllMsgBlockFetch(
        startIndex: Int,
        itemsPerPage: Int,
        stopIndex: Int
    ) {
        guard let seed = getAccountSeed() else {
            return
        }
        
        chatsFetchParams = nil
        messageFetchParams = MessageFetchParams(
            fetchStartIndex: startIndex,
            itemsPerPage: itemsPerPage,
            restoredItems: 0,
            stopIndex: stopIndex
        )
        
        firstSCIDMsgsCallback = nil
        onMessageRestoredCallback = onMessageRestored
        
        fetchMessageBlock(
            seed: seed,
            lastMessageIndex: startIndex,
            msgCountLimit: itemsPerPage
        )
    }
    
    func fetchMessageBlock(
        seed: String,
        lastMessageIndex: Int,
        msgCountLimit: Int
    ) {
        let safeLastMsgIndex = max(lastMessageIndex, 0)
        
        do {
            let rr = try fetchMsgsBatch(
                seed: seed,
                uniqueTime: getTimeWithEntropy(),
                state: loadOnionStateAsData(),
                lastMsgIdx: UInt64(safeLastMsgIndex),
                limit: UInt32(msgCountLimit),
                reverse: true
            )
            let _ = handleRunReturn(rr: rr)
        } catch let error {
            print(error)
        }
    }
}

extension SphinxOnionManager : NSFetchedResultsControllerDelegate{
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
            
            if msgs.count < SphinxOnionManager.kContactsBatchSize {
                doNextRestorePhase()
                return
            }
            
            if let scidMaxIndex = msgTotalCounts?.firstMessageMaxIndex,
                let maxRestoreIndex = maxRestoreIndex,
                let maxRestoredIndexInt = Int(maxRestoreIndex)
            {
//                startWatchdogTimer()
                
                if maxRestoredIndexInt < scidMaxIndex {
                    ///Didn't restore max index yet. Proceed to next page
                    restoreFirstScidMessages(startIndex: maxRestoredIndexInt)
                    return
                }
            }
        }
        
        doNextRestorePhase()
    }

    
    func onMessageRestored(msgs: [Msg]) {
        guard let params = messageFetchParams, let _ = msgTotalCounts?.totalMessageMaxIndex else {
            finishRestoration()
            return
        }
        
        let restoredMessages = msgs.filter({
            let allowedTypes = [
                UInt8(TransactionMessage.TransactionMessageType.unknown.rawValue),
                UInt8(TransactionMessage.TransactionMessageType.contactKey.rawValue),
                UInt8(TransactionMessage.TransactionMessageType.contactKeyConfirmation.rawValue)
            ]
            return !allowedTypes.contains($0.type ?? 0)
        })
        
        let minRestoreIndex = restoredMessages.min {
            let firstIndex = Int($0.index ?? "0") ?? -1
            let secondIndex = Int($1.index ?? "0") ?? -1
            return firstIndex < secondIndex
        }?.index ?? "0"
        
        if let minRestoredIndexInt = Int(minRestoreIndex), minRestoredIndexInt < params.stopIndex {
            finishRestoration()
            return
        }
        
        if let totalMsgCount = msgTotalCounts?.totalMessageAvailableCount {
            ///Contacts Restore progress
            if let messageRestoreCallback = messageRestoreCallback, totalMsgCount > 0 {
                params.restoredItems = params.restoredItems + msgs.count
                let msgsCount = min(params.restoredItems, totalMsgCount)
                let percentage = 20 + (Double(msgsCount) / Double(totalMsgCount)) * 80
                let pctInt = Int(percentage.rounded())
                messageRestoreCallback(pctInt)
            }
            
            ///Restore finished
            if msgs.count < SphinxOnionManager.kMessageBatchSize {
                finishRestoration()
                return
            }
        }
        
        guard let seed = getAccountSeed() else {
            return
        }
        
        fetchMessageBlock(
            seed: seed,
            lastMessageIndex: Int(minRestoreIndex)! - 1,
            msgCountLimit: params.itemsPerPage
        )
    }

    func endWatchdogTime() {
        // Invalidate any existing timer
        watchdogTimer?.invalidate()
    }
    
    func startWatchdogTimer() {
        // Invalidate any existing timer
        watchdogTimer?.invalidate()
        
        // Start a new timer
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
        
        messageFetchParams = nil
        chatsFetchParams = nil
        
        endWatchdogTime()
        resetFromRestore()
    }
    
    func finishRestoration() {
        onMessageRestoredCallback = nil
        firstSCIDMsgsCallback = nil
        
        messageFetchParams = nil
        chatsFetchParams = nil
        
        endWatchdogTime()
        resetFromRestore()
    }
    
    func resetFromRestore() {
        for chat in Chat.getAll() {
            if let lastMessage = TransactionMessage.getLastMessageFor(chat: chat) {
                chat.lastMessage = lastMessage
            }
        }
        
        for deleteRequest in TransactionMessage.getMessageDeletionRequests() {
            if let replyUUID = deleteRequest.replyUUID,
               let messageToDelete = TransactionMessage.getMessageWith(uuid: replyUUID)
            {
                messageToDelete.status = TransactionMessage.TransactionMessageStatus.deleted.rawValue
                messageToDelete.managedObjectContext?.saveContext()
            }
        }
        
        self.isV2InitialSetup = false
        self.contactRestoreCallback = nil
        self.messageRestoreCallback = nil
        self.updateIsPaidAllMessages() // ensure all paid invoices are marked as such
        
        if let hideRestoreCallback = hideRestoreCallback {
            hideRestoreCallback()
        }
    }
    
    func registerDeviceID(id: String) {
        guard let seed = getAccountSeed(), let _ = mqtt else {
            return
        }
        
        do {
            let rr = try setPushToken(
                seed: seed,
                uniqueTime: getTimeWithEntropy(),
                state: loadOnionStateAsData(),
                pushToken: id
            )
            
            let _ = handleRunReturn(rr: rr)
        } catch {
            print("Error setting push token")
        }
    }

}
