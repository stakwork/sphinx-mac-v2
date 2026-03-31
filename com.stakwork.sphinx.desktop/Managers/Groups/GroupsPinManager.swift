//
//  GroupsPinManager.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 11/01/2021.
//  Copyright © 2021 Tomas Timinskas. All rights reserved.
//

import Foundation

class GroupsPinManager: @unchecked Sendable {

    class var sharedInstance : GroupsPinManager {
        struct Static {
            nonisolated(unsafe) static let instance = GroupsPinManager()
        }
        return Static.instance
    }

    var userData = UserData.sharedInstance

    @MainActor func shouldAskForPin() -> Bool {
        if UserData.sharedInstance.isUserLogged() {
            if userData.getPINNeverOverride() {
                return false
            }
            if let date: Date = UserDefaults.Keys.lastPinDate.get() {
                let timeSeconds = Double(UserData.sharedInstance.getPINHours() * 3600)
                if Date().timeIntervalSince(date) > timeSeconds {
                    return true
                }
            }
        }
        return UserData.sharedInstance.isSignupCompleted()
    }
    
    func isValidPin(
        _ pin: String
    ) -> Bool {
        if let mnemonic = UserData.sharedInstance.getMnemonic(enteredPin: pin), SphinxOnionManager.sharedInstance.isMnemonic(code: mnemonic) {
            SphinxOnionManager.sharedInstance.appSessionPin = pin
            return true
        }
        return false
    }
}

