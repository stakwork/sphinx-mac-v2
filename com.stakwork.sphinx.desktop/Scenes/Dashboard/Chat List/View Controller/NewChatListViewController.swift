//
//  NewChatListViewController.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 05/07/2023.
//  Copyright © 2023 Tomas Timinskas. All rights reserved.
//

import Cocoa

protocol NewChatListViewControllerDelegate: NSObject {
    func didClickRowAt(chatId: Int?, contactId: Int?)
    func shouldResetContactView()
}

public enum RightClickedContactActions : Int {
    case toggleReadUnread
    case deleteContact
}

class NewChatListViewController: NSViewController {
    
    weak var delegate: NewChatListViewControllerDelegate?
    
    @IBOutlet weak var chatsCollectionView: NSCollectionView!
    
    var chatListObjects: [ChatListCommonObject] = []
    
    var onChatSelected: ((ChatListCommonObject) -> Void)?
    var onContentScrolled: ((NSScrollView) -> Void)?

    private var currentDataSnapshot: DataSourceSnapshot!
    private var dataSource: DataSource!
    
    private var contactsService = ContactsService.sharedInstance
    
    private var owner: UserContact!
    
    let dataSourceQueue = DispatchQueue(label: "chatList.datasourceQueue", attributes: .concurrent)
    
    public enum Tab: Int {
        case Friends
        case Tribes
    }
    
    var tab: Tab = Tab.Friends
    
    private let itemContentInsets = NSDirectionalEdgeInsets(
        top: 0,
        leading: 0,
        bottom: 0,
        trailing: 0
    )
    
    static func instantiate(
        tab: Tab,
        delegate: NewChatListViewControllerDelegate?
    ) -> NewChatListViewController {
        let viewController = StoryboardScene.Dashboard.newChatListViewController.instantiate()
        viewController.tab = tab
        viewController.delegate = delegate
        return viewController
    }
    
    public func updateWithNewChats(
        _ chats: [ChatListCommonObject]
    ) {
        self.chatListObjects = chats
        updateSnapshot()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        loadChatsList()
    }
    
    func loadChatsList() {
        registerViews()
        configureCollectionView()
        configureDataSource()
    }
    
    func shouldReloadChatRowWith(chatId: Int) {
        shouldReloadChatRowsFor(chatIds: [chatId])
    }
    
    func shouldReloadChatRowsFor(chatIds: [Int]) {
        self.dataSourceQueue.async {
            
            guard let dataSource = self.dataSource else {
                return
            }
            
            var snapshot = dataSource.snapshot()
            var itemIdentifiers: [DataSourceItem] = []
            
            let indexes = self.chatListObjects.indices.filter {
                if let chatId = self.chatListObjects[$0].getChat()?.id {
                    return chatIds.contains( chatId )
                }
                return false
            }
            
            for index in indexes {
                if index < snapshot.itemIdentifiers.count {
                    itemIdentifiers.append(snapshot.itemIdentifiers[index])
                }
            }
            
            snapshot.reloadItems(itemIdentifiers)
            
            DispatchQueue.main.async {
                self.dataSource.apply(snapshot, animatingDifferences: true)
            }
        }
    }
}

// MARK: - Layout & Data Structure
@available(macOS 10.15.1, *)
extension NewChatListViewController {
    enum CollectionViewSection: Int, CaseIterable {
        case all
    }
    
    struct DataSourceItem: Hashable {
        
        var objectId: String
        var messageId: Int?
        var messageStatus: Int?
        var message30SecOld: Bool
        var messageSeen: Bool
        var unseenCount: Int
        var contactStatus: Int?
        var inviteStatus: Int?
        var notify: Int
        var selected: Bool

