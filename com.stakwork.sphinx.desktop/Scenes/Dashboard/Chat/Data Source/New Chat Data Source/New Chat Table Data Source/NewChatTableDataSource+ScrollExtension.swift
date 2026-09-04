//
//  NewChatTableDataSource+ScrollExtension.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 18/07/2023.
//  Copyright © 2023 Tomas Timinskas. All rights reserved.
//

import Cocoa

@MainActor
extension NewChatTableDataSource: NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        collectionView.deselectAll(nil)
        
        if let indexPath = indexPaths.first {
            
            if messageTableCellStateArray.count > indexPath.item {
                let mutableTableCellStateArray = messageTableCellStateArray[indexPath.item]
                
                if let message = mutableTableCellStateArray.message, mutableTableCellStateArray.isThread {
                    delegate?.shouldShowThreadFor(message: message)
                }
            }
        }
        MessageOptionsHelper.sharedInstance.hideMenu()
    }
    
    func addScrollObservers() {
        NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: collectionViewScroll.contentView,
            queue: OperationQueue.main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scrollViewDidScroll()
            }
        }
    }
    
    func scrollViewDidScroll() {
        MessageOptionsHelper.sharedInstance.hideMenu()
        
        if let scrollViewDesiredOffset = scrollViewDesiredOffset {
            if scrollViewDesiredOffset == collectionViewScroll.documentYOffset {
                self.scrollViewDesiredOffset = nil
                DelayPerformedHelper.performAfterDelay(seconds: 0.05, completion: {
                    self.shimmeringView.toggle(show: false)
                    self.collectionView.alphaValue = 1.0
                })
            }
        }
        
        if collectionView.getDistanceToBottom() < 10 {
            didScrollToBottom()
        } else if collectionViewScroll.documentYOffset <= 40 {
            didScrollToTop()
        } else {
            didScrollOutOfBottomArea()
        }
    }
    
    func scrollViewShouldScrollToTop(_ scrollView: NSScrollView) -> Bool {
        return false
    }
    
    func didScrollOutOfBottomArea() {
        scrolledAtBottom = false
        
        delegate?.didScrollOutOfBottomArea()
    }
    
    func didScrollToBottom() {
        if scrolledAtBottom {
            return
        }
        
        scrolledAtBottom = true
        
        delegate?.didScrollToBottom()
    }
    
    func didScrollToTop() {
        if isSearching {
            return
        }

        switch pagination.beginLoad(isThread: isThread, hasChat: chat != nil) {
        case .skippedThread:
            print("pagination: skip didScrollToTop — thread")
            return
        case .skippedNotIdle:
            print("pagination: skip didScrollToTop — phase=\(phase)")
            return
        case .skippedNoChat:
            print("pagination: skip didScrollToTop — no chat")
            return
        case .started:
            print("pagination: idle→loading")
        }

        collectionViewScroll.verticalScrollElasticity = .none
        processMessages(
            messages: messagesArray,
            UIUpdateIndex: UIUpdateIndex,
            showLoadingMore: contact?.isAgent != true
        )

        DelayPerformedHelper.performAfterDelay(seconds: 1.0, completion: {
            self.fetchMoreItems()
        })
    }
    
    func loadMoreItems(itemsCount: Int) {
        pendingScrollRestore = true
        collectionViewScroll.contentView.animator().setBoundsOrigin(collectionViewScroll.contentView.bounds.origin)
        configureResultsController(items: messagesCountRequested + itemsCount)
        processAfterResultsControllerFetch()
    }

    // Called immediately after configureResultsController to handle the race where the background
    // context save propagates to the main context before the new NSFetchedResultsController sets
    // its delegate, preventing didChangeContentWith from firing for the fetched objects.
    private func processAfterResultsControllerFetch() {
        guard pendingScrollRestore else { return }
        guard let objects = messagesResultsController?.sections?.first?.objects as? [TransactionMessage] else { return }
        let sorted = sortedByDate(messages: objects.filter { !$0.isApprovedRequest() })
        guard sorted.count > messagesArray.count else { return }
        print("pagination: explicit process after fetch (\(messagesArray.count)→\(sorted.count))")
        messagesCountFetched = sorted.count
        messagesArray = sorted
        UIUpdateIndex += 1
        updateMessagesStatusesFrom(messages: messagesArray)
        processMessages(
            messages: messagesArray,
            UIUpdateIndex: UIUpdateIndex,
            showLoadingMore: !allItemsLoaded && contact?.isAgent != true
        )
    }
    
    @objc func loadMoreItems() {
        loadMoreItems(itemsCount: 50)
    }

    func finishPagination(exhausted: Bool) {
        print("pagination: loading→\(exhausted ? "exhausted" : "idle") pendingScrollRestore=true")
        pagination.completePage(exhausted: exhausted)
    }
    
    func fetchMoreItems() {
        guard phase == .loading else {
            print("pagination: skip fetchMoreItems — phase=\(phase)")
            return
        }
        if isThread {
            print("pagination: skip fetchMoreItems — thread")
            pagination.abortToIdle()
            return
        }
        if contact?.isAgent == true {
            print("pagination: agent local-only loadMoreItems")
            loadMoreItems()
            return
        }
        guard let publicKey = contact?.publicKey ?? chat?.ownerPubkey else {
            print("pagination: no pubkey — loading→idle")
            pagination.abortToIdle()
            processMessages(
                messages: messagesArray,
                UIUpdateIndex: UIUpdateIndex,
                showLoadingMore: false
            )
            return
        }
        guard let chat = chat else {
            print("pagination: no chat after pubkey — loading→idle")
            pagination.abortToIdle()
            processMessages(
                messages: messagesArray,
                UIUpdateIndex: UIUpdateIndex,
                showLoadingMore: false
            )
            return
        }
        guard SphinxOnionManager.sharedInstance.getAccountSeed() != nil else {
            print("pagination: nil seed — loading→idle")
            pagination.abortToIdle()
            processMessages(
                messages: messagesArray,
                UIUpdateIndex: UIUpdateIndex,
                showLoadingMore: false
            )
            return
        }

        let chatId = chat.id
        let backgroundContext = CoreDataManager.sharedManager.getBackgroundContext()
        let itemsPerPage = 100

        // Set before background work so the old NSFetchedResultsController's
        // didChangeContentWith (fired by the merge notification before Task @MainActor runs)
        // sees pendingScrollRestore=true and produces a dispatch with shouldRestoreScrollPosition=true.
        pendingScrollRestore = true

        backgroundContext.performSafely {
            guard let chat = Chat.getChatWith(id: chatId, managedContext: backgroundContext) else {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    print("pagination: chat lookup failed — loading→idle")
                    self.pagination.abortToIdle()
                    self.processMessages(messages: self.messagesArray, UIUpdateIndex: self.UIUpdateIndex, showLoadingMore: false)
                }
                return
            }
            let minIndex = TransactionMessage.getMinMessageIndex(for: chat, context: backgroundContext)

            if let minIndex = minIndex {
                if (minIndex - 1) <= 0 {
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        print("pagination: already at oldest minIndex=\(minIndex)")
                        self.finishPagination(exhausted: true)
                        self.loadMoreItems(itemsCount: 0)
                    }
                    return
                }
                DispatchQueue.global(qos: .background).async {
                    SphinxOnionManager.sharedInstance.startChatMsgBlockFetch(
                        startIndex: minIndex - 1,
                        itemsPerPage: itemsPerPage,
                        stopIndex: 0,
                        publicKey: publicKey
                    ) { messagesCount in
                        Task { @MainActor in
                            SphinxOnionManager.sharedInstance.getMessagesStatusForPendingMessages()
                            let exhausted = messagesCount < itemsPerPage
                            print("pagination: network messagesCount=\(messagesCount) itemsPerPage=\(itemsPerPage) exhausted=\(exhausted)")
                            self.finishPagination(exhausted: exhausted)
                            self.loadMoreItems(itemsCount: max(messagesCount, 0))

                            if self.isSearching {
                                self.delegate?.shouldToggleSearchLoadingWheel(active: false)
                            }
                        }
                    }
                }
            } else {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    print("pagination: nil minIndex — exhausted")
                    self.finishPagination(exhausted: true)
                    self.loadMoreItems(itemsCount: 0)
                }
            }
        }
    }
    
    @objc func shouldHideNewMsgsIndicator() -> Bool {
        return collectionView.getDistanceToBottom() < 20
    }
}
