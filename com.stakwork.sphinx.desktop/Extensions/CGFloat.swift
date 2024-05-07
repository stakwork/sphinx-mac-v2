//
//  CGFloat.swift
//  com.stakwork.sphinx.desktop
//
//  Created by Tomas Timinskas on 25/05/2020.
//  Copyright © 2020 Sphinx. All rights reserved.
//

import Foundation

extension CGFloat {
    static func random() -> CGFloat {
        return CGFloat(arc4random()) / CGFloat(UInt32.max)
    }
}

extension Float {
    var speedDescription: String {
        get {
            if self == Float(Int(self)) {
                return "\(Int(self))"
            } else {
                return self.formattedWithDotDecimalSeparator
            }
        }
    }
}

