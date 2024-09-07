//
//  ChatEmptyAvatarPlaceholder.swift
//  sphinx
//
//  Created by James Carucci on 9/6/24.
//  Copyright © 2024 sphinx. All rights reserved.
//

import Cocoa

class ChatEmptyAvatarPlaceholderView: NSView {
    
    @IBOutlet weak var contentView: NSView!
    @IBOutlet weak var avatarImageView: AspectFillNSImageView!
    @IBOutlet weak var nameLabel: NSTextField!
    @IBOutlet weak var encryptionNoticeLabel: NSTextField!
    @IBOutlet weak var lockImageView: NSImageView!
    @IBOutlet weak var subtitleTextField: NSTextField!
    @IBOutlet weak var initialsLabel: NSTextField!
    @IBOutlet weak var initialsLabelContainer: NSBox!
    
    var inviteDate : Date? = nil
    
    var isPending : Bool = false {
        didSet{
            let dateText = inviteDate?.getStringDate(format: "MMMM d yyyy") ?? ""
            let fullDateText = dateText == "" ? "Invited you" : "Invited you on \(dateText)"
            let text = (isPending == false) ? "Messages and calls are secured with end-to-end encryption" : fullDateText
            subtitleTextField.stringValue = text
            lockImageView.isHidden = isPending
        }
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        let bundle = Bundle(for: type(of: self))
        let nib = NSNib(nibNamed: "ChatEmptyAvatarPlaceholderView", bundle: bundle)!
        nib.instantiate(withOwner: self, topLevelObjects: nil)
        
        addSubview(contentView)
        contentView.frame = bounds
        contentView.autoresizingMask = [.width, .height]
    }
    
    func setupAvatarImageView(imageUrl:String){
        avatarImageView.wantsLayer = true
        avatarImageView.rounded = true
        avatarImageView.layer?.cornerRadius = avatarImageView.frame.height / 2
        contentView.setBackgroundColor(color: .black)
        self.setBackgroundColor(color: .purple)
        
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
    
    func configureWith(chat:Chat){
        let name = chat.getName()
        nameLabel.stringValue = name
        if let avatarImage = chat.getContact()?.avatarUrl,
           avatarImage != ""
        {
            setupAvatarImageView(imageUrl: avatarImage)
        }
        else{
            avatarImageView.image = nil
            showInitialsFor(chat.getContact(), in: avatarImageView, and: initialsLabelContainer)
        }
        
        isPending = chat.isPending()
        inviteDate = chat.getContact()?.createdAt
    }
    
    func showInitialsFor(_ object: ChatListCommonObject?, in imageView: AspectFillNSImageView, and container: NSView) {
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
