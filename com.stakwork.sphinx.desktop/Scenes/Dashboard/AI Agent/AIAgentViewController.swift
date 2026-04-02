//
//  AIAgentViewController.swift
//  sphinx
//
//  Created by Sphinx on 01/04/2026.
//  Copyright © 2026 sphinx. All rights reserved.
//

import Cocoa

// MARK: - Padded text-field cell (12 pt left/right inset, matches chat pill)

private class PaddedTextFieldCell: NSTextFieldCell {
    private let inset: CGFloat = 12
    override func titleRect(forBounds rect: NSRect) -> NSRect {
        return rect.insetBy(dx: inset, dy: 0)
    }
    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        super.drawInterior(withFrame: titleRect(forBounds: cellFrame), in: controlView)
    }
    override func edit(withFrame rect: NSRect, in controlView: NSView, editor: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: titleRect(forBounds: rect), in: controlView, editor: editor, delegate: delegate, event: event)
    }
    override func select(withFrame rect: NSRect, in controlView: NSView, editor: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: titleRect(forBounds: rect), in: controlView, editor: editor, delegate: delegate, start: selStart, length: selLength)
    }
}

// MARK: - AIAgentViewController

final class AIAgentViewController: NSViewController {

    // MARK: - Views

    private let scrollView      = NSScrollView()
    private let transcriptView  = NSTextView()
    private let bottomBarView   = NSView()
    private let divider         = NSBox()
    private let inputField      = NSTextField()
    private let sendButton      = NSButton()
    private let spinner         = NSProgressIndicator()

    // MARK: - Renderer
    private let renderer = MarkdownRenderer()

    // MARK: - Constants
    private let kBottomBarHeight: CGFloat    = 72
    private let kSendButtonSize: CGFloat     = 40
    private let kInputCornerRadius: CGFloat  = 20
    private let kInputFont = NSFont(name: "Roboto-Regular", size: 16.0) ?? NSFont.systemFont(ofSize: 16)
    private let kTranscriptFont = NSFont(name: "Roboto-Regular", size: 15.0) ?? NSFont.systemFont(ofSize: 15)

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

    // MARK: - Static Factory

    static func instantiate() -> AIAgentViewController {
        return AIAgentViewController()
    }

    // MARK: - Layout

    private func setupLayout() {
        let hPad: CGFloat = 12
        let vPad: CGFloat = 16
        let inputH: CGFloat = kBottomBarHeight - vPad * 2   // 40 pt — matches send button

        // ── Bottom bar ───────────────────────────────────────────────────────
        bottomBarView.wantsLayer = true
        bottomBarView.layer?.backgroundColor = NSColor.Sphinx.Body.cgColor
        bottomBarView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomBarView)

        // ── Divider ──────────────────────────────────────────────────────────
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(divider)

        // ── Transcript scroll view ────────────────────────────────────────────
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
        scrollView.documentView = transcriptView

        // ── Input field — swap cell for padded variant ────────────────────────
        let paddedCell = PaddedTextFieldCell()
        paddedCell.usesSingleLineMode    = true
        paddedCell.isScrollable          = true
        paddedCell.wraps                 = false
        paddedCell.font                  = kInputFont
        paddedCell.textColor             = NSColor.Sphinx.PrimaryText
        paddedCell.backgroundColor       = NSColor.Sphinx.ReceivedMsgBG
        paddedCell.placeholderAttributedString = NSAttributedString(
            string: "Ask Sphinx AI...",
            attributes: [
                .font: kInputFont,
                .foregroundColor: NSColor.Sphinx.PlaceholderText
            ]
        )

        inputField.cell = paddedCell
        inputField.font = kInputFont
        inputField.isBordered   = false
        inputField.isBezeled    = false
        inputField.drawsBackground  = true
        inputField.backgroundColor  = NSColor.Sphinx.ReceivedMsgBG
        inputField.focusRingType    = .none
        inputField.wantsLayer       = true
        inputField.layer?.cornerRadius  = kInputCornerRadius
        inputField.layer?.masksToBounds = true
        inputField.translatesAutoresizingMaskIntoConstraints = false
        inputField.target = self
        inputField.action = #selector(sendTapped)
        bottomBarView.addSubview(inputField)

        NotificationCenter.default.addObserver(
            self, selector: #selector(inputDidChange),
            name: NSTextField.textDidChangeNotification,
            object: inputField
        )

        // ── Send button (circle, PrimaryBlue) ────────────────────────────────
        sendButton.isBordered = false
        sendButton.wantsLayer = true
        sendButton.layer?.cornerRadius  = kSendButtonSize / 2
        sendButton.layer?.masksToBounds = true
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
        sendButton.target = self
        sendButton.action = #selector(sendTapped)
        sendButton.isEnabled = false
        bottomBarView.addSubview(sendButton)

        // ── Spinner ───────────────────────────────────────────────────────────
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.isHidden = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        bottomBarView.addSubview(spinner)

        // ── Constraints ───────────────────────────────────────────────────────
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

            // Transcript — fills everything above divider
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: divider.topAnchor),

            // Input field
            inputField.leadingAnchor.constraint(equalTo: bottomBarView.leadingAnchor, constant: hPad),
            inputField.centerYAnchor.constraint(equalTo: bottomBarView.centerYAnchor),
            inputField.heightAnchor.constraint(equalToConstant: inputH),
            inputField.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),

            // Send button
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

    // MARK: - Send Action

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
        let storage = transcriptView.textStorage!
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont(name: "Roboto-Bold", size: 14) ?? NSFont.boldSystemFont(ofSize: 14),
            .foregroundColor: NSColor.Sphinx.Text
        ]
        storage.append(NSAttributedString(string: "You: \(text)\n\n", attributes: attrs))
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
        let mutable  = NSMutableAttributedString(attributedString: rendered)
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
        transcriptView.scrollRangeToVisible(NSRange(location: storage.length, length: 0))
    }

    // MARK: - Loading state

    private func setLoading(_ loading: Bool) {
        sendButton.isEnabled  = !loading
        inputField.isEnabled  = !loading
        spinner.isHidden      = !loading
        if loading {
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
            view.window?.makeFirstResponder(inputField)
        }
    }
}
