//
//  NSViewWithTag.swift
//  com.stakwork.sphinx.desktop
//
//  Created by Tomas Timinskas on 13/05/2020.
//  Copyright © 2020 Sphinx. All rights reserved.
//

import Cocoa

class NSViewWithTag: NSView {
    
    @IBInspectable
    var viewTag: Int = -1
    
    /// When true, the view (and its subviews) is purely visual and lets mouse
    /// events pass through to whatever is underneath it.
    var ignoresMouseEvents: Bool = false

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        if ignoresMouseEvents {
            return nil
        }
        return super.hitTest(point)
    }
}
