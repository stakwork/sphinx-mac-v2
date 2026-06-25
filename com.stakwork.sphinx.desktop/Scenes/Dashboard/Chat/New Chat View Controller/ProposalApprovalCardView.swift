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

    // MARK: - State
    private let proposalId: String
    private var isActioned: Bool = false

    // MARK: - Subviews

    private let badgeLabel: NSTextField = {
        let tf = NSTextField(labelWithString: "")
        tf.font = NSFont.boldSystemFont(ofSize: 10)
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
        let tf = NSTextField(labelWithString: "")
        tf.font = NSFont.boldSystemFont(ofSize: 13)
        tf.textColor = NSColor.labelColor
        tf.lineBreakMode = .byWordWrapping
        tf.maximumNumberOfLines = 2
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.isEditable = false
        tf.isSelectable = false
        return tf
    }()

    private let descLabel: NSTextField = {
        let tf = NSTextField(labelWithString: "")
        tf.font = NSFont.systemFont(ofSize: 11)
        tf.textColor = NSColor.secondaryLabelColor
        tf.lineBreakMode = .byWordWrapping
        tf.maximumNumberOfLines = 3
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.isEditable = false
        tf.isSelectable = false
        return tf
    }()

    private let approveButton: NSButton = {
        let btn = NSButton(title: "Approve", target: nil, action: nil)
        btn.bezelStyle = .rounded
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let rejectButton: NSButton = {
        let btn = NSButton(title: "Reject", target: nil, action: nil)
        btn.bezelStyle = .rounded
        btn.translatesAutoresizingMaskIntoConstraints = false
        if #available(macOS 10.14, *) {
            btn.contentTintColor = NSColor.systemRed
        }
        return btn
    }()

    private let stampLabel: NSTextField = {
        let tf = NSTextField(labelWithString: "")
        tf.font = NSFont.boldSystemFont(ofSize: 14)
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.isEditable = false
        tf.isSelectable = false
        tf.alignment = .center
        tf.isHidden = true
        return tf
    }()

    private let dismissButton: NSButton = {
        let btn = NSButton(title: "✕", target: nil, action: nil)
        btn.bezelStyle = .inline
        btn.isBordered = false
        btn.font = NSFont.systemFont(ofSize: 11)
        btn.contentTintColor = NSColor.secondaryLabelColor
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
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
        // Badge
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
        default:           return ("Feature",    NSColor.systemBlue)
        }
    }

    // MARK: - Layout

    private func setupLayout() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor

        // Shadow
        shadow = NSShadow()
        shadow?.shadowColor = NSColor.black.withAlphaComponent(0.12)
        shadow?.shadowOffset = NSSize(width: 0, height: -2)
        shadow?.shadowBlurRadius = 6

        [badgeLabel, titleLabel, descLabel, approveButton, rejectButton, stampLabel, dismissButton].forEach {
            addSubview($0)
        }

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

            // Badge — top left
            badgeLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            badgeLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            badgeLabel.heightAnchor.constraint(equalToConstant: 18),

            // Title
            titleLabel.topAnchor.constraint(equalTo: badgeLabel.bottomAnchor, constant: 6),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            // Description
            descLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            descLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            descLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            // Approve / Reject buttons
            approveButton.topAnchor.constraint(equalTo: descLabel.bottomAnchor, constant: 10),
            approveButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            approveButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            approveButton.heightAnchor.constraint(equalToConstant: 28),

            rejectButton.topAnchor.constraint(equalTo: approveButton.topAnchor),
            rejectButton.leadingAnchor.constraint(equalTo: approveButton.trailingAnchor, constant: 8),
            rejectButton.heightAnchor.constraint(equalToConstant: 28),
            rejectButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),

            // Stamp label (hidden by default, replaces buttons when actioned)
            stampLabel.topAnchor.constraint(equalTo: descLabel.bottomAnchor, constant: 10),
            stampLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stampLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stampLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            stampLabel.heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    // MARK: - Actions

    @objc private func handleApprove() {
        guard !isActioned else { return }
        onApprove?(proposalId)
    }

    @objc private func handleReject() {
        guard !isActioned else { return }
        onReject?(proposalId)
    }

    @objc private func handleDismiss() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            animator().alphaValue = 0
        }, completionHandler: {
            self.removeFromSuperview()
        })
    }

    // MARK: - State Updates

    func showStamp(approved: Bool) {
        isActioned = true
        approveButton.isHidden = true
        rejectButton.isHidden = true
        stampLabel.isHidden = false
        if approved {
            stampLabel.stringValue = "✅ Approved"
            stampLabel.textColor = NSColor.systemGreen
        } else {
            stampLabel.stringValue = "❌ Rejected"
            stampLabel.textColor = NSColor.systemRed
        }
        // Auto-dismiss after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.handleDismiss()
        }
    }

    func resetToActionable() {
        isActioned = false
        approveButton.isHidden = false
        rejectButton.isHidden = false
        stampLabel.isHidden = true
    }
}
