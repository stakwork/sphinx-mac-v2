//
//  ChatListViewController.swift
//  com.stakwork.sphinx.desktop
//
//  Created by Tomas Timinskas on 14/05/2020.
//  Copyright © 2020 Sphinx. All rights reserved.
//

import Cocoa

class ChatListViewController : DashboardSplittedViewController {

    ///IBOutlets
    @IBOutlet weak var headerView: NewChatHeaderView!
    @IBOutlet weak var bottomBar: NSView!
    @IBOutlet weak var searchBarContainer: NSView!
    @IBOutlet weak var searchFieldContainer: NSBox!
    @IBOutlet weak var searchField: NSTextField!
    @IBOutlet weak var loadingChatsBox: NSBox!
    @IBOutlet weak var loadingChatsWheel: NSProgressIndicator!
    @IBOutlet weak var searchClearButton: NSButton!
    @IBOutlet weak var searchIcon: NSImageView!
    @IBOutlet weak var chatListVCContainer: NSView!
    @IBOutlet weak var receiveButton: CustomButton!
    @IBOutlet weak var transactionsButton: CustomButton!
    @IBOutlet weak var sendButton: CustomButton!
    @IBOutlet weak var addContactButton: CustomButton!
    
    @IBOutlet var menuListView: NewMenuListView!
    
    @IBOutlet weak var dashboardNavigationTabs: ChatsSegmentedControl! {
        didSet {
            dashboardNavigationTabs.configureFromOutlet(
                buttonTitles: [
                    "dashboard.tabs.friends".localized,
                    "dashboard.tabs.tribes".localized,
                    "dashboard.tabs.feed".localized
                ],
                delegate: self
            )
        }
    }
    
    ///Helpers
    let contactsService = ContactsService.sharedInstance
    let feedsManager = FeedsManager.sharedInstance
    let newMessageBubbleHelper = NewMessageBubbleHelper()
    var walletBalanceService = WalletBalanceService()
    
    ///Loading
    var loadingChatList = true {
        didSet {
            loadingChatsBox.isHidden = !loadingChatList
            LoadingWheelHelper.toggleLoadingWheel(loading: loadingChatList, loadingWheel: loadingChatsWheel, color: NSColor.white, controls: [])
        }
    }
    
    var headerLoading = true {
        didSet {
            headerView.loading = headerLoading
        }
    }
    
    ///Chat List VCs
    internal lazy var contactChatsContainerViewController: NewChatListViewController = {
        NewChatListViewController.instantiate(
            tab: NewChatListViewController.Tab.Friends,
            delegate: self
        )
    }()
    
    internal lazy var tribeChatsContainerViewController: NewChatListViewController = {
        NewChatListViewController.instantiate(
            tab: NewChatListViewController.Tab.Tribes,
            delegate: self
        )
    }()
    
    internal lazy var feedContainerViewController: FeedListViewController = {
        FeedListViewController.instantiate(delegate: self)
    }()
    
    static func instantiate(
        delegate: DashboardVCDelegate?
    ) -> ChatListViewController {
        let viewController = StoryboardScene.Dashboard.chatListViewController.instantiate()
        viewController.delegate = delegate
        return viewController
    }
    
    ///Lifecycle events
    override func viewDidLoad() {
        super.viewDidLoad()
        
        loadingChatList = true
        
        contactsService.configureFetchResultsController()
        
        prepareView()
        setActiveTab(
            contactsService.selectedTab,
            loadData: false
        )
        
        resetSearchField()
        
        menuListView.configureDataSource(delegate: self)
        
        bottomBar.isHidden = true
        
        listenForNotifications()
    }
    
