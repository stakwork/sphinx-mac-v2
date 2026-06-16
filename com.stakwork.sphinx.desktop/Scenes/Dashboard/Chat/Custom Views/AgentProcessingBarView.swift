//
//  AgentProcessingBarView.swift
//  Sphinx
//
//  Created on 2026-06-16.
//  Copyright © 2026 Sphinx. All rights reserved.
//

import Cocoa

final class AgentProcessingBarView: NSView {

    private let progressIndicator: NSProgressIndicator = {
        let pi = NSProgressIndicator()
        pi.style = .spinning
        pi.isIndeterminate = true
        pi.controlSize = .small
        pi.translatesAutoresizingMaskIntoConstraints = false
        return pi
    }()

    private let label: NSTextField = {
        let tf = NSTextField(labelWithString: "Working…")
        tf.font = NSFont.systemFont(ofSize: 12)
        tf.textColor = NSColor.secondaryLabelColor
        tf.isEditable = false
        tf.isSelectable = false
        tf.translatesAutoresizingMaskIntoConstraints = false
        return tf
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        addSubview(progressIndicator)
        addSubview(label)

        NSLayoutConstraint.activate([
            progressIndicator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            progressIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
            progressIndicator.widthAnchor.constraint(equalToConstant: 16),
            progressIndicator.heightAnchor.constraint(equalToConstant: 16),

            label.leadingAnchor.constraint(equalTo: progressIndicator.trailingAnchor, constant: 6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8)
        ])
    }

    func startAnimating() {
        isHidden = false
        progressIndicator.startAnimation(nil)
    }

    func stopAnimating() {
        progressIndicator.stopAnimation(nil)
        isHidden = true
    }
}
