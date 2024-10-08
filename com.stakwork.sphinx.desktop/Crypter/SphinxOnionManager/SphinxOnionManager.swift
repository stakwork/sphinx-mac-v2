//
//  SphinxOnionManager.swift
//
//
//  Created by James Carucci on 11/8/23.
//

import Foundation
import CocoaMQTT
import ObjectMapper
import SwiftyJSON
import CoreData


class SphinxOnionManager : NSObject {
    
    private static var _sharedInstance: SphinxOnionManager? = nil

    static var sharedInstance: SphinxOnionManager {
        if _sharedInstance == nil {
            _sharedInstance = SphinxOnionManager()
        }
        return _sharedInstance!
    }

    static func resetSharedInstance() {
        _sharedInstance = nil
    }
    
    let walletBalanceService = WalletBalanceService()
    
    ///Invite
    var pendingInviteLookupByTag : [String:String] = [String:String]()
    var stashedContactInfo: String? = nil
    var stashedInitialTribe: String? = nil
    var stashedInviteCode: String? = nil
    var stashedInviterAlias: String? = nil
    
    var watchdogTimer: Timer? = nil
    var reconnectionTimer: Timer? = nil
    var sendTimeoutTimers: [String: Timer] = [:]
    
    var chatsFetchParams : ChatsFetchParams? = nil
    var messageFetchParams : MessageFetchParams? = nil
    
    var deletedTribesPubKeys: [String] {
        get {
            return UserDefaults.Keys.deletedTribesPubKeys.get(defaultValue: [])
        }
        set {
            UserDefaults.Keys.deletedTribesPubKeys.set(newValue)
        }
    }
    
    var recentlyJoinedTribePubKeys: [String] = []
    
    var isV2InitialSetup: Bool = false
    var isV2Restore: Bool = false
    var shouldPostUpdates : Bool = false
    
    let tribeMinSats: Int = 3000
    let kRoutingOffset = 3
    
    var restoredContactInfoTracker = [String]()
    
    var vc: NSViewController! = nil
    var mqtt: CocoaMQTT! = nil
    
    var delayedRRObjects: [Int: RunReturn] = [:]
    var delayedRRTimers: [Int: Timer] = [:]
    var pingsMap: [String: String] = [:]
    var readyForPing = false
    
    var isConnected : Bool = false {
        didSet{
            NotificationCenter.default.post(name: .onConnectionStatusChanged, object: nil)
        }
    }
    
    var msgTotalCounts : MsgTotalCounts? = nil
    
    typealias RestoreProgressCallback = (Int) -> Void
    var messageRestoreCallback : RestoreProgressCallback? = nil
    var contactRestoreCallback : RestoreProgressCallback? = nil
    var hideRestoreCallback: (() -> ())? = nil
    var tribeMembersCallback: (([String: AnyObject]) -> ())? = nil
    var inviteCreationCallback: ((String?) -> ())? = nil
    var mqttDisconnectCallback: (() -> ())? = nil
    var paymentsHistoryCallback: ((String?, String?) -> ())? = nil
    
    ///Session Pin to decrypt mnemonic and seed
    var appSessionPin : String? = nil
    var defaultInitialSignupPin : String = "111111"
    
    public static let kContactsBatchSize = 100
    public static let kMessageBatchSize = 100
    
    public static let kCompleteStatus = "COMPLETE"
    public static let kFailedStatus = "FAILED"
    
    var onionState: [String: [UInt8]] = [:]
    
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
    
    let newMessageBubbleHelper = NewMessageBubbleHelper()
    let managedContext = CoreDataManager.sharedManager.persistentContainer.viewContext
    
    //MARK: Hardcoded Values!
    var serverIP: String {
        get {
            if let storedServerIP: String = UserDefaults.Keys.serverIP.get() {
                return storedServerIP
            }
            return kTestServerIP
        }
    }
    
