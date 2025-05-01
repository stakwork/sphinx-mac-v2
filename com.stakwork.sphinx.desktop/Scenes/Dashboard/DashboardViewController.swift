//
//  DashboardViewController.swift
//  com.stakwork.sphinx.desktop
//
//  Created by Tomas Timinskas on 13/05/2020.
//  Copyright © 2020 Sphinx. All rights reserved.
//

import Cocoa
import UserNotifications

class DashboardViewController: NSViewController {
    
    @IBOutlet weak var dashboardSplitView: NSSplitView!
    @IBOutlet weak var dashboardRightSplitView: NSSplitView!
    @IBOutlet weak var leftSplittedView: NSView!
    @IBOutlet weak var rightSplittedView: NSView!
    @IBOutlet weak var rightDetailSplittedView: NSView!
    @IBOutlet weak var rightDetailViewMinWidth: NSLayoutConstraint!
    @IBOutlet weak var rightDetailViewMaxWidth: NSLayoutConstraint!
    
    @IBOutlet weak var modalsContainerView: NSView!
    
    @IBOutlet weak var presenterBlurredBackground: NSVisualEffectView!
    @IBOutlet weak var presenterContainerView: NSView!
    @IBOutlet weak var presenterContainerBGView: NSBox!
    @IBOutlet weak var presenterContentBox: NSBox!
    @IBOutlet weak var presenterTitleLabel: NSTextField!
    @IBOutlet weak var presenterHeaderDivider: NSView!
    @IBOutlet weak var presenterBackButton: CustomButton!
    @IBOutlet weak var presenterCloseButton: CustomButton!
    @IBOutlet weak var presenterViewHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var presenterViewWidthConstraint: NSLayoutConstraint!
    @IBOutlet weak var presenterHeaderView: NSBox!
    
    weak var presenter: DashboardPresenterViewController?
    var presenterBackHandler: (() -> ())? = nil
    var presenterIdentifier: String?
    
    var dashboardDetailViewController: DashboardDetailViewController?
    
    var mediaFullScreenView: MediaFullScreenView? = nil
    
    var chatListViewModel: ChatListViewModel! = nil
    var deeplinkData: DeeplinkData? = nil
    
    let contactsService = ContactsService.sharedInstance
    
    var messageBubbleHelper = NewMessageBubbleHelper()
    
    var newDetailViewController : NewChatViewController? = nil
    var listViewController : ChatListViewController? = nil
    
    let kDetailSegueIdentifier = "ChatViewControllerSegue"
    let kListSegueIdentifier = "ChatListViewControllerSegue"
    
    let kWindowMinWidthWithLeftColumn: CGFloat = 950
    let kWindowMinWidthWithoutLeftColumn: CGFloat = 600
    let kWindowMinHeight: CGFloat = 735
    
    public static let kPodcastPlayerWidth: CGFloat = 350
    
    public static let kRightPanelMaxWidth: CGFloat = 450
    public static let kRightPanelMinWidth: CGFloat = 320
    
    var resizeTimer : Timer? = nil
    var escapeMonitor: Any? = nil
    
    static func instantiate() -> DashboardViewController {
        let viewController = StoryboardScene.Dashboard.dashboardViewController.instantiate()
        return viewController
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        chatListViewModel = ChatListViewModel()
        
        dashboardSplitView.delegate = self
        dashboardSplitView.dividerStyle = .thick
        dashboardSplitView.setValue(NSColor.Sphinx.Divider2, forKey: "dividerColor")
        
        dashboardRightSplitView.delegate = self
        dashboardRightSplitView.dividerStyle = .thin
        dashboardRightSplitView.setValue(NSColor.Sphinx.Divider2, forKey: "dividerColor")
        
        let windowState = WindowsManager.sharedInstance.getWindowState()
        leftSplittedView.isHidden = windowState.menuCollapsed
        
        setupObservers()
        addEscapeMonitor()
        addFloatingPlayer()
    }
    
    override func viewWillAppear() {
        super.viewWillAppear()
        
        listViewController?.delegate = self
        rightDetailSplittedView.isHidden = true
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        
        handleDeepLink()
        addPresenterVC()
        addDetailVCPresenter()
        
        Chat.processTimezoneChanges()
        connectToServer()
        askForNotificationsPermission()
    }
    
