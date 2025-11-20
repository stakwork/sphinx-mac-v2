//
//  SignupFieldView.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 10/02/2021.
//  Copyright © 2021 Tomas Timinskas. All rights reserved.
//

import Cocoa

class SignupFieldView: SignupCommonFieldView {
    
    func configureWith(
        placeHolder: String,
        placeHolderColor: NSColor = NSColor.Sphinx.MainBottomIcons,
        label: String,
        textColor: NSColor = NSColor(hex: "#3C3F41"),
        backgroundColor: NSColor,
        field: Int,
        value: String? = nil,
        onlyNumbers: Bool = false,
        maxChars: Int? = nil,
        delegate: SignupFieldViewDelegate
    ) {
        
        self.field = field
        self.delegate = delegate
        self.maxCharsAllowed = maxChars
        
        fieldBox.fillColor = backgroundColor
        
        topLabel.stringValue = label
        topLabel.alphaValue = 0.0
        
        textField.setPlaceHolder(color: placeHolderColor, font: NSFont(name: "Roboto-Regular", size: 14.0)!, string: placeHolder)
        textField.color = textColor
        textField.textColor = textColor
        textField.delegate = self
        
        textField.stringValue = value ?? ""
        topLabel.alphaValue = textField.stringValue.isEmpty ? 0.0 : 1.0
        
        if onlyNumbers {
            let formatter = NumberFormatter()
            formatter.numberStyle = .none
            formatter.allowsFloats = false
            formatter.minimum = 0
            formatter.maximum = 999999
            
            textField.formatter = formatter
        }
        
        textField.onFocusChange = { active in
            super.toggleActiveState(active)
        }
    }
}

extension SignupFieldView {
    override func controlTextDidChange(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField else { return }
                
        var text = textField.stringValue
        
        if let maxCharsAllowed = maxCharsAllowed {
            text = text.filter { $0.isLetter || $0.isNumber || $0 == " " }
            
            if text.count > maxCharsAllowed {
                text = String(text.prefix(maxCharsAllowed))
            }
            
            if textField.stringValue != text {
                textField.stringValue = text
            }
        }
        
        topLabel.alphaValue = textField.stringValue.isEmpty ? 0.0 : 1.0
        self.delegate?.didChangeText?(text: textField.stringValue)
    }
    
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if (commandSelector == #selector(NSResponder.insertTab(_:))) {
            self.delegate?.didUseTab?(field: field)
            return true
        }
        return false
    }
}
