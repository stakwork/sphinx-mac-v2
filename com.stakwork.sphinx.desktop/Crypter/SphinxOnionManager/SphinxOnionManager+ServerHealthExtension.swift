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
        topic == SphinxrsHealth.serverStatusTopic()
    }

    func subscribeToServerStatusTopic() {
        guard mqtt != nil else { return }
        mqtt.subscribe([
            (SphinxrsHealth.serverStatusTopic(), CocoaMQTTQoS.qos0)
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
        let json = String(data: payload, encoding: .utf8)
        var parseFailed = false
        var status: ServerStatus?

        if let json {
            do {
                status = try SphinxrsHealth.parseServerStatus(payload: json)
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
            setServerHealth(.unknown, parseFailed: true)
            return
        }

        let nowMs = currentServerHealthNowMs()
        lastServerStatus = status
        lastServerStatusSeenMs = nowMs
        let health = SphinxrsHealth.evaluateServerHealth(
            last: status,
            lastSeenMs: nowMs,
            nowMs: nowMs
        )
        setServerHealth(health, parseFailed: false)
    }

    func reevaluateServerHealth(nowMs: UInt64? = nil) {
        let now = nowMs ?? currentServerHealthNowMs()
        let health = SphinxrsHealth.evaluateServerHealth(
            last: lastServerStatus,
            lastSeenMs: lastServerStatusSeenMs,
            nowMs: now
        )
        setServerHealth(health, parseFailed: false)
    }

    func startServerHealthStalenessTimer() {
        let start: () -> Void = { [weak self] in
            guard let self else { return }
            if self.serverHealthStalenessTimer != nil { return }
            let timer = Timer.scheduledTimer(withTimeInterval: self.serverHealthStalenessInterval, repeats: true) { [weak self] _ in
                self?.reevaluateServerHealth()
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
            self?.serverHealthStalenessTimer?.invalidate()
            self?.serverHealthStalenessTimer = nil
        }

        if Thread.isMainThread {
            stop()
        } else {
            DispatchQueue.main.async(execute: stop)
        }
    }

    func setServerHealth(_ health: ServerHealth, parseFailed: Bool) {
        let apply: () -> Void = { [weak self] in
            guard let self else { return }
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
}
