//
//  NewChatTableDataSource.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 18/07/2023.
//  Copyright © 2023 Tomas Timinskas. All rights reserved.
//

import Cocoa
import WebKit

protocol NewChatTableDataSourceDelegate : AnyObject {
    ///New msgs indicator
    func configureNewMessagesIndicatorWith(newMsgCount: Int)
    
    ///Scrolling
    func didScrollToBottom()
    func didScrollOutOfBottomArea()
    
    ///Attachments
    func shouldGoToMediaFullScreenFor(messageId: Int)
    
    ///LinkPreviews
    func didTapOnContactWith(pubkey: String, and routeHint: String?)
    func didTapOnTribeWith(joinLink: String)
    
    ///Tribes
    func didDeleteTribe()
    
    ///First messages / Socket
    func didUpdateChat(_ chat: Chat)
    
    ///Message menu
//    func didLongPressOn(cell: UITableViewCell, with messageId: Int, bubbleViewRect: CGRect)
    
    ///Leaderboard
    func shouldShowMemberPopupFor(messageId: Int)
    
    ///Message reply
    func shouldReplyToMessage(message: TransactionMessage)
    
    ///Invoices
    func shouldPayInvoiceFor(messageId: Int)
    
    ///Message Menu
    func shouldShowOptionsFor(messageId: Int, from button: NSButton)
    
    ///Messages search
    func isOnStandardMode() -> Bool
    func didFinishSearchingWith(matchesCount: Int, index: Int)
    func shouldToggleSearchLoadingWheel(active: Bool)
    
    ///Threads
    func shouldShowThreadFor(message: TransactionMessage)
    func shouldReloadThreadHeader()
    func shouldCloseThread()
    
    ///Invoices
    func shouldStartCallWith(link: String, audioOnly: Bool)
    
    ///Empty chat placeholder
    func updateEmptyView()
    
    ///Pending outgoing message
    func shouldUpdateHeaderScheduleIcon(message: TransactionMessage?)
}

class NewChatTableDataSource : NSObject {
    
    ///Delegate
    weak var delegate: NewChatTableDataSourceDelegate?
    
    ///View references
    var collectionView : NSCollectionView!
    var collectionViewScroll: NSScrollView!
    var shimmeringView: ChatShimmeringView!
    var headerImage: NSImage?
    var bottomView: NSView!
    
    ///Chat
    var chat: Chat?
    var contact: UserContact?
    var tribeAdmin: UserContact?
    var owner: UserContact?
    var pinnedMessageId: Int? = nil
    
    ///Data Source related
    var messagesResultsController: NSFetchedResultsController<TransactionMessage>!
    var additionMessagesResultsController: NSFetchedResultsController<TransactionMessage>!
    
    var currentDataSnapshot: DataSourceSnapshot!
    var dataSource: DataSource!
    
    ///Helpers
    var preloaderHelper = MessagesPreloaderHelper.sharedInstance
    let messageBubbleHelper = NewMessageBubbleHelper()
    let audioPlayerHelper = NewAudioPlayerHelper()
    var podcastPlayerController = PodcastPlayerController.sharedInstance
    
    ///Messages Data
    var messagesArray: [TransactionMessage] = []
    var messageTableCellStateArray: [MessageTableCellState] = []
    var mediaCached: [Int: MessageTableCellState.MediaData] = [:]
    var uploadingProgress: [Int: MessageTableCellState.UploadProgressData] = [:]
    var replyViewAdditionalHeight: [Int: CGFloat] = [:]
    
    var searchingTerm: String? = nil
    var searchMatches: [(Int, MessageTableCellState)] = []
    var currentSearchMatchIndex: Int = 0
    var isSearching: Bool {
        get {
            return searchingTerm != nil
        }
    }
    
    ///Scroll and pagination
    var messagesCount = 0
    var loadingMoreItems = false
    var scrolledAtBottom = false
    var scrollViewDesiredOffset: CGFloat? = nil
    var isFirstLoad = true
    
    ///Messages statuses restore
    var lastMessageTagRestored = ""
    
    ///Chat Helper
    let chatHelper = ChatHelper()
    
    ///Semaphore for UI update
    var UIUpdateIndex = 0
    
    ///Data source updates queue
    let dataSourceQueue = DispatchQueue(label: "chat.datasourceQueue", attributes: .concurrent)
    let mediaReloadQueue = DispatchQueue(label: "chat.media.datasourceQueue", attributes: .concurrent)
    
    ///Constants
    static let kThreadHeaderRowIndex = -10
    
    var isThread: Bool {
        get {
            return false
        }
    }
    
    init(
        chat: Chat?,
        contact: UserContact?,
        owner: UserContact?,
        tribeAdmin: UserContact?,
        collectionView : NSCollectionView,
        collectionViewScroll: NSScrollView,
        shimmeringView: ChatShimmeringView,
        headerImage: NSImage?,
        bottomView: NSView,
        delegate: NewChatTableDataSourceDelegate?
    ) {
        super.init()
        
        self.chat = chat
        self.contact = contact
        self.owner = owner
        self.tribeAdmin = tribeAdmin
        
        self.collectionView = collectionView
        self.headerImage = headerImage
        self.collectionViewScroll = collectionViewScroll
        self.headerImage = headerImage
        self.bottomView = bottomView
        self.shimmeringView = shimmeringView
        
        self.delegate = delegate
        
        addScrollObservers()
        configureScrollView()
        configureTableView()
        configureDataSource()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: nil)
    }
    
    func updateFrame() {
        self.collectionView.collectionViewLayout?.invalidateLayout()
    }
    
    func isFinalDS() -> Bool {
        return self.chat != nil
    }
    
    func releaseMemory() {
        preloaderHelper.releaseMemory()
    }
    
    func configureScrollView() {
        collectionViewScroll.verticalScrollElasticity = .none
        collectionViewScroll.horizontalScrollElasticity = .none
    }
    
    func configureTableView() {
        collectionView.alphaValue = 0.0
        
        collectionView.delegate = self
        collectionView.reloadData()
        
        collectionView.registerItem(NewMessageCollectionViewItem.self)
        collectionView.registerItem(NewOnlyTextMessageCollectionViewitem.self)
        collectionView.registerItem(MessageNoBubbleCollectionViewItem.self)
        collectionView.registerItem(ThreadCollectionViewItem.self)
    }
    
    func makeCellProvider(
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
    
    func getThreadOriginalMessageStateAndMediaData(
        owner: UserContact,
        tribeAdmin: UserContact
    ) -> (MessageTableCellState, MessageTableCellState.MediaData?)? {
        return nil
    }
}