    func setupObservers() {
        DistributedNotificationCenter.default().addObserver(
            forName: .onInterfaceThemeChanged,
            object: nil,
            queue: OperationQueue.main
        ) { [weak self] (n: Notification) in
            self?.themeChangedNotification(notification: n)
        }
        
        NotificationCenter.default.addObserver(
            forName: .connectedToInternet,
            object: nil,
            queue: OperationQueue.main
        ) { [weak self] _ in
            self?.didConnectToInternet()
        }
        
        NotificationCenter.default.addObserver(
            forName: .disconnectedFromInternet,
            object: nil,
            queue: OperationQueue.main
        ) { [weak self] _ in
            self?.didDisconnectFromInternet()
        }
        
        NotificationCenter.default.addObserver(
            forName: .webViewImageClicked,
            object: nil,
            queue: OperationQueue.main
        ) { [weak self] (n: Notification) in
            self?.handleImageNotification(n)
        }
        
        NotificationCenter.default.addObserver(
            forName: .shouldUpdateDashboard,
            object: nil,
            queue: OperationQueue.main
        ) { [weak self] _ in
            self?.reloadData()
        }
        
        NotificationCenter.default.addObserver(
            forName: .shouldReloadViews,
            object: nil,
            queue: OperationQueue.main
        ) { [weak self] _ in
            self?.reloadView()
        }
        
        NotificationCenter.default.addObserver(
            forName: .shouldReloadChatLists,
            object: nil,
            queue: OperationQueue.main
        ) { [weak self] (n: Notification) in
            if let chatIds = n.userInfo?["chat-ids"] as? [Int] {
                self?.reloadChatListsFor(chatIds: chatIds)
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .shouldResetChat,
            object: nil,
            queue: OperationQueue.main
        ) { _ in
            ///Reset chat view
        }
        
        NotificationCenter.default.addObserver(
            forName: .chatNotificationClicked,
            object: nil,
            queue: OperationQueue.main
        ) { [weak self] (n: Notification) in
            if let chatId = n.userInfo?["chat-id"] as? Int, let chat = Chat.getChatWith(id: chatId) {
                
                if chat.isPublicGroup() {
                    self?.contactsService.selectedTribeId = chat.getObjectId()
                    self?.listViewController?.setActiveTab(.tribes)
                } else {
                    self?.contactsService.selectedFriendId = chat.getObjectId()
                    self?.listViewController?.setActiveTab(.friends)
                }
                
                self?.shouldGoToChat(chatId: chat.id)
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .onAuthDeepLink,
            object: nil,
            queue: OperationQueue.main
        ) { [weak self] (n: Notification) in
            self?.showDashboardModalsVC(n: n)
        }
        
        NotificationCenter.default.addObserver(
            forName: .onPersonDeepLink,
            object: nil,
            queue: OperationQueue.main
        ) { [weak self] (n: Notification) in
            self?.showDashboardModalsVC(n: n)
        }
        
        NotificationCenter.default.addObserver(
            forName: .onSaveProfileDeepLink,
            object: nil,
            queue: OperationQueue.main
        ) { [weak self] (n: Notification) in
            self?.showDashboardModalsVC(n: n)
        }
        
        NotificationCenter.default.addObserver(
            forName: .onStakworkAuthDeepLink,
            object: nil,
            queue: OperationQueue.main
        ) { [weak self] (n: Notification) in
            self?.showDashboardModalsVC(n: n)
        }
        
        NotificationCenter.default.addObserver(
            forName: .onRedeemSatsDeepLink,
            object: nil,
            queue: OperationQueue.main
        ) { [weak self] (n: Notification) in
            self?.showDashboardModalsVC(n: n)
        }
        
//        NotificationCenter.default.addObserver(
//            forName: .onInvoiceDeepLink,
//            object: nil,
//            queue: OperationQueue.main
//        ) { [weak self] (n: Notification) in
//            guard let vc = self else { return }
//            vc.createInvoice(n: n)
//        }
        
        NotificationCenter.default.addObserver(
            forName: .onShareContentDeeplink,
            object: nil,
            queue: OperationQueue.main
        ) { [weak self] (n: Notification) in
            self?.processContentDeeplink(n: n)
        }
        
        NotificationCenter.default.addObserver(
            forName: .onShareContactDeeplink,
            object: nil,
            queue: OperationQueue.main
        ) { [weak self] (n: Notification) in
            self?.processContactDeepLink(n: n)
        }
        
        NotificationCenter.default.addObserver(
            forName: .shouldCloseRightPanel,
            object: nil,
            queue: OperationQueue.main
        ) { [weak self] (n: Notification) in
            self?.closeButtonTapped()
        }
        
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: nil,
            queue: OperationQueue.main
        ) { [weak self] (n: Notification) in
            if let presenter = self?.presenter {
                if let bounds = self?.presenterContainerView?.bounds {
                    presenter.view.frame = bounds
                }
            }
            
            if let detailVC = self?.dashboardDetailViewController {
                if let bounds = self?.rightDetailSplittedView.bounds {
                    detailVC.view.frame = bounds
                }
            }
        }
    }
    
    override func viewWillDisappear() {
        super.viewWillDisappear()
        
        listViewController?.delegate = nil
    }
    
    deinit {
        DistributedNotificationCenter.default().removeObserver(self, name: .onInterfaceThemeChanged, object: nil)
        NotificationCenter.default.removeObserver(self, name: .connectedToInternet, object: nil)
        NotificationCenter.default.removeObserver(self, name: .disconnectedFromInternet, object: nil)
        NotificationCenter.default.removeObserver(self, name: .webViewImageClicked, object: nil)
        NotificationCenter.default.removeObserver(self, name: .shouldUpdateDashboard, object: nil)
        NotificationCenter.default.removeObserver(self, name: .shouldReloadViews, object: nil)
        NotificationCenter.default.removeObserver(self, name: .shouldResetChat, object: nil)
        NotificationCenter.default.removeObserver(self, name: .chatNotificationClicked, object: nil)
        NotificationCenter.default.removeObserver(self, name: .onAuthDeepLink, object: nil)
        NotificationCenter.default.removeObserver(self, name: .onPersonDeepLink, object: nil)
        NotificationCenter.default.removeObserver(self, name: .onSaveProfileDeepLink, object: nil)
        NotificationCenter.default.removeObserver(self, name: .onStakworkAuthDeepLink, object: nil)
        NotificationCenter.default.removeObserver(self, name: .onRedeemSatsDeepLink, object: nil)
        NotificationCenter.default.removeObserver(self, name: .onInvoiceDeepLink, object: nil)
        NotificationCenter.default.removeObserver(self, name: .onShareContentDeeplink, object: nil)
        NotificationCenter.default.removeObserver(self, name: .onShareContactDeeplink, object: nil)
        NotificationCenter.default.removeObserver(self, name: .shouldCloseRightPanel, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResizeNotification, object: nil)
        
        if let escapeMonitor = escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
        }
    }
    