    var serverPORT: UInt16 {
        get {
            if let storedServerPORT: Int = UserDefaults.Keys.serverPORT.get() {
                return UInt16(storedServerPORT)
            }
            return kTestServerPort
        }
    }
    
    var tribesServerIP: String {
        get {
            if let storedTribesServer: String = UserDefaults.Keys.tribesServerIP.get() {
                return storedTribesServer
            }
            return kTestV2TribesServer
        }
    }
    
    var storedRouteUrl: String? = nil
    var routerUrl: String {
        get {
            if let storedRouteUrl = storedRouteUrl {
                return storedRouteUrl
            }
            if let routerUrl: String = UserDefaults.Keys.routerUrl.get() {
                storedRouteUrl = routerUrl
                return routerUrl
            }
            storedRouteUrl = kTestRouterUrl
            return kTestRouterUrl
        }
        set {
            UserDefaults.Keys.routerUrl.set(newValue)
        }
    }
    
    var defaultTribePubkey: String? {
        get {
            if let defaultTribePublicKey: String = UserDefaults.Keys.defaultTribePublicKey.get() {
                if defaultTribePublicKey.isEmpty {
                    return nil
                }
                return defaultTribePublicKey
            }
            return kTestDefaultTribe
        }
    }
    
    var routerPubkey: String? {
        get {
            if let routerPubkey: String = UserDefaults.Keys.routerPubkey.get() {
                return routerPubkey
            }
            return nil
        }
    }
    
    let kTestServerIP = "75.101.247.127"
    let kTestServerPort: UInt16 = 1883
    let kProdServerPort: UInt16 = 8883
    let kTestV2TribesServer = "75.101.247.127:8801"
    let kTestDefaultTribe = "0213ddd7df0077abe11d6ec9753679eeef9f444447b70f2980e44445b3f7959ad1"
    let kTestRouterUrl = "mixer.router1.sphinx.chat"
    
    var isProductionEnvStored: Bool? = nil
    var isProductionEnv : Bool {
        get {
            if let isProductionEnvStored = isProductionEnvStored {
                return isProductionEnvStored
            }
            let isProductionEnv = UserDefaults.Keys.isProductionEnv.get(defaultValue: false)
            self.isProductionEnvStored = isProductionEnv
            return isProductionEnv
        }
        set {
            UserDefaults.Keys.isProductionEnv.set(newValue)
        }
    }
    
    var network: String {
        get {
            return isProductionEnv ? "bitcoin" : "regtest"
        }
    }

    
    //MARK: Callbacks
    ///Restore
    var totalMsgsCountCallback: (() -> ())? = nil
    var firstSCIDMsgsCallback: (([Msg]) -> ())? = nil
    var onMessageRestoredCallback: (([Msg]) -> ())? = nil
    
    var maxMessageIndex: Int? {
        get {
            if let maxMessageIndex: Int = UserDefaults.Keys.maxMessageIndex.get() {
                return maxMessageIndex
            }
            return TransactionMessage.getMaxIndex()
        }
    }
    
    ///Create tribe
    var createTribeCallback: ((String) -> ())? = nil
    
    func getAccountSeed(
        mnemonic: String? = nil
    ) -> String? {
        do {
            if let mnemonic = mnemonic { // if we have a non-default value, use it
                let seed = try Sphinx.mnemonicToSeed(mnemonic: mnemonic)
                return seed
            } else if let mnemonic = UserData.sharedInstance.getMnemonic() { //pull from memory if argument is nil
                let seed = try Sphinx.mnemonicToSeed(mnemonic: mnemonic)
                return seed
            } else {
                return nil
            }
        } catch {
            print("error in getAccountSeed")
            return nil
        }
    }
    
    func generateMnemonic() -> String? {
        var result : String? = nil
        do {
            result = try Sphinx.mnemonicFromEntropy(
                entropy: Data.randomBytes(length: 16).hexString
            )
            guard let result = result else {
                return nil
            }
            UserData.sharedInstance.save(walletMnemonic: result)
        } catch let error {
            print("error getting seed\(error)")
        }
        return result
    }
    
