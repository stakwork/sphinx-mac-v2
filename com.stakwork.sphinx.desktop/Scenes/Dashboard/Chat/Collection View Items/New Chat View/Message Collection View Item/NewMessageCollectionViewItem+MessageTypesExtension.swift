//
//  NewMessageCollectionViewItem+MessageTypesExtension.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 20/07/2023.
//  Copyright © 2023 Tomas Timinskas. All rights reserved.
//

import Cocoa

extension NewMessageCollectionViewItem {
    
    func configureWith(
        messageReply: BubbleMessageLayoutState.MessageReply?,
        and bubble: BubbleMessageLayoutState.Bubble
    ) {
        if let messageReply = messageReply {
            messageReplyView.configureWith(messageReply: messageReply, and: bubble, delegate: self)
            messageReplyView.isHidden = false
        }
    }
    
    func configureWith(
        directPayment: BubbleMessageLayoutState.DirectPayment?,
        and bubble: BubbleMessageLayoutState.Bubble
    ) {
        if let directPayment = directPayment {
            directPaymentView.configureWith(directPayment: directPayment, and: bubble)
            directPaymentView.isHidden = false
        }
    }
    
    func configureWith(
        payment: BubbleMessageLayoutState.Payment?,
        and bubble: BubbleMessageLayoutState.Bubble
    ) {
        if let payment = payment {
            invoicePaymentView.configureWith(payment: payment, and: bubble)
            invoicePaymentView.isHidden = false
            
            rightPaymentDot.isHidden = bubble.direction.isIncoming()
            leftPaymentDot.isHidden = bubble.direction.isOutgoing()
        } else {
            rightPaymentDot.isHidden = true
            leftPaymentDot.isHidden = true
        }
    }
    
    func configureWith(
        invoice: BubbleMessageLayoutState.Invoice?,
        and bubble: BubbleMessageLayoutState.Bubble
    ) {
        if let invoice = invoice {
            invoiceView.configureWith(invoice: invoice, bubble: bubble, and: self)
            invoiceView.isHidden = false
        }
    }
    
