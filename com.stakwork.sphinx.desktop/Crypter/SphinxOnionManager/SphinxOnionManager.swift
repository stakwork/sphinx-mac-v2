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


class SphinxOnionManager : NSObject, @unchecked Sendable {
    
    nonisolated(unsafe) private static var _sharedInstance: SphinxOnionManager? = nil

    static var sharedInstance: SphinxOnionManager {
        if _sharedInstance == nil {
            _sharedInstance = SphinxOnionManager()
        }
        return _sharedInstance!
    }

    static func resetSharedInstance() {
        _sharedInstance?.stopServerHealthStalenessTimer()
        _sharedInstance = nil
    }
    
    let walletBalanceService = WalletBalanceService()
    
    ///Invite
    var pendingInviteLookupByTag : [String:String] = [String:String]()
    var stashedContactInfo: String? = nil
    var stashedInitialTribe: String? = nil
    var stashedInviteCode: String? = nil
    var stashedInviterAlias: String? = nil
    
    static let kMqttKeepAlive: UInt16 = 15
    static let kConnectionTimeoutInterval: TimeInterval = 15.0
    static let kMessageFetchTimeout: TimeInterval = 30.0
    
    var reconnectionTimer: Timer? = nil
    private var mqttKeepAliveActivity: NSObjectProtocol? = nil
    private var mqttReconnectActivity: NSObjectProtocol? = nil
    var messageFetchTimeoutTimer: Timer? = nil
    var sendTimeoutTimers: [String: Timer] = [:]
    var paymentTimeoutTimers: [String: Timer] = [:]
    
    var chatsFetchParams : ChatsFetchParams? = nil
    var messageFetchParams : MessageFetchParams? = nil
    var messagePerContactFetchParams : MessagePerContactFetchParams? = nil
    
    var recentlyJoinedTribePubKeys: [String] = []
    
    var deletedTribesPubKeys: [String] {
        get {
            return UserDefaults.Keys.deletedTribesPubKeys.get(defaultValue: [])
        }
        set {
            UserDefaults.Keys.deletedTribesPubKeys.set(newValue)
        }
    }
    
    var isV2InitialSetup: Bool = false
    var isV2Restore: Bool = false
    var shouldPostUpdates : Bool = false
    
    let tribeMinSats: Int = 3000
    let kRoutingOffset = 3
    
    var restoredContactInfoTracker = [String]()
    
    var mqtt: CocoaMQTT! = nil
    /// How long to keep a torn-down `CocoaMQTT` alive after `disconnect()` so
    /// GCDAsyncSocket/CFStream workers can finish. Injectable so tests do not wait 1s.
    internal var mqttTeardownDrainInterval: TimeInterval = 1.0
    /// Identity bag of MQTT clients whose sockets are still draining.
    /// Membership and removal use `===` only — not `Hashable`.
    private var drainingMqtt: [CocoaMQTT] = []
    /// Test hook: number of clients currently held in the drain bag.
    internal var drainingMqttCount: Int { drainingMqtt.count }
    var vc: NSViewController! = nil
    var connectingStartTime: Date? = nil
    var connectionInProgress: Bool = false
    private var connectionTimeoutTimer: Timer?
    
    /// Injectable hook invoked immediately after `doInitialInviteSetup()` fires.
    /// Used in unit tests to assert exactly-once firing without a real MQTT broker.
    internal var onInitialInviteSetupFired: (() -> Void)? = nil
    
    var isConnected : Bool = false{
        didSet{
            if oldValue != isConnected {
                mqttLog("isConnected \(oldValue) -> \(isConnected) (connState=\(mqttConnStateDescription))")
            }
            NotificationCenter.default.post(name: .onConnectionStatusChanged, object: nil)
        }
    }

