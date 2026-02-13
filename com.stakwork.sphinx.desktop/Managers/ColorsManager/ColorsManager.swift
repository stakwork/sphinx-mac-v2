//
//  ColorsManager.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 07/10/2024.
//  Copyright © 2024 Tomas Timinskas. All rights reserved.
//

import Foundation

class ColorsManager : NSObject {
    
    class var sharedInstance : ColorsManager {
        struct Static {
            static let instance = ColorsManager()
        }
        return Static.instance
    }
    
    var colors: [String: String] = [:]
    
    func storeColorsInMemory() {
        let userDefaults = UserDefaults.standard
        let allDefaults = userDefaults.dictionaryRepresentation()

        for (key, value) in allDefaults {
            if key.contains("-color"), let value = value as? String {
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
    }
    
    func removeColorFor(key: String) {
        colors.removeValue(forKey: key)
    }

    func getAllColors() -> [String: String] {
        return colors
    }

    func setColorFor(colorHex: String, key: String) {
        colors[key] = colorHex
        UserDefaults.standard.set(colorHex, forKey: key)
        UserDefaults.standard.synchronize()
    }
}
