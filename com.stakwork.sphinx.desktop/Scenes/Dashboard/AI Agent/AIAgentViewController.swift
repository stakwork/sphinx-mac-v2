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

    private let scrollView      = NSScrollView()
    private let transcriptView  = NSTextView()
    private let inputField      = NSTextField()
    private let sendButton      = NSButton()
    private let spinner         = NSProgressIndicator()
    private let bottomBarView   = NSView()
    private let divider         = NSBox()

    // MARK: - Renderer

    private let renderer = MarkdownRenderer()

    // MARK: - Lifecycle

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.Sphinx.Body.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupLayout()
        configureAppearance()
        appendIntroMessage()
    }

    // MARK: - Static Factory

    static func instantiate() -> AIAgentViewController {
        return AIAgentViewController()
    }

    // MARK: - Layout

    private func setupLayout() {
        // ── Bottom bar ──
        bottomBarView.wantsLayer = true
        bottomBarView.layer?.backgroundColor = NSColor.Sphinx.Body.cgColor
        view.addSubview(bottomBarView)
        bottomBarView.translatesAutoresizingMaskIntoConstraints = false

        // ── Divider ──
        divider.boxType = .separator
        view.addSubview(divider)
        divider.translatesAutoresizingMaskIntoConstraints = false

        // ── Scroll + Transcript ──
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        transcriptView.isEditable = false
        transcriptView.isSelectable = true
        transcriptView.drawsBackground = true
        transcriptView.backgroundColor = NSColor.Sphinx.Body
        transcriptView.textColor = NSColor.Sphinx.Text
        transcriptView.textContainerInset = NSSize(width: 12, height: 12)
        transcriptView.isAutomaticQuoteSubstitutionEnabled = false
        transcriptView.isAutomaticSpellingCorrectionEnabled = false
        transcriptView.translatesAutoresizingMaskIntoConstraints = false
        transcriptView.isVerticallyResizable = true
        transcriptView.isHorizontallyResizable = false
        transcriptView.textContainer?.widthTracksTextView = true
        scrollView.documentView = transcriptView

        // ── Input field ──
        inputField.placeholderString = "Ask Sphinx AI..."
        inputField.bezelStyle = .roundedBezel
        inputField.font = NSFont.systemFont(ofSize: 13)
        inputField.translatesAutoresizingMaskIntoConstraints = false
        inputField.target = self
        inputField.action = #selector(sendTapped)
        bottomBarView.addSubview(inputField)

        // ── Send button ──
        sendButton.title = "Send"
        sendButton.bezelStyle = .rounded
        sendButton.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.target = self
        sendButton.action = #selector(sendTapped)
        bottomBarView.addSubview(sendButton)

        // ── Spinner ──
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.isHidden = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        bottomBarView.addSubview(spinner)

        // ── Constraints ──
        NSLayoutConstraint.activate([
            // Bottom bar — pinned to bottom edge
            bottomBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBarView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomBarView.heightAnchor.constraint(equalToConstant: 54),

            // Divider — sits on top of bottom bar
            divider.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            divider.bottomAnchor.constraint(equalTo: bottomBarView.topAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),

            // Scroll view — fills everything above divider
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: divider.topAnchor),

            // Transcript — matches scroll view width
            transcriptView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            transcriptView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            transcriptView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),

            // Bottom bar contents
            inputField.leadingAnchor.constraint(equalTo: bottomBarView.leadingAnchor, constant: 12),
            inputField.centerYAnchor.constraint(equalTo: bottomBarView.centerYAnchor),
            inputField.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),

            sendButton.trailingAnchor.constraint(equalTo: spinner.leadingAnchor, constant: -6),
            sendButton.centerYAnchor.constraint(equalTo: bottomBarView.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 60),

            spinner.trailingAnchor.constraint(equalTo: bottomBarView.trailingAnchor, constant: -12),
            spinner.centerYAnchor.constraint(equalTo: bottomBarView.centerYAnchor),
            spinner.widthAnchor.constraint(equalToConstant: 20),
            spinner.heightAnchor.constraint(equalToConstant: 20),
        ])
    }

    private func configureAppearance() {
        view.layer?.backgroundColor = NSColor.Sphinx.Body.cgColor
    }

    // MARK: - Intro

    private func appendIntroMessage() {
        appendAssistant("👋 Hi! I'm your Sphinx AI assistant powered by Claude. You can ask me to read recent messages or send messages to your contacts.")
    }

    // MARK: - Send Action

    @objc private func sendTapped() {
        let text = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        inputField.stringValue = ""
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
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.Sphinx.Text
        ]
        let entry = NSMutableAttributedString(string: "You: \(text)\n\n", attributes: attrs)
        storage.append(entry)
        scrollToBottom()
    }

    private func appendAssistant(_ text: String) {
        let storage = transcriptView.textStorage!

        // Label
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.Sphinx.SecondaryText
        ]
        storage.append(NSAttributedString(string: "Sphinx AI: ", attributes: labelAttrs))

        // Rendered markdown body
        let rendered = renderer.renderNS(text)
        let mutable = NSMutableAttributedString(attributedString: rendered)
        mutable.append(NSAttributedString(string: "\n\n"))
        storage.append(mutable)
        scrollToBottom()
    }

    private func appendError(_ message: String) {
        let storage = transcriptView.textStorage!
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
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
        inputField.isEnabled = !loading
        spinner.isHidden = !loading
        if loading {
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
        }
    }
}
