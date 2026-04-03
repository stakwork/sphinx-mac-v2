//
//  AIAgentViewController.swift
//  sphinx
//
//  Created by Sphinx on 01/04/2026.
//  Copyright © 2026 sphinx. All rights reserved.
//

import Cocoa

// A flipped clip view so that (0,0) is top-left and content flows top→bottom,
// matching NSStackView's natural vertical layout direction.
private final class FlippedClipView: NSClipView {
    override var isFlipped: Bool { true }
}

final class AIAgentViewController: NSViewController {

    // MARK: - Views
    private let scrollView    = NSScrollView()
    private let stackView     = NSStackView()
    private let bottomBarView = NSView()
    private let divider       = NSBox()
    private let pillView      = NSView()
    private let inputField    = PlaceHolderTextView()
    private let sendButton    = NSView()
    private let spinner       = NSProgressIndicator()

    // MARK: - Renderer
    // lazy so kTranscriptFont (Roboto 14pt) is used as the renderer's base font,
    // making every attributed-string run use the same NSFont as label.font.
    // This eliminates the AppKit selection-redraw font mismatch on received messages.
    private lazy var renderer = MarkdownRenderer(
        style: MarkdownStyle(baseFontSize: 14, baseFont: kTranscriptFont)
    )

    // MARK: - Constants
    private let kUnitSize: CGFloat        = 36
    private let kBottomBarHeight: CGFloat = 60
    private let kHPad: CGFloat            = 12
    private let kMaxInputLines: CGFloat   = 5
    private let kInputLineHeight: CGFloat = 19
    private let kVerticalPadding: CGFloat = 24   // top + bottom pill insets
    private let kInputFont      = NSFont(name: "Roboto-Regular", size: 15.0) ?? NSFont.systemFont(ofSize: 15)
    private let kTranscriptFont = NSFont(name: "Roboto-Regular", size: 14.0) ?? NSFont.systemFont(ofSize: 14)

