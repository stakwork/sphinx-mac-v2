//
//  SphinxOnionManager+ServerHealthExtension.swift
//  sphinx
//
//  Tracks mixer Lightning-node health independently of MQTT connectivity.
//

import Foundation
import CocoaMQTT

extension Notification.Name {
    static let onServerHealthChanged = Notification.Name("onServerHealthChanged")
}

extension SphinxOnionManager {

    /// Exact-topic match only. Substring must never intercept.
    func shouldInterceptServerStatus(topic: String) -> Bool {
        topic == serverStatusTopic()
    }

    func subscribeToServerStatusTopic() {
        guard mqtt != nil else { return }
        mqtt.subscribe([
            (serverStatusTopic(), CocoaMQTTQoS.qos0)
        ])
    }

    /// Intercept plaintext mixer status **before** onion `handle()`.
    /// Returns true when the topic was consumed (caller must not call `handle()`).
    @discardableResult
    func consumeServerStatusMessage(topic: String, payload: Data) -> Bool {
        guard shouldInterceptServerStatus(topic: topic) else {
            return false
        }

        let apply: () -> Void = { [weak self] in
            self?.applyServerStatusPayload(payload)
        }

        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
        return true
    }

    func applyServerStatusPayload(_ payload: Data) {
        let apply: () -> Void = { [weak self] in
            guard let self else { return }
            // Any consumed payload, including parse failure, ends the launch hold.
            // Flag and one-shot stay on main, the thread that scheduled the timer.
            self.markServerStatusReceived()
            self.applyParsedServerStatusPayload(payload)
        }

        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    /// Caller is already on the main thread.
    private func applyParsedServerStatusPayload(_ payload: Data) {
        let json = String(data: payload, encoding: .utf8)
        var parseFailed = false
        var status: ServerStatus?

        if let json {
            do {
                status = try parseServerStatus(payload: json)
            } catch {
                parseFailed = true
                status = nil
            }
        } else {
            parseFailed = true
        }

        if parseFailed {
            lastServerStatus = nil
            lastServerStatusSeenMs = 0
            let healthUnchanged = currentServerHealth == .unknown
            setServerHealth(.unknown, parseFailed: true)
            if healthUnchanged {
                NotificationCenter.default.post(name: .onServerHealthChanged, object: nil)
            }
            return
        }

        let nowMs = currentServerHealthNowMs()
        lastServerStatus = status
        lastServerStatusSeenMs = nowMs
        let health = evaluateServerHealth(
            last: status,
            lastSeenMs: nowMs,
            nowMs: nowMs,
            intervalMs: ServerHealthPresentation.defaultIntervalMs,
            maxMissed: ServerHealthPresentation.defaultMaxMissed
        )
        let healthUnchanged = currentServerHealth == health
        setServerHealth(health, parseFailed: false)
        if healthUnchanged {
            NotificationCenter.default.post(name: .onServerHealthChanged, object: nil)
        }
    }

    private func markServerStatusReceived() {
        hasReceivedServerStatus = true
        invalidateServerHealthLaunchGraceTimer()
    }

    func reevaluateServerHealth(nowMs: UInt64? = nil) {
        let now = nowMs ?? currentServerHealthNowMs()
        let health = evaluateServerHealth(
            last: lastServerStatus,
            lastSeenMs: lastServerStatusSeenMs,
            nowMs: now,
            intervalMs: ServerHealthPresentation.defaultIntervalMs,
            maxMissed: ServerHealthPresentation.defaultMaxMissed
        )
        setServerHealth(health, parseFailed: false)
    }

    func startServerHealthStalenessTimer() {
        let start: () -> Void = { [weak self] in
            guard let self else { return }
            // Arm before the staleness early-return. Repeat onion responses must
            // not reset an already-open window, and must not skip the first arm.
            self.armServerHealthLaunchGraceIfNeeded()
            if self.serverHealthStalenessTimer != nil { return }
            let timer = Timer.scheduledTimer(withTimeInterval: self.serverHealthStalenessInterval, repeats: true) { [weak self] _ in
                // While the device itself is offline, don't let the staleness
                // window flip health to `.unknown` — that reads as a real server
                // outage even though nothing is wrong with the server.
                guard let self, self.isDeviceOnline else { return }
                self.reevaluateServerHealth()
            }
            RunLoop.main.add(timer, forMode: .common)
            self.serverHealthStalenessTimer = timer
        }

        if Thread.isMainThread {
            start()
        } else {
            DispatchQueue.main.async(execute: start)
        }
    }

    func stopServerHealthStalenessTimer() {
        let stop: () -> Void = { [weak self] in
            guard let self else { return }
            self.serverHealthStalenessTimer?.invalidate()
            self.serverHealthStalenessTimer = nil
            self.clearServerHealthLaunchGrace()
        }

        if Thread.isMainThread {
            stop()
        } else {
            DispatchQueue.main.async(execute: stop)
        }
    }

    /// Idempotent. Only a nil `serverHealthTrackingStartedAtMs` opens the window.
    func armServerHealthLaunchGraceIfNeeded() {
        if serverHealthTrackingStartedAtMs != nil { return }
        serverHealthTrackingStartedAtMs = currentServerHealthNowMs()
        invalidateServerHealthLaunchGraceTimer()
        let timer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(ServerHealthPresentation.launchGraceMs) / 1000.0,
            repeats: false
        ) { [weak self] _ in
            self?.handleServerHealthLaunchGraceElapsed()
        }
        RunLoop.main.add(timer, forMode: .common)
        serverHealthLaunchGraceTimer = timer
        NotificationCenter.default.post(name: .onServerHealthChanged, object: nil)
    }

