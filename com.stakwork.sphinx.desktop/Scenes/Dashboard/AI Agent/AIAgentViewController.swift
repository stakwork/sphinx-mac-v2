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
    private let scrollView    = NSScrollView()
    private let stackView     = NSStackView()
    private let bottomBarView = NSView()
    private let divider       = NSBox()
    private let pillView      = NSView()
    private let inputField    = NSTextField()
    // NSView-based send button — exact kUnitSize × kUnitSize circle, no NSButton chrome
    private let sendButton    = NSView()
    private let spinner       = NSProgressIndicator()

    // MARK: - Renderer
    private let renderer = MarkdownRenderer()

    // MARK: - Constants
    private let kUnitSize: CGFloat        = 36
    private let kBottomBarHeight: CGFloat = 60
    private let kHPad: CGFloat            = 12
    private let kInputFont      = NSFont(name: "Roboto-Regular", size: 15.0) ?? NSFont.systemFont(ofSize: 15)
    private let kTranscriptFont = NSFont(name: "Roboto-Regular", size: 14.0) ?? NSFont.systemFont(ofSize: 14)

    // MARK: - State
    private var introAppended    = false
    private var sendButtonEnabled = false

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
        let w = scrollView.bounds.width
        if !introAppended && w > 0 {
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

        // NSStackView as documentView — bubbles stack vertically
        stackView.orientation  = .vertical
        stackView.alignment    = .leading
        stackView.spacing      = 8
        stackView.edgeInsets   = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let clipView = NSClipView()
        scrollView.contentView = clipView
        scrollView.documentView = stackView

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: clipView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
        ])

        // ── Pill container ─────────────────────────────────────────────────────
        pillView.wantsLayer = true
        pillView.layer?.cornerRadius    = kUnitSize / 2
        pillView.layer?.masksToBounds   = true
        pillView.layer?.backgroundColor = NSColor.Sphinx.ReceivedMsgBG.cgColor
        pillView.translatesAutoresizingMaskIntoConstraints = false
        bottomBarView.addSubview(pillView)

        // ── Input field ────────────────────────────────────────────────────────
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

        // ── Send button — plain NSView, exact kUnitSize × kUnitSize circle ─────
        sendButton.wantsLayer = true
        sendButton.layer?.cornerRadius    = kUnitSize / 2
        sendButton.layer?.masksToBounds   = true
        sendButton.layer?.backgroundColor = NSColor.Sphinx.PrimaryBlue.withAlphaComponent(0.4).cgColor
        sendButton.translatesAutoresizingMaskIntoConstraints = false

        let iconView = NSImageView()
        if let img = NSImage(systemSymbolName: "paperplane.fill", accessibilityDescription: "Send") {
            iconView.image = img.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            )
        }
        iconView.contentTintColor = .white
        iconView.translatesAutoresizingMaskIntoConstraints = false
        sendButton.addSubview(iconView)

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: sendButton.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: sendButton.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
        ])

        let click = NSClickGestureRecognizer(target: self, action: #selector(sendTapped))
        sendButton.addGestureRecognizer(click)
        bottomBarView.addSubview(sendButton)

        // ── Spinner ────────────────────────────────────────────────────────────
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

            // Transcript fills everything above divider
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: divider.topAnchor),

            // Pill: kUnitSize tall, left=kHPad, right butts send button
            pillView.leadingAnchor.constraint(equalTo: bottomBarView.leadingAnchor, constant: kHPad),
            pillView.centerYAnchor.constraint(equalTo: bottomBarView.centerYAnchor),
            pillView.heightAnchor.constraint(equalToConstant: kUnitSize),
            pillView.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),

            // Input field: 12pt L/R inset, centred
            inputField.leadingAnchor.constraint(equalTo: pillView.leadingAnchor, constant: 12),
            inputField.trailingAnchor.constraint(equalTo: pillView.trailingAnchor, constant: -12),
            inputField.centerYAnchor.constraint(equalTo: pillView.centerYAnchor),

            // Send button: exact kUnitSize × kUnitSize, right margin = kHPad
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
        sendButtonEnabled = hasText
        sendButton.layer?.backgroundColor = hasText
            ? NSColor.Sphinx.PrimaryBlue.cgColor
            : NSColor.Sphinx.PrimaryBlue.withAlphaComponent(0.4).cgColor
    }

    // MARK: - Intro

    private func appendIntroMessage() {
        appendAssistant("👋 Hi! I'm your Sphinx AI assistant. I can read recent messages or send messages to your contacts.\n\nConfigure your provider and API key in **Profile → Advanced → Configure AI Agent**.")
    }

    // MARK: - Send

    @objc private func sendTapped() {
        guard sendButtonEnabled else { return }
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

    // MARK: - Bubble helper

    private func makeBubble(text: String, isUser: Bool, markdownRendered: NSAttributedString? = nil) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let bubble = NSView()
        bubble.wantsLayer = true
        bubble.layer?.cornerRadius    = 12
        bubble.layer?.masksToBounds   = true
        bubble.layer?.backgroundColor = isUser
            ? NSColor.Sphinx.SentMsgBG.cgColor
            : NSColor.Sphinx.ReceivedMsgBG.cgColor
        bubble.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(wrappingLabelWithString: "")
        if let rendered = markdownRendered {
            label.attributedStringValue = rendered
        } else {
            label.stringValue = text
            label.font        = kTranscriptFont
            label.textColor   = NSColor.Sphinx.Text
        }
        label.isEditable      = false
        label.isSelectable    = true
        label.drawsBackground = false
        label.isBordered      = false
        label.translatesAutoresizingMaskIntoConstraints = false
        bubble.addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -8),
            label.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -10),
            label.widthAnchor.constraint(lessThanOrEqualToConstant: 480),
        ])

        row.addSubview(bubble)

        if isUser {
            NSLayoutConstraint.activate([
                bubble.topAnchor.constraint(equalTo: row.topAnchor),
                bubble.bottomAnchor.constraint(equalTo: row.bottomAnchor),
                bubble.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            ])
        } else {
            NSLayoutConstraint.activate([
                bubble.topAnchor.constraint(equalTo: row.topAnchor),
                bubble.bottomAnchor.constraint(equalTo: row.bottomAnchor),
                bubble.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            ])
        }

        return row
    }

    // MARK: - Transcript helpers

    private func appendUser(_ text: String) {
        let bubble = makeBubble(text: text, isUser: true)
        stackView.addArrangedSubview(bubble)
        // Stretch row full width so trailing constraint resolves correctly
        NSLayoutConstraint.activate([
            bubble.widthAnchor.constraint(equalTo: stackView.widthAnchor,
                                          constant: -(stackView.edgeInsets.left + stackView.edgeInsets.right)),
        ])
        scrollToBottom()
    }

    private func appendAssistant(_ text: String) {
        let rendered = renderer.renderNS(text)
        let bubble   = makeBubble(text: text, isUser: false, markdownRendered: rendered)
        stackView.addArrangedSubview(bubble)
        NSLayoutConstraint.activate([
            bubble.widthAnchor.constraint(equalTo: stackView.widthAnchor,
                                          constant: -(stackView.edgeInsets.left + stackView.edgeInsets.right)),
        ])
        scrollToBottom()
    }

    private func appendError(_ message: String) {
        let bubble = makeBubble(text: "[Error: \(message)]", isUser: false)
        // Tint error bubble red
        bubble.subviews.first?.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.15).cgColor
        stackView.addArrangedSubview(bubble)
        NSLayoutConstraint.activate([
            bubble.widthAnchor.constraint(equalTo: stackView.widthAnchor,
                                          constant: -(stackView.edgeInsets.left + stackView.edgeInsets.right)),
        ])
        scrollToBottom()
    }

    private func scrollToBottom() {
        guard let docView = scrollView.documentView else { return }
        let bottom = NSPoint(x: 0, y: max(0, docView.frame.height - scrollView.contentView.bounds.height))
        scrollView.contentView.scroll(to: bottom)
        scrollView.reflectScrolledClipView(scrollView.contentView)
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
