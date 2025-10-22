//
//  PaddedTextField.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 22/10/2025.
//  Copyright © 2025 Tomas Timinskas. All rights reserved.
//

import Cocoa

class PaddedTextFieldCell: NSTextFieldCell {
    
    var padding = NSEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
    
    private func paddedRect(_ rect: NSRect) -> NSRect {
        return NSRect(
            x: rect.origin.x + padding.left,
            y: rect.origin.y + padding.bottom,
            width: rect.width - padding.left - padding.right,
            height: rect.height - padding.top - padding.bottom
        )
    }
    
    // This controls where the field editor (text view) appears when editing
    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: paddedRect(rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }
    
//    // This controls where selection happens
    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: paddedRect(rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }
    
    // Override drawing rect as well
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        return super.drawingRect(forBounds: paddedRect(rect))
    }

}

class PaddedTextField: CCTextField {
    
    var contentPadding = NSEdgeInsets(top: 0, left: 16, bottom: 0, right: 16) {
        didSet {
            updateCellPadding()
        }
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupPaddedCell()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupPaddedCell()
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        setupPaddedCell()
    }
    
    private func setupPaddedCell() {
        guard !(cell is PaddedTextFieldCell) else { return }
        
        let paddedCell = PaddedTextFieldCell()
        paddedCell.padding = contentPadding
        
        // Copy all properties from existing cell
        if let existingCell = cell as? NSTextFieldCell {
            paddedCell.stringValue = existingCell.stringValue
            paddedCell.font = existingCell.font
            paddedCell.alignment = existingCell.alignment
            paddedCell.textColor = existingCell.textColor
            paddedCell.backgroundColor = existingCell.backgroundColor
            paddedCell.drawsBackground = existingCell.drawsBackground
            paddedCell.isBezeled = existingCell.isBezeled
            paddedCell.isBordered = existingCell.isBordered
            paddedCell.isEditable = existingCell.isEditable
            paddedCell.isSelectable = existingCell.isSelectable
            paddedCell.bezelStyle = existingCell.bezelStyle
            paddedCell.placeholderString = existingCell.placeholderString
            paddedCell.lineBreakMode = existingCell.lineBreakMode
            paddedCell.truncatesLastVisibleLine = existingCell.truncatesLastVisibleLine
        }
        
        self.cell = paddedCell
        needsDisplay = true
    }
    
    private func updateCellPadding() {
        if let paddedCell = cell as? PaddedTextFieldCell {
            paddedCell.padding = contentPadding
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }
    
    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width += contentPadding.left + contentPadding.right
        size.height += contentPadding.top + contentPadding.bottom + 40
        return size
    }
    
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        
        guard let paddedCell = cell as? PaddedTextFieldCell else {
            super.mouseDown(with: event)
            return
        }
        
        let textRect = paddedCell.drawingRect(forBounds: bounds)
        
        // If clicking outside text area (in padding)
        if !textRect.contains(point) {
            // Make first responder first
            window?.makeFirstResponder(self)
            
            // Create adjusted event that clicks at the edge of text
            let adjustedPoint = CGPoint(
                x: point.x < textRect.minX ? textRect.minX : (point.x > textRect.maxX ? textRect.maxX : point.x),
                y: point.y < textRect.minY ? textRect.minY : (point.y > textRect.maxY ? textRect.maxY : point.y)
            )
            
            // Convert back to window coordinates
            let adjustedLocationInWindow = convert(adjustedPoint, to: nil)
            
            // Create new event with adjusted coordinates
            if let adjustedEvent = NSEvent.mouseEvent(
                with: event.type,
                location: adjustedLocationInWindow,
                modifierFlags: event.modifierFlags,
                timestamp: event.timestamp,
                windowNumber: event.windowNumber,
                context: nil,
                eventNumber: event.eventNumber,
                clickCount: event.clickCount,
                pressure: event.pressure
            ) {
                // Pass the adjusted event to super
                super.mouseDown(with: adjustedEvent)
                return
            }
        }
        
        // Normal click in text area
        super.mouseDown(with: event)
    }
}
