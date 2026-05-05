// DiagnosticsViewController.swift
// com.stakwork.sphinx.desktop

import AppKit

class DiagnosticsViewController: NSViewController {

    // MARK: - UI

    private var scrollView: NSScrollView!
    private var textView: NSTextView!
    private var headerView: NSView!
    private var titleLabel: NSTextField!
    private var exportButton: NSButton!
    private var clearButton: NSButton!

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    // MARK: - Factory

    static func instantiate() -> DiagnosticsViewController {
        return DiagnosticsViewController()
    }

    // MARK: - loadView (programmatic)

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true

        // ── Header ─────────────────────────────────────────────────────────
        let header = NSView()
        header.wantsLayer = true
        header.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(header)
        self.headerView = header

        let title = NSTextField(labelWithString: "diagnostics.title".localized)
        title.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        title.textColor = NSColor.Sphinx.Text
        title.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(title)
        self.titleLabel = title

        let exportBtn = NSButton(title: "diagnostics.export-button".localized,
                                 target: self,
                                 action: #selector(exportButtonClicked))
        exportBtn.bezelStyle = .rounded
        exportBtn.controlSize = .regular
        exportBtn.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(exportBtn)
        self.exportButton = exportBtn

        let clearBtn = NSButton(title: "diagnostics.clear-button".localized,
                                target: self,
                                action: #selector(clearButtonClicked))
        clearBtn.bezelStyle = .rounded
        clearBtn.controlSize = .regular
        clearBtn.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(clearBtn)
        self.clearButton = clearBtn

        // Separator line
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(separator)

        // ── Scroll / Text view ─────────────────────────────────────────────
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.backgroundColor = NSColor.Sphinx.Body
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scrollView)
        self.scrollView = scrollView

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
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView
        self.textView = textView

        // ── Layout ─────────────────────────────────────────────────────────
        NSLayoutConstraint.activate([
            // Header
            header.topAnchor.constraint(equalTo: container.topAnchor),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 48),

            // Title centred vertically in header
            title.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            title.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),

            // Buttons on the right
            exportBtn.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            exportBtn.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),

            clearBtn.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            clearBtn.trailingAnchor.constraint(equalTo: exportBtn.leadingAnchor, constant: -8),

            // Separator
            separator.topAnchor.constraint(equalTo: header.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            // Scroll view fills remaining space
            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        self.view = container
    }

    // MARK: - viewDidLoad

    override func viewDidLoad() {
        super.viewDidLoad()

        // Render existing entries
        for entry in AppLogger.shared.entries {
            appendLine(for: entry)
        }

        // Live-append new entries
        AppLogger.shared.onNewEntry = { [weak self] entry in
            DispatchQueue.main.async {
                self?.appendLine(for: entry)
            }
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        // Remove live callback when hidden
        AppLogger.shared.onNewEntry = nil
    }

    // MARK: - Formatting

    private func appendLine(for entry: AppLogger.LogEntry) {
        let timeStr = Self.timeFormatter.string(from: entry.timestamp)
        let line = "[\(timeStr)] [\(entry.level.rawValue)] \(entry.message)\n"
        let color = lineColor(for: entry.level)
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: color,
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        ]
        let attrStr = NSAttributedString(string: line, attributes: attrs)
        textView.textStorage?.append(attrStr)
        scrollToBottom()
    }

    private func lineColor(for level: AppLogger.LogLevel) -> NSColor {
        switch level {
        case .error:   return NSColor.systemRed
        case .warning: return NSColor.systemYellow
        case .info:    return NSColor.Sphinx.SecondaryText
        case .debug:   return NSColor.systemGray
        }
    }

    private func scrollToBottom() {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        guard glyphRange.length > 0 else { return }
        let lastGlyph = NSRange(location: NSMaxRange(glyphRange) - 1, length: 1)
        textView.scrollRangeToVisible(lastGlyph)
    }

    // MARK: - Actions

    @objc private func exportButtonClicked() {
        guard let fileURL = AppLogger.shared.exportedFileURL() else {
            showAlert("Could not create log file.")
            return
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = fileURL.lastPathComponent
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let destURL = panel.url else { return }
            do {
                if FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.removeItem(at: destURL)
                }
                try FileManager.default.copyItem(at: fileURL, to: destURL)
            } catch {
                self?.showAlert("Export failed: \(error.localizedDescription)")
            }
        }
    }

    @objc private func clearButtonClicked() {
        AppLogger.shared.clear()
        textView.string = ""
    }

    private func showAlert(_ message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = message
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            if let window = self.view.window {
                alert.beginSheetModal(for: window)
            } else {
                alert.runModal()
            }
        }
    }
}
