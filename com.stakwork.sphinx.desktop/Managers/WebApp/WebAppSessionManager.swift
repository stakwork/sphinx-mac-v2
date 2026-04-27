//
//  WebAppSessionManager.swift
//  sphinx
//
//  Created by Tomas Timinskas on 27/04/2026.
//  Copyright © 2026 Tomas Timinskas. All rights reserved.
//

import Foundation

struct WebAppSessionKey: Hashable {
    let chatId: Int
    let isAppURL: Bool
}

struct WebAppSessionEntry {
    let vc: WebAppViewController
    var timer: Timer?
}

class WebAppSessionManager: NSObject, @unchecked Sendable {

    class var sharedInstance: WebAppSessionManager {
        struct Static {
            nonisolated(unsafe) static let instance = WebAppSessionManager()
        }
        return Static.instance
    }

    private var sessions: [WebAppSessionKey: WebAppSessionEntry] = [:]

    private static let sessionTimeout: TimeInterval = 30 * 60 // 30 minutes

    /// Stores a VC, cancels any existing timer, starts a fresh 30-min eviction timer.
    @MainActor func store(_ vc: WebAppViewController, chatId: Int, isAppURL: Bool) {
        let key = WebAppSessionKey(chatId: chatId, isAppURL: isAppURL)

        // Invalidate any existing timer for this key
        sessions[key]?.timer?.invalidate()

        let timer = Timer.scheduledTimer(
            withTimeInterval: WebAppSessionManager.sessionTimeout,
            repeats: false
        ) { [weak self] _ in
            self?.evict(chatId: chatId, isAppURL: isAppURL)
        }
        RunLoop.main.add(timer, forMode: .common)

        sessions[key] = WebAppSessionEntry(vc: vc, timer: timer)
    }

    /// Returns the cached VC and resets its 30-min timer. Returns nil if not found.
    @MainActor func retrieve(chatId: Int, isAppURL: Bool) -> WebAppViewController? {
        let key = WebAppSessionKey(chatId: chatId, isAppURL: isAppURL)
        guard let entry = sessions[key] else { return nil }

        // Reset the eviction timer
        entry.timer?.invalidate()
        let timer = Timer.scheduledTimer(
            withTimeInterval: WebAppSessionManager.sessionTimeout,
            repeats: false
        ) { [weak self] _ in
            self?.evict(chatId: chatId, isAppURL: isAppURL)
        }
        RunLoop.main.add(timer, forMode: .common)

        sessions[key] = WebAppSessionEntry(vc: entry.vc, timer: timer)
        return entry.vc
    }

    /// Tears down the VC, invalidates its timer, and removes the entry.
    @MainActor func evict(chatId: Int, isAppURL: Bool) {
        let key = WebAppSessionKey(chatId: chatId, isAppURL: isAppURL)
        guard let entry = sessions[key] else { return }
        entry.timer?.invalidate()
        entry.vc.teardown()
        sessions.removeValue(forKey: key)
    }

    /// Tears down all cached sessions (call on logout / app reset).
    @MainActor func evictAll() {
        for entry in sessions.values {
            entry.timer?.invalidate()
            entry.vc.teardown()
        }
        sessions.removeAll()
    }
}
