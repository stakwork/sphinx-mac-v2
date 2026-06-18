//
//  PinMessageDetailView.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 24/05/2023.
//  Copyright © 2023 Tomas Timinskas. All rights reserved.
//

import Cocoa

class PinMessageDetailView: NSView, LoadableNib {
    
    weak var delegate: PinnedMessageViewDelegate?
    
    @IBOutlet var contentView: NSView!

    @IBOutlet weak var backgroundBox: NSBox!
    @IBOutlet weak var avatarView: ChatSmallAvatarView!
    @IBOutlet weak var usernameLabel: NSTextField!
    @IBOutlet weak var messageLabel: MessageTextField!
    @IBOutlet weak var arrowView: NSView!
    @IBOutlet weak var unpinButtonContainer: NSView!
    @IBOutlet weak var unpinButton: CustomButton!
    @IBOutlet weak var containerButton: CustomButton!
    
    var messageId: Int? = nil
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        loadViewFromNib()
        
        configureView()
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        loadViewFromNib()
        
        configureView()
    }
    
    func configureView() {
        unpinButton.cursor = .pointingHand
        containerButton.cursor = .pointingHand
        
        messageLabel.setSelectionColor(color: NSColor.getTextSelectionColor())
        messageLabel.allowsEditingTextAttributes = true
        
        drawArrow()
        addClickEvent()
    }
    
    func addClickEvent() {
        let click = NSClickGestureRecognizer(target: self, action: #selector(shouldDismissView))
        backgroundBox.addGestureRecognizer(click)
    }
    
    @objc func shouldDismissView() {
        self.messageId = nil
        self.isHidden = true
    }
    
    func drawArrow() {
        let arrowBezierPath = NSBezierPath()
        
        arrowBezierPath.move(to: CGPoint(x: arrowView.frame.width, y: 0))
        arrowBezierPath.line(to: CGPoint(x: arrowView.frame.width, y: arrowView.frame.height))
        arrowBezierPath.line(to: CGPoint(x: 0, y: arrowView.frame.height))
        arrowBezierPath.line(to: CGPoint(x: 4, y: 0))
        arrowBezierPath.line(to: CGPoint(x: 0, y: 0))
        arrowBezierPath.close()
        
        let messageArrowLayer = CAShapeLayer()
        messageArrowLayer.path = arrowBezierPath.cgPath
        
        messageArrowLayer.frame = CGRect(
            x: 0, y: 0, width: arrowView.frame.width, height: arrowView.frame.height
        )

        messageArrowLayer.fillColor = NSColor.Sphinx.SentMsgBG.cgColor
        
        arrowView.wantsLayer = true
        arrowView.layer?.masksToBounds = false
        arrowView.layer?.addSublayer(messageArrowLayer)
    }
    
    func configureWith(
        messageId: Int,
        delegate: PinnedMessageViewDelegate
    ) {
        if let message = TransactionMessage.getMessageWith(id: messageId) {
            self.delegate = delegate
            self.messageId = messageId
            
            if message.isOutgoing() {
                if let owner = UserContact.getOwner() {
                    avatarView.configureForUserWith(
                        color: owner.getColor(),
                        alias: owner.nickname,
                        picture: owner.avatarUrl
                    )
                    
                    usernameLabel.stringValue = owner.nickname ?? "Unknown"
                    usernameLabel.textColor = owner.getColor()
                }
            } else {
                avatarView.configureForSenderWith(message: message)
                
                usernameLabel.stringValue = message.senderAlias ?? "Unknown"
                usernameLabel.textColor = ChatHelper.getSenderColorFor(message: message)
            }
            
            unpinButtonContainer.isHidden = message.chat?.isMyPublicGroup() == false
            
            if let messageContent = message.bubbleMessageContentString, messageContent.isNotEmpty {
                configureWith(
                    messageContent: BubbleMessageLayoutState.MessageContent(
                        text: messageContent.removingMarkdownDelimiters,
                        linkMatches: messageContent.stringLinks + messageContent.pubKeyMatches + messageContent.mentionMatches,
                        highlightedMatches: messageContent.highlightedMatches,
                        boldMatches: messageContent.boldMatches,
                        linkMarkdownMatches: messageContent.linkMarkdownMatches,
                        shouldLoadPaidText: false
                    )
                )
            } else {
                messageLabel.stringValue = message.bubbleMessageContentString ?? ""
            }
            
            self.isHidden = false
        }
    }
    
    func configureWith(
        messageContent: BubbleMessageLayoutState.MessageContent?
    ) {
        guard let messageContent = messageContent else { return }

        if messageContent.hasNoMarkdown {
            messageLabel.attributedStringValue = NSMutableAttributedString(string: "")
            messageLabel.stringValue = messageContent.text ?? ""
            messageLabel.font = NSFont(name: "Roboto-Light", size: 15.0)
        } else {
            let messageC = messageContent.text ?? ""
            let attributedString = NSMutableAttributedString(
                attributedString: ChatHelper.markdownRenderer.render(messageC)
            )
            ChatHelper.applySphinxLinkTransforms(to: attributedString)

            messageLabel.attributedStringValue = attributedString
            messageLabel.isEnabled = true
        }
    }
    
    @IBAction func containerButtonClicked(_ sender: Any) {
        if let messageId = self.messageId {
            delegate?.shouldNavigateTo(messageId: messageId)
        }
        shouldDismissView()
    }
    
    @IBAction func unpinMessageButtoniClicked(_ sender: Any) {
        if let messageId = messageId {
            delegate?.didTapUnpinButtonFor(messageId: messageId)
            shouldDismissView()
        }
    }
}
