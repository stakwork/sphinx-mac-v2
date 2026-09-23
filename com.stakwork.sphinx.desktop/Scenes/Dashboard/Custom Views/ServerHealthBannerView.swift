//
//  ServerHealthBannerView.swift
//  Sphinx
//
//  Non-blocking overlay for Lightning node health (degraded / unknown).
//  Separate from `HealthCheckView`, which reflects MQTT connectivity.
//

import Cocoa

@MainActor
final class ServerHealthBannerView: NSView {

    static let kHeight: CGFloat = 32

    private let messageLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont(name: "Roboto-Medium", size: 12) ?? NSFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.isEditable = false
        label.isSelectable = false
        label.isBordered = false
        label.drawsBackground = false
        label.lineBreakMode = .byTruncatingTail
        return label
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.Sphinx.SphinxOrange.cgColor
        isHidden = true

        addSubview(messageLabel)
        NSLayoutConstraint.activate([
            messageLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            messageLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            messageLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    func apply(health: ServerHealth) {
        if let copy = ServerHealthPresentation.localizedBannerCopy(for: health) {
            messageLabel.stringValue = copy
            isHidden = false
        } else {
            isHidden = true
        }
    }

    override var intrinsicContentSize: NSSize {
        CGSize(width: NSView.noIntrinsicMetric, height: ServerHealthBannerView.kHeight)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = NSColor.Sphinx.SphinxOrange.cgColor
    }
}
