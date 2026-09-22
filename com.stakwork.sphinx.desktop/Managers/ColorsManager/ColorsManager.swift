//
//  ColorsManager.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 07/10/2024.
//  Copyright © 2024 Tomas Timinskas. All rights reserved.
//

import Foundation

class ColorsManager : NSObject, @unchecked Sendable {
    
    class var sharedInstance : ColorsManager {
        struct Static {
            static let instance = ColorsManager()
        }
        return Static.instance
    }
    
    var colors: [String: String] = [:]
    
    func storeColorsInMemory() {
        let keys = UserDefaults.Keys.chatColorKeys.get(defaultValue: [String]())
        guard !keys.isEmpty else { return }

        let userDefaults = UserDefaults.standard
        for key in keys {
            if let value = userDefaults.string(forKey: key) {
                colors[key] = value
            }
        }
    }

    func getColorFor(key: String) -> String? {
        if colors.keys.contains(key) {
            return colors[key]
        }
        return nil
    }

    func saveColorFor(colorHex: String, key: String) {
        colors[key] = colorHex
        rememberColorKey(key)
    }

    func removeColorFor(key: String) {
        colors.removeValue(forKey: key)
        forgetColorKey(key)
    }

    func getAllColors() -> [String: String] {
        return colors
    }

    func setColorFor(colorHex: String, key: String) {
        colors[key] = colorHex
        UserDefaults.standard.set(colorHex, forKey: key)
        rememberColorKey(key)
    }

    private func rememberColorKey(_ key: String) {
        var keys = UserDefaults.Keys.chatColorKeys.get(defaultValue: [String]())
        if !keys.contains(key) {
            keys.append(key)
            UserDefaults.Keys.chatColorKeys.set(keys)
        }
    }

    private func forgetColorKey(_ key: String) {
        var keys = UserDefaults.Keys.chatColorKeys.get(defaultValue: [String]())
        if let index = keys.firstIndex(of: key) {
            keys.remove(at: index)
            UserDefaults.Keys.chatColorKeys.set(keys)
        }
    }
}