        init(
            objectId: String,
            messageId: Int?,
            messageStatus: Int?,
            message30SecOld: Bool,
            messageSeen: Bool,
            unseenCount: Int,
            contactStatus: Int?,
            inviteStatus: Int?,
            notify: Int,
            selected: Bool
        )
        {
            self.objectId = objectId
            self.messageId = messageId
            self.messageStatus = messageStatus
            self.message30SecOld = message30SecOld
            self.messageSeen = messageSeen
            self.unseenCount = unseenCount
            self.contactStatus = contactStatus
            self.inviteStatus = inviteStatus
            self.notify = notify
            self.selected = selected
        }
        
        static func == (lhs: DataSourceItem, rhs: DataSourceItem) -> Bool {
            let isEqual =
                lhs.objectId == rhs.objectId &&
                lhs.messageId == rhs.messageId &&
                lhs.messageStatus == rhs.messageStatus &&
                lhs.message30SecOld == rhs.message30SecOld &&
                lhs.messageSeen == rhs.messageSeen &&
                lhs.unseenCount == rhs.unseenCount &&
                lhs.contactStatus == rhs.contactStatus &&
                lhs.inviteStatus == rhs.inviteStatus &&
                lhs.notify == rhs.notify &&
                lhs.selected == rhs.selected
            
            return isEqual
         }

        func hash(into hasher: inout Hasher) {
            hasher.combine(objectId)
        }
    }


    typealias CollectionViewCell = ChatListCollectionViewItem
    typealias CellDataItem = DataSourceItem
    
    @available(macOS 10.15.1, *)
    typealias DataSource = NSCollectionViewDiffableDataSource<CollectionViewSection, CellDataItem>
    
    @available(macOS 10.15.1, *)
    typealias DataSourceSnapshot = NSDiffableDataSourceSnapshot<CollectionViewSection, CellDataItem>
}

// MARK: - Collection View Configuration and View Registration
extension NewChatListViewController {

    func registerViews() {
        if let nib = CollectionViewCell.nib {
            chatsCollectionView.register(
                nib,
                forItemWithIdentifier: NSUserInterfaceItemIdentifier(rawValue: CollectionViewCell.reuseID)
            )
        }
    }


    func configureCollectionView() {
        chatsCollectionView.collectionViewLayout = makeLayout()
        chatsCollectionView.delegate = self
    }
}

// MARK: - Layout Composition
extension NewChatListViewController {

    func makeSectionHeader() -> NSCollectionLayoutBoundarySupplementaryItem {
        let headerSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .estimated(80)
        )

        return NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: headerSize,
            elementKind: NSCollectionView.elementKindSectionHeader,
            alignment: .top
        )
    }


    func makeListSection() -> NSCollectionLayoutSection {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .fractionalHeight(1)
        )
        
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        item.contentInsets = itemContentInsets

        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .absolute(Constants.kChatListRowHeight)
        )
        
        let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitems: [item])

        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .none
        section.contentInsets = NSDirectionalEdgeInsets(top: 8.0, leading: 0, bottom: 8.0, trailing: 0)

        return section
    }


    func makeSectionProvider() -> NSCollectionViewCompositionalLayoutSectionProvider {
        { (sectionIndex, layoutEnvironment) -> NSCollectionLayoutSection? in
            switch CollectionViewSection(rawValue: sectionIndex) {
            case .all:
                return self.makeListSection()
            case nil:
                return nil
            }
        }
    }


    func makeLayout() -> NSCollectionViewLayout {
        let layoutConfiguration = NSCollectionViewCompositionalLayoutConfiguration()

        let layout = NSCollectionViewCompositionalLayout(
            sectionProvider: makeSectionProvider()
        )

        layout.configuration = layoutConfiguration

        return layout
    }
}

// MARK: - Private Helpers
extension NewChatListViewController {
    
    func forceReload() {
        dataSource = nil
        
        configureDataSource()
    }
    
    func reloadCollectionView() {
        loadChatsList()
    }
    
    func configureDataSource() {
        if let _ = dataSource {
            return
        }
        
        guard let _ = chatsCollectionView else {
            return
        }
        
        dataSource = makeDataSource()

        updateSnapshot()
    }
    
    func makeDataSource() -> DataSource {
        return DataSource(
            collectionView: chatsCollectionView,
            itemProvider: makeCellProvider()
        )
    }
}

