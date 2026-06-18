//
//  ThreadCollectionView+MessageTypesExtension.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 27/09/2023.
//  Copyright © 2023 Tomas Timinskas. All rights reserved.
//

import Cocoa

extension ThreadCollectionViewItem {
    
    func configureWith(
        threadMessages: BubbleMessageLayoutState.ThreadMessages?,
        and bubble: BubbleMessageLayoutState.Bubble
    ) {
        if let threadMessages = threadMessages {
            threadRepliesView.configureWith(
                threadMessages: threadMessages,
                direction: bubble.direction
            )
            
            threadRepliesView.isHidden = false
        }
    }
    
    func configureWith(
        threadLastReply: BubbleMessageLayoutState.ThreadLastReply?,
        and bubble: BubbleMessageLayoutState.Bubble
    ) {
        if let threadLastReply = threadLastReply {
            threadLastMessageHeader.configureWith(threadLastReply: threadLastReply)
            threadLastMessageHeader.isHidden = false
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
                let delayTime = DispatchTime.now() + Double(Int64(0.1 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
                DispatchQueue.main.asyncAfter(deadline: delayTime) {
                    self.delegate?.shouldLoadAudioDataFor(
                        messageId: messageId,
                        and: self.rowIndex
                    )
                }
            }
        }
    }

    func configureWith(
        originalMessageMedia: BubbleMessageLayoutState.MessageMedia?,
        mediaData: MessageTableCellState.MediaData?,
        and bubble: BubbleMessageLayoutState.Bubble
    ) {
        if let originalMessageMedia = originalMessageMedia {
            
            mediaMessageView.configureWith(
                messageMedia: originalMessageMedia,
                mediaData: mediaData,
                bubble: bubble,
                and: self,
                isThreadRow: true
            )
            mediaMessageView.isHidden = false
            mediaMessageContainer.isHidden = false
            
            mediaMessageView.mediaButton.isEnabled = false
            
            if let originalMessageId = originalMessageId, mediaData == nil {
                let delayTime = DispatchTime.now() + Double(Int64(0.1 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
                DispatchQueue.main.asyncAfter(deadline: delayTime) {
                    if originalMessageMedia.isImage {
                        self.delegate?.shouldLoadImageDataFor(
                            messageId: originalMessageId,
                            and: self.rowIndex
                        )
                    } else if originalMessageMedia.isPdf {
                        self.delegate?.shouldLoadPdfDataFor(
                            messageId: originalMessageId,
                            and: self.rowIndex
                        )
                    } else if originalMessageMedia.isVideo {
                        self.delegate?.shouldLoadVideoDataFor(
                            messageId: originalMessageId,
                            and: self.rowIndex
                        )
                    } else if originalMessageMedia.isGiphy {
                        self.delegate?.shouldLoadGiphyDataFor(
                            messageId: originalMessageId,
                            and: self.rowIndex
                        )
                    }
                }
            }
        }
    }

    func configureWith(
        originalMessageAudio: BubbleMessageLayoutState.Audio?,
        mediaData: MessageTableCellState.MediaData?,
        and bubble: BubbleMessageLayoutState.Bubble
    ) {
        if let originalMessageAudio = originalMessageAudio {
            audioMessageView.configureWith(
                audio: originalMessageAudio,
                mediaData: mediaData,
                bubble: bubble,
                and: self
            )
            audioMessageView.isHidden = false
            
            if let originalMessageId = originalMessageId, mediaData == nil {
                let delayTime = DispatchTime.now() + Double(Int64(0.1 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
                DispatchQueue.main.asyncAfter(deadline: delayTime) {
                    self.delegate?.shouldLoadAudioDataFor(
                        messageId: originalMessageId,
                        and: self.rowIndex
                    )
                }
            }
        }
    }

    func configureWith(
        originalMessaggeGenericFile: BubbleMessageLayoutState.GenericFile?,
        mediaData: MessageTableCellState.MediaData?
    ) {
        if let _ = originalMessaggeGenericFile {
            
            fileDetailsView.configureWith(
                mediaData: mediaData,
                and: self
            )
            
            fileDetailsView.isHidden = false
            
            if let originalMessageId = originalMessageId, mediaData == nil {
                let delayTime = DispatchTime.now() + Double(Int64(0.1 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
                DispatchQueue.main.asyncAfter(deadline: delayTime) {
                    self.delegate?.shouldLoadFileDataFor(
                        messageId: originalMessageId,
                        and: self.rowIndex
                    )
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
                let delayTime = DispatchTime.now() + Double(Int64(0.1 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
                DispatchQueue.main.asyncAfter(deadline: delayTime) {
                    self.delegate?.shouldLoadFileDataFor(
                        messageId: messageId,
                        and: self.rowIndex
                    )
                }
            }
        }
    }

    func configureOriginalMessageTextWith(
        threadMessage: BubbleMessageLayoutState.ThreadMessages?,
        searchingTerm: String?,
        collectionViewWidth: CGFloat
    ) {
        if let originalMessage = threadMessage?.originalMessage, let text = originalMessage.text, text.isNotEmpty {
            
            let labelHeight = ChatHelper.getThreadOriginalTextMessageHeightFor(
                text,
                collectionViewWidth: collectionViewWidth,
                maxHeight: Constants.kMessageLineHeight * 2
            )
            
            labelHeightConstraint.constant = labelHeight
            textMessageView.superview?.layoutSubtreeIfNeeded()
            
            messageLabel.stringValue = text
            messageLabel.font = NSFont.getMessageFont()
            
            textMessageView.isHidden = false
            
//            if let messageId = messageId, messageContent.shouldLoadPaidText {
//                let delayTime = DispatchTime.now() + Double(Int64(0.1 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
//                DispatchQueue.global().asyncAfter(deadline: delayTime) {
//                    self.delegate?.shouldLoadTextDataFor(
//                        messageId: messageId,
//                        and: self.rowIndex
//                    )
//                }
//            }
        }
    }
    
    func configureLastReplyWith(
        messageContent: BubbleMessageLayoutState.MessageContent?,
        searchingTerm: String?,
        collectionViewWidth: CGFloat
    ) {
        if let messageContent = messageContent, let text = messageContent.text, text.isNotEmpty {
            
            let usePlainText = messageContent.hasNoMarkdown && !text.containsMarkdownSyntax
            
            let labelHeight: CGFloat
            if usePlainText {
                let maxWidth = min(
                    CommonNewMessageCollectionViewitem.kMaximumThreadBubbleWidth,
                    collectionViewWidth - CommonNewMessageCollectionViewitem.kTextLabelMargins
                )
                labelHeight = ChatHelper.getTextHeightFor(
                    text: text,
                    width: maxWidth,
                    useMarkdown: false
                )
            } else {
                labelHeight = ChatHelper.getThreadOriginalTextMessageHeightFor(
                    text,
                    collectionViewWidth: collectionViewWidth,
                    highlightedMatches: messageContent.highlightedMatches,
                    boldMatches: messageContent.boldMatches,
                    linkMatches: messageContent.linkMatches,
                    linkMarkdownMatches: messageContent.linkMarkdownMatches
                )
            }
            
            lastReplyLabelHeightConstraint.constant = labelHeight
            textMessageView.superview?.layoutSubtreeIfNeeded()
            
            lastReplyTextMessageView.isHidden = false
            
            if usePlainText && searchingTerm == nil {
                lastReplyMessageLabel.attributedStringValue = NSMutableAttributedString(string: "")

                lastReplyMessageLabel.stringValue = messageContent.text ?? ""
                lastReplyMessageLabel.font = NSFont.getMessageFont()
            } else {
                let messageC = messageContent.text ?? ""

                let attributedString = NSMutableAttributedString(
                    attributedString: ChatHelper.markdownRenderer.render(messageC)
                )
                ChatHelper.applySphinxLinkTransforms(to: attributedString)

                ///Search term formatting
                if let term = searchingTerm, !term.isEmpty {
                    let searchingTermRange = (messageC.lowercased() as NSString).range(of: term.lowercased())
                    attributedString.addAttributes(
                        [NSAttributedString.Key.backgroundColor: NSColor.Sphinx.PrimaryGreen],
                        range: searchingTermRange
                    )
                }

                lastReplyMessageLabel.attributedStringValue = attributedString
                lastReplyMessageLabel.isEnabled = true
            }
            
//            if let messageId = messageId, messageContent.shouldLoadPaidText {
//                let delayTime = DispatchTime.now() + Double(Int64(0.1 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
//                DispatchQueue.global().asyncAfter(deadline: delayTime) {
//                    self.delegate?.shouldLoadTextDataFor(
//                        messageId: messageId,
//                        and: self.rowIndex
//                    )
//                }
//            }
        }
    }
    
    func configureLastReplyWith(
        audio: BubbleMessageLayoutState.Audio?,
        mediaData: MessageTableCellState.MediaData?,
        and bubble: BubbleMessageLayoutState.Bubble
    ) {
        if let audio = audio {
            lastReplyAudioMessageView.configureWith(
                audio: audio,
                mediaData: mediaData,
                bubble: bubble,
                and: self
            )
            lastReplyAudioMessageView.isHidden = false
            
            if let messageId = messageId, mediaData == nil {
                let delayTime = DispatchTime.now() + Double(Int64(0.1 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
                DispatchQueue.main.asyncAfter(deadline: delayTime) {
                    self.delegate?.shouldLoadAudioDataFor(
                        messageId: messageId,
                        and: self.rowIndex
                    )
                }
            }
        }
    }

    func configureLastReplyWith(
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
                    lastReplyMediaMessageView.mediaButton.isEnabled = false
                    
                }
//                else if let messageId = messageId, mediaData == nil {
//                    let delayTime = DispatchTime.now() + Double(Int64(0.1 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
//                    DispatchQueue.global().asyncAfter(deadline: delayTime) {
//                        self.delegate?.shouldLoadLinkImageDataFor(
//                            messageId: messageId,
//                            and: self.rowIndex
//                        )
//                    }
//                }
            } else {
                lastReplyMediaMessageView.configureWith(
                    messageMedia: messageMedia,
                    mediaData: mediaData,
                    bubble: bubble,
                    and: self
                )
                lastReplyMediaMessageView.isHidden = false
                lastReplyMediaMessageView.mediaButton.isEnabled = false
                
                if let messageId = messageId, mediaData == nil {
                    let delayTime = DispatchTime.now() + Double(Int64(0.1 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
                    DispatchQueue.main.asyncAfter(deadline: delayTime) {
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
    
    func configureLastReplyWith(
        genericFile: BubbleMessageLayoutState.GenericFile?,
        mediaData: MessageTableCellState.MediaData?
    ) {
        if let _ = genericFile {
            
            lastReplyFileDetailsView.configureWith(
                mediaData: mediaData,
                and: self
            )
            
            lastReplyFileDetailsView.isHidden = false
            
            if let messageId = messageId, mediaData == nil {
                let delayTime = DispatchTime.now() + Double(Int64(0.1 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
                DispatchQueue.main.asyncAfter(deadline: delayTime) {
                    self.delegate?.shouldLoadFileDataFor(
                        messageId: messageId,
                        and: self.rowIndex
                    )
                }
            }
        }
    }

    func configureLastReplyWith(
        boosts: BubbleMessageLayoutState.Boosts?,
        and bubble: BubbleMessageLayoutState.Bubble
    ) {
        if let boosts = boosts {
            lastReplyMessageBoostView.configureWith(boosts: boosts, and: bubble)
            lastReplyMessageBoostView.isHidden = false
        }
    }

    func configureLastReplyWith(
        callLink: BubbleMessageLayoutState.CallLink?,
        participantsData: MessageTableCellState.ParticipantsData? = nil
    ) {
        if let callLink = callLink {
            lastReplyCallLinkView.configureWith(callLink: callLink, and: self)
            lastReplyCallLinkView.configureWith(participantsData: participantsData)
            lastReplyCallLinkView.isHidden = false

            if let messageId = messageId, let rowIndex = rowIndex {
                let urlString = callLink.link
                if let url = URL(string: urlString),
                   let roomName = url.pathComponents.filter({ !$0.isEmpty && $0 != "/" }).last {
                    delegate?.shouldLoadCallParticipantsFor(messageId: messageId, roomName: roomName, and: rowIndex)
                }
            }
        }
    }
}
