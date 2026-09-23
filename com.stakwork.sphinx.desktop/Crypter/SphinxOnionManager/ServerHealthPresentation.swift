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
