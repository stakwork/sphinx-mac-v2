import AppKit

// MARK: - MarkdownStyle

struct MarkdownStyle {
    var textColor: NSColor       = .Sphinx.Text
    var secondaryColor: NSColor  = .Sphinx.SecondaryText
    var codeBackground: NSColor  = NSColor(red: 0, green: 0, blue: 0, alpha: 0.25)
    var codeForeground: NSColor  = NSColor.Sphinx.Text.withAlphaComponent(0.75)
    var linkColor: NSColor       = .Sphinx.PrimaryBlue
    var mentionColor: NSColor    = .Sphinx.PrimaryBlue
    var quoteColor: NSColor      = .Sphinx.SecondaryText
    var quoteBarColor: NSColor   = .Sphinx.LightDivider

    var baseFont: NSFont { Constants.kMessageFont }
    var boldFont: NSFont { Constants.kMessageBoldFont }
    var italicFont: NSFont {
        let desc = Constants.kMessageFont.fontDescriptor.withSymbolicTraits(.italic)
        return NSFont(descriptor: desc, size: Constants.kMessageFont.pointSize) ?? Constants.kMessageFont
    }
    var boldItalicFont: NSFont {
        let desc = Constants.kMessageFont.fontDescriptor.withSymbolicTraits([.italic, .bold])
        return NSFont(descriptor: desc, size: Constants.kMessageFont.pointSize) ?? Constants.kMessageBoldFont
    }
    var codeFont: NSFont {
        let size = Constants.kMessageFont.pointSize - 2
        return NSFont(name: "Menlo-Regular", size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    func headingFont(level: Int) -> NSFont {
        let base = Constants.kMessageFont.pointSize
        let offsets: [CGFloat] = [7, 5, 3, 1, 0, 0]
        let size = base + offsets[max(0, min(level - 1, 5))]
        return NSFont(name: "Roboto-Black", size: size) ?? NSFont.boldSystemFont(ofSize: size)
    }
}

final class MarkdownRenderer {

    let style: MarkdownStyle

    init(style: MarkdownStyle = MarkdownStyle()) {
        self.style = style
    }

    // MARK: - Public Entry Point

    func render(_ raw: String) -> NSAttributedString {
        let preprocessed = preprocess(raw)
        let lines = preprocessed.components(separatedBy: "\n")
        let result = NSMutableAttributedString()
        var i = 0

        while i < lines.count {
            let line = lines[i]

            // Fenced code block (optional language identifier after ```, handles indented fences)
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.hasPrefix("```") {
                // Strip optional language identifier (e.g. ```ts → ignore "ts")
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                i += 1 // skip closing ```
                let codeText = codeLines.joined(separator: "\n")
                result.append(renderCodeBlock(codeText))
                result.append(newline())
                continue
            }

            // Blockquote
            if line.hasPrefix("> ") || line == ">" {
                var quoteLines: [String] = []
                while i < lines.count && (lines[i].hasPrefix("> ") || lines[i] == ">") {
                    quoteLines.append(String(lines[i].dropFirst(lines[i].hasPrefix("> ") ? 2 : 1)))
                    i += 1
                }
                result.append(renderBlockquote(quoteLines.joined(separator: "\n")))
                result.append(newline())
                continue
            }

            // Heading
            if let (level, text) = parseHeading(line) {
                result.append(renderHeading(text, level: level))
                result.append(newline())
                i += 1
                continue
            }

            // Task list item (- [ ] or - [x])
            if let (checked, text) = parseTaskItem(line) {
                result.append(renderTaskItem(text, checked: checked))
                result.append(newline())
                i += 1
                continue
            }

            // Unordered list item
            if let text = parseUnorderedItem(line) {
                result.append(renderListItem(text, ordered: false, number: 0))
                result.append(newline())
                i += 1
                continue
            }

            // Ordered list item
            if let (number, text) = parseOrderedItem(line) {
                result.append(renderListItem(text, ordered: true, number: number))
                result.append(newline())
                i += 1
                continue
            }

            // Horizontal rule
            if isHorizontalRule(line) {
                result.append(renderHorizontalRule())
                result.append(newline())
                i += 1
                continue
            }

            // Blank line (paragraph break)
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if result.length > 0 {
                    result.append(newline())
                }
                i += 1
                continue
            }

            // Normal paragraph line
            result.append(renderInline(line, font: style.baseFont, color: style.textColor))
            result.append(newline())
            i += 1
        }

        // Trim trailing newlines
        let str = result.mutableCopy() as! NSMutableAttributedString
        while str.string.hasSuffix("\n") {
            str.deleteCharacters(in: NSRange(location: str.length - 1, length: 1))
        }
        return str
    }

    // MARK: - Preprocessor

    private func preprocess(_ raw: String) -> String {
        var s = raw
        // Literal escape sequences → actual characters
        s = s.replacingOccurrences(of: "\\n", with: "\n")
        s = s.replacingOccurrences(of: "\\t", with: "\t")
        s = s.replacingOccurrences(of: "\\\"", with: "\"")
        s = s.replacingOccurrences(of: "\\'", with: "'")
        return s
    }

    // MARK: - Line Parsers

    private func parseHeading(_ line: String) -> (Int, String)? {
        var level = 0
        var rest = line
        while rest.hasPrefix("#") {
            level += 1
            rest = String(rest.dropFirst())
            if level == 6 { break }
        }
        guard level > 0, rest.hasPrefix(" ") else { return nil }
        return (level, String(rest.dropFirst()).trimmingCharacters(in: .whitespaces))
    }

    private func parseTaskItem(_ line: String) -> (Bool, String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("- [ ] ") { return (false, String(trimmed.dropFirst(6))) }
        if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") { return (true, String(trimmed.dropFirst(6))) }
        return nil
    }

    private func parseUnorderedItem(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for prefix in ["- ", "* ", "+ "] {
            if trimmed.hasPrefix(prefix) { return String(trimmed.dropFirst(prefix.count)) }
        }
        return nil
    }

    private func parseOrderedItem(_ line: String) -> (Int, String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let dotRange = trimmed.range(of: ". "),
              let number = Int(String(trimmed[trimmed.startIndex..<dotRange.lowerBound])) else { return nil }
        return (number, String(trimmed[dotRange.upperBound...]))
    }

    private func isHorizontalRule(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "")
        return trimmed == "---" || trimmed == "***" || trimmed == "___"
    }