// MARK: - Data Source View Providers
extension NewChatListViewController {

    func makeCellProvider() -> DataSource.ItemProvider {
        { [weak self] (collectionView, indexPath, chatItem) -> NSCollectionViewItem? in
            guard let self else {
                return nil
            }
            
            let section = CollectionViewSection.allCases[indexPath.section]

            switch section {
            case .all:
                guard let cell = collectionView.makeItem(
                    withIdentifier: NSUserInterfaceItemIdentifier(
                        rawValue: CollectionViewCell.reuseID
                    ),
                    for: indexPath
                ) as? CollectionViewCell else { return nil }

                cell.render(
                    with: self.chatListObjects[indexPath.item],
                    owner: self.owner,
                    selected: chatItem.selected,
                    delegate: self
                )

                return cell
            }
        }
    }
}

// MARK: - Data Source Snapshot
extension NewChatListViewController {

    func updateSnapshot(
        completion: (() -> ())? = nil
    ) {
        configureDataSource()
        
        guard let _ = dataSource else {
            return
        }
        
        updateOwner()
        
        guard let owner = owner else {
            return
        }
        
        var snapshot = DataSourceSnapshot()

        snapshot.appendSections(CollectionViewSection.allCases)
        
        let selectedObjectId = (tab == .Friends) ?
            contactsService.selectedFriendId :
            contactsService.selectedTribeId

        let items = chatListObjects.enumerated().map { (index, element) in
            
            DataSourceItem(
                objectId: element.getObjectId(),
                messageId: element.lastMessage?.id,
                messageStatus: element.lastMessage?.status,
                message30SecOld: (element.lastMessage?.date ?? Date()) < Date().addingTimeInterval(-30),
                messageSeen: element.isSeen(ownerId: owner.id),
                unseenCount: element.unseenMessagesCount,
                contactStatus: element.getContactStatus(),
                inviteStatus: element.getInviteStatus(),
                notify: element.getChat()?.notify ?? Chat.NotificationLevel.SeeAll.rawValue,
                selected: selectedObjectId == element.getObjectId()
            )
            
        }
        
        dataSourceQueue.sync {
            snapshot.appendItems(items, toSection: .all)
            
            self.dataSource.apply(snapshot, animatingDifferences: true) {
                completion?()
            }
        }
    }
    
    func updateOwner() {
        if owner == nil {
            owner = UserContact.getOwner()
        }
    }
}

extension NewChatListViewController : NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        
        collectionView.deselectAll(nil)
        
        if let indexPath = indexPaths.first {
            
            if (tab == .Friends) {
                contactsService.selectedFriendId = self.chatListObjects[indexPath.item].getObjectId()
            } else {
                contactsService.selectedTribeId = self.chatListObjects[indexPath.item].getObjectId()
            }
            
            updateSnapshot()
            
            DelayPerformedHelper.performAfterDelay(seconds: 0.05, completion: {
                let chat = self.chatListObjects[indexPath.item] as? Chat
                let contact = self.chatListObjects[indexPath.item] as? UserContact
                
                self.delegate?.didClickRowAt(
                    chatId: chat?.id,
                    contactId: contact?.id
                )
            })
        }
    }
}

extension NewChatListViewController: ChatListCollectionViewItemDelegate {
    func didRightClickOn(item: NSCollectionViewItem) {
        if let indexPath = chatsCollectionView.indexPath(for: item) {
            let chat = self.chatListObjects[indexPath.item] as? Chat
            let contact = self.chatListObjects[indexPath.item] as? UserContact
            
            showContextMenuFor(chat: chat, contact: contact)
        }
    }
    