    /// Mixer Lightning-node health. Starts `unknown` — MQTT up is not node-ok.
    var lastServerStatus: ServerStatus? = nil
    var lastServerStatusSeenMs: UInt64 = 0
    var currentServerHealth: ServerHealth = .unknown
    var serverHealthStalenessTimer: Timer? = nil
    /// Test hook: override local clock used for health evaluation.
    var serverHealthNowMsOverride: UInt64? = nil
    /// Test hook: staleness timer interval (defaults to mixer heartbeat interval).
    var serverHealthStalenessInterval: TimeInterval = TimeInterval(SphinxrsHealth.defaultIntervalMs) / 1000.0
    /// Test hook invoked immediately before onion `handle()` — not for the status topic.
    var onOnionHandleInvoked: ((String) -> Void)? = nil
    
    // MARK: - MQTT diagnostics state (instrumentation only, no behavior change)
    var mqttConnectAttemptCount: Int = 0
    var mqttConnectedSince: Date? = nil
    var mqttLastPingSentAt: Date? = nil
    var mqttLastPongReceivedAt: Date? = nil
    var mqttMissedPongCount: Int = 0
    
    var delayedRRObjects: [Int: RunReturn] = [:]
    var delayedRRTimers: [Int: Timer] = [:]
    var pingsMap: [String: String] = [:]
    var readyForPing = false
    
    var msgTotalCounts : MsgTotalCounts? = nil
    
    typealias RestoreProgressCallback = (Int) -> Void
    var messageRestoreCallback: RestoreProgressCallback? = nil
    var contactRestoreCallback: RestoreProgressCallback? = nil
    var hideRestoreCallback: ((Bool) -> ())? = nil
    var errorCallback: (() -> ())? = nil
    var tribeMembersCallback: (([String: AnyObject]) -> ())? = nil
    var paymentsHistoryCallback: ((String?, String?) -> ())? = nil
    var inviteCreationCallback: ((String?) -> ())? = nil
    var invoiceGeneratedCallback: ((String?) -> Void)? = nil
    var invoiceGeneratedTimeoutTimer: Timer? = nil
    var mqttDisconnectCallback: (() -> ())? = nil
    
    ///Session Pin to decrypt mnemonic and seed
    var appSessionPin : String? = nil
    var defaultInitialSignupPin : String = "111111"
    
    public static let kContactsBatchSize = 100
    public static let kMessageBatchSize = 100

    public static let kCompleteStatus = "COMPLETE"
    public static let kFailedStatus = "FAILED"
    
    var onionState: [String: [UInt8]] = [:]
    let onionStateQueue = DispatchQueue(label: "sphinx.onionState", qos: .userInitiated)
    
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
    nonisolated(unsafe) let managedContext: NSManagedObjectContext = CoreDataManager.sharedManager.persistentContainer.viewContext
    nonisolated(unsafe) let backgroundContext: NSManagedObjectContext = CoreDataManager.sharedManager.getBackgroundContext()
    
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
    
    var restoringMsgsForPublicKey: String? = nil
    var onMessagePerPublicKeyRestoredCallback: ((Int) -> ())? = nil
    