    func getAccountXpub(seed: String) -> String?  {
        do {
            let xpub = try xpubFromSeed(
                seed: seed,
                time: getTimeWithEntropy(),
                network: network
            )
            return xpub
        } catch {
            return nil
        }
    }
    
    func getAccountOnlyKeysendPubkey(
        seed: String
    ) -> String? {
        do {
            let pubkey = try pubkeyFromSeed(
                seed: seed,
                idx: 0,
                time: getTimeWithEntropy(),
                network: network
            )
            return pubkey
        } catch {
            return nil
        }
    }
    
    func getTimeWithEntropy() -> String {
        let currentTimeMilliseconds = Int(Date().timeIntervalSince1970 * 1000)
        let upperBound = 1_000
        let randomInt = generateCryptographicallySecureRandomInt(upperBound: upperBound)
        let timePlusRandom = currentTimeMilliseconds + randomInt!
        let randomString = String(describing: timePlusRandom)
        return randomString
    }
    
    func connectToBroker(
        seed: String,
        xpub: String
    ) -> Bool {
        do {
            let now = getTimeWithEntropy()
            
            let sig = try rootSignMs(
                seed: seed,
                time: now,
                network: network
            )
            
            mqtt = CocoaMQTT(
                clientID: xpub,
                host: serverIP,
                port: serverPORT
            )
            
            mqtt.username = now
            mqtt.password = sig
            
            if isProductionEnv {
                mqtt.enableSSL = true
                mqtt.allowUntrustCACertificate = true
                
                mqtt.sslSettings = [
                    "kCFStreamSSLPeerName": "\(serverIP)" as NSObject
                ] as [String: NSObject]
            }
            
            let success = mqtt.connect()
            print("mqtt.connect success:\(success)")
            return success
        } catch {
            return false
        }
    }
    
    func disconnectMqtt(
        callback: (() -> ())? = nil
    ) {
        if self.mqtt == nil || mqtt?.connState == .disconnected {
            callback?()
            return
        }
        mqttDisconnectCallback = callback
        mqtt?.disconnect()
    }
    
    func isFetchingContent() -> Bool {
        return onMessageRestoredCallback != nil || firstSCIDMsgsCallback != nil || totalMsgsCountCallback != nil
    }
    
    func reconnectToServer(
        connectingCallback: (() -> ())? = nil,
        hideRestoreViewCallback: (()->())? = nil
    ) {
        if let mqtt = self.mqtt, mqtt.connState == .connected && isConnected {
            ///If already fetching content, then process is already running
            if !isFetchingContent() {
                self.hideRestoreCallback = hideRestoreViewCallback
                self.getReads()
                self.syncNewMessages()
            }
            return
        }
        connectToServer(
            connectingCallback: connectingCallback,
            hideRestoreViewCallback: hideRestoreViewCallback
        )
    }
    
    func syncNewMessages() {
        let maxIndex = maxMessageIndex
        
        startAllMsgBlockFetch(
            startIndex: (maxIndex != nil) ? maxIndex! + 1 : 0,
            itemsPerPage: SphinxOnionManager.kMessageBatchSize,
            stopIndex: 0,
            reverse: false
        )
    }