    /// Re-reads the gate via observers. Does not compute a second show/hide decision.
    func handleServerHealthLaunchGraceElapsed() {
        invalidateServerHealthLaunchGraceTimer()
        NotificationCenter.default.post(name: .onServerHealthChanged, object: nil)
    }

    private func clearServerHealthLaunchGrace() {
        hasReceivedServerStatus = false
        serverHealthTrackingStartedAtMs = nil
        invalidateServerHealthLaunchGraceTimer()
        NotificationCenter.default.post(name: .onServerHealthChanged, object: nil)
    }

    private func invalidateServerHealthLaunchGraceTimer() {
        serverHealthLaunchGraceTimer?.invalidate()
        serverHealthLaunchGraceTimer = nil
    }

    func setServerHealth(_ health: ServerHealth, parseFailed: Bool) {
        // Generated `ServerHealth` is Equatable/Hashable only — not Sendable — so the
        // main-queue hop must not capture it. Rebuild the case from a Sendable raw tag.
        let healthTag = Self.serverHealthTag(health)
        let apply: () -> Void = { [weak self] in
            guard let self else { return }
            let health = Self.serverHealth(fromTag: healthTag)
            if parseFailed {
                self.mqttLog("server health parse-failure=true")
            }
            if self.currentServerHealth != health {
                self.mqttLog("server health \(self.describe(self.currentServerHealth)) -> \(self.describe(health))")
                self.currentServerHealth = health
                NotificationCenter.default.post(name: .onServerHealthChanged, object: nil)
            }
        }

        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    private static func serverHealthTag(_ health: ServerHealth) -> UInt8 {
        switch health {
        case .ok: return 1
        case .degraded: return 2
        case .unknown: return 3
        }
    }

    private static func serverHealth(fromTag tag: UInt8) -> ServerHealth {
        switch tag {
        case 1: return .ok
        case 2: return .degraded
        default: return .unknown
        }
    }

    private func describe(_ health: ServerHealth) -> String {
        switch health {
        case .ok: return "ok"
        case .degraded: return "degraded"
        case .unknown: return "unknown"
        }
    }

    func currentServerHealthNowMs() -> UInt64 {
        if let override = serverHealthNowMsOverride {
            return override
        }
        let ms = Date().timeIntervalSince1970 * 1000.0
        return ms > 0 ? UInt64(ms) : 0
    }

    var isServerHealthBannerVisible: Bool {
        ServerHealthPresentation.shouldShowBanner(
            health: currentServerHealth,
            hasReceivedServerStatus: hasReceivedServerStatus,
            trackingStartedAtMs: serverHealthTrackingStartedAtMs,
            nowMs: currentServerHealthNowMs(),
            isDeviceOnline: isDeviceOnline
        )
    }

    // MARK: - Device reachability (banner suppression + bolt gate)

    /// UI-facing device reachability. The test provider seam takes priority
    /// over the real `NetworkMonitor` so unit tests never depend on the real
    /// `NWPathMonitor`.
    var isDeviceOnline: Bool {
        if let deviceOnlineProvider {
            return deviceOnlineProvider()
        }
        return NetworkMonitor.shared.isReachableOrUnknown
    }

    /// Registers the block observers that drive `handleDeviceReachabilityChange()`.
    /// Called once from `init()`. Mac's `NetworkMonitor` posts `.connectedToInternet` /
    /// `.disconnectedFromInternet` on every path callback (not just changes), off the
    /// `NWMonitor` background queue, so these use `queue: .main` and the handler dedupes.
    func registerReachabilityObservers() {
        let connected = NotificationCenter.default.addObserver(
            forName: .connectedToInternet,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleDeviceReachabilityChange()
        }

        let disconnected = NotificationCenter.default.addObserver(
            forName: .disconnectedFromInternet,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleDeviceReachabilityChange()
        }

        reachabilityObserverTokens.append(contentsOf: [connected, disconnected])
    }

    func removeReachabilityObservers() {
        for token in reachabilityObserverTokens {
            NotificationCenter.default.removeObserver(token)
        }
        reachabilityObserverTokens.removeAll()
    }

    /// Main-thread only. De-dupes Mac's per-callback reachability posts so
    /// `.onServerHealthChanged` only fires once per real transition.
    func handleDeviceReachabilityChange() {
        let online = isDeviceOnline
        if lastReportedDeviceOnline == online { return }

        let wasOnline = lastReportedDeviceOnline
        lastReportedDeviceOnline = online

        if online {
            mqttLog("device online — server-health banner re-evaluated")
            // Give the server a full staleness window to send a heartbeat
            // before the staleness timer can mark health `.unknown` again —
            // otherwise the banner would show "server status unknown" the
            // instant the device reconnects, which looks like a real outage.
            if wasOnline == false && hasReceivedServerStatus {
                lastServerStatusSeenMs = currentServerHealthNowMs()
            }
        } else {
            mqttLog("device offline — server-health banner suppressed")
        }

        NotificationCenter.default.post(name: .onServerHealthChanged, object: nil)
    }
}