    // MARK: - State
    private var introAppended     = false
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
            rebuildTranscriptOrShowIntro()
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(inputField)
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: .aiAgentReconfigured, object: nil)
    }

    // MARK: - Factory
    static func instantiate() -> AIAgentViewController { AIAgentViewController() }

    // MARK: - Layout

    private func setupLayout() {
        // ── Bottom bar ─────────────────────────────────────────────────────────
        bottomBarView.wantsLayer = true
        bottomBarView.layer?.backgroundColor = NSColor.Sphinx.HeaderBG.cgColor
        bottomBarView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomBarView)

        // ── Divider ────────────────────────────────────────────────────────────
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(divider)

        // ── Transcript scroll ──────────────────────────────────────────────────
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers  = true
        scrollView.drawsBackground     = true
        scrollView.backgroundColor     = NSColor.Sphinx.Body
        scrollView.contentView.backgroundColor = NSColor.Sphinx.Body
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        stackView.orientation  = .vertical
        stackView.alignment    = .leading
        stackView.spacing      = 8
        stackView.edgeInsets   = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let clipView = FlippedClipView()
        clipView.drawsBackground = true
        clipView.backgroundColor = NSColor.Sphinx.Body
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

        // ── Input field (PlaceHolderTextView / NSTextView) ─────────────────────
        inputField.isEditable              = true
        inputField.isRichText              = false
        inputField.drawsBackground         = false
        inputField.isBordered              = false
        inputField.font                    = kInputFont
        inputField.textColor               = NSColor.Sphinx.PrimaryText
        // typingAttributes must be set so every typed character picks up
        // the correct font + colour (NSTextView won't inherit them automatically).
        inputField.typingAttributes = [
            .font:            kInputFont as Any,
            .foregroundColor: NSColor.Sphinx.PrimaryText as Any,
        ]
        inputField.isAutomaticQuoteSubstitutionEnabled  = false
        inputField.isAutomaticSpellingCorrectionEnabled = false
        inputField.lineBreakEnable = true   // Shift+Return inserts \n
        inputField.delegate        = self   // NSTextViewDelegate: Return → send
        inputField.setPlaceHolder(
            color:  NSColor.Sphinx.PlaceholderText,
            font:   kInputFont,
            string: "Ask Sphinx AI..."
        )
        // Allow vertical growth; fix width to the scroll view so text wraps.
        inputField.isVerticallyResizable   = true
        inputField.isHorizontallyResizable = false
        inputField.textContainer?.widthTracksTextView = true
        // Height is unbounded; width is managed by widthTracksTextView (leave at default 0).
        inputField.textContainer?.containerSize = NSSize(
            width:  0,
            height: CGFloat.greatestFiniteMagnitude
        )
        inputField.translatesAutoresizingMaskIntoConstraints = false

        // Wrap in a scroll view so long content scrolls inside the fixed pill.
        let inputScrollView = NSScrollView()
        inputScrollView.hasVerticalScroller = false
        inputScrollView.drawsBackground     = false
        inputScrollView.contentView.backgroundColor = .clear   // don't paint over pill bg
        inputScrollView.documentView        = inputField
        inputScrollView.translatesAutoresizingMaskIntoConstraints = false
        pillView.addSubview(inputScrollView)

        NSLayoutConstraint.activate([
            inputScrollView.leadingAnchor.constraint(equalTo: pillView.leadingAnchor,  constant:  12),
            inputScrollView.trailingAnchor.constraint(equalTo: pillView.trailingAnchor, constant: -12),
            inputScrollView.topAnchor.constraint(equalTo: pillView.topAnchor,     constant:  8),
            inputScrollView.bottomAnchor.constraint(equalTo: pillView.bottomAnchor, constant: -8),
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onAgentReconfigured),
            name: .aiAgentReconfigured,
            object: nil
        )

        // ── Send button ────────────────────────────────────────────────────────
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

        // Store mutable constraints for dynamic height updates
        bottomBarHeightConstraint = bottomBarView.heightAnchor.constraint(equalToConstant: kBottomBarHeight)
        pillHeightConstraint = pillView.heightAnchor.constraint(equalToConstant: kUnitSize)

        NSLayoutConstraint.activate([
            // Bottom bar — dynamic height (grows with input)
            bottomBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBarView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomBarHeightConstraint,

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

            // Pill — fixed height, centred in bottom bar, right butts send button
            pillView.leadingAnchor.constraint(equalTo: bottomBarView.leadingAnchor, constant: kHPad),
            pillView.topAnchor.constraint(equalTo: bottomBarView.topAnchor, constant: 12),
            pillHeightConstraint,
            pillView.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),

            // Send button — kUnitSize circle, centred, right margin
            sendButton.trailingAnchor.constraint(equalTo: bottomBarView.trailingAnchor, constant: -kHPad),
            sendButton.bottomAnchor.constraint(equalTo: bottomBarView.bottomAnchor, constant: -12),
            sendButton.widthAnchor.constraint(equalToConstant: kUnitSize),
            sendButton.heightAnchor.constraint(equalToConstant: kUnitSize),

            // Spinner over send button
            spinner.centerXAnchor.constraint(equalTo: sendButton.centerXAnchor),
            spinner.bottomAnchor.constraint(equalTo: bottomBarView.bottomAnchor, constant: -12),
            spinner.widthAnchor.constraint(equalToConstant: 20),
            spinner.heightAnchor.constraint(equalToConstant: 20),
        ])
    }

    // MARK: - Input change

    @objc private func inputDidChange() {
        let hasText = !inputField.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        sendButtonEnabled = hasText
        sendButton.layer?.backgroundColor = hasText
            ? NSColor.Sphinx.PrimaryBlue.cgColor
            : NSColor.Sphinx.PrimaryBlue.withAlphaComponent(0.4).cgColor
    }

    // MARK: - Dynamic height

    private func updateBottomBarHeight() {
        let contentH    = inputField.contentSize.height
        let maxContentH = kInputLineHeight * kMaxInputLines
        let clampedH    = min(contentH, maxContentH)
        let newPillH    = max(kUnitSize, clampedH + kVerticalPadding)
        let newBarH     = newPillH + 24   // 12pt top + 12pt bottom margin

        pillHeightConstraint.constant      = newPillH
        bottomBarHeightConstraint.constant = newBarH

        // Full circle when single-line, rounded rect when multiline
        pillView.layer?.cornerRadius = (newPillH == kUnitSize) ? kUnitSize / 2 : 12

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            view.layoutSubtreeIfNeeded()
        }
    }

    // MARK: - Intro / Transcript rebuild

    private func rebuildTranscriptOrShowIntro() {
        let history = AIAgentManager.sharedInstance.conversationHistory
        if history.isEmpty {
            appendIntroMessage()
        } else {
            for msg in history {
                switch msg {
                case .user(let userMsg):
                    if case .text(let t) = userMsg.content { appendUser(t) }
                case .assistant(let assistantMsg):
                    if case .text(let t) = assistantMsg.content { appendAssistant(t) }
                default:
                    break
                }
            }
        }
        updateInputState()
    }

    private func appendIntroMessage() {
        let text: String
        if AIAgentManager.sharedInstance.isConfigured {
            text = "👋 Hi! I'm your Sphinx AI assistant. I can read recent messages or send messages to your contacts and tribes."
        } else {
            text = "Configure your provider and API key in **Profile → Advanced → Configure AI Agent** to get started."
        }
        AIAgentManager.sharedInstance.appendAssistantMessage(text)
        appendAssistant(text)
    }

    private func updateInputState() {
        let configured = AIAgentManager.sharedInstance.isConfigured
        inputField.isEditable = configured
        sendButtonEnabled = configured && !inputField.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        pillView.layer?.opacity = configured ? 1.0 : 0.5
        sendButton.layer?.backgroundColor = configured
            ? NSColor.Sphinx.PrimaryBlue.withAlphaComponent(0.4).cgColor
            : NSColor.Sphinx.PrimaryBlue.withAlphaComponent(0.2).cgColor
    }

    @objc private func onAgentReconfigured() {
        updateInputState()
    }

    // MARK: - Send

    @objc private func sendTapped() {
        guard sendButtonEnabled else { return }
        let text = inputField.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        inputField.string = ""
        inputDidChange()
        updateBottomBarHeight()
        appendUser(text)
        setLoading(true)

        Task {
            let response = await AIAgentManager.sharedInstance.chat(text)
            await MainActor.run {
                self.appendAssistant(response)
                self.setLoading(false)
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
        // Set font and textColor BEFORE attributedStringValue.
        // AppKit uses these as the fallback during selection redraw — they must
        // match what the attributed string actually contains to avoid a size jump.
        label.font      = kTranscriptFont
        label.textColor = NSColor.Sphinx.Text
        if let rendered = markdownRendered {
            label.attributedStringValue = rendered
        } else {
            label.stringValue = text
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
        NSLayoutConstraint.activate([
            bubble.widthAnchor.constraint(
                equalTo: stackView.widthAnchor,
                constant: -(stackView.edgeInsets.left + stackView.edgeInsets.right)
            ),
        ])
        scrollToBottom()
    }

    private func appendAssistant(_ text: String) {
        let rendered = renderer.renderNS(text)
        let bubble   = makeBubble(text: text, isUser: false, markdownRendered: rendered)
        stackView.addArrangedSubview(bubble)
        NSLayoutConstraint.activate([
            bubble.widthAnchor.constraint(
                equalTo: stackView.widthAnchor,
                constant: -(stackView.edgeInsets.left + stackView.edgeInsets.right)
            ),
        ])
        scrollToBottom()
    }

    private func appendError(_ message: String) {
        let bubble = makeBubble(text: "[Error: \(message)]", isUser: false)
        bubble.subviews.first?.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.15).cgColor
        stackView.addArrangedSubview(bubble)
        NSLayoutConstraint.activate([
            bubble.widthAnchor.constraint(
                equalTo: stackView.widthAnchor,
                constant: -(stackView.edgeInsets.left + stackView.edgeInsets.right)
            ),
        ])
        scrollToBottom()
    }

    private func scrollToBottom() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let docView = self.scrollView.documentView else { return }
            let docHeight  = docView.frame.height
            let clipHeight = self.scrollView.contentView.bounds.height
            let y = max(0, docHeight - clipHeight)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                ctx.allowsImplicitAnimation = true
                self.scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
                self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
            }
        }
    }

    // MARK: - Loading state

    private func setLoading(_ loading: Bool) {
        sendButton.isHidden = loading
        spinner.isHidden    = !loading
        if loading {
            inputField.isEditable = false
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
            updateInputState()
            view.window?.makeFirstResponder(inputField)
        }
    }
}

// MARK: - NSTextViewDelegate

extension AIAgentViewController: NSTextViewDelegate {

    func textView(
        _ textView: NSTextView,
        shouldChangeTextIn affectedCharRange: NSRange,
        replacementString: String?
    ) -> Bool {
        // Plain Return → send. Shift+Return is handled inside PlaceHolderTextView.addingBreakLine.
        if let str = replacementString, str == "\n" {
            sendTapped()
            return false
        }
        return true
    }

    override func textDidChange(_ notification: Notification) {
        inputDidChange()
    }
}