    func addFloatingPlayer() {
        let floatingView = FloatingAudioPlayer(frame: NSRect(x: 15, y: 10, width: 320, height: 192))
        floatingView.wantsLayer = true

        self.view.addSubview(floatingView)
    }
    
    func askForNotificationsPermission() {
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            appDelegate.askForNotificationsPermission()
        }
    }
    
    func connectToServer() {
        SphinxOnionManager.sharedInstance.fetchMyAccountFromState()
        SphinxOnionManager.sharedInstance.deleteOwnerFromState()
        
        SphinxOnionManager.sharedInstance.connectToServer(
            connectingCallback: {
                DispatchQueue.main.async {
                    self.listViewController?.headerLoading = true
                }
            },
            contactRestoreCallback: self.contactRestoreCallback(percentage:),
            messageRestoreCallback: self.messageRestoreCallback(percentage:),
            hideRestoreViewCallback: self.hideRestoreViewCallback
        )
    }
    
    func reconnectToServer() {
        SphinxOnionManager.sharedInstance.reconnectToServer(
            hideRestoreViewCallback: self.hideRestoreViewCallback
        )
    }
    
    private func didConnectToInternet() {
        self.reconnectToServer()
    }

    private func didDisconnectFromInternet() {
        SphinxOnionManager.sharedInstance.isConnected = false
    } 
    
    func refreshUnreadStatus(){
        SphinxOnionManager.sharedInstance.getReads()
        SphinxOnionManager.sharedInstance.getMuteLevels()
        SphinxOnionManager.sharedInstance.getMessagesStatusForPendingMessages()
    }
    
    func hideRestoreViewCallback(isRestore: Bool){
        DispatchQueue.main.async {
            self.listViewController?.headerLoading = false
            
            self.shouldHideRetoreModal()
            self.refreshUnreadStatus()
            
            if isRestore {
                self.finishUserInfoSetup()
            }
        }
    }
    
    func processTimezoneChanges() {
        DispatchQueue.global(qos: .background).async {
            let backgroundContext = CoreDataManager.sharedManager.getBackgroundContext()
            
            backgroundContext.perform { [weak self] in
                guard let _ = self else {
                    return
                }
                let didMigrateToTZ: Bool = UserDefaults.Keys.didMigrateToTZ.get(defaultValue: false)
                
                if !didMigrateToTZ {
                    Chat.resetTimezones(context: backgroundContext)
                }
                
                if let systemTimezone: String? = UserDefaults.Keys.systemTimezone.get() {
                    if systemTimezone != TimeZone.current.abbreviation() {
                        Chat.setChatsToTimezoneUpdated(context: backgroundContext)
                    }
                }
                
                UserDefaults.Keys.systemTimezone.set(TimeZone.current.abbreviation())
                UserDefaults.Keys.didMigrateToTZ.set(true)
                
                backgroundContext.saveContext()
            }
        }
    }
    
    func finishUserInfoSetup() {
        if let owner = UserContact.getOwner(), (owner.nickname ?? "").trim().isEmpty == true {
            WindowsManager.sharedInstance.showProfileWindow()
            
            messageBubbleHelper.showGenericMessageView(
                text: "profile.finish-setup".localized,
                delay: 5,
                textColor: NSColor.white,
                backColor: NSColor.Sphinx.PrimaryGreen,
                backAlpha: 1.0
            )
            
        }
    }
    
    func contactRestoreCallback(percentage: Int) {
        DispatchQueue.main.async {
            let value = min(percentage, 100)
            
            self.shouldShowRestoreModal(
                with: value,
                label: "restoring-contacts".localized,
                buttonEnabled: false
            )
            
            if value >= 100 { self.shouldHideRetoreModal() }
        }
    }
    
    func messageRestoreCallback(percentage: Int) {
        DispatchQueue.main.async {
            let value = min(percentage, 100)
            
            self.shouldShowRestoreModal(
                with: value,
                label: "restoring-messages".localized,
                buttonEnabled: true
            )
            if value >= 100 { self.shouldHideRetoreModal() }
        }
    }
    
    func addPresenterVC() {
        presenterBlurredBackground.blendingMode = .withinWindow
        presenterBlurredBackground.material = .fullScreenUI
        presenterBlurredBackground.alphaValue = 1
        
        presenterBackButton.cursor = .pointingHand
        presenterCloseButton.cursor = .pointingHand
        
        if let _ = presenter {
            return
        }
        presenter = DashboardPresenterViewController.instantiate()
        
        if let presenter {
            self.addChildVC(
                child: presenter,
                container: self.presenterContainerView
            )
            
            self.presenterContainerBGView.isHidden = true
        }
    }
    
    func addDetailVCPresenter() {
        if let _ = dashboardDetailViewController {
            return
        }
        dashboardDetailViewController = DashboardDetailViewController.instantiate(delegate: self)
        
        if let dashboardDetailViewController {
            self.addChildVC(
                child: dashboardDetailViewController,
                container: self.rightDetailSplittedView
            )
            
            dashboardDetailViewController.view.frame = rightDetailSplittedView.bounds
            self.rightDetailSplittedView.isHidden = true
        }
    }
    
    func handleDeepLink() {
        if let linkQuery: String = UserDefaults.Keys.linkQuery.get(), let url = URL(string: linkQuery) {
            DeepLinksHandlerHelper.handleLinkQueryFrom(url: url)
            UserDefaults.Keys.linkQuery.removeValue()
        }
    }
    
    @IBAction func closeButtonTapped(_ sender: NSButton) {
        if let profileVC = self.presenter?.contentVC?.last as? ProfileViewController {
            profileVC.closeOnCompletion() {
                self.closePresenter()
            }
            return
        }
        closePresenter()
    }
    
    func closePresenter() {
        WindowsManager.sharedInstance.dismissViewFromCurrentWindow()
    }
    
    @IBAction func presenterBackButtonTapped(_ sender: NSButton) {
        if let presenterBackHandler = presenterBackHandler {
            presenterBackHandler()
        }
    }
    
    @objc func themeChangedNotification(notification: Notification) {
        self.listViewController?.configureHeaderAndBottomBar()
        
        self.presentChatVCFor(
            chatId: self.newDetailViewController?.chat?.id,
            contactId: self.newDetailViewController?.contact?.id,
            forceReload: true
        )
    }
    
    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        switch (segue.identifier) {
        case kListSegueIdentifier:
            listViewController = (segue.destinationController as? ChatListViewController) ?? nil
            break
        case kDetailSegueIdentifier:
            newDetailViewController = (segue.destinationController as? NewChatViewController) ?? nil
            break
        default:
            break
        }
        
        if let splitedVC = segue.destinationController as? DashboardSplittedViewController {
            splitedVC.delegate = self
        }
    }
    
    func processContactDeepLink(n: Notification){
        if let query = n.userInfo?["query"] as? String,
           let pubkey = query.getLinkValueFor(key: "pubKey") {
            let userInfo: [String: Any] = ["pub-key" : pubkey]
            NotificationCenter.default.post(name: .onPubKeyClick, object: nil, userInfo: userInfo)
        }
    }
    
    func processContentDeeplink(n: Notification){
        var success = false
        
        if let query = n.userInfo?["query"] as? String,
           let feedID = query.getLinkValueFor(key: "feedID"),
           let itemID = query.getLinkValueFor(key: "itemID"){
            print(query)
            
            if let feed = ContentFeed.getFeedById(feedId: feedID),
               let chat = feed.chat {
                let timestamp = query.getLinkValueFor(key: "atTime")
                let finalTS = Int(timestamp ?? "") ?? 0
                
                self.deeplinkData = DeeplinkData(
                    feedID: feedID,
                    itemID: itemID,
                    timestamp: finalTS
                )
                
                self.didClickOnChatRow(
                    chatId: chat.id,
                    contactId: nil
                )
                
                success = true
            }
        }
        if success == false{
            //throw error
            print("Error opening content deeplink")
            AlertHelper.showAlert(title: "deeplink.issue.title".localized, message: "deeplink.issue.message".localized)
        }
    }
    
    func showDashboardModalsVC(n: Notification) {
        if let query = n.userInfo?["query"] as? String {
            for childVC in self.children {
                if let childVC = childVC as? DashboardModalsViewController {
                    self.modalsContainerView.isHidden = false
                    childVC.showWithQuery(query, and: self)
                }
            }
        }
    }
    
    func handleImageNotification(n: Notification) {
        if let imageURL = n.userInfo?["image_url"] as? URL,
           let messageId = n.userInfo?["message_id"] as? Int,
           let message = TransactionMessage.getMessageWith(id: messageId) {
            
            goToMediaFullView(imageURL: imageURL, message: message)
        } else {
            NewMessageBubbleHelper().showGenericMessageView(text: "Error pulling image data.")
        }
    }
    
    func goToMediaFullView(
        imageURL: URL,
        message: TransactionMessage
    ){
        if mediaFullScreenView == nil {
            mediaFullScreenView = MediaFullScreenView()
        }

        if let mediaFullScreenView = mediaFullScreenView {
            view.addSubview(mediaFullScreenView)
            
            mediaFullScreenView.showWith(imageURL: imageURL, message: message,completion: {
                mediaFullScreenView.delegate = self
                mediaFullScreenView.constraintTo(view: self.view)
                mediaFullScreenView.currentMode = MediaFullScreenView.ViewMode.Viewing
                mediaFullScreenView.loading = false
                mediaFullScreenView.mediaImageView.alphaValue = 1.0
                mediaFullScreenView.mediaImageView.gravity = .resizeAspect
            })
            mediaFullScreenView.isHidden = false
        }
    }
    
    func shouldGoToChat(chatId: Int) {
        self.listViewController?.selectRowFor(chatId: chatId)
    }
    
    func reloadView() {
        self.listViewController?.contactChatsContainerViewController.forceReload()
        self.listViewController?.tribeChatsContainerViewController.forceReload()
        self.newDetailViewController?.forceReload()
    }
    
    func reloadChatListsFor(chatIds: [Int]) {
        self.listViewController?.contactChatsContainerViewController.shouldReloadChatRowsFor(chatIds: chatIds)
        self.listViewController?.tribeChatsContainerViewController.shouldReloadChatRowsFor(chatIds: chatIds)
    }
    
    func reloadData() {
        reconnectToMQTT()
        
        let backgroundContext = CoreDataManager.sharedManager.getBackgroundContext()
        
        backgroundContext.perform { [weak self] in
            guard let _ = self else {
                return
            }
            let receivedUnseenCount = TransactionMessage.getReceivedUnseenMessagesCount(context: backgroundContext)
            
            DispatchQueue.main.async {
                if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
                    appDelegate.setBadge(count: receivedUnseenCount)
                }
            }
        }
    }
    
    func reconnectToMQTT() {
        SphinxOnionManager.sharedInstance.reconnectToServer(
            connectingCallback: {
                DispatchQueue.main.async {
                    self.listViewController?.headerLoading = true
                }
            },
            hideRestoreViewCallback: { _ in
                DispatchQueue.main.async {
                    self.listViewController?.headerLoading = false
                }
            }
        )
    }
    
    func addEscapeMonitor() {
        //add event monitor in case user never clicks the textfield
        if let escapeMonitor = escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
        }
    
        escapeMonitor = nil
    
        self.escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { (event) in
            if event.keyCode == 53 {
                if let windowToClose = WindowsManager.sharedInstance.getLastTaggedWindows(), windowToClose.isKeyWindow {
                    windowToClose.close()
                    return nil
                } else if self.listViewController?.isMenuExpanded() == true {
                    self.listViewController?.closeButtonTapped()
                    return nil
                } else if self.mediaFullScreenView?.isHidden == false {
                    self.mediaFullScreenView?.closeView()
                    return nil
                ///Hide dashboard views popups (Profile, Create Tribe, etc)
                } else if !self.presenterContainerBGView.isHidden {
                    WindowsManager.sharedInstance.dismissViewFromCurrentWindow()
                    return nil
                ///Hide modals (auth, etc)
                } else if !self.modalsContainerView.isHidden {
                    for childVC in self.children {
                        if let childVC = childVC as? DashboardModalsViewController {
                            childVC.shouldDismissModals()
                        }
                    }
                ///Hide chat modals (send payment, calls, etc)
                } else if self.newDetailViewController?.hideModals() == true {
                    return nil
                ///Hide right panel view
                } else if !self.rightDetailSplittedView.isHidden {
                    self.dashboardDetailViewController?.closeButtonTapped()
                    return nil
                }
            }
            return event
        }
    }
}

