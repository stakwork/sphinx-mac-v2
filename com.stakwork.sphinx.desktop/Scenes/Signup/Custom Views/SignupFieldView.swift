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
        validationType: ValidationType? = nil,
        delegate: SignupFieldViewDelegate
    ) {
        
        self.field = field
        self.delegate = delegate
        
        self.validationType = validationType
        
        fieldBox.fillColor = backgroundColor
        
        topLabel.stringValue = label
        topLabel.alphaValue = 0.0
        
        textField.setPlaceHolder(color: placeHolderColor, font: NSFont(name: "Roboto-Regular", size: 14.0)!, string: placeHolder)
        textField.color = textColor
        textField.textColor = textColor
        textField.delegate = self
        
        textField.stringValue = value ?? ""
        topLabel.alphaValue = textField.stringValue.isEmpty ? 0.0 : 1.0
        
        textField.onFocusChange = { active in
            super.toggleActiveState(active)
        }
    }
}

extension SignupFieldView {
    override func controlTextDidChange(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField else { return }
                
        let text = textField.stringValue
        let corrected = correctText(text)
        
        if text != corrected {
            textField.stringValue = corrected
        }
        
        topLabel.alphaValue = textField.stringValue.isEmpty ? 0.0 : 1.0
        self.delegate?.didChangeText?(text: textField.stringValue)
    }
    
    private func correctText(_ text: String) -> String {
        if let validationType = validationType {
            switch validationType {
            case .alphanumericWithSpaces(let maxLength):
                var filtered = text.filter { $0.isLetter || $0.isNumber || $0 == " " }
                if filtered.count > maxLength {
                    filtered = String(filtered.prefix(maxLength))
                }
                return filtered
                
            case .alphanumericOnly:
                return text.filter { $0.isLetter || $0.isNumber }
                
            case .url:
                return cleanURL(text)
            }
        }
        return text
    }
    
    private func cleanURL(_ text: String) -> String {
        // Step 1: Keep only valid URL characters
        let allowedChars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.:/-")
        var cleaned = text.filter { char in
            String(char).rangeOfCharacter(from: allowedChars) != nil
        }
        
        // Step 2: Remove port (anything like :8080, :3000, etc.)
        // But keep : in http:// and https://
        if cleaned.contains("://") {
            // Find where the protocol ends
            if let protocolRange = cleaned.range(of: "://") {
                let scheme = String(cleaned[..<protocolRange.upperBound])  // "http://"
                var rest = String(cleaned[protocolRange.upperBound...])     // "localhost:8080/path"
                
                // Remove port from the rest
                // Port is : followed by digits
                if let colonIndex = rest.firstIndex(of: ":") {
                    // Get everything after the colon
                    let afterColon = String(rest[rest.index(after: colonIndex)...])
                    
                    // Find where digits end (either at / or end of string)
                    var portEnd = afterColon.startIndex
                    for char in afterColon {
                        if char.isNumber {
                            portEnd = afterColon.index(after: portEnd)
                        } else {
                            break
                        }
                    }
                    
                    // If we found digits after colon, it's a port - remove it
                    if portEnd > afterColon.startIndex {
                        let beforeColon = String(rest[..<colonIndex])
                        let afterPort = String(afterColon[portEnd...])
                        rest = beforeColon + afterPort
                    }
                }
                
                cleaned = scheme + rest
            }
        }
        
        return cleaned
    }
    
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if (commandSelector == #selector(NSResponder.insertTab(_:))) {
            self.delegate?.didUseTab?(field: field)
            return true
        }
        return false
    }
}
