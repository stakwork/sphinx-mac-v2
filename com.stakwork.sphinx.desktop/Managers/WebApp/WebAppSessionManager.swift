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
}

class WebAppSessionManager: NSObject, @unchecked Sendable {

    class var sharedInstance: WebAppSessionManager {
        struct Static {
            nonisolated(unsafe) static let instance = WebAppSessionManager()
        }
        return Static.instance
    }

    private var sessions: [WebAppSessionKey: WebAppSessionEntry] = [:]
    private var webAppVisible: [Int: Bool] = [:] // keyed by chatId

    /// Stores a VC with no expiry — sessions live indefinitely until explicitly evicted.
    @MainActor func store(_ vc: WebAppViewController, chatId: Int, isAppURL: Bool) {
        let key = WebAppSessionKey(chatId: chatId, isAppURL: isAppURL)
        sessions[key] = WebAppSessionEntry(vc: vc)
    }

    /// Returns the cached VC. Returns nil if not found.
    @MainActor func retrieve(chatId: Int, isAppURL: Bool) -> WebAppViewController? {
        let key = WebAppSessionKey(chatId: chatId, isAppURL: isAppURL)
        guard let entry = sessions[key] else { return nil }
        sessions[key] = WebAppSessionEntry(vc: entry.vc)
        return entry.vc
    }

    /// Tears down the VC and removes the entry.
    @MainActor func evict(chatId: Int, isAppURL: Bool) {
        let key = WebAppSessionKey(chatId: chatId, isAppURL: isAppURL)
        guard let entry = sessions[key] else { return }
        entry.vc.teardown()
        sessions.removeValue(forKey: key)
        webAppVisible.removeValue(forKey: chatId)
    }

    /// Tears down all cached sessions (call on logout / app reset).
    @MainActor func evictAll() {
        for entry in sessions.values {
            entry.vc.teardown()
        }
        sessions.removeAll()
        webAppVisible.removeAll()
    }

    @MainActor func setVisible(_ visible: Bool, chatId: Int) {
        webAppVisible[chatId] = visible
    }

    @MainActor func isVisible(chatId: Int) -> Bool {
        return webAppVisible[chatId] ?? false
    }
}
