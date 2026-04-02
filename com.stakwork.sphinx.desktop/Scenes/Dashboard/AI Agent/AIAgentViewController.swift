//
//  AIAgentViewController.swift
//  sphinx
//
//  Created by Sphinx on 01/04/2026.
//  Copyright © 2026 sphinx. All rights reserved.
//

import Cocoa

final class AIAgentViewController: NSViewController {

    // MARK: - Views
    private let scrollView     = NSScrollView()
    private let transcriptView = NSTextView()
    private let bottomBarView  = NSView()
    private let divider        = NSBox()
    private let pillView       = NSView()
    private let inputField     = NSTextField()
    private let sendButton     = NSButton()
    private let spinner        = NSProgressIndicator()

    // MARK: - Renderer
    private let renderer = MarkdownRenderer()

    // MARK: - Constants
    private let kBottomBarHeight: CGFloat   = 72
    /// Send button and pill share the same size — circular button, equal-height pill
    private let kUnitSize: CGFloat          = 40
    private let kInputCornerRadius: CGFloat = 20
    private let kHPad: CGFloat             = 12
    private let kVPad: CGFloat             = 16
    private let kInputFont      = NSFont(name: "Roboto-Regular", size: 16.0) ?? NSFont.systemFont(ofSize: 16)
    private let kTranscriptFont = NSFont(name: "Roboto-Regular", size: 15.0) ?? NSFont.systemFont(ofSize: 15)

    // MARK: - State
    private var introAppended = false

    // MARK: - Lifecycle

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.Sphinx.Body.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupLayout()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateTranscriptFrame()

        // Append intro once we have real dimensions
        if !introAppended && scrollView.bounds.width > 0 {
            introAppended = true
            appendIntroMessage()
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(inputField)
    }

    // MARK: - Factory
    static func instantiate() -> AIAgentViewController { AIAgentViewController() }

    // MARK: - Transcript frame management
    //
    // NSTextView-as-documentView does NOT use Auto Layout for its own frame;
    // the scroll view drives its width via autoresizingMask and we set height
    // to whatever is needed to show all content (verticallyResizable = true).
    private func updateTranscriptFrame() {
        let w = scrollView.bounds.width
        guard w > 0 else { return }
        let h = max(transcriptView.frame.height, scrollView.bounds.height)
        if abs(transcriptView.frame.width - w) > 1 {
            transcriptView.frame = NSRect(x: 0, y: 0, width: w, height: h)
        }
    }

    // MARK: - Layout

    private func setupLayout() {
        // ── Bottom bar ─────────────────────────────────────────────────────────
        bottomBarView.wantsLayer = true
        bottomBarView.layer?.backgroundColor = NSColor.Sphinx.Body.cgColor
        bottomBarView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomBarView)

        // ── Divider ────────────────────────────────────────────────────────────
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(divider)

