//
//  ProposalApprovalCardView.swift
//  Sphinx
//
//  Created on 2026-06-24.
//  Copyright © 2026 Sphinx. All rights reserved.
//

import Cocoa

final class ProposalApprovalCardView: NSView {

    // MARK: - Callbacks
    var onApprove: ((String) -> Void)?
    var onReject: ((String) -> Void)?
    var onDismiss: (() -> Void)?

    // MARK: - State
    private let proposalId: String
    private(set) var isActioned: Bool = false
    private var isLoading: Bool = false

    // MARK: - Dynamic height constraints
    private var titleHeightConstraint: NSLayoutConstraint?
    private var descHeightConstraint: NSLayoutConstraint?
    private var errorHeightConstraint: NSLayoutConstraint?

    // MARK: - Subviews

    private let badgeLabel: NSTextField = {
        let tf = NSTextField(labelWithString: "")
        tf.font = NSFont(name: "Roboto-Bold", size: 12) ?? NSFont.boldSystemFont(ofSize: 12)
        tf.textColor = .white
        tf.alignment = .center
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.wantsLayer = true
        tf.layer?.cornerRadius = 4
        tf.isEditable = false
        tf.isSelectable = false
        return tf
    }()

    private let titleLabel: NSTextField = {
        let tf = NSTextField(wrappingLabelWithString: "")
        tf.font = NSFont(name: "Roboto-Bold", size: 13) ?? NSFont.boldSystemFont(ofSize: 13)
        tf.textColor = NSColor.Sphinx.Text
        tf.maximumNumberOfLines = 2
        tf.translatesAutoresizingMaskIntoConstraints = false
        return tf
    }()

    private let descLabel: NSTextField = {
        let tf = NSTextField(wrappingLabelWithString: "")
        tf.font = NSFont(name: "Roboto-Regular", size: 11) ?? NSFont.systemFont(ofSize: 11)
        tf.textColor = NSColor.Sphinx.SecondaryText
        tf.maximumNumberOfLines = 3
        tf.translatesAutoresizingMaskIntoConstraints = false
        return tf
    }()

    private let approveButton: CustomButton = {
        let btn = CustomButton(title: "Approve", target: nil, action: nil)
        btn.wantsLayer = true
        btn.isBordered = false
        btn.layer?.backgroundColor = NSColor.Sphinx.PrimaryBlue.cgColor
        btn.layer?.cornerRadius = 8
        btn.contentTintColor = .white
        btn.font = NSFont(name: "Roboto-Medium", size: 12) ?? NSFont.systemFont(ofSize: 12, weight: .medium)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.cursor = .pointingHand
        return btn
    }()

    private let rejectButton: CustomButton = {
        let btn = CustomButton(title: "Reject", target: nil, action: nil)
        btn.wantsLayer = true
        btn.isBordered = false
        btn.layer?.backgroundColor = NSColor.Sphinx.PrimaryBlue.withAlphaComponent(0.15).cgColor
        btn.layer?.cornerRadius = 8
        btn.contentTintColor = NSColor.Sphinx.PrimaryBlue
        btn.font = NSFont(name: "Roboto-Medium", size: 12) ?? NSFont.systemFont(ofSize: 12, weight: .medium)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.cursor = .pointingHand
        return btn
    }()

    private let stampLabel: NSTextField = {
        let tf = NSTextField(labelWithString: "")
        tf.font = NSFont(name: "Roboto-Bold", size: 14) ?? NSFont.boldSystemFont(ofSize: 14)
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.isEditable = false
        tf.isSelectable = false
        tf.alignment = .center
        tf.isHidden = true
        return tf
    }()

    private let dismissButton: CustomButton = {
        let btn = CustomButton(title: "✕", target: nil, action: nil)
        btn.bezelStyle = .inline
        btn.isBordered = false
        btn.font = NSFont.systemFont(ofSize: 11)
        btn.contentTintColor = NSColor.Sphinx.SecondaryText
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.cursor = .pointingHand
        return btn
    }()