    var maxMessageIndex: Int? {
        get {
            if let maxMessageIndex: Int = UserDefaults.Keys.maxMessageIndex.get() {
                return maxMessageIndex
            }
            return TransactionMessage.getMaxIndex()
        }
        set {
            UserDefaults.Keys.maxMessageIndex.set(newValue)
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
            // generateHardenedEntropyHex validates the secure RNG, XOR-mixes two sources,
            // and zeroizes raw byte buffers before returning. Keep the hex string alive as
            // briefly as possible before the FFI call (see generateHardenedEntropyHex docs).
            let entropyHex = try generateHardenedEntropyHex()
            result = try Sphinx.mnemonicFromEntropy(entropy: entropyHex)
            guard let result = result else {
                return nil
            }
            UserData.sharedInstance.save(walletMnemonic: result)
        } catch let error as SphinxOnionManagerError {
            // Log the error type/OSStatus only — never the entropy or mnemonic itself.
            print("error getting seed: \(error.localizedDescription)")
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

            if let existing = self.mqtt {
                mqttLog("Force-closing existing connection (state: \(existing.connState)) before opening new one")
                forceTeardownMqtt(existing)
            }

            mqtt = CocoaMQTT(
                clientID: xpub,
                host: serverIP,
                port: serverPORT
            )
            
            mqtt.username = now
            mqtt.password = sig
            mqtt.keepAlive = SphinxOnionManager.kMqttKeepAlive
            
            mqttConnectAttemptCount += 1
            mqttLog("connect attempt #\(mqttConnectAttemptCount) -> \(serverIP):\(serverPORT) ssl=\(isProductionEnv) keepAlive=\(SphinxOnionManager.kMqttKeepAlive)s clientID=\(xpub.prefix(12))… previousConnState=\(mqttConnStateDescription)")
            attachMqttDiagnosticHooks(to: mqtt)

            if isProductionEnv {
                mqtt.enableSSL = true
                mqtt.allowUntrustCACertificate = true
                
                mqtt.sslSettings = [
                    "kCFStreamSSLPeerName": "\(serverIP)" as NSObject
                ] as [String: NSObject]
            }
            
            let success = mqtt.connect()
            print("mqtt.connect success:\(success)")
            if success {
                connectingStartTime = Date()
            } else {
                mqttLog("socket connect() returned false — no reconnection is scheduled from this path", level: .warn)
            }
            return success
        } catch {
            mqttLog("connectToBroker threw before connecting: \(error)", level: .error)
            return false
        }
    }
    
    func disconnectMqtt(
        callback: (() -> ())? = nil
    ) {
        connectionTimeoutTimer?.invalidate()
        connectionTimeoutTimer = nil
        if self.mqtt == nil || mqtt?.connState == .disconnected {
            callback?()
            return
        }
        mqttDisconnectCallback = callback
        mqttLog("disconnectMqtt() requested (connState=\(mqttConnStateDescription))")
        endReconnectionTimer()
        endKeepAliveActivity()
        endReconnectActivity()
        stopServerHealthStalenessTimer()
        mqtt?.disconnect()
    }