extension DashboardViewController : NSSplitViewDelegate {
    func splitViewDidResizeSubviews(_ notification: Notification) {
        if let _ = view.window {
            resizeSubviews()

            resizeTimer?.invalidate()
            resizeTimer = Timer.scheduledTimer(
                timeInterval: 0.05,
                target: self,
                selector: #selector(resizeSubviews),
                userInfo: nil,
                repeats: false
            )
        }
    }

    @objc func resizeSubviews() {
        newDetailViewController?.resizeSubviews(frame: rightSplittedView.bounds)
        dashboardDetailViewController?.resizeSubviews(frame: rightDetailSplittedView.bounds)
        listViewController?.menuListView.menuDataSource?.updateFrame()
        
        listViewController?.view.frame = leftSplittedView.bounds
        dashboardDetailViewController?.updateCurrentVCFrame()
    }
}

extension DashboardViewController : DashboardVCDelegate {
    func shouldResetContactView() {
        contactsService.selectedFriendId = nil
        
        didClickOnChatRow(
            chatId: nil,
            contactId: nil
        )
    }
    
    func shouldResetTribeView() {
        contactsService.selectedTribeId = nil
        
        didClickOnChatRow(
            chatId: nil,
            contactId: nil
        )
    }
    
    func didSwitchToTab() {
        let (chatId, contactId) = contactsService.getObjectIdForCurrentSelection()
        
        if let chatId = chatId {
            didClickOnChatRow(
                chatId: chatId,
                contactId: nil
            )
        } else if let contactId = contactId {
            didClickOnChatRow(
                chatId: nil,
                contactId: contactId
            )
        }
    }
    
