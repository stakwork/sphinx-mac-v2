//
//  ThreadRepliesView.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 27/09/2023.
//  Copyright © 2023 Tomas Timinskas. All rights reserved.
//

import Cocoa

class ThreadRepliesView: NSView, LoadableNib {
    
    @IBOutlet var contentView: NSView!
    
    @IBOutlet weak var firstReplyContainer: NSView!
    @IBOutlet weak var firstReplyBubbleView: NSBox!
    @IBOutlet weak var firstReplyAvatarView: ChatSmallAvatarView!
    @IBOutlet weak var firstReplyAvatarOverlay: NSBox!
    
    @IBOutlet weak var secondReplyContainer: NSView!
    @IBOutlet weak var secondReplyBubbleView: NSBox!
    @IBOutlet weak var secondReplyAvatarView: ChatSmallAvatarView!
    @IBOutlet weak var secondReplyAvatarOverlay: NSBox!
    
    @IBOutlet weak var moreRepliesContainer: NSView!
    @IBOutlet weak var moreRepliesBubbleView: NSBox!
    @IBOutlet weak var moreRepliesCountView: NSBox!
    @IBOutlet weak var moreRepliesCountLabel: NSTextField!
    @IBOutlet weak var moreRepliesLabel: NSTextField!
    
    @IBOutlet weak var messageFakeContainer: NSView!
    @IBOutlet weak var messageFakeBubbleView: NSBox!
    
    var mentionsBadgeContainer: NSBox!
    var mentionsBadgeLabel: NSTextField!
    
    static let kViewHeight1Reply: CGFloat = 29
    static let kViewHeight2Replies: CGFloat = 49
    static let kViewHeightSeveralReplies: CGFloat = 84

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        loadViewFromNib()
        setup()
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        loadViewFromNib()
        setup()
    }
    
    func setup() {
        moreRepliesLabel.stringValue = "more-replies".localized
        
        firstReplyContainer.wantsLayer = true
        firstReplyContainer.layer?.masksToBounds = false
        
        secondReplyContainer.wantsLayer = true
        secondReplyContainer.layer?.masksToBounds = false
        
        moreRepliesContainer.wantsLayer = true
        moreRepliesContainer.layer?.masksToBounds = false
        
        messageFakeContainer.wantsLayer = true
        messageFakeContainer.layer?.masksToBounds = false
        
        firstReplyAvatarView.setInitialLabelSize(size: 10)
        firstReplyAvatarView.resetView()
        
        secondReplyAvatarView.setInitialLabelSize(size: 10)
        secondReplyAvatarView.resetView()
        
        setupMentionsBadge()
    }
    
    func setupMentionsBadge() {
        let badge = NSBox()
        badge.boxType = .custom
        badge.fillColor = NSColor.Sphinx.PrimaryBlue
        badge.borderWidth = 0
        badge.cornerRadius = 9
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.isHidden = true
        contentView.addSubview(badge)
        
        let label = NSTextField(labelWithString: "")
        label.textColor = NSColor.white
        label.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        badge.addSubview(label)
        
        NSLayoutConstraint.activate([
            badge.trailingAnchor.constraint(equalTo: moreRepliesContainer.trailingAnchor, constant: -12),
            badge.centerYAnchor.constraint(equalTo: moreRepliesContainer.centerYAnchor),
            badge.heightAnchor.constraint(equalToConstant: 18),
            badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 36),
            
            label.leadingAnchor.constraint(equalTo: badge.leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: badge.trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
        ])
        
        mentionsBadgeContainer = badge
        mentionsBadgeLabel = label
    }
    
    func configureWith(
        threadMessages: BubbleMessageLayoutState.ThreadMessages,
        direction: MessageTableCellState.MessageDirection
    ) {
        let firstReplySenderInfo = threadMessages.firstReplySenderInfo
        
        firstReplyAvatarView.configureForUserWith(
            color: firstReplySenderInfo.0,
            alias: firstReplySenderInfo.1,
            picture: firstReplySenderInfo.2
        )
        
        if let secondReplySenderInfo = threadMessages.secondReplySenderInfo {
            secondReplyAvatarView.configureForUserWith(
                color: secondReplySenderInfo.0,
                alias: secondReplySenderInfo.1,
                picture: secondReplySenderInfo.2
            )
            secondReplyContainer.isHidden = false
        } else {
            secondReplyContainer.isHidden = true
        }
        
        if threadMessages.moreRepliesCount > 0 {
            moreRepliesCountLabel.stringValue = "\(threadMessages.moreRepliesCount)"
            moreRepliesContainer.isHidden = false
        } else {
            moreRepliesContainer.isHidden = true
        }
        
        let mentionsCount = threadMessages.mentionsCount
        if mentionsCount > 0 {
            mentionsBadgeLabel.stringValue = "@ \(mentionsCount)"
            mentionsBadgeContainer.isHidden = false
        } else {
            mentionsBadgeContainer.isHidden = true
        }
        
        let isOutgoing = direction.isOutgoing()
        let threadBubbleColor = isOutgoing ? NSColor.Sphinx.ReceivedMsgBG : NSColor.Sphinx.ThreadLastReply
        messageFakeBubbleView.fillColor = threadBubbleColor
        messageFakeBubbleView.borderWidth = 0
    }
}
