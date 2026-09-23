//
//  ServerHealthPresentation.swift
//  sphinx
//
//  Mac-only copy and staleness defaults for mixer health.
//  Parsing and evaluation go through the generated sphinx-ffi bindings.
//

import Foundation

enum ServerHealthPresentation {
    /// Default mixer status heartbeat interval (30s).
    static let defaultIntervalMs: UInt64 = 30_000
    /// Missed-interval threshold N = 3 (~90s) → unknown.
    static let defaultMaxMissed: UInt32 = 3
    /// Hold the opening unknown banner until the first status, or this long.
    static let launchGraceMs: UInt64 = 15_000

    /// Localized client copy for a mixer `code`. Missing code → generic fallback.
    /// Never returns raw mixer `reason` / JSON, and never echoes an unrecognized code.
    static func localizedMessage(forCode raw: String?) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            return "generic.error.message".localized
        }

        // Real `parseMixerErrorCode` is case-sensitive — do not uppercase first.
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

    /// Visibility gate. Does not change how health is evaluated.
    /// Unknown with no status yet stays hidden until tracking has been running
    /// for `launchGraceMs`. Degraded, and unknown after any status, show at once.
    static func shouldShowBanner(
        health: ServerHealth,
        hasReceivedServerStatus: Bool,
        trackingStartedAtMs: UInt64?,
        nowMs: UInt64
    ) -> Bool {
        switch health {
        case .ok:
            return false
        case .degraded:
            return true
        case .unknown:
            if hasReceivedServerStatus {
                return true
            }
            guard let startedAt = trackingStartedAtMs else {
                return false
            }
            guard nowMs >= startedAt else {
                return false
            }
            return nowMs - startedAt >= launchGraceMs
        }
    }

    /// Banner copy for a health state. `.ok` hides the banner. Never the payload reason.
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
}