    func didClickOnChatRow(
        chatId: Int?,
        contactId: Int?
    ) {
        if let contactId = contactId, let contact = UserContact.getContactWith(id: contactId), contact.isPending(), let invite = contact.invite {
            goToInviteCodeString(
                inviteCode: invite.inviteString ?? ""
            )
        } else {
            presentChatVCFor(
                chatId: chatId,
                contactId: contactId
            )
        }
    }
    
    func shouldReloadChatRowWith(chatId: Int) {
        listViewController?.shouldReloadChatRowWith(chatId: chatId)
    }
    
    func goToInviteCodeString(inviteCode: String) {
        if inviteCode == "" {
            return
        }
        let shareInviteCodeVC = ShareInviteCodeViewController.instantiate(qrCodeString: inviteCode, viewMode: .Invite)
        WindowsManager.sharedInstance.showInviteCodeWindow(vc: shareInviteCodeVC, window: view.window)
    }
    
    func presentChatVCFor(
        chatId: Int?,
        contactId: Int?,
        forceReload: Bool = false
    ) {
        if let chatId = chatId, newDetailViewController?.chat?.id == chatId, !forceReload {
            return
        }
        
        if let contactId = contactId, newDetailViewController?.contact?.id == contactId, !forceReload {
            return
        }
        
        if let detailViewController = newDetailViewController {
            detailViewController.resetVC()
            
            self.removeChildVC(child: detailViewController)
            
            newDetailViewController = nil
        }
        
        let chat = chatId != nil ? Chat.getChatWith(id: chatId!) : nil
        let contact = contactId != nil ? UserContact.getContactWith(id: contactId!) : chat?.getConversationContact()
        
        let newChatVCController = NewChatViewController.instantiate(
            contactId: contact?.id,
            chatId: chat?.id,
            delegate: self,
            deepLinkData: deeplinkData
        )
        
        self.addChildVC(
            child: newChatVCController,
            container: rightSplittedView
        )
        dashboardDetailViewController?.closeButtonTapped()
        
        newDetailViewController = newChatVCController

        deeplinkData = nil
    }
    
