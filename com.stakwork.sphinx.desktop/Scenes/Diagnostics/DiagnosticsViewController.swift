// DiagnosticsViewController.swift
// com.stakwork.sphinx.desktop

import AppKit

class DiagnosticsViewController: NSViewController {

    // MARK: - UI

    private var scrollView: NSScrollView!
    private var textView: NSTextView!
    private var loadingWheel: NSProgressIndicator!
    private var headerView: NSView!
    private var titleLabel: NSTextField!
    private var exportButton: NSButton!
    private var clearButton: NSButton!
    private var newWindowButton: NSButton!
    private var logObserverID: UUID?

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

        let exportBtn = makeIconButton(systemSymbol: "square.and.arrow.up", tooltip: "Export logs", action: #selector(exportButtonClicked))
        header.addSubview(exportBtn)
        self.exportButton = exportBtn

        let clearBtn = makeIconButton(systemSymbol: "trash", tooltip: "Clear logs", action: #selector(clearButtonClicked))
        header.addSubview(clearBtn)
        self.clearButton = clearBtn

        let newWinBtn = makeIconButton(systemSymbol: "openNewWindow", tooltip: "Open in new window", action: #selector(openInNewWindowButtonClicked))
        header.addSubview(newWinBtn)
        self.newWindowButton = newWinBtn

        // Separator line
        let separator = NSBox()
        separator.boxType = .separator
        separator.borderColor = NSColor.Sphinx.SecondaryText
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

        // ── Loading Wheel ──────────────────────────────────────────────────
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.isIndeterminate = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.isHidden = true
        container.addSubview(spinner)
        self.loadingWheel = spinner

        // ── Layout ─────────────────────────────────────────────────────────
        NSLayoutConstraint.activate([
            // Header
            header.topAnchor.constraint(equalTo: container.topAnchor),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 48),

            // Buttons on the right
            exportBtn.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            exportBtn.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),

            clearBtn.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            clearBtn.trailingAnchor.constraint(equalTo: exportBtn.leadingAnchor, constant: -8),

            newWinBtn.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            newWinBtn.trailingAnchor.constraint(equalTo: clearBtn.leadingAnchor, constant: -8),

            // Separator
            separator.topAnchor.constraint(equalTo: header.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            // Scroll view fills remaining space
            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            // Spinner centred over scroll view
            spinner.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
        ])

        self.view = container
    }

    // MARK: - viewDidLoad

    override func viewDidLoad() {
        super.viewDidLoad()

        // Show spinner, hide text view until entries are rendered
        textView.isHidden = true
        loadingWheel.isHidden = false
        loadingWheel.startAnimation(nil)

        // Snapshot the last 2000 entries — full log is always available via export
        let entries = Array(AppLogger.shared.entries.suffix(10000))

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            // Build full attributed string off main thread
            let monoFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            let combined = NSMutableAttributedString()
            for entry in entries {
                let timeStr = Self.timeFormatter.string(from: entry.timestamp)
                let timestampPart = NSAttributedString(
                    string: "[\(timeStr)] ",
                    attributes: [.foregroundColor: NSColor.Sphinx.PrimaryBlue, .font: monoFont]
                )
                let bodyPart = NSAttributedString(
                    string: "[\(entry.level.rawValue)] \(entry.message)\n",
                    attributes: [.foregroundColor: self.lineColor(for: entry.level), .font: monoFont]
                )
                combined.append(timestampPart)
                combined.append(bodyPart)
            }

            DispatchQueue.main.async {
                self.textView.textStorage?.setAttributedString(combined)
                self.scrollToBottom()
                LoadingWheelHelper.toggleLoadingWheel(
                    loading: false,
                    loadingWheel: self.loadingWheel,
                    color: NSColor.Sphinx.SecondaryText,
                    controls: []
                )
                self.textView.isHidden = false

                // Register live callback AFTER initial render to avoid mid-load race
                self.logObserverID = AppLogger.shared.addObserver { [weak self] entry in
                    self?.appendLine(for: entry)
                }
            }
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        if let id = logObserverID {
            AppLogger.shared.removeObserver(id)
            logObserverID = nil
        }
    }

    // MARK: - Formatting

    private func appendLine(for entry: AppLogger.LogEntry) {
        let monoFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let timeStr = Self.timeFormatter.string(from: entry.timestamp)
        let timestampPart = NSAttributedString(
            string: "[\(timeStr)] ",
            attributes: [.foregroundColor: NSColor.Sphinx.PrimaryBlue, .font: monoFont]
        )
        let bodyPart = NSAttributedString(
            string: "[\(entry.level.rawValue)] \(entry.message)\n",
            attributes: [.foregroundColor: lineColor(for: entry.level), .font: monoFont]
        )
        let combined = NSMutableAttributedString()
        combined.append(timestampPart)
        combined.append(bodyPart)
        textView.textStorage?.append(combined)
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

        guard let window = view.window else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = fileURL.lastPathComponent
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: window) { [weak self] response in
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

    @objc private func openInNewWindowButtonClicked() {
        WindowsManager.sharedInstance.showNewWindow(
            with: "diagnostics".localized,
            size: CGSize(width: 700, height: 700),
            identifier: "diagnostics-new-window",
            contentVC: DiagnosticsViewController.instantiate()
        )
    }

    private func makeIconButton(systemSymbol: String, tooltip: String, action: Selector) -> NSButton {
        var img: NSImage? = nil
        
        if let systemImg = NSImage(systemSymbolName: systemSymbol, accessibilityDescription: tooltip) {
            let config = NSImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
            img = systemImg.withSymbolConfiguration(config)
        } else if let assetImg = NSImage(named: systemSymbol) {
            img = assetImg
        }
        
        let btn = NSButton(image: img!, target: self, action: action)
        btn.bezelStyle = .texturedRounded
        btn.isBordered = false
        btn.toolTip = tooltip
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.widthAnchor.constraint(equalToConstant: 36).isActive = true
        btn.heightAnchor.constraint(equalToConstant: 36).isActive = true
        return btn
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