    func configureWith(
        audio: BubbleMessageLayoutState.Audio?,
        mediaData: MessageTableCellState.MediaData?,
        and bubble: BubbleMessageLayoutState.Bubble
    ) {
        if let audio = audio {
            audioMessageView.configureWith(
                audio: audio,
                mediaData: mediaData,
                bubble: bubble,
                and: self
            )
            audioMessageView.isHidden = false
            
            if let messageId = messageId, mediaData == nil {
                let delayTime = DispatchTime.now() + Double(Int64(0.5 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
                DispatchQueue.global().asyncAfter(deadline: delayTime) {
                    self.delegate?.shouldLoadAudioDataFor(
                        messageId: messageId,
                        and: self.rowIndex
                    )
                }
            }
        }
    }
    
    func configureWith(
        podcastComment: BubbleMessageLayoutState.PodcastComment?,
        mediaData: MessageTableCellState.MediaData?,
        and bubble: BubbleMessageLayoutState.Bubble
    ) {
        if let podcastComment = podcastComment {
            podcastAudioView.configureWith(
                podcastComment: podcastComment,
                mediaData: mediaData,
                bubble: bubble,
                and: self
            )
            podcastAudioView.isHidden = false
            
            if let messageId = messageId, mediaData == nil {
                let delayTime = DispatchTime.now() + Double(Int64(0.5 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
                DispatchQueue.global().asyncAfter(deadline: delayTime) {
                    self.delegate?.shouldPodcastCommentDataFor(
                        messageId: messageId,
                        and: self.rowIndex
                    )
                }
            }
        }
    }
    
    func configureWith(
        messageMedia: BubbleMessageLayoutState.MessageMedia?,
        mediaData: MessageTableCellState.MediaData?,
        and bubble: BubbleMessageLayoutState.Bubble
    ) {
        if let messageMedia = messageMedia {
            if messageMedia.isImageLink {
                if let mediaData = mediaData {
                    mediaMessageView.configureWith(
                        messageMedia: messageMedia,
                        mediaData: mediaData,
                        bubble: bubble,
                        and: self
                    )
                    mediaMessageView.isHidden = false
                } else if let messageId = messageId, mediaData == nil {
                    let delayTime = DispatchTime.now() + Double(Int64(0.5 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
                    DispatchQueue.global().asyncAfter(deadline: delayTime) {
                        self.delegate?.shouldLoadLinkImageDataFor(
                            messageId: messageId,
                            and: self.rowIndex
                        )
                    }
                }
            } else {
                mediaMessageView.configureWith(
                    messageMedia: messageMedia,
                    mediaData: mediaData,
                    bubble: bubble,
                    and: self
                )
                mediaMessageView.isHidden = false
                
                if let messageId = messageId, mediaData == nil {
                    let delayTime = DispatchTime.now() + Double(Int64(0.5 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
                    DispatchQueue.global().asyncAfter(deadline: delayTime) {
                        if messageMedia.isImage {
                            self.delegate?.shouldLoadImageDataFor(
                                messageId: messageId,
                                and: self.rowIndex
                            )
                        } else if messageMedia.isPdf {
                            self.delegate?.shouldLoadPdfDataFor(
                                messageId: messageId,
                                and: self.rowIndex
                            )
                        } else if messageMedia.isVideo {
                            self.delegate?.shouldLoadVideoDataFor(
                                messageId: messageId,
                                and: self.rowIndex
                            )
                        } else if messageMedia.isGiphy {
                            self.delegate?.shouldLoadGiphyDataFor(
                                messageId: messageId,
                                and: self.rowIndex
                            )
                        }
                    }
                }
            }
        }
    }
    
    func configureWith(
        genericFile: BubbleMessageLayoutState.GenericFile?,
        mediaData: MessageTableCellState.MediaData?
    ) {
        if let _ = genericFile {
            
            fileDetailsView.configureWith(
                mediaData: mediaData,
                and: self
            )
            
            fileDetailsView.isHidden = false
            
            if let messageId = messageId, mediaData == nil {
                let delayTime = DispatchTime.now() + Double(Int64(0.5 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
                DispatchQueue.global().asyncAfter(deadline: delayTime) {
                    self.delegate?.shouldLoadFileDataFor(
                        messageId: messageId,
                        and: self.rowIndex
                    )
                }
            }
        }
    }
    
    func configureWith(
        messageCellState: MessageTableCellState,
        searchingTerm: String?,
        linkData: MessageTableCellState.LinkData? = nil,
        tribeData: MessageTableCellState.TribeData? = nil,
        collectionViewWidth: CGFloat
    ) {
        var mutableMessageCellState = messageCellState
        
        if let messageContent = mutableMessageCellState.messageContent {
            
            let labelHeight = ChatHelper.getTextMessageHeightFor(
                mutableMessageCellState,
                linkData: linkData,
                tribeData: tribeData,
                collectionViewWidth: collectionViewWidth
            )
            
            labelHeightConstraint.constant = labelHeight
            textMessageView.superview?.layoutSubtreeIfNeeded()
                        
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
                
                ///Hightlighted text formatting
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
                                    NSAttributedString.Key.foregroundColor: NSColor.Sphinx.PrimaryBlue,
                                    NSAttributedString.Key.underlineStyle: NSUnderlineStyle.single.rawValue,
                                    NSAttributedString.Key.font: NSFont.getMessageFont(),
                                    NSAttributedString.Key.link: url
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
            
            textMessageView.isHidden = false
            
            if let messageId = messageId, messageContent.shouldLoadPaidText {
                let delayTime = DispatchTime.now() + Double(Int64(0.5 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
                DispatchQueue.global().asyncAfter(deadline: delayTime) {
                    self.delegate?.shouldLoadTextDataFor(
                        messageId: messageId,
                        and: self.rowIndex
                    )
                }
            }
        }
    }
    
    func configureWith(
        callLink: BubbleMessageLayoutState.CallLink?
    ) {
        if let callLink = callLink {
            callLinkView.configureWith(callLink: callLink, and: self)
            callLinkView.isHidden = false
        }
    }
    
    func configureWith(
        podcastBoost: BubbleMessageLayoutState.PodcastBoost?
    ) {
        if let podcastBoost = podcastBoost {
            podcastBoostView.configureWith(podcastBoost: podcastBoost)
            podcastBoostView.isHidden = false
        }
    }
    
    func configureWith(
        webLink: BubbleMessageLayoutState.WebLink?,
        linkData: MessageTableCellState.LinkData?
    ) {
        if let _ = webLink {
            
            linkPreviewView.configureWith(
                linkData: linkData,
                delegate: self
            )
            
            linkPreviewView.isHidden = false
            
            if let messageId = messageId, linkData == nil {
                let delayTime = DispatchTime.now() + Double(Int64(0.5 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
                DispatchQueue.global().asyncAfter(deadline: delayTime) {
                    self.delegate?.shouldLoadLinkDataFor(
                        messageId: messageId,
                        and: self.rowIndex
                    )
                }
            }
        }
    }
    
    func configureWith(
        contactLink: BubbleMessageLayoutState.ContactLink?,
        and bubble: BubbleMessageLayoutState.Bubble
    ) {
        if let contactLink = contactLink {
            contactLinkPreviewView.configureWith(contactLink: contactLink, and: bubble, delegate: self)
            contactLinkPreviewView.isHidden = false
        }
    }
    
    func configureWith(
        tribeLink: BubbleMessageLayoutState.TribeLink?,
        tribeData: MessageTableCellState.TribeData?,
        and bubble: BubbleMessageLayoutState.Bubble
    ) {
        if let _ = tribeLink {
            if let tribeData = tribeData {
                tribeLinkPreviewView.configureWith(tribeData: tribeData, and: bubble, delegate: self)
                tribeLinkPreviewView.isHidden = false
            } else if let messageId = messageId {
                let delayTime = DispatchTime.now() + Double(Int64(0.5 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
                DispatchQueue.global().asyncAfter(deadline: delayTime) {
                    self.delegate?.shouldLoadTribeInfoFor(
                        messageId: messageId,
                        and: self.rowIndex
                    )
                }
            }
        }
    }
    
    func configureWith(
        boosts: BubbleMessageLayoutState.Boosts?,
        and bubble: BubbleMessageLayoutState.Bubble
    ) {
        if let boosts = boosts {
            messageBoostView.configureWith(boosts: boosts, and: bubble)
            messageBoostView.isHidden = false
        }
    }
    
    func configureWith(
        paidContent: BubbleMessageLayoutState.PaidContent?,
        and bubble: BubbleMessageLayoutState.Bubble
    ) {
        if let paidContent = paidContent {
            if bubble.direction.isIncoming() {
                paidAttachmentView.configure(paidContent: paidContent, and: self)
                paidAttachmentView.isHidden = false
            } else {
                sentPaidDetailsView.configureWith(paidContent: paidContent)
                sentPaidDetailsView.isHidden = false
            }
            
            paidTextMessageView.isHidden = !paidContent.shouldAddPadding
        }
    }
}
