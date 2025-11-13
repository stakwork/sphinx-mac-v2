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
        delegate: SignupFieldViewDelegate
    ) {
        
        self.field = field
        self.delegate = delegate
        
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