    /// Holds `instance` alive for `mqttTeardownDrainInterval` after `disconnect()`
    /// so GCDAsyncSocket/CFStream workers cannot UAF the client. Called only from
    /// contexts that already run on the same (effectively main-confined) queue as
    /// the rest of this class's `mqtt`-mutating code — no queue hop here, so
    /// `instance` (non-Sendable) never needs to cross an isolation boundary.
    /// Overlapping teardown of the same pointer keeps the original drain window
    /// (no second append / release timer).
    private func retainMqttForDrain(_ instance: CocoaMQTT) {
        if drainingMqtt.contains(where: { $0 === instance }) {
            return
        }
        drainingMqtt.append(instance)
        let instanceID = ObjectIdentifier(instance)
        mqttLog("Teardown retain \(instanceID) state: \(instance.connState)")
        let interval = mqttTeardownDrainInterval
        // Capture only the (Sendable) identifier, never `instance` itself —
        // CocoaMQTT isn't Sendable, and this closure crosses the async-after
        // queue-hop boundary. `drainingMqtt` already holds the real strong
        // reference; removal only needs identity comparison.
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) { [weak self] in
            guard let self else { return }
            self.drainingMqtt.removeAll { ObjectIdentifier($0) == instanceID }
            self.mqttLog("Released draining client \(instanceID)")
        }
    }

    /// No-op callbacks first, then disconnect, then drain-retain, then nil the
    /// live slot. Do not wait for didDisconnect — CFStream close work continues
    /// after that callback, which is why release is time-based.
    func forceTeardownMqtt(_ instance: CocoaMQTT?) {
        guard let instance = instance else { return }
        instance.didReceiveMessage = { _, _, _ in }
        instance.didDisconnect = { _, _ in }
        instance.didConnectAck = { _, _ in }
        instance.didReceiveTrust = { _, _, completionHandler in
            completionHandler(true)
        }
        instance.disconnect()
        retainMqttForDrain(instance)
        if mqtt === instance {
            mqtt = nil
        }
    }

    func isFetchingContent() -> Bool {
        return onMessageRestoredCallback != nil || firstSCIDMsgsCallback != nil || totalMsgsCountCallback != nil
    }
    
    // MARK: - Shared connection-completion handler
    
    /// Single shared handler called from every `didConnectAck` path (both
    /// `createMyAccount` and `connectToServer`). Performs connect-success work
    /// and then atomically checks/consumes `isV2InitialSetup`.
    ///
    /// - Parameter myPubkey: The owner pubkey to subscribe topics for.
    /// - Parameter idx: Key index (always 0 for the primary key).
    /// - Parameter inviteCode: Optional invite code forwarded from `createMyAccount`.
    /// - Parameter hideRestoreViewCallback: Forwarded from `connectToServer`.
    /// - Parameter triggeredBy: A label for the log line (e.g. "createMyAccount" or "connectToServer").
    func handleDidConnectAck(
        myPubkey: String,
        idx: Int,
        inviteCode: String? = nil,
        hideRestoreViewCallback: ((Bool) -> ())? = nil,
        triggeredBy: String = "connectToServer"
    ) {
        connectionTimeoutTimer?.invalidate()
        connectionTimeoutTimer = nil
        let connectDuration = connectingStartTime.map { String(format: "%.2fs", Date().timeIntervalSince($0)) } ?? "n/a"
        mqttLog("CONNACK handled via \(triggeredBy) after \(connectDuration) (connState=\(mqttConnStateDescription), isV2Restore=\(isV2Restore))")
        mqttConnectedSince = Date()
        mqttLastPingSentAt = nil
        mqttLastPongReceivedAt = nil
        mqttMissedPongCount = 0
        isConnected = true
        beginKeepAliveActivity()
        connectionInProgress = false
        endReconnectionTimer()
        
        subscribeAndPublishMyTopics(pubkey: myPubkey, idx: idx, inviteCode: inviteCode)
        
        // Atomically consume isV2InitialSetup. Only fire doInitialInviteSetup()
        // when we are certain a pending invite exists (stashedInviteCode is non-nil),
        // guarding against restore-mode logins (isV2Restore = true) and stale flags.
        if isV2InitialSetup && !isV2Restore && stashedInviteCode != nil {
            isV2InitialSetup = false
            print("[MQTT] doInitialInviteSetup firing — branch: \(triggeredBy) (shared didConnectAck handler)")
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.doInitialInviteSetup()
                self.onInitialInviteSetupFired?()
            }
        } else if isV2InitialSetup {
            // Flag set but no invite data or this is a restore — clear flag safely.
            isV2InitialSetup = false
        }
        
        if isV2Restore {
            self.hideRestoreCallback = { [weak self] _ in
                guard let self = self else { return }
                self.isV2Restore = false
                hideRestoreViewCallback?(true)
            }
            syncContactsAndMessages()
        } else {
            self.contactRestoreCallback = nil
            self.messageRestoreCallback = nil
            startNewMsgsSync()
        }
    }
    
    /// Immediately consumes `isV2InitialSetup` when the connection is confirmed live
    /// (safe-immediate path, e.g. the "already connected" guard in `reconnectToServer`).
    /// Must be called on the main thread.
    func consumeInitialSetupIfPending(triggeredBy: String) {
        guard isV2InitialSetup && !isV2Restore && stashedInviteCode != nil else {
            if isV2InitialSetup { isV2InitialSetup = false }
            return
        }
        isV2InitialSetup = false
        print("[MQTT] doInitialInviteSetup firing — branch: \(triggeredBy) (safe-immediate, already connected)")
        doInitialInviteSetup()
        onInitialInviteSetupFired?()
    }

    func reconnectToServer(
        connectingCallback: (() -> ())? = nil,
        hideRestoreViewCallback: ((Bool)->())? = nil,
        forceReconnect: Bool = false
    ) {
        mqttLog("reconnectToServer(force=\(forceReconnect)) connState=\(mqttConnStateDescription) isConnected=\(isConnected) connectionInProgress=\(connectionInProgress)")
        if let mqtt = self.mqtt, !forceReconnect {
            if mqtt.connState == .connecting {
                // Stale connecting attempts (<10s) — deferred-pending: leave isV2InitialSetup
                // untouched so the in-flight didConnectAck (routed through handleDidConnectAck)
                // consumes it once the connection is actually confirmed.
                if let startTime = connectingStartTime, Date().timeIntervalSince(startTime) < 10.0 {
                    mqttLog("reconnectToServer skipped — still connecting (\(String(format: "%.1f", Date().timeIntervalSince(startTime)))s elapsed)")
                    return
                }
                mqttLog("reconnectToServer: stale connecting attempt (>10s) — falling through to connectToServer", level: .warn)
            } else if mqtt.connState == .connected && isConnected {
                if !isV2Restore {
                    // Safe-immediate: connection is confirmed live, consume the flag now.
                    consumeInitialSetupIfPending(triggeredBy: "reconnectToServer/already-connected")
                    if !isFetchingContent() {
                        startNewMsgsSync()
                    }
                    hideRestoreViewCallback?(false)
                }
                mqttLog("reconnectToServer skipped — already connected")
                return
            }
        }
        if let mqtt = self.mqtt, forceReconnect, mqtt.connState == .connected {
            mqttLog("forceReconnect while connState=connected — existing CocoaMQTT instance will be replaced without disconnect (duplicate clientID likely)", level: .warn)
        }
        connectToServer(
            connectingCallback: connectingCallback,
            hideRestoreViewCallback: hideRestoreViewCallback
        )
    }
    
    func startNewMsgsSync() {
        self.getReads()
        self.getMuteLevels()
        self.syncNewMessages()
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
        hideRestoreViewCallback: ((Bool)->())? = nil
    ){
        connectingCallback?()
        
        guard let seed = getAccountSeed(),
              let myPubkey = getAccountOnlyKeysendPubkey(seed: seed),
              let my_xpub = getAccountXpub(seed: seed) else
        {
            mqttLog("connectToServer aborted — seed/pubkey/xpub unavailable", level: .error)
            hideRestoreViewCallback?(false)
            return
        }
        
        guard !connectionInProgress else {
            // Deferred-pending: do NOT fire or clear isV2InitialSetup here.
            // The in-flight connection's eventual didConnectAck (routed through
            // handleDidConnectAck) will consume the flag once the connection is confirmed.
            print("[MQTT] connectToServer skipped — connection already in progress (flag deferred to didConnectAck)")
            return
        }
        connectionInProgress = true

        if isV2Restore {
            contactRestoreCallback?(2)
        }

        self.hideRestoreCallback = hideRestoreViewCallback
        self.contactRestoreCallback = contactRestoreCallback
        self.messageRestoreCallback = messageRestoreCallback

        let success = connectToBroker(seed: seed, xpub: my_xpub)

        if (success == false) {
            mqttLog("connectToServer: connectToBroker failed — giving up until next wake/reachability/app-active trigger", level: .warn)
            connectionInProgress = false
            hideRestoreViewCallback?(false)
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.connectionTimeoutTimer?.invalidate()
            self.connectionTimeoutTimer = Timer.scheduledTimer(withTimeInterval: SphinxOnionManager.kConnectionTimeoutInterval, repeats: false) { [weak self] _ in
                guard let self = self, self.connectionInProgress else { return }
                self.mqttLog("Connection timed out after \(Int(SphinxOnionManager.kConnectionTimeoutInterval))s — force-closing and retrying")
                self.connectionInProgress = false
                self.forceTeardownMqtt(self.mqtt)
                self.startReconnectionTimer(delay: 2.0)
            }
        }

        let connectingMqtt = mqtt
        mqtt.didConnectAck = { [weak self] _, ack in
            guard let self = self else {
                return
            }
            self.logConnAck(ack, triggeredBy: "connectToServer")
            // If self.mqtt has been replaced by a newer connection, discard this stale ack
            guard self.mqtt === connectingMqtt else {
                self.mqttLog("stale CONNACK from a replaced CocoaMQTT instance — disconnecting it", level: .warn)
                connectingMqtt?.disconnect()
                return
            }

            self.handleDidConnectAck(
                myPubkey: myPubkey,
                idx: 0,
                hideRestoreViewCallback: hideRestoreViewCallback,
                triggeredBy: "connectToServer"
            )
        }
        
        mqtt.didReceiveTrust = { _, _, completionHandler in
            completionHandler(true)
        }
        
        let disconnectingMqtt = mqtt
        mqtt.didDisconnect = { [weak self] mqttInstance, error in
            guard let self = self else { return }
            self.logDisconnect(error: error, instance: mqttInstance, isCurrent: self.mqtt === disconnectingMqtt, path: "connectToServer")
            self.connectionTimeoutTimer?.invalidate()
            self.connectionTimeoutTimer = nil
            self.connectionInProgress = false
            self.isConnected = false
            self.mqttDisconnectCallback?()
            self.retainMqttForDrain(mqttInstance)
            if self.mqtt === disconnectingMqtt {
                self.isConnected = false
                self.endKeepAliveActivity()
                self.mqtt = nil
                self.startReconnectionTimer()
            }
        }
    }
    
    func endReconnectionTimer() {
        reconnectionTimer?.invalidate()
        reconnectionTimer = nil
        endReconnectActivity()
    }
    
    func startReconnectionTimer(
        delay: Double = 0.5
    ) {
        guard Thread.isMainThread else {
            print("[MQTT] startReconnectionTimer called off main thread — re-dispatching")
            reconnectionTimer?.invalidate()
            DispatchQueue.main.async { [weak self] in
                self?.startReconnectionTimer(delay: delay)
            }
            return
        }
        reconnectionTimer?.invalidate()
        beginReconnectActivity()
        mqttLog("scheduling reconnect in \(delay)s")
        reconnectionTimer = Timer.scheduledTimer(
            timeInterval: delay,
            target: self,
            selector: #selector(reconnectionTimerFired),
            userInfo: nil,
            repeats: false
        )
    }
    
    private func beginKeepAliveActivity() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.beginKeepAliveActivity() }
            return
        }
        guard mqttKeepAliveActivity == nil else { return }
        print("[MQTT] Beginning keepalive background activity")
        mqttKeepAliveActivity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiated,
            reason: "MQTT keepalive — prevent App Nap suppressing PINGREQ"
        )
    }
    
    private func endKeepAliveActivity() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.endKeepAliveActivity() }
            return
        }
        guard let a = mqttKeepAliveActivity else { return }
        print("[MQTT] Ending keepalive background activity")
        ProcessInfo.processInfo.endActivity(a)
        mqttKeepAliveActivity = nil
    }
    
    private func beginReconnectActivity() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.beginReconnectActivity() }
            return
        }
        guard mqttReconnectActivity == nil else { return }
        print("[MQTT] Beginning reconnect background activity")
        mqttReconnectActivity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiated,
            reason: "MQTT reconnection — prevent App Nap throttling reconnect timer"
        )
    }
    
    private func endReconnectActivity() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.endReconnectActivity() }
            return
        }
        guard let a = mqttReconnectActivity else { return }
        print("[MQTT] Ending reconnect background activity")
        ProcessInfo.processInfo.endActivity(a)
        mqttReconnectActivity = nil
    }
    
    @objc func reconnectionTimerFired() {
        mqttLog("reconnect timer fired")
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
            
            mqtt.didReceiveMessage = { [weak self] mqtt, receivedMessage, id in
                self?.isConnected = true
                self?.processMqttMessages(message: receivedMessage)
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
                (tribeMgmtTopic, CocoaMQTTQoS.qos0)
            ])
            self.subscribeToServerStatusTopic()
            self.startServerHealthStalenessTimer()
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