    func connectToServer(
        connectingCallback: (() -> ())? = nil,
        contactRestoreCallback: RestoreProgressCallback? = nil,
        messageRestoreCallback: RestoreProgressCallback? = nil,
        hideRestoreViewCallback: (()->())? = nil
    ){
        connectingCallback?()
        
        guard let seed = getAccountSeed(),
              let myPubkey = getAccountOnlyKeysendPubkey(seed: seed),
              let my_xpub = getAccountXpub(seed: seed) else
        {
            hideRestoreViewCallback?()
            return
        }
        
        mqtt?.disconnect()
        
        if isV2Restore {
            contactRestoreCallback?(2)
        }
        
        self.hideRestoreCallback = hideRestoreViewCallback
        self.contactRestoreCallback = contactRestoreCallback
        self.messageRestoreCallback = messageRestoreCallback
        
        let success = connectToBroker(seed: seed, xpub: my_xpub)
        
        if (success == false) {
            hideRestoreViewCallback?()
            return
        }
        
        mqtt.didConnectAck = { [weak self] _, _ in
            guard let self = self else {
                return
            }
            
            self.endReconnectionTimer()
            self.isConnected = true
            
            self.subscribeAndPublishMyTopics(pubkey: myPubkey, idx: 0)
            
            if (self.isV2InitialSetup) {
                self.isV2InitialSetup = false
                self.doInitialInviteSetup()
            }
             
            if self.isV2Restore {
                self.hideRestoreCallback = {
                    self.isV2Restore = false
                    
                    hideRestoreViewCallback?()
                }
                self.syncContactsAndMessages()
            } else {
                self.contactRestoreCallback = nil
                self.messageRestoreCallback = nil

                self.getReads()
                self.syncNewMessages()
            }
        }
        
        mqtt.didReceiveTrust = { _, _, completionHandler in
            completionHandler(true)
        }
        
        mqtt.didDisconnect = { _, _ in
            self.isConnected = false
            self.mqttDisconnectCallback?()
            self.mqtt = nil
            self.startReconnectionTimer()
        }
    }
    
    func endReconnectionTimer() {
        reconnectionTimer?.invalidate()
        reconnectionTimer = nil
    }
    
    func startReconnectionTimer(
        delay: Double = 0.5
    ) {
        reconnectionTimer?.invalidate()
        
        reconnectionTimer = Timer.scheduledTimer(
            timeInterval: delay,
            target: self,
            selector: #selector(reconnectionTimerFired),
            userInfo: nil,
            repeats: false
        )
    }
    
    @objc func reconnectionTimerFired() {
        if !NetworkMonitor.shared.isConnected {
            return
        }
        
        connectToServer(
            contactRestoreCallback: self.contactRestoreCallback,
            messageRestoreCallback: self.messageRestoreCallback,
            hideRestoreViewCallback: self.hideRestoreCallback
        )
    }
    
    func subscribeAndPublishMyTopics(
        pubkey: String,
        idx: Int,
        inviteCode: String? = nil
    ) {
        do {
            let ret = try Sphinx.setNetwork(network: network)
            let _ = handleRunReturn(rr: ret)
            
            guard let seed = getAccountSeed() else{
                return
            }
            
            mqtt.didReceiveMessage = { mqtt, receivedMessage, id in
                self.isConnected = true
                self.processMqttMessages(message: receivedMessage)
            }
            
            let ret3 = try Sphinx.initialSetup(
                seed: seed,
                uniqueTime: getTimeWithEntropy(),
                state: loadOnionStateAsData(),
                device: UUID().uuidString,
                inviteCode: inviteCode
            )
            
            let _ = handleRunReturn(rr: ret3)
            
            let tribeMgmtTopic = try Sphinx.getTribeManagementTopic(
                seed: seed,
                uniqueTime: getTimeWithEntropy(),
                state: loadOnionStateAsData()
            )
            
            self.mqtt.subscribe([
                (tribeMgmtTopic, CocoaMQTTQoS.qos1)
            ])
        } catch {}
    }
    
    func fetchMyAccountFromState() {
        guard let seed = getAccountSeed() else{
            return
        }
        do {
            let _ = try Sphinx.pubkeyFromSeed(
                seed: seed,
                idx: 0,
                time: getTimeWithEntropy(),
                network: network
            )

            let listContactsResponse = try Sphinx.listContacts(state: loadOnionStateAsData())
            print("MY LIST CONTACTS RESPONSE \(listContactsResponse)")
        } catch {}
    }
    
