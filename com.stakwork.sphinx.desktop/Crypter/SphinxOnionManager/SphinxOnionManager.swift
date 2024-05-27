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
    var stashedContactInfo:String? = nil
    var stashedInitialTribe:String? = nil
    var stashedInviteCode:String? = nil
    var stashedInviterAlias:String? = nil
    
    var watchdogTimer:Timer? = nil
    
    var nextMessageBlockWasReceived = false
    
    var chatsFetchParams : ChatsFetchParams? = nil
    var messageFetchParams : MessageFetchParams? = nil
    
    var isV2InitialSetup: Bool = false
    var isV2Restore: Bool = false
    var shouldPostUpdates : Bool = false
    let tribeMinEscrowSats = 3
    
    var vc: NSViewController! = nil
    var mqtt: CocoaMQTT! = nil
    
    var isConnected : Bool = false{
        didSet{
            NotificationCenter.default.post(name: .onConnectionStatusChanged, object: nil)
        }
    }
    
    var msgTotalCounts : MsgTotalCounts? = nil
    
    typealias RestoreProgressCallback = (Int) -> Void
    var messageRestoreCallback : RestoreProgressCallback? = nil
    var contactRestoreCallback : RestoreProgressCallback? = nil
    var hideRestoreCallback: (() -> ())? = nil
    var tribeMembersCallback : (([String: AnyObject]) -> ())? = nil
    var inviteCreationCallback : ((String?) -> ())? = nil
    var mqttDisconnectCallback : (() -> ())? = nil
    
    ///Session Pin to decrypt mnemonic and seed
    var appSessionPin : String? = nil
    var defaultInitialSignupPin : String = "111111"
    
    public static let kContactsBatchSize = 250
    public static let kMessageBatchSize = 50

    //MARK: Hardcoded Values!
    var server_IP = "34.229.52.200"
    let server_PORT = 1883
    let defaultTribePubkey = "02792ee5b9162f9a00686aaa5d5274e91fd42a141113007797b5c1872d43f78e07"
    
    let network = "regtest"
    
    let kCompleteStatus = "COMPLETE"
    let kFailedStatus = "FAILED"
    
    let newMessageBubbleHelper = NewMessageBubbleHelper()
    let managedContext = CoreDataManager.sharedManager.persistentContainer.viewContext
    
    ///Callbacks
    ///Restore
    var totalMsgsCountCallback: (() -> ())? = nil
    var firstSCIDMsgsCallback: (([Msg]) -> ())? = nil
    var onMessageRestoredCallback: (([Msg]) -> ())? = nil
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
        let randomInt = CrypterManager().generateCryptographicallySecureRandomInt(upperBound: upperBound)
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
                host: server_IP,
                port: UInt16(server_PORT)
            )
            
            mqtt.username = now
            mqtt.password = sig
            
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
    
    func reconnectToServer(
        connectingCallback: (() -> ())? = nil,
        hideRestoreViewCallback: (()->())? = nil
    ) {
        guard let mqtt = self.mqtt, mqtt.connState == .disconnected else {
            self.syncNewMessages()
            return
        }
        connectToServer(
            connectingCallback: connectingCallback,
            hideRestoreViewCallback: hideRestoreViewCallback
        )
    }
    
    func syncNewMessages() {
        let maxIndex = TransactionMessage.getMaxIndex()
        
        startAllMsgBlockFetch(
            startIndex: maxIndex ?? 0,
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
            AlertHelper.showAlert(title: "Error", message: "Could not get Account seed and xPubKey")
            hideRestoreViewCallback?()
            return
        }
        
        mqtt?.disconnect()
        
        if isV2Restore {
            contactRestoreCallback?(2)
        }
        
        let success = connectToBroker(seed: seed, xpub: my_xpub)
        
        if (success == false) {
            AlertHelper.showAlert(title: "Error", message: "Could not connect to MQTT Broker.")
            hideRestoreViewCallback?()
            return
        }
        
        mqtt.didConnectAck = { [weak self] _, _ in
            guard let self = self else {
                return
            }
            
            self.subscribeAndPublishMyTopics(pubkey: myPubkey, idx: 0)
            
            if (self.isV2InitialSetup) {
                self.isV2InitialSetup = false
                self.doInitialInviteSetup()
            }
             
            if self.isV2Restore {
                self.syncContactsAndMessages(
                    contactRestoreCallback: contactRestoreCallback,
                    messageRestoreCallback: messageRestoreCallback,
                    hideRestoreViewCallback: {
                        self.isV2Restore = false
                        
                        hideRestoreViewCallback?()
                    }
                )
            } else {
                self.hideRestoreCallback = {
                    hideRestoreViewCallback?()
                }
                
                self.syncNewMessages()
            }
        }
        
        self.mqtt.didDisconnect = { _, _ in
            self.mqttDisconnectCallback?()
            self.mqtt = nil
        }
    }
    
    func subscribeAndPublishMyTopics(
        pubkey: String,
        idx: Int
    ) {
        do {
            let ret = try Sphinx.setNetwork(network: network)
            let _ = handleRunReturn(rr: ret)
            
            let ret2 = try Sphinx.setBlockheight(blockheight: 0)
            let _ = handleRunReturn(rr: ret2)
            
            guard let seed = getAccountSeed() else{
                return
            }
            
            let subtopic = try Sphinx.getSubscriptionTopic(
                seed: seed,
                uniqueTime: getTimeWithEntropy(),
                state: loadOnionStateAsData()
            )
            
            mqtt.didReceiveMessage = { mqtt, receivedMessage, id in
                self.isConnected = true
                self.processMqttMessages(message: receivedMessage)
            }
            
            self.mqtt.subscribe([
                (subtopic, CocoaMQTTQoS.qos1)
            ])
            
            let ret3 = try Sphinx.initialSetup(
                seed: seed,
                uniqueTime: getTimeWithEntropy(),
                state: loadOnionStateAsData()
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
    
    
    func createMyAccount(mnemonic: String) -> Bool {
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
        let success = connectToBroker(seed:seed, xpub: my_xpub)
        
        //4. Subscribe to relevant topics based on OK key
        let idx = 0
        
        if success {
            mqtt.didReceiveMessage = { mqtt, receivedMessage, id in
                self.isConnected = true
                self.processMqttMessages(message: receivedMessage)
            }
            
            //subscribe to relevant topics
            mqtt.didConnectAck = { _, _ in
                //self.showSuccessWithMessage("MQTT connected")
                print("SphinxOnionManager: MQTT Connected")
                print("mqtt.didConnectAck")
                
                self.subscribeAndPublishMyTopics(pubkey: pubkey, idx: idx)
            }
        }
        return success
    }
    
    func processMqttMessages(message: CocoaMQTTMessage) {
        guard let seed = getAccountSeed() else{
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
            print(error)
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
    func chooseImportOrGenerateSeed(completion:@escaping (Bool)->()){
//        let requestEnteredMneumonicCallback: (() -> ()) = {
//            self.importSeedPhrase()
//        }
        
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
        
//        AlertHelper.showTwoOptionsAlert(
//            title: "profile.mnemonic-generate-or-import-title".localized,
//            message: "profile.mnemonic-generate-or-import-prompt".localized,
//            confirm: generateSeedCallback,
//            cancel: requestEnteredMneumonicCallback,
//            confirmLabel: "profile.mnemonic-generate-prompt".localized,
//            cancelLabel: "profile.mnemonic-import-prompt".localized
//        )
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