    func showContextMenuFor(
        chat: Chat?,
        contact: UserContact?
    ) {
        let contextMenu = NSMenu(title: "Context Menu")
        contextMenu.autoenablesItems = true
        contextMenu.items = []
        var newItems = [NSMenuItem]()

        if let chat = chat {
            if let lastMessage = chat.lastMessage, !lastMessage.isOutgoing() {
                let isChatRead = lastMessage.seen
                
                let toggleReadUnreadItem = NSMenuItem(
                    title: isChatRead ? "mark.as.unread".localized : "mark.as.read".localized,
                    action: #selector(self.handleMenuItemClick(_:)),
                    keyEquivalent: ""
                )
                toggleReadUnreadItem.representedObject = chat
                toggleReadUnreadItem.target = self
                toggleReadUnreadItem.tag = RightClickedContactActions.toggleReadUnread.rawValue
                toggleReadUnreadItem.isEnabled = true
                
                newItems.append(toggleReadUnreadItem)
            }
        }
        
        if let contact = contact ?? chat?.getContact() {
            
            let deleteContactItem = NSMenuItem(
                title: (chat == nil ? "delete.invite" : "delete.contact").localized,
                action: #selector(self.handleMenuItemClick(_:)),
                keyEquivalent: ""
            )
            deleteContactItem.representedObject = contact
            deleteContactItem.target = self
            deleteContactItem.tag = RightClickedContactActions.deleteContact.rawValue
            deleteContactItem.isEnabled = true
            
            newItems.append(deleteContactItem)
        }
        
        if newItems.isEmpty {
            return
        }
        
        contextMenu.items = newItems
        
        contextMenu.popUp(
            positioning: contextMenu.item(at: 0),
            at: NSEvent.mouseLocation,
            in: nil
        )
    }
    
    @objc func handleMenuItemClick(_ sender: NSMenuItem) {
        if let action = RightClickedContactActions(rawValue: sender.tag) {
            switch action {
            case .deleteContact:
                guard let contactId = (sender.representedObject as? UserContact)?.id else {
                    return
                    
                }
                initiateDeletion(contactId: contactId)
            case .toggleReadUnread:
                guard let chat = (sender.representedObject as? Chat), let lastMessage = chat.lastMessage else {
                    return
                }
                
                guard let previousMsg = TransactionMessage.getMessagePreviousTo(
                    messageId: lastMessage.id,
                    on: chat
                ) else {
                    return
                }
                
                let success = SphinxOnionManager.sharedInstance.setReadLevel(
                    index: UInt64(previousMsg.id),
                    chat: chat,
                    recipContact: chat.getContact()
                )
                
                if success {
                    let desiredState = !chat.seen
                    
                    lastMessage.seen = desiredState
                    chat.seen = desiredState
                    chat.saveChat()
                } else {
                    AlertHelper.showAlert(
                        title: "generic.error.title".localized,
                        message: "generic.error.message".localized
                    )
                }
            }
        }
    }

    
    func initiateDeletion(contactId: Int){
        guard let contact = UserContact.getContactWith(id: contactId) else {
            AlertHelper.showAlert(
                title: "generic.error.title".localized,
                message: "generic.error.message".localized
            )
            
            return
        }
        
        let confirmDeletionCallback: (() -> ()) = {
            self.shouldDeleteContact(contact: contact)
        }
            
        AlertHelper.showTwoOptionsAlert(
            title: "warning".localized,
            message: (contact.isInvite() ? "delete.invite.warning" : "delete.contact.warning").localized,
            confirm: confirmDeletionCallback
        )
    }
    
    func shouldDeleteContact(contact: UserContact) {
        let som = SphinxOnionManager.sharedInstance
        
        if let inviteCode = contact.invite?.inviteString, contact.isInvite() {
            if !som.cancelInvite(inviteCode: inviteCode) {
                AlertHelper.showAlert(
                    title: "generic.error.title".localized,
                    message: "generic.error.message".localized
                )
                return
            }
        }
        
        if let publicKey = contact.publicKey, publicKey.isNotEmpty {
            if som.deleteContactOrChatMsgsFor(contact: contact) {
                som.deleteContactFromState(pubkey: publicKey)
            }
        }
                
        CoreDataManager.sharedManager.deleteContactObjectsFor(contact)
    }
}