    // MARK: - Block Renderers

    private func renderHeading(_ text: String, level: Int) -> NSAttributedString {
        return renderInline(text, font: style.headingFont(level: level), color: style.textColor)
    }

    private func renderCodeBlock(_ code: String) -> NSAttributedString {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: style.codeFont,
            .foregroundColor: style.codeForeground,
            .backgroundColor: style.codeBackground
        ]
        // Pad each line with spaces so background covers the full block width
        let paddedLines = code.components(separatedBy: "\n").map { "  \($0)  " }
        let padded = "\n" + paddedLines.joined(separator: "\n") + "\n"
        return NSAttributedString(string: padded, attributes: attrs)
    }

    private func renderBlockquote(_ text: String) -> NSAttributedString {
        let inner = render(text)
        let result = NSMutableAttributedString(attributedString: inner)
        result.addAttributes([
            .foregroundColor: style.quoteColor,
            .font: style.italicFont
        ], range: NSRange(location: 0, length: result.length))
        // Prepend "│ " indicator
        let prefix = NSAttributedString(string: "┃ ", attributes: [
            .foregroundColor: style.quoteBarColor,
            .font: style.baseFont
        ])
        let combined = NSMutableAttributedString(attributedString: prefix)
        combined.append(result)
        return combined
    }

    private func renderListItem(_ text: String, ordered: Bool, number: Int) -> NSAttributedString {
        let bullet = ordered ? "\(number). " : "• "
        let prefix = NSAttributedString(string: bullet, attributes: [
            .font: style.boldFont,
            .foregroundColor: style.textColor
        ])
        let content = renderInline(text, font: style.baseFont, color: style.textColor)
        let result = NSMutableAttributedString(attributedString: prefix)
        result.append(content)
        // Extra spacing below each list item
        result.append(NSAttributedString(string: "\n", attributes: [.font: style.baseFont]))
        return result
    }

    private func renderTaskItem(_ text: String, checked: Bool) -> NSAttributedString {
        let box = checked ? "☑ " : "☐ "
        let prefix = NSAttributedString(string: box, attributes: [
            .font: style.baseFont,
            .foregroundColor: checked ? style.linkColor : style.textColor
        ])
        // Use renderInline so bold/italic/code inside task items are handled
        let contentColor = checked ? style.secondaryColor : style.textColor
        let content = renderInline(text, font: style.baseFont, color: contentColor)
        if checked {
            let mutable = NSMutableAttributedString(attributedString: content)
            mutable.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue,
                                 range: NSRange(location: 0, length: mutable.length))
            let result = NSMutableAttributedString(attributedString: prefix)
            result.append(mutable)
            // Extra spacing below each task item
            result.append(NSAttributedString(string: "\n", attributes: [.font: style.baseFont]))
            return result
        }
        let result = NSMutableAttributedString(attributedString: prefix)
        result.append(content)
        // Extra spacing below each task item
        result.append(NSAttributedString(string: "\n", attributes: [.font: style.baseFont]))
        return result
    }

    private func renderHorizontalRule() -> NSAttributedString {
        return NSAttributedString(string: "─────────────────", attributes: [
            .foregroundColor: style.quoteBarColor,
            .font: style.baseFont
        ])
    }

    // MARK: - Inline Renderer

    /// Renders inline markdown: bold, italic, bold-italic, strikethrough, inline code, links.
    func renderInline(_ text: String, font: NSFont, color: NSColor) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var s = text
        // Base attrs
        let base: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]

        while !s.isEmpty {
            // Bold-italic: ***text***
            if let range = firstRange(in: s, pattern: #"\*\*\*(.+?)\*\*\*"#) {
                appendLiteral(s[s.startIndex..<range.lowerBound], attrs: base, to: result)
                let inner = String(s[range].dropFirst(3).dropLast(3))
                result.append(renderInline(inner, font: style.boldItalicFont, color: color))
                s = String(s[range.upperBound...])
                continue
            }
            // Bold: **text** or __text__
            if let range = firstRange(in: s, pattern: #"(\*\*|__)(.+?)(\*\*|__)"#) {
                appendLiteral(s[s.startIndex..<range.lowerBound], attrs: base, to: result)
                let full = String(s[range])
                let inner = String(full.dropFirst(2).dropLast(2))
                result.append(renderInline(inner, font: style.boldFont, color: color))
                s = String(s[range.upperBound...])
                continue
            }
            // Italic: *text*
            if let range = firstRange(in: s, pattern: #"\*([^*]+?)\*"#) {
                appendLiteral(s[s.startIndex..<range.lowerBound], attrs: base, to: result)
                let inner = String(s[range].dropFirst(1).dropLast(1))
                result.append(NSAttributedString(string: inner, attributes: [.font: style.italicFont, .foregroundColor: color]))
                s = String(s[range.upperBound...])
                continue
            }
            // Italic: _text_ (only when _ is not flanked by a word character)
            if let range = firstRange(in: s, pattern: #"(?<!\w)_([^_]+?)_(?!\w)"#) {
                appendLiteral(s[s.startIndex..<range.lowerBound], attrs: base, to: result)
                let inner = String(s[range].dropFirst(1).dropLast(1))
                result.append(NSAttributedString(string: inner, attributes: [.font: style.italicFont, .foregroundColor: color]))
                s = String(s[range.upperBound...])
                continue
            }
            // Strikethrough: ~~text~~
            if let range = firstRange(in: s, pattern: #"~~(.+?)~~"#) {
                appendLiteral(s[s.startIndex..<range.lowerBound], attrs: base, to: result)
                let inner = String(s[range].dropFirst(2).dropLast(2))
                result.append(NSAttributedString(string: inner, attributes: [
                    .font: font,
                    .foregroundColor: style.secondaryColor,
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue
                ]))
                s = String(s[range.upperBound...])
                continue
            }
            // Inline code: `code`
            if let range = firstRange(in: s, pattern: #"`(.+?)`"#) {
                appendLiteral(s[s.startIndex..<range.lowerBound], attrs: base, to: result)
                let inner = String(s[range].dropFirst(1).dropLast(1))
                result.append(NSAttributedString(string: " \(inner) ", attributes: [
                    .font: style.codeFont,
                    .foregroundColor: style.codeForeground,
                    .backgroundColor: style.codeBackground
                ]))
                s = String(s[range.upperBound...])
                continue
            }
            // Link: [text](url)
            if let range = firstRange(in: s, pattern: #"\[(.+?)\]\((.+?)\)"#) {
                appendLiteral(s[s.startIndex..<range.lowerBound], attrs: base, to: result)
                let full = String(s[range])
                // Extract text and url
                if let textEnd = full.firstIndex(of: "]"),
                   let urlStart = full.range(of: "](") {
                    let linkText = String(full[full.index(after: full.startIndex)..<textEnd])
                    let urlStr   = String(full[urlStart.upperBound..<full.index(before: full.endIndex)])
                    var linkAttrs: [NSAttributedString.Key: Any] = [
                        .font: font,
                        .foregroundColor: style.linkColor,
                        .underlineStyle: NSUnderlineStyle.single.rawValue
                    ]
                    if let url = URL(string: urlStr) { linkAttrs[.link] = url }
                    result.append(NSAttributedString(string: linkText, attributes: linkAttrs))
                }
                s = String(s[range.upperBound...])
                continue
            }
            // Mention: @alias
            if let range = firstRange(in: s, pattern: #"\B@[^\s]+"#) {
                appendLiteral(s[s.startIndex..<range.lowerBound], attrs: base, to: result)
                let mention = String(s[range])
                result.append(NSAttributedString(string: mention, attributes: [
                    .font: font,
                    .foregroundColor: style.mentionColor
                ]))
                s = String(s[range.upperBound...])
                continue
            }
            // Bare URL: https://... or http://...
            if let range = firstRange(in: s, pattern: #"https?://[^\s]+"#) {
                appendLiteral(s[s.startIndex..<range.lowerBound], attrs: base, to: result)
                let urlStr = String(s[range])
                var linkAttrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: style.linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ]
                if let url = URL(string: urlStr) { linkAttrs[.link] = url }
                result.append(NSAttributedString(string: urlStr, attributes: linkAttrs))
                s = String(s[range.upperBound...])
                continue
            }
            // No more patterns — append rest as-is
            result.append(NSAttributedString(string: s, attributes: base))
            break
        }
        return result
    }

    // MARK: - Helpers

    private func firstRange(in string: String, pattern: String) -> Range<String.Index>? {
        return try! string.range(of: pattern, options: .regularExpression)
    }

    private func appendLiteral(_ sub: Substring, attrs: [NSAttributedString.Key: Any], to result: NSMutableAttributedString) {
        if !sub.isEmpty {
            result.append(NSAttributedString(string: String(sub), attributes: attrs))
        }
    }

    private func newline() -> NSAttributedString {
        NSAttributedString(string: "\n", attributes: [.font: style.baseFont, .foregroundColor: style.textColor])
    }
}
