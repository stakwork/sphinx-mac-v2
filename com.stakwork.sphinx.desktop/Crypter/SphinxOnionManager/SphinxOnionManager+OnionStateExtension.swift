//
//  SphinxOnionManager+OnionStateExtension.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 07/10/2024.
//  Copyright © 2024 Tomas Timinskas. All rights reserved.
//

import Foundation
import MessagePack

extension SphinxOnionManager {
    func storeOnionStateInMemory() {
        let userDefaults = UserDefaults.standard
        let allDefaults = userDefaults.dictionaryRepresentation()
        let inMemoryMutationKeys = mutationKeys

        for (key, value) in allDefaults {
            if inMemoryMutationKeys.contains(key), let value = value as? [UInt8] {
                onionState[key] = value
            }
        }
    }
    
    func loadOnionStateAsData() -> Data {
        let state = loadOnionState()
        
        var mpDic = [MessagePackValue:MessagePackValue]()

        for (key, value) in state {
            mpDic[MessagePackValue(key)] = MessagePackValue(Data(value))
        }
        
        let stateBytes = pack(
            MessagePackValue(mpDic)
        ).bytes
        
        return Data(stateBytes)
    }
    

    func storeOnionState(inc: [UInt8]) -> [NSNumber] {
        let muts = try? unpack(Data(inc))
        
        guard let mutsDictionary = (muts?.value as? MessagePackValue)?.dictionaryValue else {
            return []
        }
        
        persist_muts(muts: mutsDictionary)

        return []
    }

    private func persist_muts(muts: [MessagePackValue: MessagePackValue]) {
        var keys: [String] = []
        
        for  mut in muts {
            if let key = mut.key.stringValue, let value = mut.value.dataValue?.bytes {
                keys.append(key)
                UserDefaults.standard.removeObject(forKey: key)
                UserDefaults.standard.synchronize()
                UserDefaults.standard.set(value, forKey: key)
                UserDefaults.standard.synchronize()
                
                onionState[key] = value
            }
        }
        
        keys.append(contentsOf: mutationKeys)
        mutationKeys = Array(Set(keys))
    }
    
    func handleStateToDelete(stateToDelete:[String]){
        for key in stateToDelete {
            UserDefaults.standard.removeObject(forKey: key)
            UserDefaults.standard.synchronize()
            
            onionState.removeValue(forKey: key)
        }
    }
    
    func loadOnionState() -> [String: [UInt8]] {
        return onionState
    }
}