    func deleteOwnerFromState() {
        if let publicKey = UserContact.getOwner()?.publicKey {
            SphinxOnionManager.sharedInstance.deleteContactFromState(pubkey: publicKey)
        }
    }
    
    func createMyAccount(
        mnemonic: String,
        inviteCode: String? = nil
    ) -> Bool {
        //1. Generate Seed -> Display to screen the mnemonic for backup???
        guard let seed = getAccountSeed(mnemonic: mnemonic) else {
            //possibly send error message?
            return false
        }
        //2. Create the 0th pubkey
        guard let pubkey = getAccountOnlyKeysendPubkey(seed: seed), let my_xpub = getAccountXpub(seed: seed) else{
            return false
        }
        //3. Connect to server/broker
        let success = connectToBroker(seed: seed, xpub: my_xpub)
        
        //4. Subscribe to relevant topics based on OK key
        let idx = 0
        
        if success {
            mqtt.didReceiveMessage = { mqtt, receivedMessage, id in
                self.isConnected = true
                self.processMqttMessages(message: receivedMessage)
            }
            
            mqtt.didDisconnect = { _, error in
                self.isConnected = false
                self.mqttDisconnectCallback?()
                self.mqtt = nil
            }
            
            mqtt.didReceiveTrust = { _, _, completionHandler in
                completionHandler(true)
            }
            
            //subscribe to relevant topics
            mqtt.didConnectAck = { _, _ in
                self.isConnected = true
                
                self.subscribeAndPublishMyTopics(
                    pubkey: pubkey,
                    idx: idx,
                    inviteCode: inviteCode
                )
            }
        }
        return success
    }
    
    func processMqttMessages(message: CocoaMQTTMessage) {
        guard let seed = getAccountSeed() else{
            return
        }
        if !readyForPing && message.topic.contains("ping") {
            return
        }
        
        do {
            let owner = UserContact.getOwner()
            let alias = owner?.nickname ?? ""
            let pic = owner?.avatarUrl ?? ""
            
            let ret4 = try handle(
                topic: message.topic,
                payload: Data(message.payload),
                seed: seed,
                uniqueTime: getTimeWithEntropy(),
                state: self.loadOnionStateAsData(),
                myAlias: alias,
                myImg: pic
            )
            
            let _ = handleRunReturn(
                rr: ret4,
                topic: message.topic
            )
        } catch let error {
            print("Handle error \(error)")
        }
    }
    
    func showSuccessWithMessage(_ message: String) {
        self.newMessageBubbleHelper.showGenericMessageView(
            text: message,
            delay: 6,
            textColor: NSColor.white,
            backColor: NSColor.Sphinx.PrimaryGreen,
            backAlpha: 1.0
        )
    }
}

extension SphinxOnionManager {//Sign Up UI Related:
    func showMnemonicToUser(
        completion:@escaping (Bool)->()
    ){
        let generateSeedCallback: (() -> ()) = {
            guard let mneomnic = self.generateMnemonic(), let _ = self.vc as? WelcomeCodeViewController else {
                completion(false)
                return
            }
            
            self.showMnemonicToUser(mnemonic: mneomnic, callback: {
                completion(true)
            })
        }
        
        generateSeedCallback()
    }
    
    func importSeedPhrase(){
        if let vc = self.vc as? ImportSeedViewDelegate {
            vc.showImportSeedView()
        }
    }
    
    func showMnemonicToUser(mnemonic: String, callback: @escaping () -> ()) {
        guard let _ = vc else {
            callback()
            return
        }
        
        AlertHelper.showAlert(
            title: "profile.store-mnemonic".localized,
            message: mnemonic,
            confirmLabel: "Copy",
            confirm: {
                ClipboardHelper.copyToClipboard(text: mnemonic, message: "profile.mnemonic-copied".localized)
                callback()
            }
        )
    }
}