    func shouldShowFullMediaFor(message: TransactionMessage) {
        goToMediaFullView(message: message)
    }
    
    func shouldShowFullMediaFor(url: String) {
        if mediaFullScreenView == nil {
            mediaFullScreenView = MediaFullScreenView()
        }
        
        if let mediaFullScreenView = mediaFullScreenView {
            view.addSubview(mediaFullScreenView)
            
            mediaFullScreenView.delegate = self
            mediaFullScreenView.constraintTo(view: view)
            mediaFullScreenView.showWith(imageUrl: url)
            mediaFullScreenView.isHidden = false
        }
    }
    
    func goToMediaFullView(message: TransactionMessage?) {
        if mediaFullScreenView == nil {
            mediaFullScreenView = MediaFullScreenView()
        }
        
        if let mediaFullScreenView = mediaFullScreenView, let message = message {
            view.addSubview(mediaFullScreenView)
            
            mediaFullScreenView.delegate = self
            mediaFullScreenView.constraintTo(view: view)
            mediaFullScreenView.showWith(message: message)
            mediaFullScreenView.isHidden = false
        }
    }
    
    func handleImageNotification(_ notification: Notification) {
        if let imageURL = notification.userInfo?["imageURL"] as? URL,
           let message = notification.userInfo?["transactionMessage"] as? TransactionMessage {
            goToMediaFullView(imageURL: imageURL,message: message)
        } else {
            NewMessageBubbleHelper().showGenericMessageView(text: "Error pulling image data.")
        }
    }
    
