//
//  KeychainManager.swift
//  com.stakwork.sphinx.desktop
//
//  Created by Tomas Timinskas on 05/05/2020.
//  Copyright © 2020 Sphinx. All rights reserved.
//

import Foundation
import KeychainAccess

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
        case aiAgentSearchApiKey = "mac.ai_agent_search_api_key"
    }
    
    let keychain = Keychain(service: "sphinx-app", accessGroup: KeychainManager.kKeychainGroup).synchronizable(true)
    let deleteKeychain = Keychain(service: "sphinx-app", accessGroup: KeychainManager.kKeychainGroup).synchronizable(false)

    
    func getValueFor(composedKey: String) -> String? {
        do {
            let value = try keychain.get(composedKey)
            return value
        } catch let error {
            print(error.localizedDescription)
            return nil
        }
    }
    
    func save(value: String, forComposedKey key: String) -> Bool {
        do {
            try keychain.set(value, key: key)
            return true
        } catch let error {
            print(error.localizedDescription)
            return false
        }
    }
    
    func deleteValueFor(composedKey: String) -> Bool {
        do {
            try deleteKeychain.remove(composedKey)
            return true
        } catch let error {
            print(error.localizedDescription)
            return false
        }
    }
}
