//
//  LinkHandlerTextField.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 03/07/2020.
//  Copyright © 2020 Tomas Timinskas. All rights reserved.
//

import Cocoa

class MessageTextField: PaddedTextField, NSTextViewDelegate {
    func textViewDidChangeSelection(_ notification: Notification) {
        if let textView = notification.object as? NSTextView {
            textView.selectedTextAttributes = [NSAttributedString.Key.backgroundColor : color]
        }
    }
    
    /// Handle link clicks in the embedded field editor.
    /// Returns true to prevent the field editor from entering edit mode
    /// (which would replace the attributed string with plain text),
    /// and opens the URL in the default browser / deep-link handler.
    func textView(
        _ textView: NSTextView,
        clickedOnLink link: Any,
        at charIndex: Int
    ) -> Bool {
        // Resign first responder so the field doesn't stay in edit mode,
        // which would clear the attributed-string formatting from the label.
        DispatchQueue.main.async {
            self.window?.makeFirstResponder(nil)
        }
        
        var resolvedURL: URL?
        if let url = link as? URL { resolvedURL = url }
        else if let str = link as? String { resolvedURL = URL(string: str) }
        guard let url = resolvedURL else { return false }

        if url.scheme == "sphinx" {
            if url.getLinkAction() == "webapp" {
                NotificationCenter.default.post(
                    name: .onWebAppLinkTapped,
                    object: nil,
                    userInfo: ["link": url.absoluteString]
                )
            } else {
                DeepLinksHandlerHelper.handleLinkQueryFrom(url: url)
            }
            return true
        }

        NSWorkspace.shared.open(url)
        return true
    }
}