//            listAndUpdateContacts()
        } catch {}
    }
    
    func listAndUpdateContacts() {
        do {
            let listContactsResponse = try Sphinx.listContacts(state: loadOnionStateAsData())

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
            mqtt.didReceiveMessage = { [weak self] mqtt, receivedMessage, id in
                self?.isConnected = true
                self?.processMqttMessages(message: receivedMessage)
            }
            
            mqtt.didDisconnect = { mqttInstance, error in
                self.logDisconnect(error: error, instance: mqttInstance, isCurrent: self.mqtt === mqttInstance, path: "createMyAccount")
                self.endKeepAliveActivity()
                self.isConnected = false
                self.mqttDisconnectCallback?()
                self.retainMqttForDrain(mqttInstance)
                if self.mqtt === mqttInstance {
                    self.mqtt = nil
                }
            }
            
            mqtt.didReceiveTrust = { _, _, completionHandler in
                completionHandler(true)
            }
            
            //subscribe to relevant topics and consume any pending initial-setup flag
            mqtt.didConnectAck = { [weak self] _, ack in
                guard let self = self else { return }
                self.logConnAck(ack, triggeredBy: "createMyAccount")
                self.handleDidConnectAck(
                    myPubkey: pubkey,
                    idx: idx,
                    inviteCode: inviteCode,
                    triggeredBy: "createMyAccount"
                )
            }
        }
        return success
    }
    
    func processMqttMessages(message: CocoaMQTTMessage) {
        if !readyForPing && message.topic.contains("ping") {
            return
        }

        if consumeServerStatusMessage(topic: message.topic, payload: Data(message.payload)) {
            return
        }

        onOnionHandleInvoked?(message.topic)

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
            print("Handle error \(error)")
        }
    }
    
    func showSuccessWithMessage(_ message: String) {
        Task { @MainActor in
            self.newMessageBubbleHelper.showGenericMessageView(
                text: message,
                delay: 6,
                textColor: NSColor.white,
                backColor: NSColor.Sphinx.PrimaryGreen,
                backAlpha: 1.0
            )
        }
    }
}

