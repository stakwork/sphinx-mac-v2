import AppKit

// MARK: - MarkdownStyle

struct MarkdownStyle {
    var textColor: NSColor = NSColor.Sphinx.Text
    var linkColor: NSColor = NSColor.Sphinx.PrimaryBlue
    var secondaryColor: NSColor = NSColor.Sphinx.SecondaryText
    var baseFontSize: CGFloat = 15
    /// Optional base font. When set, attributed-string runs are derived from this font
    /// instead of NSFont.systemFont, so label.font and the rendered runs share the
    /// same family — eliminating AppKit's selection-redraw font mismatch.
    var baseFont: NSFont? = nil
}

// MARK: - MarkdownRenderer

final class MarkdownRenderer {
    let style: MarkdownStyle

    init(style: MarkdownStyle = MarkdownStyle()) {
        self.style = style
    }

    // MARK: - Public API — returns SwiftUI AttributedString

    func render(_ text: String) -> AttributedString {
        let ns = renderNS(text)
        return (try? AttributedString(ns, including: \.appKit)) ?? AttributedString(text)
    }

    // MARK: - Internal — NSAttributedString

    func renderNS(_ text: String) -> NSAttributedString {
        let lines = text.components(separatedBy: "\n")
        let result = NSMutableAttributedString()

        for (index, line) in lines.enumerated() {
            result.append(renderLine(line))
            if index < lines.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: baseAttributes()))
            }
        }
        return result
    }

    // MARK: - Line rendering

    private func renderLine(_ line: String) -> NSAttributedString {
        if line.hasPrefix("### ") {
            return renderInline(String(line.dropFirst(4)), font: boldFont(size: style.baseFontSize + 2))
        } else if line.hasPrefix("## ") {
            return renderInline(String(line.dropFirst(3)), font: boldFont(size: style.baseFontSize + 4))
        } else if line.hasPrefix("# ") {
            return renderInline(String(line.dropFirst(2)), font: boldFont(size: style.baseFontSize + 6))
        }
        if line.hasPrefix("- ") || line.hasPrefix("* ") {
            return renderInline("• " + String(line.dropFirst(2)), font: regularFont(size: style.baseFontSize))
        }
        if line.hasPrefix("    ") || line.hasPrefix("\t") {
            return renderInline(line, font: monoFont(size: style.baseFontSize))
        }
        return renderInline(line, font: regularFont(size: style.baseFontSize))
    }

    // MARK: - Inline rendering

    func renderInline(_ text: String, font: NSFont) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var remaining = text

        while !remaining.isEmpty {
            // Bold-italic ***text***
            if let (before, inner, after) = extractSpan(marker: "***", from: remaining) {
                if !before.isEmpty { result.append(plain(before, font: font)) }
                result.append(plain(inner, font: boldItalicFont(size: font.pointSize)))
                remaining = after
                continue
            }
            // Bold **text**
            if let (before, inner, after) = extractSpan(marker: "**", from: remaining) {
                if !before.isEmpty { result.append(plain(before, font: font)) }
                result.append(plain(inner, font: boldFont(size: font.pointSize)))
                remaining = after
                continue
            }
            // Italic *text*
            if let (before, inner, after) = extractItalicSpan(marker: "*", from: remaining) {
                if !before.isEmpty { result.append(plain(before, font: font)) }
                result.append(plain(inner, font: italicFont(size: font.pointSize)))
                remaining = after
                continue
            }
            // Italic _text_
            if let (before, inner, after) = extractSpan(marker: "_", from: remaining) {
                if !before.isEmpty { result.append(plain(before, font: font)) }
                result.append(plain(inner, font: italicFont(size: font.pointSize)))
                remaining = after
                continue
            }
            // Inline code `text`
            if let (before, inner, after) = extractSpan(marker: "`", from: remaining) {
                if !before.isEmpty { result.append(plain(before, font: font)) }
                let codeAttr = NSAttributedString(string: inner, attributes: [
                    .font: monoFont(size: font.pointSize),
                    .foregroundColor: style.secondaryColor
                ])
                result.append(codeAttr)
                remaining = after
                continue
            }
            // Link [label](url)
            if let link = parseLink(from: remaining) {
                let before = String(remaining[remaining.startIndex..<link.fullRange.lowerBound])
                if !before.isEmpty { result.append(plain(before, font: font)) }
                var attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: style.linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ]
                if let url = URL(string: link.url) {
                    attrs[.link] = url
                }
                result.append(NSAttributedString(string: link.label, attributes: attrs))
                remaining = String(remaining[link.fullRange.upperBound...])
                continue
            }
            // Plain text
            result.append(plain(remaining, font: font))
            remaining = ""
        }
        return result
    }

    // MARK: - Span extraction helpers

    /// Extracts content between exact marker occurrences: marker...marker
    private func extractSpan(marker: String, from text: String) -> (before: String, inner: String, after: String)? {
        guard let open = text.range(of: marker) else { return nil }
        let searchStart = open.upperBound
        guard searchStart < text.endIndex,
              let close = text.range(of: marker, range: searchStart..<text.endIndex),
              open.lowerBound != close.lowerBound else { return nil }
        let before = String(text[text.startIndex..<open.lowerBound])
        let inner  = String(text[open.upperBound..<close.lowerBound])
        let after  = String(text[close.upperBound...])
        return (before, inner, after)
    }

    /// Like extractSpan for `*` but ensures it's not `**`
    private func extractItalicSpan(marker: String, from text: String) -> (before: String, inner: String, after: String)? {
        var searchFrom = text.startIndex
        while let open = text.range(of: marker, range: searchFrom..<text.endIndex) {
            // Skip ** (bold marker)
            let nextIdx = open.upperBound
            if nextIdx < text.endIndex && text[nextIdx] == Character(marker) {
                searchFrom = nextIdx
                continue
            }
            guard let close = text.range(of: marker, range: nextIdx..<text.endIndex) else { return nil }
            // Ensure closing * isn't part of **
            let afterClose = close.upperBound
            if afterClose < text.endIndex && text[afterClose] == Character(marker) {
                searchFrom = afterClose
                continue
            }
            let before = String(text[text.startIndex..<open.lowerBound])
            let inner  = String(text[open.upperBound..<close.lowerBound])
            let after  = String(text[close.upperBound...])
            return (before, inner, after)
        }
        return nil
    }

    private struct LinkMatch {
        let label: String
        let url: String
        let fullRange: Range<String.Index>
    }

    private func parseLink(from text: String) -> LinkMatch? {
        guard let bracketOpen  = text.range(of: "["),
              let bracketClose = text.range(of: "]", range: bracketOpen.upperBound..<text.endIndex) else { return nil }
        let afterClose = bracketClose.upperBound
        guard afterClose < text.endIndex, text[afterClose] == "(" else { return nil }
        let parenStart = text.index(afterClose, offsetBy: 1)
        guard let parenClose = text.range(of: ")", range: parenStart..<text.endIndex) else { return nil }
        let label = String(text[bracketOpen.upperBound..<bracketClose.lowerBound])
        let url   = String(text[parenStart..<parenClose.lowerBound])
        return LinkMatch(label: label, url: url, fullRange: bracketOpen.lowerBound..<parenClose.upperBound)
    }

    // MARK: - Attribute / Font helpers

    private func baseAttributes() -> [NSAttributedString.Key: Any] {
        [.font: regularFont(size: style.baseFontSize), .foregroundColor: style.textColor]
    }

    private func plain(_ string: String, font: NSFont) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: style.textColor])
    }

    private func regularFont(size: CGFloat) -> NSFont {
        guard let base = style.baseFont else { return NSFont.systemFont(ofSize: size) }
        return size == base.pointSize ? base : NSFontManager.shared.convert(base, toSize: size)
    }
    private func boldFont(size: CGFloat) -> NSFont {
        let base = regularFont(size: size)
        return NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask)
    }
    private func italicFont(size: CGFloat) -> NSFont {
        let base = regularFont(size: size)
        return NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
    }
    private func boldItalicFont(size: CGFloat) -> NSFont {
        let base = boldFont(size: size)
        return NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
    }
    private func monoFont(size: CGFloat) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
}
