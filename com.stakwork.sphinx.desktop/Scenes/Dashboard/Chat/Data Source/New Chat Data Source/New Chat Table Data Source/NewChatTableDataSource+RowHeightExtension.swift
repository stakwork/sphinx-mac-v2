//
//  NewChatTableDataSource+RowHeightExtension.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 19/07/2023.
//  Copyright © 2023 Tomas Timinskas. All rights reserved.
//

import Cocoa

extension NewChatTableDataSource: NSCollectionViewDelegateFlowLayout {

    func collectionView(
        _ collectionView: NSCollectionView,
        layout collectionViewLayout: NSCollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> NSSize {
        guard let tableCellState = getTableCellStateFor(rowIndex: indexPath.item) else {
            return CGSize(width: collectionView.frame.width, height: 0.0)
        }

        let linkData = (tableCellState.linkWeb?.link != nil) ? self.preloaderHelper.linksData[tableCellState.linkWeb!.link] : nil
        let tribeData = (tableCellState.linkTribe?.uuid != nil) ? self.preloaderHelper.tribesData[tableCellState.linkTribe!.uuid] : nil
        let mediaData = (tableCellState.messageId != nil) ? self.mediaCached[tableCellState.messageId!] : nil
        let replyViewAdditionalHeight = (tableCellState.messageId != nil) ? self.replyViewAdditionalHeight[tableCellState.messageId!] : nil

        // Create cache key based on factors that affect row height
        let cacheKey = createHeightCacheKey(
            messageId: tableCellState.messageId,
            bubbleState: tableCellState.bubbleState,
            linkData: linkData,
            tribeData: tribeData,
            mediaData: mediaData,
            replyViewAdditionalHeight: replyViewAdditionalHeight,
            width: collectionView.frame.width
        )

        // Return cached height if available
        if let cachedHeight = rowHeightCache[cacheKey] {
            return CGSize(width: collectionView.frame.width, height: cachedHeight)
        }

        // Calculate and cache height
        let rowHeight = ChatHelper.getRowHeightFor(
            tableCellState,
            linkData: linkData,
            tribeData: tribeData,
            mediaData: mediaData,
            replyViewAdditionalHeight: replyViewAdditionalHeight,
            collectionViewWidth: collectionView.frame.width
        )

        rowHeightCache[cacheKey] = rowHeight

        return CGSize(width: collectionView.frame.width, height: rowHeight)
    }

    private func createHeightCacheKey(
        messageId: Int?,
        bubbleState: MessageTableCellState.BubbleState?,
        linkData: MessageTableCellState.LinkData?,
        tribeData: MessageTableCellState.TribeData?,
        mediaData: MessageTableCellState.MediaData?,
        replyViewAdditionalHeight: CGFloat?,
        width: CGFloat
    ) -> String {
        // Build a cache key from factors that affect row height
        var key = "\(messageId ?? 0)"
        key += "_\(Int(width))"
        key += "_\(linkData != nil ? 1 : 0)"
        key += "_\(tribeData != nil ? 1 : 0)"
        key += "_\(mediaData?.image != nil ? 1 : 0)"
        key += "_\(Int(replyViewAdditionalHeight ?? 0))"
        // Use string representation of bubble state for cache key
        if let bubbleState = bubbleState {
            key += "_\(String(describing: bubbleState))"
        }
        return key
    }

}