// MARK: - MQTT diagnostics (instrumentation only)

// Note: CocoaMQTT's own logger already prints socket errors and protocol
// warnings to stdout at its default (.warning) level, e.g.
// "CocoaMQTT(error): socket connect error: ...", and AppLogger captures stdout.
// Its only info-level lines are per-message receipts (already logged by the
// app) and auto-reconnect notices (feature unused), so the level is left as is.

extension SphinxOnionManager {
    enum MqttLogLevel: String { case info = "INFO", warn = "WARN", error = "ERROR" }
    
    func mqttLog(_ message: String, level: MqttLogLevel = .info) {
        print("[MQTT][\(level.rawValue)] \(message)")
    }
    
    var mqttConnStateDescription: String {
        guard let mqtt = mqtt else { return "nil" }
        switch mqtt.connState {
        case .connected: return "connected"
        case .connecting: return "connecting"
        case .disconnected: return "disconnected"
        @unknown default: return "unknown"
        }
    }
    
    /// Ping/pong tracking. CocoaMQTT 2.1.6 never times out a missing PINGRESP,
    /// so a half-open socket looks "connected" forever. This only records and logs.
    func attachMqttDiagnosticHooks(to mqtt: CocoaMQTT) {
        mqtt.didPing = { [weak self] _ in
            guard let self = self else { return }
            let now = Date()
            if let lastPing = self.mqttLastPingSentAt {
                let pongAfterLastPing = (self.mqttLastPongReceivedAt ?? .distantPast) >= lastPing
                if !pongAfterLastPing {
                    self.mqttMissedPongCount += 1
                    let lastPongAgo = self.mqttLastPongReceivedAt.map { String(format: "%.0fs ago", now.timeIntervalSince($0)) } ?? "never"
                    self.mqttLog("PINGREQ sent but no PINGRESP since previous ping (missed=\(self.mqttMissedPongCount), last pong \(lastPongAgo), isConnected=\(self.isConnected)) — possible half-open socket", level: .warn)
                }
            }
            self.mqttLastPingSentAt = now
        }
        mqtt.didReceivePong = { [weak self] _ in
            guard let self = self else { return }
            self.mqttLastPongReceivedAt = Date()
            if self.mqttMissedPongCount > 0 {
                self.mqttLog("PINGRESP received again after \(self.mqttMissedPongCount) missed")
                self.mqttMissedPongCount = 0
            }
        }
        mqtt.didSubscribeTopics = { [weak self] _, success, failed in
            guard let self = self else { return }
            if !failed.isEmpty {
                self.mqttLog("SUBACK failed for \(failed.count) topic(s): \(failed.map { "…" + $0.suffix(40) })", level: .warn)
            } else {
                self.mqttLog("SUBACK ok for \(success.count) topic(s): \(success.allKeys.compactMap { ($0 as? String).map { "…" + $0.suffix(40) } })")
            }
        }
    }
    
