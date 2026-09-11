//
//  KeychainManager.swift
//  com.stakwork.sphinx.desktop
//
//  Created by Tomas Timinskas on 05/05/2020.
//  Copyright © 2020 Sphinx. All rights reserved.
//

import Foundation
import KeychainAccess

protocol KeychainBackingStore: Sendable {
    func get(_ key: String) throws -> String?
    func set(_ value: String, key: String) throws
    func remove(_ key: String) throws
}

/// Production adapter: get/save/delete all hit the same `.synchronizable(true)`
/// KeychainAccess item. `@unchecked Sendable` because `Keychain` is not Sendable.
struct KeychainAccessBackingStore: KeychainBackingStore, @unchecked Sendable {
    private let keychain: Keychain

    init(
        keychain: Keychain = Keychain(
            service: "sphinx-app",
            accessGroup: KeychainManager.kKeychainGroup
        ).synchronizable(true)
    ) {
        self.keychain = keychain
    }

    func get(_ key: String) throws -> String? {
        try keychain.get(key)
    }

    func set(_ value: String, key: String) throws {
        try keychain.set(value, key: key)
    }

    func remove(_ key: String) throws {
        try keychain.remove(key)
    }
}

class KeychainManager: @unchecked Sendable {
    
    class var sharedInstance : KeychainManager {
        struct Static {
            nonisolated(unsafe) static let instance = KeychainManager()
        }
        return Static.instance
    }
    
    public static let kKeychainGroup = "8297M44YTW.sphinxV2SharedItems"
    
    enum KeychainKeys : String {
        case walletMnemonic = "mac.wallet_mnemonic"
        case balance_msats = "mac.balance_msats"
        case personalGraphUrl = "mac.personal_graph_url"
        case personalGraphToken = "mac.personal_graph_token"
        case personalGraphWorkflowId = "mac.personal_graph_workflow_id"
        case personalGraphLabel = "mac.personal_graph_label"
        case aiAgentProvider = "mac.ai_agent_provider"
        case aiAgentApiKey = "mac.ai_agent_api_key"
        case strutApiKey = "mac.strut_api_key"
    }
    
    private let store: any KeychainBackingStore

    init(store: any KeychainBackingStore = KeychainAccessBackingStore()) {
        self.store = store
    }

    func getValueFor(composedKey: String) -> String? {
        do {
            let value = try store.get(composedKey)
            return value
        } catch let error {
            print(error.localizedDescription)
            return nil
        }
    }
    
    func save(value: String, forComposedKey key: String) -> Bool {
        do {
            try store.set(value, key: key)
            return true
        } catch let error {
            print(error.localizedDescription)
            return false
        }
    }
    
    func deleteValueFor(composedKey: String) -> Bool {
        do {
            try store.remove(composedKey)
            return true
        } catch let error {
            print(error.localizedDescription)
            return false
        }
    }
}