    func listenForNotifications() {
        NotificationCenter.default.addObserver(
            forName: .onContactsAndChatsChanged,
            object: nil,
            queue: OperationQueue.main
        ) { [weak self] (n: Notification) in
            self?.dataDidChange()
        }
        
        NotificationCenter.default.addObserver(
            forName: .onPubKeyClick,
            object: nil,
            queue: OperationQueue.main
        ) { [weak self] (n: Notification) in
            
            guard let self = self else { return }
            
            if let pubkey = n.userInfo?["pub-key"] as? String {
                if pubkey == UserData.sharedInstance.getUserPubKey() { return }
                let (pk, _) = pubkey.pubkeyComponents
                let (existing, user) = pk.isExistingContactPubkey()
                
                if let user = user, existing {
                    
                    let chat = user.getChat()
                    
                    if chat?.isPublicGroup() == true {
                        self.contactsService.selectedTab = .tribes
                        self.contactsService.selectedTribeId = chat?.getObjectId()
                        self.setActiveTab(.tribes, shouldSwitchChat: false)
                    } else {
                        self.contactsService.selectedTab = .friends
                        self.contactsService.selectedFriendId = chat?.getObjectId() ?? user.getObjectId()
                        self.setActiveTab(.friends, shouldSwitchChat: false)
                    }
                    
                    self.dashboardNavigationTabs.updateButtonsOnIndexChange()
                    
                    self.didClickRowAt(
                        chatId: chat?.id,
                        contactId: user.id
                    )
                } else {
                    
                    let contactVC = NewContactViewController.instantiate(
                        delegate: self,
                        pubkey: pubkey
                    )
                    
                    WindowsManager.sharedInstance.showOnCurrentWindow(
                        with: "new.contact".localized,
                        identifier: "add-contact-window",
                        contentVC: contactVC,
                        height: 500
                    )
                }
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .onJoinTribeClick,
            object: nil,
            queue: OperationQueue.main
        ) { [weak self] (n: Notification) in
            guard let self = self else { return }
            
            if let tribeLink = n.userInfo?["tribe_link"] as? String {
                if let tribeInfo = GroupsManager.sharedInstance.getGroupInfo(query: tribeLink), let ownerPubkey = tribeInfo.ownerPubkey {
                    if let chat = Chat.getTribeChatWithOwnerPubkey(ownerPubkey: ownerPubkey) {
                        
                        self.contactsService.selectedTab = .tribes
                        self.contactsService.selectedTribeId = chat.getObjectId()
                        self.dashboardNavigationTabs.updateButtonsOnIndexChange()
                        self.setActiveTab(.tribes, shouldSwitchChat: false)
                        
                        self.didClickRowAt(
                            chatId: chat.id,
                            contactId: chat.getConversationContact()?.id
                        )
                    } else {
                        let joinTribeVC = JoinTribeViewController.instantiate(
                            tribeInfo: tribeInfo,
                            delegate: self
                        )
                        
                        WindowsManager.sharedInstance.showOnCurrentWindow(
                            with: "join.tribe".localized,
                            identifier: "join-tribe-window",
                            contentVC: joinTribeVC
                        )
                    }
                }
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: .onContactsAndChatsChanged, object: nil)
        NotificationCenter.default.removeObserver(self, name: .onPubKeyClick, object: nil)
        NotificationCenter.default.removeObserver(self, name: .onJoinTribeClick, object: nil)
    }
    
    override func viewDidLayout() {
        for childVC in self.children {
            childVC.view.frame = chatListVCContainer.bounds
        }
    }
    
    override func viewWillAppear() {
        super.viewWillAppear()
        configureHeaderAndBottomBar()
        headerView.delegate = self
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        
        DelayPerformedHelper.performAfterDelay(seconds: 0.5, completion: {
            self.loadingChatList = false
        })
    }
    
    override func viewWillDisappear() {
        super.viewWillDisappear()
    }
    
    func prepareView() {
        receiveButton.cursor = .pointingHand
        sendButton.cursor = .pointingHand
        transactionsButton.cursor = .pointingHand
        addContactButton.cursor = .pointingHand
        
        searchField.setPlaceHolder(
            color: NSColor.Sphinx.SecondaryText,
            font: NSFont(name: "Roboto-Regular", size: 14.0)!,
            string: "search".localized
        )
        
        searchField.delegate = self
        menuListView.delegate = self
        
        self.view.window?.makeFirstResponder(self)
    }
    
    internal func syncContentFeedStatus(
        restoring: Bool,
        progressCallback: @escaping (Int) -> (),
        completionCallback: @escaping () -> ()
    ) {
        if !restoring {
            completionCallback()
            return
        }
        
        CoreDataManager.sharedManager.saveContext()
        
        feedsManager.restoreContentFeedStatus(
            progressCallback: { contentProgress in
                progressCallback(contentProgress)
            },
            completionCallback: {
                completionCallback()
            }
        )
    }
    
    func selectRowFor(chatId: Int) {
        if let chat = Chat.getChatWith(id: chatId) {
            didClickRowAt(
                chatId: chat.id,
                contactId: chat.getConversationContact()?.id
            )
        }
    }
    
    func shouldReloadChatRowWith(chatId: Int) {
        contactChatsContainerViewController.shouldReloadChatRowWith(chatId: chatId)
        tribeChatsContainerViewController.shouldReloadChatRowWith(chatId: chatId)
    }
    
    @IBAction func addContactButtonClicked(_ sender: Any) {
        let addFriendVC = AddFriendViewController.instantiate(delegate: self, dismissDelegate: self)
        
        WindowsManager.sharedInstance.showOnCurrentWindow(
            with: "new.contact".localized,
            identifier: "add-contact-window",
            contentVC: addFriendVC,
            height: 500
        )
    }
    
    @IBAction func upgradeButtonClicked(_ sender: Any) {
        if let url = URL(string: "https://testflight.apple.com/join/QoaCkJn6") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @IBAction func hideMenuButtonClicked(_ sender: Any) {
        delegate?.shouldToggleLeftView(show: false)
    }
    
    @IBAction func clearButtonClicked(_ sender: Any) {
        resetSearchField()
    }
    
    @IBAction func receiveButtonClicked(_ sender: Any) {
        handleReceiveClick()
    }
    
    @IBAction func sendButtonClicked(_ sender: Any) {
        handleSentClick()
    }
    
    @IBAction func transactionsButtonClicked(_ sender: Any) {
        WindowsManager.sharedInstance.showTransationsListWindow()
    }
}

extension ChatListViewController: NewContactDismissDelegate {
    func shouldDismissView() {
        WindowsManager.sharedInstance.dismissViewFromCurrentWindow()
    }
}

extension ChatListViewController: NewChatHeaderViewDelegate {
    func qrButtonTapped() {
        guard let shareInviteCodeVC = getQRCodeVC() else {
            return
        }
        
        navigateToNewVC(
            vc: shareInviteCodeVC,
            title: "",
            identifier: "share-pub-key-window",
            hideDivider: true,
            height: 496,
            width: 312,
            hideHeaderView: true
        )
    }
    
    func refreshTapped() {
        NotificationCenter.default.post(name: .shouldUpdateDashboard, object: nil)
    }
    
    func profileButtonClicked() {
        WindowsManager.sharedInstance.showProfileWindow()
    }
    
    func menuTapped(_ frame: CGRect) {
        menuListView.isHidden = false
    }
    
    func isMenuExpanded() -> Bool {
        return !menuListView.isHidden
    }
}


extension ChatListViewController: NewMenuListViewDelegate {
    func buttonClicked(id: Int) {
        let vcInfo = getViewControllerToLoadInfo(vcId: id)
        
        navigateToNewVC(
            vc: vcInfo.0,
            title: vcInfo.1,
            identifier: vcInfo.2,
            hideDivider: vcInfo.3,
            height: vcInfo.4,
            width: vcInfo.5,
            hideHeaderView: vcInfo.6
        )
    }
    
    func closeButtonTapped() {
        menuListView.isHidden = true
    }
}

extension ChatListViewController: NewMenuItemDataSourceDelegate {
    func itemSelected(at index: Int) {
        let vcInfo = getViewControllerToLoadInfo(vcId: index)
        
        navigateToNewVC(
            vc: vcInfo.0,
            title: vcInfo.1,
            identifier: vcInfo.2,
            hideDivider: vcInfo.3,
            height: vcInfo.4,
            hideHeaderView: vcInfo.6
        )
    }
    
    func getViewControllerToLoadInfo(vcId: Int) -> (NSViewController, String, String, Bool, CGFloat?, CGFloat?, Bool){
        switch vcId {
        case MenuItems.Profile.rawValue:
            return (
                ProfileViewController.instantiate(),
                "profile".localized,
                "profile-window",
                false, 
                nil,
                nil,
                false
            )
//        case 1:
//            return (
//                AddFriendViewController.instantiate(delegate: self, dismissDelegate: self),
//                "new.contact".localized,
//                "add-contact-window",
//                true,
//                500,
//                nil,
//                false
//            )
        case MenuItems.Transactions.rawValue:
            return (
                TransactionsListViewController.instantiate(),
                "transactions".localized,
                "transactions-window",
                false,
                nil,
                nil,
                false
            )
        case MenuItems.RequestPayment.rawValue:
            return (
                CreateInvoiceViewController.instantiate(
                    childVCDelegate: self,
                    viewModel: PaymentViewModel(mode: .Request),
                    delegate: self,
                    mode: .Window
                ),
                "create.invoice".localized,
                "create-invoice-window",
                true,
                500,
                nil,
                false
            )
        case MenuItems.PayInvoice.rawValue:
            return (
                SendPaymentForInvoiceVC.instantiate(),
                "pay.invoice".localized,
                "send-payment-window",
                true,
                447,
                nil,
                false
            )
        case MenuItems.AddFriend.rawValue:
            return (
                AddFriendViewController.instantiate(delegate: self, dismissDelegate: self),
                "new.contact".localized,
                "add-contact-window",
                true,
                500,
                nil,
                false
            )
        case MenuItems.CreateTribe.rawValue:
            return (
                CreateTribeViewController.instantiate(),
                "Create Tribe",
                "create-tribe-window",
                false,
                nil,
                nil,
                false
            )
        case MenuItems.ShareQR.rawValue:
            guard let shareInviteCodeVC = getQRCodeVC() else {
                return (NSViewController(), "pubkey.upper".localized.localizedCapitalized, "", true, nil, nil, false)
            }
            return (
                shareInviteCodeVC,
                "",
                "create-tribe-window",
                true,
                496,
                312,
                true
            )
            
        default:
            return (NSViewController(), "", "", false, nil, nil, false)
        }
    }
    
    func getQRCodeVC() -> NewShareQrCodeViewController? {
        guard let profile = UserContact.getOwner(), let address = profile.getAddress(), !address.isEmpty else {
            return nil
        }
        
        let shareQrCodeVC = NewShareQrCodeViewController.instantiate(profile: profile, delegate: self)
        return shareQrCodeVC
    }
    
    func navigateToNewVC(
        vc: NSViewController,
        title: String,
        identifier: String,
        hideDivider: Bool = false,
        height: CGFloat? = nil,
        width: CGFloat? = nil,
        hideHeaderView: Bool = false
    ) {
        closeButtonTapped()
        
        WindowsManager.sharedInstance.showOnCurrentWindow(
            with: title,
            identifier: identifier,
            contentVC: vc,
            hideDivider: hideDivider,
            hideBackButton: true,
            replacingVC: false,
            height: height,
            width: width,
            hideHeaderView: hideHeaderView
        )
    }
}

