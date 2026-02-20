//
//  ThreadTableDataSource.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 28/09/2023.
//  Copyright © 2023 Tomas Timinskas. All rights reserved.
//

import Cocoa
import WebKit

class ThreadTableDataSource : NewChatTableDataSource {
    
    var threadUUID: String!
    var threadOriginalMessage: TransactionMessage? = nil
    
    override var isThread: Bool {
        get {
            return true
        }
    }
    
    init(
        chat: Chat?,
        contact: UserContact?,
        owner: UserContact?,
        tribeAdmin: UserContact?,
        threadUUID: String,
        collectionView: NSCollectionView,
        collectionViewScroll: NSScrollView,
        shimmeringView: ChatShimmeringView,
        headerImage: NSImage?,
        bottomView: NSView,
        delegate: NewChatTableDataSourceDelegate?
    ) {
        
        self.threadUUID = threadUUID
        
        super.init(
            chat: chat,
            contact: contact,
            owner: owner,
            tribeAdmin: tribeAdmin,
            collectionView: collectionView,
            collectionViewScroll: collectionViewScroll,
            shimmeringView: shimmeringView,
            headerImage: headerImage,
            bottomView: bottomView,
            delegate: delegate
        )
    }
    
    override func configureScrollView() {
        super.configureScrollView()
        
        collectionViewScroll.hasVerticalScroller = false
        collectionViewScroll.hasHorizontalScroller = false
        collectionViewScroll.verticalScroller?.alphaValue = 0
        collectionViewScroll.horizontalScroller?.alphaValue = 0
        collectionViewScroll.automaticallyAdjustsContentInsets = false
    }
    
    override func loadMoreItems() {
        ///Nothing to do
    }
    
    override func restorePreloadedOrLoadMessages() {
        configureResultsController(items: max(dataSource.snapshot().numberOfItems, 100))
    }

    override func saveMessagesToPreloader() {
        ///Nothing to do
    }
    
    override func makeCellProvider(
        for collectionView: NSCollectionView
    ) -> DataSource.ItemProvider {
        { [weak self] (tableView, indexPath, dataSourceItem) -> NSCollectionViewItem? in
            guard let self else {
                return nil
            }
            
            return self.getCellFor(
                dataSourceItem: dataSourceItem,
                indexPath: indexPath
            )
        }
    }
    
    override func getThreadOriginalMessageStateAndMediaData(
        owner: UserContact,
        tribeAdmin: UserContact
    ) -> (MessageTableCellState, MessageTableCellState.MediaData?)? {
        guard let threadUUID = threadUUID, let chat = chat else {
            return nil
        }
        
        if threadOriginalMessage == nil {
            threadOriginalMessage = TransactionMessage.getMessageWith(uuid: threadUUID)
        }
        
        guard let threadOriginalMessage = threadOriginalMessage else {
            return nil
        }
        
        let boostMessagesMap = getBoostMessagesMapFor(messages: [threadOriginalMessage])
        let boostMessages = (threadOriginalMessage.uuid != nil) ? (boostMessagesMap[threadOriginalMessage.uuid!] ?? []) : []
        
        let messageTableCellState = MessageTableCellState(
            message: threadOriginalMessage,
            chat: chat,
            owner: owner,
            contact: contact,
            tribeAdmin: tribeAdmin,
            bubbleState: MessageTableCellState.BubbleState.Isolated,
            boostMessages: boostMessages,
            timezoneData: chat.timezoneData,
            isThreadHeaderMessage: true
        )
        
        let mediaData = self.mediaCached[threadOriginalMessage.id]
        
        return (messageTableCellState, mediaData)
    }
}
