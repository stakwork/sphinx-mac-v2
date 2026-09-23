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

    static let kHeight: CGFloat = 48

    private let messageLabel: NSTextField = {
        let label = NSTextField(wrappingLabelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont(name: "Roboto-Medium", size: 12) ?? NSFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.isEditable = false
        label.isSelectable = false
        label.isBordered = false
        label.drawsBackground = false
        label.usesSingleLineMode = false
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byWordWrapping
        label.cell?.wraps = true
        label.cell?.truncatesLastVisibleLine = true
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
            messageLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            messageLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])
    }

    func apply(health: ServerHealth) {
        guard SphinxOnionManager.sharedInstance.isServerHealthBannerVisible,
              let copy = ServerHealthPresentation.localizedBannerCopy(for: health) else {
            isHidden = true
            return
        }
        messageLabel.stringValue = copy
        isHidden = false
    }

    override var intrinsicContentSize: NSSize {
        CGSize(width: NSView.noIntrinsicMetric, height: ServerHealthBannerView.kHeight)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = NSColor.Sphinx.SphinxOrange.cgColor
    }
}
