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
        and bubble: BubbleMessageLayoutState.Bubble,
        replyViewAdditionalHeight: CGFloat?
    ) {
        if let messageReply = messageReply {
            replyViewHeightConstraint.constant = NewMessageReplyView.kViewHeight + (replyViewAdditionalHeight ?? 0)
            messageReplyView.configureWith(messageReply: messageReply, and: bubble, delegate: self, isMouseOver: replyViewAdditionalHeight != nil)
            messageReplyView.layoutSubtreeIfNeeded()
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
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 100_000_000)
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
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 100_000_000)
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
                    if mediaData.failed {
                        return
                    }
                    mediaMessageView.configureWith(
                        messageMedia: messageMedia,
                        mediaData: mediaData,
                        bubble: bubble,
                        and: self
                    )
                    mediaMessageView.isHidden = false
                } else if let messageId = messageId, mediaData == nil {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 100_000_000)
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
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 100_000_000)
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
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 100_000_000)
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
            
            textMessageView.isHidden = false
            
            if let messageId = messageId, messageContent.shouldLoadPaidText {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 100_000_000)
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
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 100_000_000)
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
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 100_000_000)
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
