import AppKit

// MARK: - MarkdownStyle

struct MarkdownStyle {
    var textColor: NSColor = NSColor.Sphinx.Text
    var linkColor: NSColor = NSColor.Sphinx.PrimaryBlue
    var secondaryColor: NSColor = NSColor.Sphinx.SecondaryText
    var baseFontSize: CGFloat = 15
}

// MARK: - MarkdownRenderer

final class MarkdownRenderer {
    let style: MarkdownStyle

    init(style: MarkdownStyle = MarkdownStyle()) {
        self.style = style
    }

    // MARK: - Public API

    func render(_ text: String) -> NSAttributedString {
        let lines = text.components(separatedBy: "\n")
        let result = NSMutableAttributedString()

        for (index, line) in lines.enumerated() {
            let lineAttr = renderLine(line)
            result.append(lineAttr)
            if index < lines.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: baseAttributes()))
            }
        }
        return result
    }

    // MARK: - Line rendering

    private func renderLine(_ line: String) -> NSAttributedString {
        // Headings
        if line.hasPrefix("### ") {
            return renderInline(String(line.dropFirst(4)), font: boldFont(size: style.baseFontSize + 2))
        } else if line.hasPrefix("## ") {
            return renderInline(String(line.dropFirst(3)), font: boldFont(size: style.baseFontSize + 4))
        } else if line.hasPrefix("# ") {
            return renderInline(String(line.dropFirst(2)), font: boldFont(size: style.baseFontSize + 6))
        }

        // Unordered list
        if line.hasPrefix("- ") || line.hasPrefix("* ") {
            let inner = "• " + String(line.dropFirst(2))
            return renderInline(inner, font: regularFont(size: style.baseFontSize))
        }

        // Code block line (indented or fenced — treat as monospace)
        if line.hasPrefix("    ") || line.hasPrefix("\t") {
            return renderInline(line, font: monoFont(size: style.baseFontSize))
        }

        return renderInline(line, font: regularFont(size: style.baseFontSize))
    }

    // MARK: - Inline rendering (bold, italic, code, links)

    func renderInline(_ text: String, font: NSFont) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var remaining = text

        while !remaining.isEmpty {
            // Bold-italic ***text***
            if let range = remaining.range(of: "***"),
               let endRange = remaining.range(of: "***", range: remaining.index(range.upperBound, offsetBy: 0)..<remaining.endIndex) {
                let before = String(remaining[remaining.startIndex..<range.lowerBound])
                if !before.isEmpty {
                    result.append(NSAttributedString(string: before, attributes: makeAttributes(font: font)))
                }
                let inner = String(remaining[range.upperBound..<endRange.lowerBound])
                let boldItalicF = boldItalicFont(size: font.pointSize)
                result.append(NSAttributedString(string: inner, attributes: makeAttributes(font: boldItalicF)))
                remaining = String(remaining[endRange.upperBound...])
                continue
            }

            // Bold **text**
            if let range = remaining.range(of: "**"),
               let endRange = remaining.range(of: "**", range: remaining.index(range.upperBound, offsetBy: 0)..<remaining.endIndex) {
                let before = String(remaining[remaining.startIndex..<range.lowerBound])
                if !before.isEmpty {
                    result.append(NSAttributedString(string: before, attributes: makeAttributes(font: font)))
                }
                let inner = String(remaining[range.upperBound..<endRange.lowerBound])
                let boldF = boldFont(size: font.pointSize)
                result.append(NSAttributedString(string: inner, attributes: makeAttributes(font: boldF)))
                remaining = String(remaining[endRange.upperBound...])
                continue
            }

            // Italic *text* or _text_
            if let (markerLen, range, endRange) = findItalicRange(in: remaining) {
                let before = String(remaining[remaining.startIndex..<range.lowerBound])
                if !before.isEmpty {
                    result.append(NSAttributedString(string: before, attributes: makeAttributes(font: font)))
                }
                let inner = String(remaining[range.upperBound..<endRange.lowerBound])
                let italicF = italicFont(size: font.pointSize)
                result.append(NSAttributedString(string: inner, attributes: makeAttributes(font: italicF)))
                let afterIndex = remaining.index(endRange.lowerBound, offsetBy: markerLen)
                remaining = String(remaining[afterIndex...])
                continue
            }

            // Inline code `text`
            if let range = remaining.range(of: "`"),
               let endRange = remaining.range(of: "`", range: remaining.index(range.upperBound, offsetBy: 0)..<remaining.endIndex) {
                let before = String(remaining[remaining.startIndex..<range.lowerBound])
                if !before.isEmpty {
                    result.append(NSAttributedString(string: before, attributes: makeAttributes(font: font)))
                }
                let inner = String(remaining[range.upperBound..<endRange.lowerBound])
                var codeAttrs = makeAttributes(font: monoFont(size: font.pointSize))
                codeAttrs[.foregroundColor] = style.secondaryColor
                result.append(NSAttributedString(string: inner, attributes: codeAttrs))
                remaining = String(remaining[endRange.upperBound...])
                continue
            }

            // Link [label](url)
            if let linkResult = parseLinkAtStart(in: remaining) {
                let before = String(remaining[remaining.startIndex..<linkResult.fullRange.lowerBound])
                if !before.isEmpty {
                    result.append(NSAttributedString(string: before, attributes: makeAttributes(font: font)))
                }
                var linkAttrs = makeAttributes(font: font)
                if let url = URL(string: linkResult.url) {
                    linkAttrs[.link] = url
                    linkAttrs[.foregroundColor] = style.linkColor
                    linkAttrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                }
                result.append(NSAttributedString(string: linkResult.label, attributes: linkAttrs))
                remaining = String(remaining[linkResult.fullRange.upperBound...])
                continue
            }

            // Plain text — consume until next potential marker
            let specialChars: [Character] = ["*", "_", "`", "["]
            if let idx = remaining.firstIndex(where: { specialChars.contains($0) }) {
                let before = String(remaining[remaining.startIndex..<idx])
                if !before.isEmpty {
                    result.append(NSAttributedString(string: before, attributes: makeAttributes(font: font)))
                }
                remaining = String(remaining[idx...])

                // Peek ahead — if no closing marker found, emit the char as plain text
                let marker = String(remaining.prefix(1))
                if !canFindClosingMarker(for: marker, in: String(remaining.dropFirst())) {
                    result.append(NSAttributedString(string: marker, attributes: makeAttributes(font: font)))
                    remaining = String(remaining.dropFirst())
                }
            } else {
                result.append(NSAttributedString(string: remaining, attributes: makeAttributes(font: font)))
                remaining = ""
            }
        }

        return result
    }

    // MARK: - Helpers

    private func findItalicRange(in text: String) -> (markerLen: Int, range: Range<String.Index>, endRange: Range<String.Index>)? {
        // Try *...*
        if let range = text.range(of: "*"),
           let endRange = text.range(of: "*", range: text.index(range.upperBound, offsetBy: 0)..<text.endIndex) {
            // Make sure it's not ** (bold)
            let nextChar = text[range.upperBound]
            if nextChar != Character("*") {
                return (1, range, endRange)
            }
        }
        // Try _..._
        if let range = text.range(of: "_"),
           let endRange = text.range(of: "_", range: text.index(range.upperBound, offsetBy: 0)..<text.endIndex) {
            return (1, range, endRange)
        }
        return nil
    }

    private func canFindClosingMarker(for marker: String, in text: String) -> Bool {
        return text.contains(marker)
    }

    private struct LinkParseResult {
        let label: String
        let url: String
        let fullRange: Range<String.Index>
    }

    private func parseLinkAtStart(in text: String) -> LinkParseResult? {
        // Find [ ... ]( ... ) anywhere in remaining — must appear at a non-excluded position
        guard let bracketOpen = text.range(of: "["),
              let bracketClose = text.range(of: "]", range: bracketOpen.upperBound..<text.endIndex) else {
            return nil
        }
        // After ] must be (
        let afterBracketClose = bracketClose.upperBound
        guard afterBracketClose < text.endIndex, text[afterBracketClose] == "(" else {
            return nil
        }
        let parenOpenIdx = afterBracketClose
        let parenStart = text.index(parenOpenIdx, offsetBy: 1)
        guard let parenClose = text.range(of: ")", range: parenStart..<text.endIndex) else {
            return nil
        }
        let label = String(text[bracketOpen.upperBound..<bracketClose.lowerBound])
        let url = String(text[parenStart..<parenClose.lowerBound])
        let fullRange = bracketOpen.lowerBound..<parenClose.upperBound
        return LinkParseResult(label: label, url: url, fullRange: fullRange)
    }

    // MARK: - Attribute factories

    private func baseAttributes() -> [NSAttributedString.Key: Any] {
        return makeAttributes(font: regularFont(size: style.baseFontSize))
    }

    private func makeAttributes(font: NSFont) -> [NSAttributedString.Key: Any] {
        return [
            .font: font,
            .foregroundColor: style.textColor
        ]
    }

    // MARK: - Font helpers

    private func regularFont(size: CGFloat) -> NSFont {
        return NSFont.systemFont(ofSize: size)
    }

    private func boldFont(size: CGFloat) -> NSFont {
        return NSFont.boldSystemFont(ofSize: size)
    }

    private func italicFont(size: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: size)
        return NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
    }

    private func boldItalicFont(size: CGFloat) -> NSFont {
        let base = NSFont.boldSystemFont(ofSize: size)
        return NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
    }

    private func monoFont(size: CGFloat) -> NSFont {
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
}
