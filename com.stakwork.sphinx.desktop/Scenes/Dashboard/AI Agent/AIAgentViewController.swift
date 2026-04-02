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

    private let scrollView       = NSScrollView()
    private let transcriptView   = NSTextView()
    private let bottomBarView    = NSView()
    private let divider          = NSBox()

    // Input container (matches chat UI — rounded, ReceivedMsgBG)
    private let inputContainer   = NSView()
    private let inputTextView    = NSTextView()
    private let inputScrollView  = NSScrollView()

    // Send button (matches chat UI — circle, PrimaryBlue)
    private let sendButton       = NSButton()
    private let spinner          = NSProgressIndicator()

    // MARK: - Renderer

    private let renderer = MarkdownRenderer()

    // MARK: - Constants (mirrors ChatMessageFieldView)
    private let kBottomBarHeight: CGFloat    = 72
    private let kInputContainerRadius: CGFloat = 20
    private let kSendButtonSize: CGFloat      = 40
    private let kInputFont = NSFont(name: "Roboto-Regular", size: 16.0)
                          ?? NSFont.systemFont(ofSize: 16)
    private let kTranscriptFont = NSFont(name: "Roboto-Regular", size: 15.0)
                               ?? NSFont.systemFont(ofSize: 15)

    // MARK: - Lifecycle

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.Sphinx.Body.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupLayout()
        appendIntroMessage()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        // Keep input container corner radius live
        inputContainer.layer?.cornerRadius = kInputContainerRadius
        sendButton.layer?.cornerRadius = kSendButtonSize / 2
    }

    // MARK: - Static Factory

    static func instantiate() -> AIAgentViewController {
        return AIAgentViewController()
    }

    // MARK: - Layout

    private func setupLayout() {
        // ── Bottom bar ──────────────────────────────────────────────────────
        bottomBarView.wantsLayer = true
        bottomBarView.layer?.backgroundColor = NSColor.Sphinx.Body.cgColor
        view.addSubview(bottomBarView)
        bottomBarView.translatesAutoresizingMaskIntoConstraints = false

        // ── Divider ─────────────────────────────────────────────────────────
        divider.boxType = .separator
        view.addSubview(divider)
        divider.translatesAutoresizingMaskIntoConstraints = false

        // ── Transcript scroll view ───────────────────────────────────────────
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers  = true
        scrollView.drawsBackground     = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

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
        transcriptView.textContainer?.widthTracksTextView = true
        transcriptView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = transcriptView

        // ── Input container (rounded pill, ReceivedMsgBG) ───────────────────
        inputContainer.wantsLayer = true
        inputContainer.layer?.backgroundColor = NSColor.Sphinx.ReceivedMsgBG.cgColor
        inputContainer.layer?.cornerRadius = kInputContainerRadius
        inputContainer.translatesAutoresizingMaskIntoConstraints = false
        bottomBarView.addSubview(inputContainer)

        // Input text view (inside scroll, matches PlaceHolderTextView style)
        inputScrollView.hasVerticalScroller = false
        inputScrollView.hasHorizontalScroller = false
        inputScrollView.drawsBackground = false
        inputScrollView.translatesAutoresizingMaskIntoConstraints = false
        inputContainer.addSubview(inputScrollView)

        inputTextView.isRichText   = false
        inputTextView.font         = kInputFont
        inputTextView.textColor    = NSColor.Sphinx.PrimaryText
        inputTextView.backgroundColor = .clear
        inputTextView.drawsBackground  = false
        inputTextView.isEditable       = true
        inputTextView.isSelectable     = true
        inputTextView.isVerticallyResizable   = true
        inputTextView.isHorizontallyResizable = false
        inputTextView.textContainer?.widthTracksTextView = true
        inputTextView.translatesAutoresizingMaskIntoConstraints = false
        inputTextView.delegate = self
        setPlaceholder()
        inputScrollView.documentView = inputTextView

        // ── Send button (circle, PrimaryBlue, SF symbol paper.plane) ────────
        sendButton.isBordered = false
        sendButton.wantsLayer = true
        sendButton.layer?.cornerRadius = kSendButtonSize / 2
        sendButton.layer?.backgroundColor = NSColor.Sphinx.PrimaryBlue.cgColor
        sendButton.imagePosition = .imageOnly
        sendButton.imageScaling  = .proportionallyDown
        if let img = NSImage(systemSymbolName: "paperplane.fill", accessibilityDescription: "Send") {
            var cfg = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            sendButton.image = img.withSymbolConfiguration(cfg)
        } else {
            sendButton.title = "Send"
        }
        sendButton.contentTintColor = NSColor.white
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.target = self
        sendButton.action = #selector(sendTapped)
        sendButton.isEnabled = false
        bottomBarView.addSubview(sendButton)

        // ── Spinner ─────────────────────────────────────────────────────────
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.isHidden = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        bottomBarView.addSubview(spinner)

        // ── Constraints ──────────────────────────────────────────────────────
        let vPad: CGFloat = 16   // vertical padding inside bottom bar
        let hPad: CGFloat = 12   // horizontal padding

        NSLayoutConstraint.activate([
            // Bottom bar
            bottomBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBarView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomBarView.heightAnchor.constraint(greaterThanOrEqualToConstant: kBottomBarHeight),

            // Divider
            divider.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            divider.bottomAnchor.constraint(equalTo: bottomBarView.topAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),

            // Transcript scroll
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: divider.topAnchor),

            // Transcript text view matches scroll width
            transcriptView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            transcriptView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            transcriptView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),

            // Input container (left of send button, right margin for spinner)
            inputContainer.leadingAnchor.constraint(equalTo: bottomBarView.leadingAnchor, constant: hPad),
            inputContainer.topAnchor.constraint(equalTo: bottomBarView.topAnchor, constant: vPad),
            inputContainer.bottomAnchor.constraint(equalTo: bottomBarView.bottomAnchor, constant: -vPad),
            inputContainer.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),

            // Input scroll inside container
            inputScrollView.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor, constant: 12),
            inputScrollView.trailingAnchor.constraint(equalTo: inputContainer.trailingAnchor, constant: -12),
            inputScrollView.topAnchor.constraint(equalTo: inputContainer.topAnchor, constant: 4),
            inputScrollView.bottomAnchor.constraint(equalTo: inputContainer.bottomAnchor, constant: -4),

            // Input text view matches scroll width
            inputTextView.topAnchor.constraint(equalTo: inputScrollView.contentView.topAnchor),
            inputTextView.leadingAnchor.constraint(equalTo: inputScrollView.contentView.leadingAnchor),
            inputTextView.trailingAnchor.constraint(equalTo: inputScrollView.contentView.trailingAnchor),

            // Send button — fixed circle
            sendButton.trailingAnchor.constraint(equalTo: spinner.leadingAnchor, constant: -8),
            sendButton.centerYAnchor.constraint(equalTo: bottomBarView.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: kSendButtonSize),
            sendButton.heightAnchor.constraint(equalToConstant: kSendButtonSize),

            // Spinner
            spinner.trailingAnchor.constraint(equalTo: bottomBarView.trailingAnchor, constant: -hPad),
            spinner.centerYAnchor.constraint(equalTo: bottomBarView.centerYAnchor),
            spinner.widthAnchor.constraint(equalToConstant: 20),
            spinner.heightAnchor.constraint(equalToConstant: 20),
        ])
    }

    // MARK: - Placeholder

    private func setPlaceholder() {
        let placeholder = NSAttributedString(
            string: "Ask Sphinx AI...",
            attributes: [
                .font: kInputFont,
                .foregroundColor: NSColor.Sphinx.PlaceholderText
            ]
        )
        // NSTextView doesn't natively support placeholder; we fake it via content check
        if inputTextView.string.isEmpty {
            inputTextView.textStorage?.setAttributedString(placeholder)
            inputTextView.textColor = NSColor.Sphinx.PlaceholderText
        }
    }

    private func clearPlaceholder() {
        if inputTextView.textColor == NSColor.Sphinx.PlaceholderText {
            inputTextView.string = ""
            inputTextView.textColor = NSColor.Sphinx.PrimaryText
            inputTextView.font = kInputFont
        }
    }

    private var inputText: String {
        if inputTextView.textColor == NSColor.Sphinx.PlaceholderText {
            return ""
        }
        return inputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Intro

    private func appendIntroMessage() {
        appendAssistant("👋 Hi! I'm your Sphinx AI assistant. You can ask me to read recent messages or send messages to your contacts.\n\nMake sure you've set your AI provider and API key in **Profile → Advanced → Configure AI Agent**.")
    }

    // MARK: - Send Action

    @objc private func sendTapped() {
        let text = inputText
        guard !text.isEmpty else { return }

        // Clear input
        inputTextView.string = ""
        setPlaceholder()
        sendButton.isEnabled = false

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

    // MARK: - Transcript Helpers

    private func appendUser(_ text: String) {
        let storage = transcriptView.textStorage!
        let userAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont(name: "Roboto-Bold", size: 14) ?? NSFont.boldSystemFont(ofSize: 14),
            .foregroundColor: NSColor.Sphinx.Text
        ]
        storage.append(NSAttributedString(string: "You: \(text)\n\n", attributes: userAttrs))
        scrollToBottom()
    }

    private func appendAssistant(_ text: String) {
        let storage = transcriptView.textStorage!

        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont(name: "Roboto-Medium", size: 13) ?? NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.Sphinx.SecondaryText
        ]
        storage.append(NSAttributedString(string: "Sphinx AI: ", attributes: labelAttrs))

        let rendered = renderer.renderNS(text)
        let mutable = NSMutableAttributedString(attributedString: rendered)
        mutable.append(NSAttributedString(string: "\n\n"))
        storage.append(mutable)
        scrollToBottom()
    }

    private func appendError(_ message: String) {
        let storage = transcriptView.textStorage!
        let attrs: [NSAttributedString.Key: Any] = [
            .font: kTranscriptFont,
            .foregroundColor: NSColor.systemRed
        ]
        storage.append(NSAttributedString(string: "[Error: \(message)]\n\n", attributes: attrs))
        scrollToBottom()
    }

    private func scrollToBottom() {
        guard let storage = transcriptView.textStorage else { return }
        let range = NSRange(location: storage.length, length: 0)
        transcriptView.scrollRangeToVisible(range)
    }

    // MARK: - Loading State

    private func setLoading(_ loading: Bool) {
        sendButton.isEnabled = !loading
        inputTextView.isEditable = !loading
        spinner.isHidden = !loading
        if loading {
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
        }
    }
}

// MARK: - NSTextViewDelegate

extension AIAgentViewController: NSTextViewDelegate {

    func textDidChange(_ notification: Notification) {
        guard notification.object as? NSTextView === inputTextView else { return }

        let hasText = !inputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        sendButton.isEnabled = hasText
        sendButton.layer?.backgroundColor = hasText
            ? NSColor.Sphinx.PrimaryBlue.cgColor
            : NSColor.Sphinx.PrimaryBlue.withAlphaComponent(0.4).cgColor
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        // Send on Return (without Shift)
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                return false   // Shift+Return → newline
            }
            sendTapped()
            return true
        }
        return false
    }

    // Clear placeholder on begin editing
    func textViewDidChangeSelection(_ notification: Notification) {}

    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
        if textView === inputTextView {
            clearPlaceholder()
        }
        return true
    }
}