    /// Logs every outgoing publish compactly (topic suffix identifies the request
    /// type, e.g. .../getreads). When the socket is not yet connected the publish
    /// reaches the server before CONNECT and the server closes the socket, so in
    /// that case also log who triggered it.
    func logPublish(topic: String, bytes: Int, kind: String) {
        let suffix = "…" + topic.suffix(44)
        let state = mqttConnStateDescription
        if mqtt == nil || mqtt?.connState != .connected {
            let frames = Thread.callStackSymbols.dropFirst(2).prefix(8)
                .map { $0.split(separator: " ", omittingEmptySubsequences: true).dropFirst(3).joined(separator: " ") }
                .map { String($0.prefix(90)) }
            mqttLog("\(kind) while NOT connected (connState=\(state)) topic=\(suffix) bytes=\(bytes) — will poison a connecting socket or be lost", level: .warn)
            mqttLog("  triggered from: \(frames.joined(separator: " <- "))", level: .warn)
        } else {
            // Disabled: this fired on every successful MQTT publish, adding write volume to the
            // persistent sphinx_logs.txt Diagnostics file with limited debugging value on the success path.
            // mqttLog("\(kind) topic=\(suffix) bytes=\(bytes)")
        }
    }
    
    func logConnAck(_ ack: CocoaMQTTConnAck, triggeredBy: String) {
        if ack == .accept {
            mqttLog("CONNACK accept (\(triggeredBy))")
        } else {
            // CocoaMQTT invokes didConnectAck for rejections too, and the handlers below
            // currently proceed as if connected. Logged loudly until that is fixed.
            mqttLog("CONNACK REJECTED code=\(ack.rawValue) (\(ack)) via \(triggeredBy) — handler still runs the success path (known defect)", level: .error)
        }
    }
    