    func shouldToggleLeftView(show: Bool?) {
        if let window = view.window {
            let menuVisible = show ?? !isLeftMenuCollapsed()
            newDetailViewController?.toggleExpandMenuButton(show: !menuVisible)
            let (minWidth, _) = getWindowMinWidth(leftColumnVisible: menuVisible)
            leftSplittedView.isHidden = !menuVisible
            window.minSize = CGSize(width: minWidth, height: kWindowMinHeight)

            let newWidth = menuVisible ? max(window.frame.width, minWidth) : window.frame.width
            let newFrame = CGRect(x: window.frame.origin.x, y: window.frame.origin.y, width: newWidth, height: window.frame.height)
            window.setFrame(newFrame, display: true)
        }
    }

    func isLeftMenuCollapsed() -> Bool {
        return leftSplittedView.isHidden
    }

    func getWindowMinWidth(leftColumnVisible: Bool) -> (CGFloat, CGFloat) {
        let podcastPlayerWidth =  newDetailViewController?.podcastPlayerView.frame.width ?? 0
        let leftPanelWidth = leftSplittedView.frame.width
        let minWidth: CGFloat = leftColumnVisible ? kWindowMinWidthWithoutLeftColumn + leftPanelWidth : kWindowMinWidthWithoutLeftColumn
        return (minWidth + podcastPlayerWidth, leftPanelWidth)
    }
    
