//
//  NewChatTableDataSource+PreloaderExtension.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 18/07/2023.
//  Copyright © 2023 Tomas Timinskas. All rights reserved.
//

import Foundation

extension NewChatTableDataSource {

    private static let maxPreloadedRows = 200

    @objc func restorePreloadedOrLoadMessages() {
        guard let chat = chat else {
            return
        }

        if let preloadedMessagesState = preloaderHelper.getPreloadedMessagesState(for: chat.id) {
            messageTableCellStateArray = preloadedMessagesState.messageCellStates
            updatePreloadedSnapshot()

            DelayPerformedHelper.performAfterDelay(seconds: 0.2, completion: { [weak self] in
                guard let self = self else { return }
                self.configureResultsController(
                    items: max(self.dataSource.snapshot().numberOfItems, preloadedMessagesState.resultsControllerCount)
                )
            })
        } else {
            configureResultsController(items: max(dataSource.snapshot().numberOfItems, 100))
        }
    }

    @objc func saveMessagesToPreloader() {
        let collectionViewOffsetY = collectionViewScroll.documentYOffset + collectionViewScroll.contentInsets.top
        let firstVisibleItem = collectionView.indexPathForItem(at: NSPoint(x: 0, y: collectionViewOffsetY))?.item ?? 0

        guard let chat = chat, collectionView.numberOfSections > 0 else {
            return
        }

        let numberOfItems = collectionView.numberOfItems(inSection: 0)
        let rowsFromVisibleItem = max(numberOfItems - firstVisibleItem, 0) + 10
        let rowsToPreload = min(rowsFromVisibleItem, Self.maxPreloadedRows)

        preloaderHelper.add(
            messageStateArray: messageTableCellStateArray.endSubarray(size: rowsToPreload),
            resultsControllerCount: messagesCount,
            for: chat.id
        )
    }

    @objc func saveSnapshotCurrentState() {
        saveScrollPosition()
        saveMessagesToPreloader()
    }

    func deleteSnapshotCurrentState() {
        guard let chatId = chat?.id else {
            return
        }

        self.preloaderHelper.reset(
            for: chatId
        )
    }

    @objc func restoreScrollLastPosition() {
        guard let chatId = chat?.id else { return }

        if let scrollState = self.preloaderHelper.getScrollState(
            for: chatId,
            pinnedMessageId: pinnedMessageId
        ), !scrollState.isAtBottom {

            ///Find index of stored first visible item
            if let index = messageTableCellStateArray.firstIndex(where: { $0.getUniqueIdentifier() == scrollState.firstRowId}) {

                let numberOfItems = collectionView.numberOfItems(inSection: 0)
                guard index < numberOfItems else {
                    return
                }
                ///Scroll to stored first visible item
                collectionView.scrollToItems(at: [IndexPath(item: index, section: 0)], scrollPosition: .top)

                ///Get y position  of first visible item
                if let collectionViewOffsetY = collectionView.item(at: index)?.view.frame.origin.y {

                    ///Scroll to visible item offset
                    let newOffset = collectionViewOffsetY + scrollState.difference - collectionViewScroll.contentInsets.top
                    scrollViewDesiredOffset = newOffset
                    collectionViewScroll.documentYOffset = newOffset

                    if (index == 0 && scrollState.difference == 0) {
                        scrollViewDidScroll()
                    }
                }
                return
            }
        }

        ///Scroll to bottom if it didn't scroll to spefici position
        let collectionViewContentSize = collectionView.collectionViewLayout?.collectionViewContentSize.height ?? 0
        let offset = collectionViewContentSize - collectionViewScroll.frame.height + collectionViewScroll.contentInsets.top
        scrollViewDesiredOffset = offset
        collectionViewScroll.documentYOffset = offset

        if scrolledAtBottom {
            return
        }

        scrolledAtBottom = true

        delegate?.didScrollToBottom()
        scrollViewDidScroll()
    }

    func saveScrollPosition() {
        guard let _ = collectionView.enclosingScrollView else { return }
        if collectionView.alphaValue == 0 { return }

        guard let chatId = chat?.id else {
            return
        }

        let collectionViewOffsetY = collectionViewScroll.documentYOffset + collectionViewScroll.contentInsets.top

        ///Find first visible item
        if let firstVisibleRow = collectionView.indexPathForItem(at: NSPoint(x: 0, y: collectionViewOffsetY))?.item {
            ///Find first visible item y position
            if var firstVisibleRowY = collectionView.item(at: firstVisibleRow)?.view.frame.origin.y {
                ///Find unique identifier for first visible item
                var firstVisibleItem = dataSource.snapshot().itemIdentifiers[firstVisibleRow]
                var firstRowId = dataSource.snapshot().itemIdentifiers[firstVisibleRow].getUniqueIdentifier()

                ///If first visible row is date separator, then take next since date separator can change its position based on number of items displayed
                if !firstVisibleItem.isMessageRow && dataSource.snapshot().itemIdentifiers.count > firstVisibleRow + 1 {
                    firstRowId = dataSource.snapshot().itemIdentifiers[firstVisibleRow + 1].getUniqueIdentifier()
                    firstVisibleRowY = collectionView.item(at: firstVisibleRow + 1)?.view.frame.origin.y ?? 0
                }

                ///Save scroll position based on visible item and offset
                self.preloaderHelper.save(
                    firstRowId: firstRowId,
                    difference: collectionViewOffsetY - firstVisibleRowY,
                    isAtBottom: collectionView.isAtBottom(),
                    for: chatId
                )
            }
        }
    }

}
