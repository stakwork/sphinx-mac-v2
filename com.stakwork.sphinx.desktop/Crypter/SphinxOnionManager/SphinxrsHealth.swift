//
//  SphinxrsHealth.swift
//  sphinx
//
//  Native stand-in for sphinx-ffi health helpers (`parse_server_status`,
//  `evaluate_server_health`, `parse_mixer_error_code`, `server_status_topic`).
//  Replace this file with the regenerated UniFFI bindings once they land.
//

import Foundation

/// Mixer heartbeat payload `{ cln_ok, degraded, reason, ts }`.
struct ServerStatus: Equatable, Sendable {
    var clnOk: Bool
    var degraded: Bool
    var reason: String?
    var ts: UInt64
}

/// Shared Lightning-node health: independent of MQTT connected/disconnected.
enum ServerHealth: Equatable, Sendable {
    case ok
    case degraded
    case unknown
}

/// Structured mixer send/pay failure codes.
enum MixerErrorCode: Equatable, Sendable {
    case clnUnavailable
    case clnTimeout
    case insufficientBalance
    case unknown
}

enum SphinxrsHealth {
    /// Default mixer status heartbeat interval (30s).
    static let defaultIntervalMs: UInt64 = 30_000
    /// Missed-interval threshold N = 3 (~90s) → unknown.
    static let defaultMaxMissed: UInt32 = 3

    /// Global mixer status topic (same family as `blockheight`); the mixer publishes periodically, there is no broker-side retained delivery on subscribe.
    /// Single constant — update here when `sphinx/src/topics.rs` is finalized.
    static func serverStatusTopic() -> String {
        "server_status"
    }

    /// Parses the mixer status JSON. Invalid/malformed JSON throws `SphinxError`.
    static func parseServerStatus(payload: String) throws -> ServerStatus {
        guard let data = payload.data(using: .utf8) else {
            throw SphinxError.BadResponse(r: "invalid server status JSON")
        }

        let object: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw SphinxError.BadResponse(r: "invalid server status JSON")
            }
            object = parsed
        } catch {
            throw SphinxError.BadResponse(r: "invalid server status JSON")
        }

        guard let clnOk = boolValue(object["cln_ok"]) else {
            throw SphinxError.BadResponse(r: "invalid server status JSON")
        }

        let degraded = boolValue(object["degraded"]) ?? false
        let reason: String?
        if object["reason"] is NSNull || object["reason"] == nil {
            reason = nil
        } else if let value = object["reason"] as? String {
            reason = value
        } else {
            throw SphinxError.BadResponse(r: "invalid server status JSON")
        }

        guard let ts = uint64Value(object["ts"]) else {
            throw SphinxError.BadResponse(r: "invalid server status JSON")
        }

        return ServerStatus(clnOk: clnOk, degraded: degraded, reason: reason, ts: ts)
    }

    /// Evaluates health from the last sample and **local** receipt time.
    /// Payload `ts` is a freshness gate only — never used as `last_seen_ms`.
    static func evaluateServerHealth(
        last: ServerStatus?,
        lastSeenMs: UInt64,
        nowMs: UInt64,
        intervalMs: UInt64 = defaultIntervalMs,
        maxMissed: UInt32 = defaultMaxMissed
    ) -> ServerHealth {
        guard let last else {
            return .unknown
        }

        let maxAge = intervalMs * UInt64(maxMissed)

        if nowMs < lastSeenMs || nowMs &- lastSeenMs > maxAge {
            return .unknown
        }

        // Stale last-good payload, or unusable/future payload timestamp.
        if last.ts == 0 || last.ts > nowMs || nowMs &- last.ts > maxAge {
            return .unknown
        }

        if last.degraded || !last.clnOk {
            return .degraded
        }

        return .ok
    }

    /// Accepts a JSON object with a `code` field or a bare code string.
    /// Unrecognized input maps to `unknown` and never throws.
    static func parseMixerErrorCode(raw: String) -> MixerErrorCode {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .unknown
        }

        if let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let code = object["code"] as? String
        {
            return mapMixerErrorCode(code)
        }

        return mapMixerErrorCode(trimmed)
    }

    /// Localized client copy for a mixer `code`. Missing code → generic fallback.
    /// Never returns raw mixer `reason` / JSON.
    static func localizedMessage(forCode raw: String?) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            return "generic.error.message".localized
        }

        switch parseMixerErrorCode(raw: trimmed) {
        case .clnUnavailable:
            return "mixer.error.cln.unavailable".localized
        case .clnTimeout:
            return "mixer.error.cln.timeout".localized
        case .insufficientBalance:
            return "mixer.error.insufficient.balance".localized
        case .unknown:
            return "mixer.error.unknown".localized
        }
    }

    static func localizedBannerCopy(for health: ServerHealth) -> String? {
        switch health {
        case .ok:
            return nil
        case .degraded:
            return "server.health.banner.degraded".localized
        case .unknown:
            return "server.health.banner.unknown".localized
        }
    }

    private static func mapMixerErrorCode(_ code: String) -> MixerErrorCode {
        switch code.uppercased() {
        case "CLN_UNAVAILABLE":
            return .clnUnavailable
        case "CLN_TIMEOUT":
            return .clnTimeout
        case "INSUFFICIENT_BALANCE":
            return .insufficientBalance
        default:
            return .unknown
        }
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool {
            return bool
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        return nil
    }

    private static func uint64Value(_ value: Any?) -> UInt64? {
        if let number = value as? NSNumber {
            let doubleValue = number.doubleValue
            if doubleValue < 0 { return nil }
            return number.uint64Value
        }
        if let int = value as? Int, int >= 0 {
            return UInt64(int)
        }
        if let uint = value as? UInt64 {
            return uint
        }
        return nil
    }
}
