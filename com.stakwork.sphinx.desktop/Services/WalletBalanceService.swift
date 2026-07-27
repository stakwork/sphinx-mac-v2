//
//  WalletBalanceService.swift
//  com.stakwork.sphinx.desktop
//
//  Created by Tomas Timinskas on 14/05/2020.
//  Copyright © 2020 Sphinx. All rights reserved.
//

import Cocoa

@MainActor
public final class WalletBalanceService {
    
    var balance: UInt64? {
        get {
            if let balance = UserData.sharedInstance.getBalanceSats() {
                return UInt64(balance)
            }
            return nil
        }
        set {
            if let balance = newValue {
                UserData.sharedInstance.save(balance: balance)
            }
        }
    }
    
    nonisolated init() {}
    
    func updateBalance(labels: [NSTextField]) {
        DispatchQueue.main.async {
            if let storedBalance = self.balance {
                self.updateLabels(labels: labels, balance: storedBalance.formattedWithSeparator)
            }
        }
    }
    
    func updateLabels(labels: [NSTextField], balance: String) {
        for label in labels {
            label.stringValue = balance
        }
    }
}