    private let spinner: NSProgressIndicator = {
        let s = NSProgressIndicator()
        s.style = .spinning
        s.controlSize = .small
        s.isIndeterminate = true
        s.isHidden = true
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private let errorLabel: NSTextField = {
        let tf = NSTextField(wrappingLabelWithString: "")
        tf.font = NSFont(name: "Roboto-Regular", size: 11) ?? NSFont.systemFont(ofSize: 11)
        tf.textColor = NSColor.systemRed
        tf.maximumNumberOfLines = 2
        tf.isHidden = true
        tf.translatesAutoresizingMaskIntoConstraints = false
        return tf
    }()

    // MARK: - Init

    init(proposal: AIAgentManager.PendingProposal) {
        self.proposalId = proposal.proposalId
        super.init(frame: .zero)
        configure(with: proposal)
        setupLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    // MARK: - Configuration

    private func configure(with proposal: AIAgentManager.PendingProposal) {
        let (badgeText, badgeColor) = kindAttributes(for: proposal.kind)
        badgeLabel.stringValue = " \(badgeText) "
        badgeLabel.wantsLayer = true
        badgeLabel.layer?.backgroundColor = badgeColor.cgColor

        titleLabel.stringValue = proposal.title
        descLabel.stringValue = proposal.description ?? ""
        descLabel.isHidden = (proposal.description == nil || proposal.description?.isEmpty == true)
    }

    private func kindAttributes(for kind: String) -> (String, NSColor) {
        switch kind.lowercased() {
        case "initiative": return ("Initiative", NSColor.systemPurple)
        case "milestone":  return ("Milestone",  NSColor.systemOrange)
        default:           return ("Feature",    NSColor.Sphinx.PrimaryBlue)
        }
    }

    // MARK: - Layout

    private func setupLayout() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.Sphinx.ReceivedMsgBG.cgColor
        layer?.cornerRadius = 10
        layer?.borderWidth = 0

        // Subtle shadow for elevation without border
        shadow = NSShadow()
        shadow?.shadowColor = NSColor.black.withAlphaComponent(0.10)
        shadow?.shadowOffset = NSSize(width: 0, height: -2)
        shadow?.shadowBlurRadius = 6

        [badgeLabel, titleLabel, descLabel, approveButton, rejectButton,
         stampLabel, dismissButton, spinner, errorLabel].forEach { addSubview($0) }

        approveButton.target = self
        approveButton.action = #selector(handleApprove)
        rejectButton.target = self
        rejectButton.action = #selector(handleReject)
        dismissButton.target = self
        dismissButton.action = #selector(handleDismiss)

        NSLayoutConstraint.activate([
            // Dismiss button — top right
            dismissButton.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            dismissButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            dismissButton.widthAnchor.constraint(equalToConstant: 20),
            dismissButton.heightAnchor.constraint(equalToConstant: 20),

            // Badge — vertically centered in its row (alongside dismiss button row)
            badgeLabel.centerYAnchor.constraint(equalTo: dismissButton.centerYAnchor),
            badgeLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),

            // Title
            titleLabel.topAnchor.constraint(equalTo: dismissButton.bottomAnchor, constant: 6),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            // Description
            descLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            descLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            descLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            // Error label (below desc, above buttons)
            errorLabel.topAnchor.constraint(equalTo: descLabel.bottomAnchor, constant: 6),
            errorLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            errorLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            // Approve / Reject buttons row
            approveButton.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 8),
            approveButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            approveButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            approveButton.heightAnchor.constraint(equalToConstant: 28),
            approveButton.widthAnchor.constraint(equalToConstant: 80),

            rejectButton.topAnchor.constraint(equalTo: approveButton.topAnchor),
            rejectButton.leadingAnchor.constraint(equalTo: approveButton.trailingAnchor, constant: 8),
            rejectButton.heightAnchor.constraint(equalToConstant: 28),
            rejectButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            rejectButton.widthAnchor.constraint(equalToConstant: 70),

            // Spinner — trailing the reject button
            spinner.centerYAnchor.constraint(equalTo: approveButton.centerYAnchor),
            spinner.leadingAnchor.constraint(equalTo: rejectButton.trailingAnchor, constant: 10),
            spinner.widthAnchor.constraint(equalToConstant: 16),
            spinner.heightAnchor.constraint(equalToConstant: 16),

            // Stamp label (hidden by default, replaces buttons when actioned)
            stampLabel.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 8),
            stampLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stampLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stampLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            stampLabel.heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        let textWidth = bounds.width - 24
        guard textWidth > 0 else { return }

        let titleH = ceil(textHeight(for: titleLabel, maxLines: 2, maxWidth: textWidth))
        let descH = descLabel.isHidden ? 0 : ceil(textHeight(for: descLabel, maxLines: 3, maxWidth: textWidth))
        let errH = errorLabel.isHidden ? 0 : ceil(textHeight(for: errorLabel, maxLines: 2, maxWidth: textWidth))

        var changed = false

        if let c = titleHeightConstraint {
            if abs(c.constant - titleH) > 0.5 { c.constant = titleH; changed = true }
        } else if titleH > 0 {
            let c = titleLabel.heightAnchor.constraint(equalToConstant: titleH)
            c.isActive = true
            titleHeightConstraint = c
            changed = true
        }

        if let c = descHeightConstraint {
            if abs(c.constant - descH) > 0.5 { c.constant = descH; changed = true }
        } else {
            let c = descLabel.heightAnchor.constraint(equalToConstant: descH)
            c.isActive = true
            descHeightConstraint = c
            changed = true
        }

        if let c = errorHeightConstraint {
            if abs(c.constant - errH) > 0.5 { c.constant = errH; changed = true }
        } else {
            let c = errorLabel.heightAnchor.constraint(equalToConstant: errH)
            c.isActive = true
            errorHeightConstraint = c
            changed = true
        }

        if changed { superview?.needsLayout = true }
    }

