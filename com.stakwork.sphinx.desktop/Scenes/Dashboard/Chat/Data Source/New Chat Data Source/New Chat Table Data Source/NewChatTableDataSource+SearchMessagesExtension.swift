//
//  NewChatTableDataSource+SearchMessagesExtension.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 18/07/2023.
//  Copyright © 2023 Tomas Timinskas. All rights reserved.
//

import Cocoa

extension NewChatTableDataSource {
    func shouldSearchFor(term: String) {
        let searchTerm = term.trim()
        
        if searchTerm.isNotEmpty && searchTerm.count > 2 {
            performSearch(term: searchTerm)
        } else {
            
            if searchTerm.count > 0 {
                messageBubbleHelper.showGenericMessageView(text: "Search term must be longer than 3 characters")
            }
            
            resetResults()
        }
    }
    
    func performSearch(
        term: String
    ) {
        guard let _ = chat else {
            return
        }
        
        let isNewSearch = searchingTerm != term
        
        searchingTerm = term
        
        if isNewSearch {
            processMessages(
                messages: messagesArray,
                UIUpdateIndex: self.UIUpdateIndex,
                showLoadingMore: false
            )
        } else {
            fetchMoreItems()
        }
    }
    
    func resetResults() {
        searchingTerm = nil
        searchMatches = []
        currentSearchMatchIndex = 0
        
        delegate?.didFinishSearchingWith(
            matchesCount: 0,
            index: currentSearchMatchIndex
        )
        
        DelayPerformedHelper.performAfterDelay(seconds: 0.5, completion: {
            self.reloadAllVisibleRows()
        })
    }
    
    func shouldEndSearch() {
        resetResults()
    }
    
    func processForSearch(
        message: TransactionMessage,
        messageTableCellState: MessageTableCellState,
        index: Int
    ) -> (Int, MessageTableCellState)? {
        guard let searchingTerm = searchingTerm else {
            return nil
        }
        
        if message.isBotHTMLResponse() || message.isPayment() || message.isInvoice() || message.isDeleted() {
            return nil
        }
        
        if let messageContent = message.bubbleMessageContentString, messageContent.isNotEmpty {
            if messageContent.lowercased().contains(searchingTerm.lowercased()) {
                return (index, messageTableCellState)
            }
        }
        return nil
    }
    
    func startSearchProcess() {
        searchMatches = []
    }
    
    func finishSearchProcess(matches: [(Int, MessageTableCellState)]) {
        guard let _ = searchingTerm else {
            return
        }
        
        let isNewSearch = currentSearchMatchIndex == 0

        searchMatches = matches.reversed()
        
        ///should scroll to first results after current scroll position
        if isNewSearch {
            let firstVisibleIndex = (collectionView.indexPathsForVisibleItems().sorted(by: { return $0.item > $1.item }).first?.item ?? 0)
            let newIndex = searchMatches.firstIndex(
                where: {
                    $0.0 <= firstVisibleIndex
                }
            ) ?? 0
            currentSearchMatchIndex = newIndex
        }
        
        ///Show search results
        DispatchQueue.main.async {
            self.delegate?.didFinishSearchingWith(
                matchesCount: self.searchMatches.count,
                index: self.currentSearchMatchIndex
            )
            
            self.scrollToSearchAt(
                index: self.currentSearchMatchIndex,
                shouldScroll: isNewSearch
            )
        }
    }
    
    func scrollToSearchAt(
        index: Int,
        shouldScroll: Bool = true
    ) {
        if searchMatches.count > index && index >= 0 {
            let searchMatchIndex = searchMatches[index].0
            
            if shouldScroll {
                collectionView.scrollToIndex(
                    targetIndex: searchMatchIndex,
                    animated: false,
                    position: NSCollectionView.ScrollPosition.top
                )
                
                if index + 1 == searchMatches.count {
                    loadMoreItemForSearch()
                }
            }
        }
    }
    
    func loadMoreItemForSearch() {
        delegate?.shouldToggleSearchLoadingWheel(active: true)
        
        DelayPerformedHelper.performAfterDelay(seconds: 1.0, completion: {
            self.performSearch(
                term: self.searchingTerm ?? ""
            )
        })
    }
    
    func reloadAllVisibleRows(
        animated: Bool = false,
        completion: (() -> ())? = nil
    ) {
        let tableCellStates = getTableCellStatesForVisibleRows()

        self.dataSourceQueue.sync {
            var snapshot = self.dataSource.snapshot()
            snapshot.reloadItems(tableCellStates)
            DispatchQueue.main.async {
                self.dataSource.apply(snapshot, animatingDifferences: animated) {
                    completion?()
                }
            }
        }
    }
    
    func shouldNavigateOnSearchResultsWith(
        button: ChatSearchResultsBar.NavigateArrowButton
    ) {
        switch(button) {
        case ChatSearchResultsBar.NavigateArrowButton.Up:
            currentSearchMatchIndex += 1
            break
        case ChatSearchResultsBar.NavigateArrowButton.Down:
            currentSearchMatchIndex -= 1
            break
        }
        
        scrollToSearchAt(
            index: currentSearchMatchIndex
        )
    }
}
