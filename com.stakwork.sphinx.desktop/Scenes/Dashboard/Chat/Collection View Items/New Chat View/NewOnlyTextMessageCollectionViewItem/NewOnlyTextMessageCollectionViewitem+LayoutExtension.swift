//
//  NewOnlyTextMessageCollectionViewitem+LayoutExtension.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 18/07/2023.
//  Copyright © 2023 Tomas Timinskas. All rights reserved.
//

import Cocoa

extension NewOnlyTextMessageCollectionViewitem {
    func configureWith(
        statusHeader: BubbleMessageLayoutState.StatusHeader?
    ) {
        if let statusHeader = statusHeader {
            statusHeaderView.configureWith(
                statusHeader: statusHeader,
                uploadProgressData: nil
            )
        }
    }
    
    func configureWith(
        messageContent: BubbleMessageLayoutState.MessageContent?,
        searchingTerm: String?
    ) {
        if let messageContent = messageContent {
            if messageContent.hasNoMarkdown && searchingTerm == nil {
                messageLabel.attributedStringValue = NSMutableAttributedString(string: "")

                messageLabel.stringValue = messageContent.text ?? ""
                messageLabel.font = NSFont.getMessageFont()
            } else {
                let messageC = messageContent.text ?? ""
                let attributedString = NSMutableAttributedString(string: messageC)
                
                attributedString.addAttributes(
                    [
                        NSAttributedString.Key.font: NSFont.getMessageFont(),
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
                            NSAttributedString.Key.font: NSFont.getHighlightedMessageFont()
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
                            NSAttributedString.Key.font: NSFont.getMessageBoldFont()
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
                        } else if substring.starts(with: API.sharedInstance.kVideoCallServer) {
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
                                    NSAttributedString.Key.font: NSFont.getMessageFont()
                                ],
                                range: nsRange
                            )

                        }
                    }
                }
                
                ///Markdown Links formatting
                for (textCheckingResult, _, link, _) in messageContent.linkMarkdownMatches {
                    
                    let nsRange = textCheckingResult.range
                    
                    if let _ = messageContent.text {
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
                
                ///Search term formatting
                let term = searchingTerm ?? ""

                let searchingTermRange = (messageC.lowercased() as NSString).range(of: term.lowercased())
                attributedString.addAttributes(
                    [
                        NSAttributedString.Key.backgroundColor: NSColor.Sphinx.PrimaryGreen
                    ]
                    , range: searchingTermRange
                )

                messageLabel.attributedStringValue = attributedString
                messageLabel.isEnabled = true
            }
        }
    }
    
    func configureWith(
        avatarImage: BubbleMessageLayoutState.AvatarImage?
    ) {
        if let avatarImage = avatarImage {
            chatAvatarView.configureForUserWith(
                color: avatarImage.color,
                alias: avatarImage.alias,
                picture: avatarImage.imageUrl,
                radius: kChatAvatarHeight / 2,
                image: avatarImage.image,
                delegate: self
            )
        } else {
            chatAvatarView.resetView()
        }
    }
    
    func configureWith(
        bubble: BubbleMessageLayoutState.Bubble
    ) {
        configureWith(direction: bubble.direction)
        configureWith(bubbleState: bubble.grouping, direction: bubble.direction)
    }
    
    func configureWith(
        direction: MessageTableCellState.MessageDirection
    ) {
        let isOutgoing = direction.isOutgoing()
        
        sentMessageMargingView.isHidden = !isOutgoing
        receivedMessageMarginView.isHidden = isOutgoing
        
        receivedArrow.isHidden = isOutgoing
        sentArrow.isHidden = !isOutgoing
        
        receivedMessageMenuButton.isHidden = isOutgoing
        sentMessageMenuButton.isHidden = !isOutgoing
        
        messageLabelLeadingConstraint.priority = NSLayoutConstraint.Priority(isOutgoing ? 1 : 1000)
        messageLabelTrailingConstraint.priority = NSLayoutConstraint.Priority(isOutgoing ? 1000 : 1)
        
        let bubbleColor = isOutgoing ? NSColor.Sphinx.SentMsgBG : NSColor.Sphinx.ReceivedMsgBG
        bubbleOnlyText.fillColor = bubbleColor
        
        statusHeaderView.configureWith(direction: direction)
    }
    
    func configureWith(
        bubbleState: MessageTableCellState.BubbleState,
        direction: MessageTableCellState.MessageDirection
    ) {
        let outgoing = direction == .Outgoing
        
        switch (bubbleState) {
        case .Isolated:
            chatAvatarContainerView.alphaValue = outgoing ? 0.0 : 1.0
            statusHeaderViewContainer.isHidden = false
            
            receivedArrow.alphaValue = 1.0
            sentArrow.alphaValue = 1.0
            break
        case .First:
            chatAvatarContainerView.alphaValue = outgoing ? 0.0 : 1.0
            statusHeaderViewContainer.isHidden = false
            
            receivedArrow.alphaValue = 1.0
            sentArrow.alphaValue = 1.0
            break
        case .Middle:
            chatAvatarContainerView.alphaValue = 0.0
            statusHeaderViewContainer.isHidden = true
            
            receivedArrow.alphaValue = 0.0
            sentArrow.alphaValue = 0.0
            break
        case .Last:
            chatAvatarContainerView.alphaValue = 0.0
            statusHeaderViewContainer.isHidden = true
            
            receivedArrow.alphaValue = 0.0
            sentArrow.alphaValue = 0.0
            break
        case .Empty:
            break
        }
    }
    
    func configureWith(
        invoiceLines: BubbleMessageLayoutState.InvoiceLines
    ) {
        switch (invoiceLines.linesState) {
        case .None:
            leftLineContainer.isHidden = true
            rightLineContainer.isHidden = true
            break
        case .Left:
            leftLineContainer.isHidden = false
            rightLineContainer.isHidden = true
            break
        case .Right:
            leftLineContainer.isHidden = true
            rightLineContainer.isHidden = false
            break
        case .Both:
            leftLineContainer.isHidden = false
            rightLineContainer.isHidden = false
            break
        }
    }
}

extension NewOnlyTextMessageCollectionViewitem : ChatSmallAvatarViewDelegate {
    func didClickAvatarView() {
        if let messageId = messageId {
            delegate?.didTapAvatarViewFor(messageId: messageId, and: rowIndex)
        }
    }
}
