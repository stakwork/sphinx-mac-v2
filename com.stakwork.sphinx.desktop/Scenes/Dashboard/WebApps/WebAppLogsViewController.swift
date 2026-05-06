// WebAppLogsViewController.swift
// Sphinx

import AppKit

class WebAppLogsViewController: NSViewController {

    private var textView: NSTextView!
    private var scrollView: NSScrollView!
    private weak var store: WebAppLogStore?

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    // MARK: - Factory

    static func instantiate(store: WebAppLogStore) -> WebAppLogsViewController {
        let vc = WebAppLogsViewController()
        vc.store = store
        return vc
    }

    // MARK: - View lifecycle

    override func loadView() {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.backgroundColor = NSColor.Sphinx.Body

        let contentSize = scrollView.contentSize
        let textView = NSTextView(frame: NSRect(origin: .zero, size: contentSize))
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.backgroundColor = NSColor.Sphinx.Body
        textView.textColor = NSColor.Sphinx.SecondaryText
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                       height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView

        self.scrollView = scrollView
        self.textView = textView
        self.view = scrollView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Replay any existing entries
        if let store = store {
            for entry in store.entries {
                appendLine(for: entry)
            }
        }

        // Subscribe for new entries
        store?.onNewEntry = { [weak self] entry in
            self?.appendLine(for: entry)
        }
    }

    // MARK: - Formatting

    private func appendLine(for entry: WebAppLogStore.WebAppLogEntry) {
        let timeStr = Self.timeFormatter.string(from: entry.timestamp)
        let sourceTag = sourceLabel(entry.source)
        let levelTag = levelLabel(entry.level)
        let line = "[\(timeStr)] [\(sourceTag)] [\(levelTag)] \(entry.message)\n"

        let color = lineColor(level: entry.level, source: entry.source)
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: color,
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        ]
        let attrString = NSAttributedString(string: line, attributes: attrs)

        textView.textStorage?.append(attrString)
        scrollToBottom()
    }

    private func sourceLabel(_ source: WebAppLogStore.LogSource) -> String {
        switch source {
        case .jsConsole:       return "JS"
        case .navigation:      return "NAV"
        case .bridgeInbound:   return "BRIDGE-IN"
        case .bridgeOutbound:  return "BRIDGE-OUT"
        case .network:         return "NET"
        }
    }

    private func levelLabel(_ level: WebAppLogStore.LogLevel) -> String {
        switch level {
        case .log:   return "LOG"
        case .warn:  return "WARN"
        case .error: return "ERROR"
        case .info:  return "INFO"
        }
    }

    private func lineColor(level: WebAppLogStore.LogLevel, source: WebAppLogStore.LogSource) -> NSColor {
        switch source {
        case .navigation:
            return NSColor.systemBlue
        case .bridgeInbound, .bridgeOutbound:
            return NSColor.systemGreen
        case .network:
            return NSColor.systemOrange
        case .jsConsole:
            break
        }
        switch level {
        case .error: return NSColor.systemRed
        case .warn:  return NSColor.systemYellow
        case .log, .info: return NSColor.Sphinx.SecondaryText
        }
    }

    private func scrollToBottom() {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        if glyphRange.length > 0 {
            let lastGlyph = NSRange(location: NSMaxRange(glyphRange) - 1, length: 1)
            textView.scrollRangeToVisible(lastGlyph)
        }
    }
}