    func logDisconnect(error: Error?, instance: CocoaMQTT, isCurrent: Bool, path: String) {
        let connectedFor = mqttConnectedSince.map { String(format: "%.0fs", Date().timeIntervalSince($0)) } ?? "never-acked"
        let sinceLastPong = mqttLastPongReceivedAt.map { String(format: "%.0fs ago", Date().timeIntervalSince($0)) } ?? "n/a"
        let errorText: String
        if let error = error {
            let ns = error as NSError
            errorText = "\(ns.domain)#\(ns.code): \(ns.localizedDescription)"
        } else {
            errorText = "nil (clean close by peer or local disconnect)"
        }
        mqttLog("DISCONNECTED (\(path)) current=\(isCurrent) connectedFor=\(connectedFor) lastPong=\(sinceLastPong) missedPongs=\(mqttMissedPongCount) error=\(errorText)", level: .warn)
        if isCurrent { mqttConnectedSince = nil }
    }
}

extension SphinxOnionManager {//Sign Up UI Related:
    @MainActor func showMnemonicToUser(
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
            Task { @MainActor in vc.showImportSeedView() }
        }
    }
    
    @MainActor func showMnemonicToUser(mnemonic: String, callback: @escaping () -> ()) {
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
    
    func getPersonalKeys() -> Keys? {
        if let mnemonic = UserData.sharedInstance.getMnemonic() {
            if let seed = try? Sphinx.mnemonicToSeed(mnemonic: mnemonic) {
                if let keys = try? Sphinx.nodeKeys(net: "bitcoin", seed: seed) {
                    return keys
                }
            }
        }
        return nil
    }
}