    func shouldHideRestoreModal(){
        for childVC in self.children.compactMap({$0 as? DashboardModalsViewController}) {
            if !childVC.restoreProgressView.isHidden {
                modalsContainerView.isHidden = true
            }
        }
    }
    
    func shouldShowRestoreModal(
        with progress: Int,
        label: String,
        buttonEnabled: Bool
    ) {
        for childVC in self.children {
            if let childVC = childVC as? DashboardModalsViewController {
                modalsContainerView.isHidden = false
                
                childVC.showProgressViewWith(
                    with: progress,
                    label: label,
                    buttonEnabled: buttonEnabled,
                    delegate: self
                )
            }
        }
    }
    
    func shouldHideRetoreModal() {
        didFinishRestoring()
    }
    
    func showFinishingRestore() {
        for childVC in self.children {
            if let childVC = childVC as? DashboardModalsViewController {
                modalsContainerView.isHidden = false
                
                childVC.setFinishingRestore()
            }
        }
    }
}

extension DashboardViewController : MediaFullScreenDelegate {
    func willDismissView() {
        if let mediaFullScreenView = mediaFullScreenView {
            mediaFullScreenView.removeFromSuperview()
            self.mediaFullScreenView = nil
        }
    }
}

extension DashboardViewController : PeopleModalsViewControllerDelegate {
    func shouldHideContainer() {
        modalsContainerView.isHidden = true
    }
}

extension DashboardViewController : RestoreModalViewControllerDelegate {
    func didFinishRestoreManually() {
        chatListViewModel.finishRestoring()
        showFinishingRestore()
        SphinxOnionManager.sharedInstance.attempFinishResotoration()
    }
    
    func didFinishRestoring() {
        shouldHideRestoreModal()
    }
}

extension DashboardViewController: NewContactDismissDelegate {
    func shouldDismissView() {
        closePresenter()
    }
}

extension DashboardViewController: DashboardDetailDismissDelegate {
    func closeButtonTapped() {
        rightDetailViewMaxWidth.constant = 0
        rightDetailSplittedView.isHidden = true
        
        newDetailViewController?.chatBottomView.messageFieldView.isThreadOpen = false
        newDetailViewController?.chatBottomView.messageFieldView.updatePriceTagField()
    }
}