        // ── Transcript scroll ──────────────────────────────────────────────────
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers  = true
        scrollView.drawsBackground     = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        // NSTextView-as-documentView: frame-based, grows vertically with content
        transcriptView.isEditable    = false
        transcriptView.isSelectable  = true
        transcriptView.drawsBackground = true
        transcriptView.backgroundColor = NSColor.Sphinx.Body
        transcriptView.textColor       = NSColor.Sphinx.Text
        transcriptView.font            = kTranscriptFont
        transcriptView.textContainerInset = NSSize(width: 16, height: 16)
        transcriptView.isAutomaticQuoteSubstitutionEnabled  = false
        transcriptView.isAutomaticSpellingCorrectionEnabled = false
        transcriptView.isVerticallyResizable   = true
        transcriptView.isHorizontallyResizable = false
        transcriptView.minSize = NSSize(width: 0, height: 0)
        transcriptView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                        height: CGFloat.greatestFiniteMagnitude)
        transcriptView.autoresizingMask = .width   // width tracks scroll view
        transcriptView.textContainer?.widthTracksTextView  = true
        transcriptView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        // Give it a non-zero initial frame so content is visible immediately
        transcriptView.frame = NSRect(x: 0, y: 0, width: 620, height: 3000)
        scrollView.documentView = transcriptView

        // ── Pill container (rounded background for input field) ────────────────
        pillView.wantsLayer = true
        pillView.layer?.cornerRadius    = kInputCornerRadius
        pillView.layer?.masksToBounds   = true
        pillView.layer?.backgroundColor = NSColor.Sphinx.ReceivedMsgBG.cgColor
        pillView.translatesAutoresizingMaskIntoConstraints = false
        bottomBarView.addSubview(pillView)

        // ── Input field — plain NSTextField, no wantsLayer, no custom cell ─────
        // Constrain it to pill's center with an explicit height = kUnitSize so
        // the cell's vertical padding doesn't shift the placeholder off-center.
        inputField.stringValue       = ""
        inputField.placeholderString = "Ask Sphinx AI..."
        inputField.font              = kInputFont
        inputField.textColor         = NSColor.Sphinx.PrimaryText
        inputField.backgroundColor   = .clear
        inputField.drawsBackground   = false
        inputField.isBordered        = false
        inputField.isBezeled         = false
        inputField.focusRingType     = .none
        inputField.isEditable        = true
        inputField.isSelectable      = true
        inputField.cell?.usesSingleLineMode = true
        inputField.cell?.isScrollable       = true
        inputField.cell?.wraps              = false
        inputField.translatesAutoresizingMaskIntoConstraints = false
        inputField.target = self
        inputField.action = #selector(sendTapped)
        pillView.addSubview(inputField)

        NotificationCenter.default.addObserver(
            self, selector: #selector(inputDidChange),
            name: NSTextField.textDidChangeNotification,
            object: inputField
        )

        // ── Send button (kUnitSize × kUnitSize circle) ─────────────────────────
        sendButton.isBordered   = false
        sendButton.wantsLayer   = true
        sendButton.layer?.cornerRadius   = kUnitSize / 2
        sendButton.layer?.masksToBounds  = true
        sendButton.layer?.backgroundColor = NSColor.Sphinx.PrimaryBlue.withAlphaComponent(0.4).cgColor
        sendButton.imagePosition = .imageOnly
        sendButton.imageScaling  = .proportionallyDown
        if let img = NSImage(systemSymbolName: "paperplane.fill", accessibilityDescription: "Send") {
            sendButton.image = img.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
            )
        } else {
            sendButton.title = "▶"
        }
        sendButton.contentTintColor = NSColor.white
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.target  = self
        sendButton.action  = #selector(sendTapped)
        sendButton.isEnabled = false
        bottomBarView.addSubview(sendButton)

        // ── Spinner (centred over send button while loading) ───────────────────
        spinner.style           = .spinning
        spinner.controlSize     = .small
        spinner.isIndeterminate = true
        spinner.isHidden        = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        bottomBarView.addSubview(spinner)

        // ── Constraints ────────────────────────────────────────────────────────
        NSLayoutConstraint.activate([
            // Bottom bar — fixed height
            bottomBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBarView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomBarView.heightAnchor.constraint(equalToConstant: kBottomBarHeight),

            // Divider
            divider.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            divider.bottomAnchor.constraint(equalTo: bottomBarView.topAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),

            // Transcript scroll — fills everything above divider
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: divider.topAnchor),

            // Pill: left=hPad, same height as send button, centred vertically
            pillView.leadingAnchor.constraint(equalTo: bottomBarView.leadingAnchor, constant: kHPad),
            pillView.centerYAnchor.constraint(equalTo: bottomBarView.centerYAnchor),
            pillView.heightAnchor.constraint(equalToConstant: kUnitSize),
            pillView.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),

            // Input field: fills pill, explicit height = kUnitSize so the cell's
            // internal padding doesn't shift the placeholder vertically
            inputField.leadingAnchor.constraint(equalTo: pillView.leadingAnchor, constant: 12),
            inputField.trailingAnchor.constraint(equalTo: pillView.trailingAnchor, constant: -12),
            inputField.centerYAnchor.constraint(equalTo: pillView.centerYAnchor),
            inputField.heightAnchor.constraint(equalToConstant: kUnitSize),

            // Send button — kUnitSize × kUnitSize circle, right margin = left margin
            sendButton.trailingAnchor.constraint(equalTo: bottomBarView.trailingAnchor, constant: -kHPad),
            sendButton.centerYAnchor.constraint(equalTo: bottomBarView.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: kUnitSize),
            sendButton.heightAnchor.constraint(equalToConstant: kUnitSize),

            // Spinner centred over send button
            spinner.centerXAnchor.constraint(equalTo: sendButton.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: sendButton.centerYAnchor),
            spinner.widthAnchor.constraint(equalToConstant: 20),
            spinner.heightAnchor.constraint(equalToConstant: 20),
        ])
    }

    // MARK: - Input change

    @objc private func inputDidChange() {
        let hasText = !inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        sendButton.isEnabled = hasText
        sendButton.layer?.backgroundColor = hasText
            ? NSColor.Sphinx.PrimaryBlue.cgColor
            : NSColor.Sphinx.PrimaryBlue.withAlphaComponent(0.4).cgColor
    }

    // MARK: - Intro

    private func appendIntroMessage() {
        appendAssistant("👋 Hi! I'm your Sphinx AI assistant. You can ask me to read recent messages or send messages to your contacts.\n\nMake sure you've configured your AI provider and API key in **Profile → Advanced → Configure AI Agent**.")
    }

    // MARK: - Send

    @objc private func sendTapped() {
        let text = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        inputField.stringValue = ""
        inputDidChange()
        appendUser(text)
        setLoading(true)

        Task {
            do {
                let response = try await AIAgentManager.sharedInstance.chat(text)
                await MainActor.run {
                    self.appendAssistant(response)
                    self.setLoading(false)
                }
            } catch {
                await MainActor.run {
                    self.appendError(error.localizedDescription)
                    self.setLoading(false)
                }
            }
        }
    }

    // MARK: - Transcript helpers

    private func appendUser(_ text: String) {
        guard let storage = transcriptView.textStorage else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont(name: "Roboto-Bold", size: 14) ?? NSFont.boldSystemFont(ofSize: 14),
            .foregroundColor: NSColor.Sphinx.Text
        ]
        storage.append(NSAttributedString(string: "You: \(text)\n\n", attributes: attrs))
        scrollToBottom()
    }

    private func appendAssistant(_ text: String) {
        guard let storage = transcriptView.textStorage else { return }
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont(name: "Roboto-Medium", size: 13) ?? NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.Sphinx.SecondaryText
        ]
        storage.append(NSAttributedString(string: "Sphinx AI:\n", attributes: labelAttrs))
        let rendered = renderer.renderNS(text)
        let mutable  = NSMutableAttributedString(attributedString: rendered)
        mutable.append(NSAttributedString(string: "\n\n"))
        storage.append(mutable)
        scrollToBottom()
    }

    private func appendError(_ message: String) {
        guard let storage = transcriptView.textStorage else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: kTranscriptFont,
            .foregroundColor: NSColor.systemRed
        ]
        storage.append(NSAttributedString(string: "[Error: \(message)]\n\n", attributes: attrs))
        scrollToBottom()
    }

    private func scrollToBottom() {
        guard let len = transcriptView.textStorage?.length else { return }
        transcriptView.scrollRangeToVisible(NSRange(location: len, length: 0))
    }

    // MARK: - Loading state

    private func setLoading(_ loading: Bool) {
        sendButton.isHidden  = loading
        inputField.isEnabled = !loading
        spinner.isHidden     = !loading
        if loading {
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
            view.window?.makeFirstResponder(inputField)
        }
    }
}