    private func textHeight(for field: NSTextField, maxLines: Int, maxWidth: CGFloat) -> CGFloat {
        let attrStr = field.attributedStringValue
        guard attrStr.length > 0 else { return 0 }
        let rect = attrStr.boundingRect(
            with: NSSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        if let font = attrStr.attribute(.font, at: 0, effectiveRange: nil) as? NSFont {
            let lineH = font.ascender - font.descender + font.leading
            return min(rect.height, lineH * CGFloat(maxLines))
        }
        return rect.height
    }

    // MARK: - Actions

    @objc private func handleApprove() {
        guard !isActioned, !isLoading else { return }
        showLoading()
        onApprove?(proposalId)
    }

    @objc private func handleReject() {
        guard !isActioned, !isLoading else { return }
        showLoading()
        onReject?(proposalId)
    }

    @objc private func handleDismiss() {
        if let onDismiss = onDismiss {
            // Let the host VC handle cleanup (inset restoration etc.)
            onDismiss()
        } else {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                animator().alphaValue = 0
            }, completionHandler: {
                self.removeFromSuperview()
            })
        }
    }

    // MARK: - State Machine

    func showLoading() {
        guard !isActioned, !isLoading else { return }
        isLoading = true
        approveButton.isEnabled = false
        rejectButton.isEnabled = false
        spinner.isHidden = false
        spinner.startAnimation(nil)
        errorLabel.isHidden = true
    }

    func showError(_ message: String) {
        isLoading = false
        spinner.stopAnimation(nil)
        spinner.isHidden = true
        approveButton.isEnabled = true
        rejectButton.isEnabled = true
        approveButton.isHidden = false
        rejectButton.isHidden = false
        stampLabel.isHidden = true
        errorLabel.font = NSFont(name: "Roboto-Regular", size: 11) ?? NSFont.systemFont(ofSize: 11)
        errorLabel.textColor = NSColor.systemRed
        errorLabel.stringValue = message
        errorLabel.isHidden = false
        needsLayout = true
    }

    func showStamp(approved: Bool) {
        isActioned = true
        isLoading = false
        spinner.stopAnimation(nil)
        spinner.isHidden = true
        approveButton.isHidden = true
        rejectButton.isHidden = true
        stampLabel.isHidden = true

        errorLabel.font = NSFont(name: "Roboto-Bold", size: 11) ?? NSFont.boldSystemFont(ofSize: 11)
        if approved {
            errorLabel.stringValue = "✓ Approved"
            errorLabel.textColor = NSColor.Sphinx.PrimaryGreen
        } else {
            errorLabel.stringValue = "✗ Rejected"
            errorLabel.textColor = NSColor.systemRed
        }
        errorLabel.isHidden = false
        needsLayout = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.handleDismiss()
        }
    }

    func resetToActionable() {
        isActioned = false
        isLoading = false
        spinner.stopAnimation(nil)
        spinner.isHidden = true
        approveButton.isEnabled = true
        rejectButton.isEnabled = true
        approveButton.isHidden = false
        rejectButton.isHidden = false
        stampLabel.isHidden = true
        errorLabel.font = NSFont(name: "Roboto-Regular", size: 11) ?? NSFont.systemFont(ofSize: 11)
        errorLabel.textColor = NSColor.systemRed
        errorLabel.isHidden = true
    }
}
