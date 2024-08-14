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
        let normalFont = NSFont(name: "Roboto-Light", size: 15.0)!
        let highlightedFont = NSFont(name: "Roboto-Light", size: 15.0)!
        let boldFont = NSFont(name: "Roboto-Black", size: 15.0)!
        
        if let messageContent = messageContent {
            if messageContent.hasNoMarkdown {
                messageLabel.attributedStringValue = NSMutableAttributedString(string: "")

                messageLabel.stringValue = messageContent.text ?? ""
                messageLabel.font = normalFont
            } else {
                let messageC = messageContent.text ?? ""
                let attributedString = NSMutableAttributedString(string: messageC)
                
                attributedString.addAttributes(
                    [
                        NSAttributedString.Key.font: normalFont,
                        NSAttributedString.Key.foregroundColor: NSColor.Sphinx.Text
                    ]
                    , range: messageC.nsRange
                )
                
                ///Highlighted text formatting
                let highlightedNsRanges = messageContent.highlightedMatches.map {
                    return $0.range
                }
                
                for nsRange in highlightedNsRanges {

                    let adaptedRange = NSRange(
                        location: nsRange.location,
                        length: nsRange.length
                    )
                    
                    attributedString.addAttributes(
                        [
                            NSAttributedString.Key.foregroundColor: NSColor.Sphinx.HighlightedText,
                            NSAttributedString.Key.backgroundColor: NSColor.Sphinx.HighlightedTextBackground,
                            NSAttributedString.Key.font: highlightedFont
                        ],
                        range: adaptedRange
                    )
                }
                
                ///Bold text formatting
                let boldNsRanges = messageContent.boldMatches.map {
                    return $0.range
                }
                
                for nsRange in boldNsRanges {
                    let adaptedRange = NSRange(
                        location: nsRange.location,
                        length: nsRange.length
                    )
                    
                    attributedString.addAttributes(
                        [
                            NSAttributedString.Key.font: boldFont
                        ],
                        range: adaptedRange
                    )
                }

                ///Links formatting
                var nsRanges = messageContent.linkMatches.map {
                    return $0.range
                }
                
                nsRanges = ChatHelper.removeDuplicatedContainedFrom(urlRanges: nsRanges)

                for nsRange in nsRanges {
                    
                    if let text = messageContent.text, let range = Range(nsRange, in: text) {
                        
                        var substring = String(text[range])
                        
                        if substring.isPubKey {
                            substring = substring.shareContactDeepLink
                        } else if substring.starts(with: API.kVideoCallServer) {
                            substring = substring.callLinkDeepLink
                        } else if !substring.isTribeJoinLink {
                            substring = substring.withProtocol(protocolString: "http")
                        }
                         
                        if let url = URL(string: substring)  {
                            attributedString.addAttributes(
                                [
                                    NSAttributedString.Key.link: url,
                                    NSAttributedString.Key.foregroundColor: NSColor.Sphinx.PrimaryBlue,
                                    NSAttributedString.Key.underlineStyle: NSUnderlineStyle.single.rawValue,
                                    NSAttributedString.Key.font: normalFont
                                ],
                                range: nsRange
                            )

                        }
                    }
                }
                
                ///Markdown Links formatting
                for (textCheckingResult, _, link, _) in messageContent.linkMarkdownMatches {
                    
                    let nsRange = textCheckingResult.range
                    
                    if let text = messageContent.text {
                        
                        if let url = URL(string: link)  {
                            attributedString.addAttributes(
                                [
                                    NSAttributedString.Key.link: url,
                                    NSAttributedString.Key.foregroundColor: NSColor.Sphinx.PrimaryBlue,
                                    NSAttributedString.Key.underlineStyle: NSUnderlineStyle.single.rawValue,
                                    NSAttributedString.Key.font: NSFont.getMessageFont()
                                ],
                                range: nsRange
                            )
                        }
                    }
                }
                
                messageLabel.attributedStringValue = attributedString
                messageLabel.isEnabled = true
            }
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
