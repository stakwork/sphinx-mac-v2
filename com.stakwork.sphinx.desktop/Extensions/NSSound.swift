//
//  NSSound.swift
//  com.stakwork.sphinx.desktop
//
//  Created by Tomas Timinskas on 14/05/2020.
//  Copyright © 2020 Sphinx. All rights reserved.
//

import Cocoa

public extension NSSound {

    #if !swift(>=4)
    private convenience init?(named name: Name) {
        self.init(named: name as String)
    }
    #endif

    @MainActor static let morse     = NSSound(named: .morse)
    @MainActor static let ping      = NSSound(named: .ping)
    @MainActor static let pop       = NSSound(named: .pop)
    @MainActor static let tink      = NSSound(named: .tink)
    @MainActor static let tock      = NSSound(named: .tock)
}



public extension NSSound.Name {

    #if !swift(>=4)
    private convenience init(_ rawValue: String) {
        self.init(string: rawValue)
    }
    #endif

    static let morse     = NSSound.Name("Morse")
    static let ping      = NSSound.Name("Ping")
    static let pop       = NSSound.Name("Pop")
    static let tink      = NSSound.Name("Tink")
    static let tock      = NSSound.Name("Tock")
}
