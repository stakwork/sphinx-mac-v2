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
        let inMemoryMutationKeys = mutationKeys

        var hydrated: [String: [UInt8]] = [:]
        for key in inMemoryMutationKeys where !key.isEmpty {
            guard let value = decodeOnionStateValue(userDefaults.object(forKey: key)) else {
                continue
            }
            hydrated[key] = value
        }

        onionStateQueue.sync {
            for (key, value) in hydrated {
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

        let stateBytes = [UInt8](pack(MessagePackValue(mpDic)))
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
            if let key = mut.key.stringValue, let data = mut.value.dataValue {
                let value = [UInt8](data)
                keys.append(key)
                UserDefaults.standard.set(value, forKey: key)

                onionStateQueue.sync { onionState[key] = value }
            }
        }

        keys.append(contentsOf: mutationKeys)
        mutationKeys = Array(Set(keys))
    }

    ///The core drops a chunk buffer `kChunkBufferTimeoutSeconds` after its first fragment
    ///(`CHUNK_TIMEOUT_SECS` in sphinx-ffi `chunk.rs`), together with the fragment that finds it
    ///stale. Removing stale buffers before a catch-up lets fragments fetched again start afresh.
    static let kChunkBufferPrefix = "chunkbuf_"
    static let kChunkBufferTimeoutSeconds: UInt64 = 300

    static func timedOutChunkBufferKeys(
        state: [String: [UInt8]],
        now: UInt64
    ) -> [String] {
        return state.compactMap { (key, value) in
            guard key.hasPrefix(kChunkBufferPrefix) else {
                return nil
            }
            guard let buffer = (try? JSONSerialization.jsonObject(with: Data(value))) as? [String: Any],
                  let firstReceived = (buffer["first_received_ts"] as? NSNumber)?.uint64Value else {
                return key
            }
            return now > firstReceived && now - firstReceived > kChunkBufferTimeoutSeconds ? key : nil
        }
    }

    func purgeTimedOutChunkBuffers() {
        let keys = SphinxOnionManager.timedOutChunkBufferKeys(
            state: loadOnionState(),
            now: UInt64(Date().timeIntervalSince1970)
        )
        if !keys.isEmpty {
            print("[chunk] purging \(keys.count) timed out chunk buffers")
            handleStateToDelete(stateToDelete: keys)
        }
    }

    func handleStateToDelete(stateToDelete:[String]){
        for key in stateToDelete {
            UserDefaults.standard.removeObject(forKey: key)

            onionStateQueue.sync { onionState.removeValue(forKey: key) }
        }
    }

    func loadOnionState() -> [String: [UInt8]] {
        return onionStateQueue.sync { onionState }
    }

    /// UserDefaults typically returns `NSArray`/`NSNumber` (or `Data`) for values
    /// stored as `[UInt8]`, so hydrate must accept those representations.
    private func decodeOnionStateValue(_ raw: Any?) -> [UInt8]? {
        guard let raw else { return nil }

        if let data = raw as? Data {
            return [UInt8](data)
        }

        if let bytes = raw as? [UInt8] {
            return bytes
        }

        if let ints = raw as? [Int] {
            guard ints.allSatisfy({ (0...255).contains($0) }) else { return nil }
            return ints.map { UInt8($0) }
        }

        if let numbers = raw as? [NSNumber] {
            return numbers.map { UInt8(truncating: $0) }
        }

        if let array = raw as? NSArray {
            var bytes: [UInt8] = []
            bytes.reserveCapacity(array.count)
            for item in array {
                if let number = item as? NSNumber {
                    bytes.append(UInt8(truncating: number))
                } else if let int = item as? Int, (0...255).contains(int) {
                    bytes.append(UInt8(int))
                } else if let uint8 = item as? UInt8 {
                    bytes.append(uint8)
                } else {
                    return nil
                }
            }
            return bytes
        }

        return nil
    }
}
