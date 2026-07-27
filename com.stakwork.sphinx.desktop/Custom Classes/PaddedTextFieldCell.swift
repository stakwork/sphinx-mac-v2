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
    
    /// When > 0, `intrinsicContentSize.height` is clamped to this value.
    /// Set externally (e.g. from ThreadCollectionViewItem) before calling
    /// `invalidateIntrinsicContentSize()` so auto-layout uses the capped size.
    var maximumHeight: CGFloat = 0
    
    // One-entry height cache keyed on (stringValue, effectiveWidth).
    // Avoids repeated boundingRect calls within a single layout pass.
    private var _cachedHeight: CGFloat = -1
    private var _cacheText: String = ""
    private var _cacheWidth: CGFloat = 0
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        DispatchQueue.main.async {
            self.setupPaddedCell()
        }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        DispatchQueue.main.async {
            self.setupPaddedCell()
        }
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        DispatchQueue.main.async {
            self.setupPaddedCell()
        }
    }
    
    override func invalidateIntrinsicContentSize() {
        _cachedHeight = -1
        super.invalidateIntrinsicContentSize()
    }
    
    /// Internal so the unit-test target can drain the run-loop and call this
    /// directly, ensuring `PaddedTextFieldCell` is installed before measurement.
    func setupPaddedCell() {
        guard !(cell is PaddedTextFieldCell) else { return }
        
        let paddedCell = PaddedTextFieldCell()
        paddedCell.padding = contentPadding
        
        // Copy all properties from existing cell
        if let existingCell = cell as? NSTextFieldCell {
            // Must set allowsEditingTextAttributes before attributedStringValue
            // so rich text attributes (links, formatting) are preserved correctly
            paddedCell.allowsEditingTextAttributes = existingCell.allowsEditingTextAttributes
            // Copy attributed string instead of plain stringValue to preserve
            // link attributes, colors, underlines, etc.
            paddedCell.attributedStringValue = existingCell.attributedStringValue
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
        invalidateIntrinsicContentSize()
        needsLayout = true
        needsDisplay = true
    }
    
    private func updateCellPadding() {
        if let paddedCell = cell as? PaddedTextFieldCell {
            paddedCell.padding = contentPadding
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }
    
    /// Override to ensure the cell's allowsEditingTextAttributes stays in sync.
    /// This is essential for link tapping to work: when the cell is replaced by
    /// setupPaddedCell() asynchronously, we need the PaddedTextFieldCell to
    /// also reflect any later changes to this property.
    override var allowsEditingTextAttributes: Bool {
        get { return super.allowsEditingTextAttributes }
        set {
            super.allowsEditingTextAttributes = newValue
            (cell as? PaddedTextFieldCell)?.allowsEditingTextAttributes = newValue
        }
    }
    
    override var intrinsicContentSize: NSSize {
        let hPad = contentPadding.left + contentPadding.right
        let vPad = contentPadding.top  + contentPadding.bottom
        // PaddedTextFieldCell narrows the drawing rect by hPad, so measure text
        // at the actual available width; otherwise super underestimates height and
        // the bubble (NSBox) clips the last line.
        let effectiveWidth = bounds.width - hPad

        if effectiveWidth > 0 {
            let currentText = stringValue
            let height: CGFloat

            if currentText == _cacheText && effectiveWidth == _cacheWidth && _cachedHeight >= 0 {
                height = _cachedHeight
            } else {
                let attrStr = attributedStringValue
                var measured = ceil(attrStr.boundingRect(
                    with: NSSize(width: effectiveWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading]
                ).height)
                if maximumHeight > 0 {
                    measured = min(measured, maximumHeight)
                }
                _cacheText    = currentText
                _cacheWidth   = effectiveWidth
                _cachedHeight = measured
                height = measured
            }

            var size = super.intrinsicContentSize
            // NSTextField returns noIntrinsicMetric (-1) for width when wrapping.
            // Adding hPad to -1 yields ~31 pt, which auto-layout treats as a real
            // intrinsic width at hugging-priority 1000, collapsing the field.
            // Only add padding when super returns a real (non-sentinel) width.
            if size.width != NSView.noIntrinsicMetric {
                size.width += hPad
            }
            size.height = height + vPad
            return size
        }

        // Fallback when bounds aren't established yet.
        var size = super.intrinsicContentSize
        if size.width != NSView.noIntrinsicMetric {
            size.width += hPad
        }
        size.height += vPad + 40
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
