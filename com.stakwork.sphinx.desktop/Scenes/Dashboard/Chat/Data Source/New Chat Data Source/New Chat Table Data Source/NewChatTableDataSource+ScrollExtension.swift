//
//  NewChatTableDataSource+ScrollExtension.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 18/07/2023.
//  Copyright © 2023 Tomas Timinskas. All rights reserved.
//

import Cocoa

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
            self?.scrollViewDidScroll()
        }        
    }
    
    func scrollViewDidScroll() {
        MessageOptionsHelper.sharedInstance.hideMenu()
        
        if let scrollViewDesiredOffset = scrollViewDesiredOffset {
            if scrollViewDesiredOffset == collectionViewScroll.documentYOffset {
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
        
        if loadingMoreItems {
            return
        }
        
        if allItemsLoaded {
            return
        }
        
        collectionViewScroll.verticalScrollElasticity = .none
        loadingMoreItems = true
        
        DelayPerformedHelper.performAfterDelay(seconds: 1.0, completion: {
            self.fetchMoreItems()
        })
    }
    
    func loadMoreItems(itemsCount: Int) {
        collectionViewScroll.contentView.animator().setBoundsOrigin(collectionViewScroll.contentView.bounds.origin)
        configureResultsController(items: messagesCount + itemsCount)
    }
    
    @objc func loadMoreItems() {
        loadMoreItems(itemsCount: 50)
    }
    
    func fetchMoreItems() {
        if isThread {
            return
        }
        if let publicKey = contact?.publicKey ?? chat?.ownerPubkey {
            if let chat = chat {
                let backgroundContext = CoreDataManager.sharedManager.getBackgroundContext()
                var minIndex: Int? = nil
                let itemsPerPage = 100
                
                backgroundContext.performSafely {
                    minIndex = TransactionMessage.getMinMessageIndex(for: chat, context: backgroundContext)
                    
                    if let minIndex = minIndex {
                        if (minIndex - 1) <= 0 {
                            return
                        }
                        DispatchQueue.global(qos: .background).async {
                            SphinxOnionManager.sharedInstance.startChatMsgBlockFetch(
                                startIndex: minIndex - 1,
                                itemsPerPage: itemsPerPage,
                                stopIndex: 0,
                                publicKey: publicKey
                            ) { messagesCount in
                                if messagesCount < itemsPerPage {
                                    self.allItemsLoaded = true
                                    
                                    self.processMessages(
                                        messages: self.messagesArray,
                                        UIUpdateIndex: self.UIUpdateIndex,
                                        showLoadingMore: false
                                    )
                                    
                                    if self.isSearching {
                                        self.delegate?.shouldToggleSearchLoadingWheel(active: false)
                                    }
                                } else {
                                    self.loadMoreItems(itemsCount: messagesCount)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    @objc func shouldHideNewMsgsIndicator() -> Bool {
        return collectionView.getDistanceToBottom() < 20
    }
}
