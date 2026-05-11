//
//  ParticipantBoxView.swift
//  Sphinx
//
//  Created for live call participants strip in tribe chat.
//

import Cocoa

@MainActor
class ParticipantBoxView: NSView {
    
    private let avatarImageView: AspectFillNSImageView = {
        let imageView = AspectFillNSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.wantsLayer = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.rounded = true
        imageView.gravity = .resizeAspectFill
        return imageView
    }()
    
    private let nameLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 9)
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.isEditable = false
        label.isSelectable = false
        label.isBordered = false
        label.drawsBackground = false
        label.textColor = .Sphinx.Text
        label.alignment = .center
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
        wantsLayer = true
        layer?.backgroundColor = NSColor.Sphinx.Body.withAlphaComponent(0.08).cgColor
        layer?.cornerRadius = 8
        
        translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(avatarImageView)
        addSubview(nameLabel)
        
        NSLayoutConstraint.activate([
            avatarImageView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            avatarImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            avatarImageView.widthAnchor.constraint(equalToConstant: 24),
            avatarImageView.heightAnchor.constraint(equalToConstant: 24),
            
            nameLabel.topAnchor.constraint(equalTo: avatarImageView.bottomAnchor, constant: 4),
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 2),
            nameLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: 2),
            
            widthAnchor.constraint(greaterThanOrEqualToConstant: 37)
        ])
        
        // Make avatar circular
        avatarImageView.wantsLayer = true
        avatarImageView.layer?.cornerRadius = 12
        avatarImageView.layer?.masksToBounds = true
        avatarImageView.layer?.borderWidth = 1
        avatarImageView.layer?.borderColor = NSColor.separatorColor.cgColor
    }
    
    func configure(with participant: BubbleMessageLayoutState.CallParticipantInfo) {
        nameLabel.stringValue = participant.name.isEmpty ? participant.identity : participant.name
        alphaValue = participant.isActive ? 1.0 : 0.5
        
        // Load profile picture or use initials placeholder
        if let urlString = participant.profilePictureUrl, let url = URL(string: urlString) {
            avatarImageView.image = initialsImage(for: participant)
            MediaLoader.asyncLoadImage(
                imageView: avatarImageView,
                nsUrl: url,
                placeHolderImage: initialsImage(for: participant)
            )
        } else {
            avatarImageView.image = initialsImage(for: participant)
        }
    }
    
    private func initialsImage(for participant: BubbleMessageLayoutState.CallParticipantInfo) -> NSImage {
        let displayName = participant.name.isEmpty ? participant.identity : participant.name
        let initials = String(displayName.prefix(1)).uppercased()
        
        let size = CGSize(width: 24, height: 24)
        let image = NSImage(size: size)
        image.lockFocus()
        
        // Background color derived from name
        let color = colorFor(name: displayName)
        color.setFill()
        NSBezierPath(ovalIn: NSRect(origin: .zero, size: size)).fill()
        
        // Draw initials
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 10),
            .foregroundColor: NSColor.white
        ]
        let attrString = NSAttributedString(string: initials, attributes: attrs)
        let textSize = attrString.size()
        let textRect = NSRect(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        attrString.draw(in: textRect)
        
        image.unlockFocus()
        return image
    }
    
    private func colorFor(name: String) -> NSColor {
        let colors: [NSColor] = [
            NSColor(red: 0.38, green: 0.54, blue: 1.0, alpha: 1),
            NSColor(red: 0.29, green: 0.79, blue: 0.60, alpha: 1),
            NSColor(red: 0.96, green: 0.50, blue: 0.27, alpha: 1),
            NSColor(red: 0.91, green: 0.35, blue: 0.35, alpha: 1),
            NSColor(red: 0.60, green: 0.40, blue: 0.85, alpha: 1),
        ]
        let hash = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return colors[abs(hash) % colors.count]
    }
}
