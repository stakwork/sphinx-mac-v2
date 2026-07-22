//
//  CommonNewMessageCollectionViewItem.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 18/07/2023.
//  Copyright © 2023 Tomas Timinskas. All rights reserved.
//

import Cocoa

@MainActor
class CommonNewMessageCollectionViewitem : NSCollectionViewItem {
    
    weak var delegate: ChatCollectionViewItemDelegate!
    
    var rowIndex: Int!
    var messageId: Int?
    var originalMessageId: Int?
    
    let kChatAvatarHeight: CGFloat = 36
    
    static let kMaximumLabelBubbleWidth: CGFloat = 500
    static let kMaximumMediaBubbleWidth: CGFloat = 400
    static let kMaximumLinksBubbleWidth: CGFloat = 400
    static let kMaximumFileBubbleWidth: CGFloat = 300
    static let kMaximumPodcastBoostBubbleWidth: CGFloat = 200
    static let kMaximumCallLinkBubbleWidth: CGFloat = 250
    static let kMaximumGenericFileBubbleWidth: CGFloat = 300
    static let kMaximumDirectPaymentWithMediaBubbleWidth: CGFloat = 300
    static let kMaximumDirectPaymentWithTextBubbleWidth: CGFloat = 250
    static let kMaximumDirectPaymentBubbleWidth: CGFloat = 200
    static let kMaximumAudioBubbleWidth: CGFloat = 300
    static let kMaximumPodcastAudioBubbleWidth: CGFloat = 400
    static let kMaximumPaidTextViewBubbleWidth: CGFloat = 400
    static let kMaximumInvoiceBubbleWidth: CGFloat = 300
    static let kMaximumThreadBubbleWidth: CGFloat = 400
    /// Outer horizontal margin consumed by the layout for **received** messages:
    /// 16 (outer leading) + 40 (avatar container) + 4 (avatar spacer) + 7 (trailing spacer) + 16 (outer trailing) = 83
    static let kTextLabelMargins: CGFloat = 83

    /// Outer horizontal margin consumed by the layout for **outgoing** messages:
    /// 16 (outer leading) + 0 (no avatar/spacer) + 7 (trailing spacer) + 16 (outer trailing) = 39
    /// Using the received margin (83) for outgoing over-estimates the horizontal space consumed,
    /// which narrows the measurement width and causes height over-estimation (not clipping),
    /// but using the accurate value ensures heights are correct for both directions.
    static let kTextLabelMarginsOutgoing: CGFloat = 39
    
    static let kHighlightedTextVerticalExtraPadding: CGFloat = 12
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    func getBubbleView() -> NSBox? {
        return nil
    }
}
