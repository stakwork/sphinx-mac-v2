//
//  LinkHandlerTextField.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 03/07/2020.
//  Copyright © 2020 Tomas Timinskas. All rights reserved.
//

import Cocoa

// Custom attribute key used to store a URL without triggering
// AppKit's built-in link-color override (which ignores .foregroundColor).
extension NSAttributedString.Key {
    static let sphinxURL = NSAttributedString.Key("sphinxURL")
}

class MessageTextField: PaddedTextField, NSTextViewDelegate {

    // MARK: - Attributed string interception

    /// Strip the standard `.link` attribute and replace it with our custom
    /// `.sphinxURL` key.  This prevents NSTextField / NSTextFieldCell from
    /// overriding the `.foregroundColor` that MarkdownRenderer already set.
    override var attributedStringValue: NSAttributedString {
        get { return super.attributedStringValue }
        set {
            super.attributedStringValue = MessageTextField.stripLinkAttributes(from: newValue)
        }
    }

    /// Walk every run in `attributed`, move `.link` → `.sphinxURL`, leave
    /// `.foregroundColor` and every other attribute untouched.
    private static func stripLinkAttributes(from attributed: NSAttributedString) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: attributed)
        let full = NSRange(location: 0, length: mutable.length)

        mutable.enumerateAttribute(.link, in: full, options: []) { value, range, _ in
            guard let value = value else { return }
            mutable.removeAttribute(.link, range: range)
            mutable.addAttribute(.sphinxURL, value: value, range: range)
        }
        return mutable
    }

    // MARK: - URL tap detection

    override func mouseDown(with event: NSEvent) {
        if tryHandleURLTap(event: event) { return }
        super.mouseDown(with: event)
    }

    /// Returns true and opens the URL if the click landed on a `.sphinxURL` run.
    private func tryHandleURLTap(event: NSEvent) -> Bool {
        let localPoint = convert(event.locationInWindow, from: nil)

        let attributed = attributedStringValue
        guard attributed.length > 0 else { return false }

        // Build a temporary layout stack so we can hit-test character positions
        // without relying on the field editor being active.
        let textStorage  = NSTextStorage(attributedString: attributed)
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(
            containerSize: NSSize(width: bounds.width - contentPadding.left - contentPadding.right,
                                  height: CGFloat.greatestFiniteMagnitude)
        )
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        // Offset for cell padding so coordinates align with the drawn text.
        let textOrigin = NSPoint(x: contentPadding.left, y: contentPadding.top)
        let pointInText = NSPoint(x: localPoint.x - textOrigin.x,
                                  y: localPoint.y - textOrigin.y)

        var fraction: CGFloat = 0
        let charIndex = layoutManager.characterIndex(
            for: pointInText,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: &fraction
        )

        guard charIndex < attributed.length else { return false }

        let attrs = attributed.attributes(at: charIndex, effectiveRange: nil)
        guard let urlValue = attrs[.sphinxURL] else { return false }

        var resolved: URL?
        if let url = urlValue as? URL         { resolved = url }
        else if let str = urlValue as? String { resolved = URL(string: str) }
        guard let url = resolved else { return false }

        openURL(url)
        return true
    }

    // MARK: - URL opening (shared with field-editor delegate path)

    private func openURL(_ url: URL) {
        if url.scheme == "sphinx.chat" {
            if url.getLinkAction() == "webapp" {
                NotificationCenter.default.post(
                    name: .onWebAppLinkTapped,
                    object: nil,
                    userInfo: ["link": url.absoluteString]
                )
            } else {
                DeepLinksHandlerHelper.handleLinkQueryFrom(url: url)
            }
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - NSTextViewDelegate (field-editor callbacks)

    func textViewDidChangeSelection(_ notification: Notification) {
        if let textView = notification.object as? NSTextView {
            textView.selectedTextAttributes = [NSAttributedString.Key.backgroundColor: color]
        }
    }
}
