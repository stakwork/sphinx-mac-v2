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
            let rendered = NSMutableAttributedString(
                attributedString: ChatHelper.markdownRenderer.render(messageContent.text ?? "")
            )
            
            if let term = searchingTerm, !term.isEmpty {
                let messageC = messageContent.text ?? ""
                let searchRange = (messageC.lowercased() as NSString).range(of: term.lowercased())
                rendered.addAttributes(
                    [.backgroundColor: NSColor.Sphinx.PrimaryGreen],
                    range: searchRange
                )
            }
            
            // Clear the control-level font so NSTextField doesn't override
            // per-run font attributes (bold, code, headings) in the attributed string.
            messageLabel.font = nil
            messageLabel.attributedStringValue = rendered
            messageLabel.isEnabled = true
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
