//
//  ChatEmptyAvatarPlaceholder.swift
//  sphinx
//
//  Created by James Carucci on 9/6/24.
//  Copyright © 2024 sphinx. All rights reserved.
//

import Cocoa

class ChatEmptyAvatarPlaceholderView: NSView, LoadableNib {
    
    @IBOutlet weak var contentView: NSView!
    @IBOutlet weak var avatarImageView: AspectFillNSImageView!
    @IBOutlet weak var nameLabel: NSTextField!
    @IBOutlet weak var lockImageView: NSImageView!
    @IBOutlet weak var subtitleTextField: NSTextField!
    @IBOutlet weak var initialsLabel: NSTextField!
    @IBOutlet weak var initialsLabelContainer: NSBox!
    @IBOutlet weak var pendingContactTitle: NSTextField!
    @IBOutlet weak var clockImageView: NSImageView!
    @IBOutlet weak var dashedOutlinePlaceholderView: NSView!
    @IBOutlet weak var pendingClockBackgroundView: NSView!
    
    var inviteDate : Date? = nil
    
    var isPending : Bool = false {
        didSet {
            let dateText = inviteDate?.getStringDate(format: "MMMM d yyyy") ?? ""
            let fullDateText = dateText == "" ? "Invited" : "Invited on \(dateText)"
            let text = (isPending == false) ? "messages.encrypted.disclaimer".localized : fullDateText
            
            subtitleTextField.stringValue = text
            lockImageView.isHidden = isPending
            
            clockImageView.isHidden = !isPending
            pendingContactTitle.isHidden = !isPending
            
            if (isPending) {
                pendingClockBackgroundView.setBackgroundColor(color: NSColor.Sphinx.Body)
                pendingClockBackgroundView.makeCircular()
                pendingClockBackgroundView.isHidden = false
                dashedOutlinePlaceholderView.isHidden = false
                
                dashedOutlinePlaceholderView.addDottedCircularBorder(
                    lineWidth: 1.0,
                    dashPattern: [5,5],
                    color: NSColor.Sphinx.PlaceholderText
                )
            } else {
                dashedOutlinePlaceholderView.layer?.sublayers?.forEach { layer in
                    layer.removeFromSuperlayer()
                }
                pendingClockBackgroundView.isHidden = true
                dashedOutlinePlaceholderView.isHidden = true
            }
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        loadViewFromNib()
        setupView()
    }
    
    func setupView() {
        pendingContactTitle.stringValue = "contact.pending.subtitle".localized
    }
    
    func setupAvatarImageView(imageUrl: String) {
        avatarImageView.wantsLayer = true
        avatarImageView.rounded = true
        avatarImageView.layer?.cornerRadius = avatarImageView.frame.height / 2
        
        let imageUrl = imageUrl.trim()
        if imageUrl != "" {
            MediaLoader.loadAvatarImage(url: imageUrl, objectId: imageUrl.hashValue, completion: { (image, id) in
                guard let image = image else {
                    return
                }
                self.avatarImageView.bordered = false
                self.avatarImageView.image = image
            })
        } else {
            avatarImageView.image = NSImage(named: "profileAvatar")
        }
    }
    
    func configureWith(contact: UserContact) {
        let name = contact.getName()
        nameLabel.stringValue = name
        inviteDate = contact.createdAt
        isPending = contact.isPending()
        
        if let avatarImage = contact.avatarUrl, avatarImage != "" {
            setupAvatarImageView(imageUrl: avatarImage)
        } else {
            avatarImageView.image = nil
            showInitialsFor(contact, in: avatarImageView, and: initialsLabelContainer)
        }
        
    }
    
    func configureWith(chat: Chat) {
        let name = chat.getName()
        nameLabel.stringValue = name
        inviteDate = chat.getContact()?.createdAt
        isPending = chat.isPending()
        
        if let avatarImage = chat.getContact()?.avatarUrl, avatarImage != "" {
            setupAvatarImageView(imageUrl: avatarImage)
        } else {
            avatarImageView.image = nil
            showInitialsFor(chat.getContact(), in: avatarImageView, and: initialsLabelContainer)
        }
        
    }
    
    func showInitialsFor(
        _ object: ChatListCommonObject?,
        in imageView: AspectFillNSImageView,
        and container: NSView
    ) {
        let senderInitials = object?.getName().getInitialsFromName() ?? "UK"
        let senderColor = object?.getColor()
        
        initialsLabelContainer.isHidden = false
        imageView.bordered = false
        imageView.image = nil
        
        initialsLabelContainer.wantsLayer = true
        initialsLabelContainer.layer?.cornerRadius = initialsLabelContainer.frame.size.height / 2
        initialsLabelContainer.layer?.backgroundColor = senderColor?.cgColor
        
        initialsLabel.stringValue = senderInitials
    }
}
