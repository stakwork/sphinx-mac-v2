//
//  AppDelegate.swift
//  com.stakwork.sphinx.desktop
//
//  Created by Tomas Timinskas on 10/03/2020.
//  Copyright © 2020 Sphinx. All rights reserved.
//

import Cocoa
import CoreData
import SDWebImage
import WebKit

@NSApplicationMain
 class AppDelegate: NSObject, NSApplicationDelegate {
    
    let notificationsHelper = NotificationsHelper()
    var newMessageBubbleHelper = NewMessageBubbleHelper()
    
    let onionConnector = SphinxOnionConnector.sharedInstance
    
    var statusBarItem: NSStatusItem!
    
    @IBOutlet weak var appearanceMenu: NSMenu!
    @IBOutlet weak var notificationTypeMenu: NSMenu!
    @IBOutlet weak var notificationSoundMenu: NSMenu!
    @IBOutlet weak var messagesSizeMenu: NSMenu!
    
    @IBOutlet weak var logoutMenuItem: NSMenuItem!
    @IBOutlet weak var removeAccountMenuItem: NSMenuItem!
    
    let actionsManager = ActionsManager.sharedInstance
    let feedsManager = FeedsManager.sharedInstance
    let podcastPlayerController = PodcastPlayerController.sharedInstance
    
    public enum SphinxMenuButton: Int {
        case Logout = 0
        case RemoveAccount = 1
    }
    
    var lastClearSDMemoryDate: Date? {
        get {
            return UserDefaults.Keys.clearSDMemoryDate.get(defaultValue: nil)
        }
        set {
            UserDefaults.Keys.clearSDMemoryDate.set(newValue)
        }
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        setAppSettings()
        clearWebkitCache()
        
        SDImageCache.shared.clearMemory()
        SDImageCache.shared.config.maxMemoryCount = 100
        MediaLoader.deleteOldMedia()
        
        listenToSleepEvents()
        
        NetworkMonitor.shared.startMonitoring()
        
        ColorsManager.sharedInstance.storeColorsInMemory()
        SphinxOnionManager.sharedInstance.storeOnionStateInMemory()
        
        setInitialVC()
    }
    
    func clearWebkitCache() {
        URLCache.shared.removeAllCachedResponses()

        if let cookies = HTTPCookieStorage.shared.cookies {
            for cookie in cookies {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }
        
        WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: Date(timeIntervalSince1970: 0),
            completionHandler: {}
        )
    }
    
    func application(_ application: NSApplication, open urls: [URL]) {
        if urls.count > 0 {
            if let _ = getDashboardWindow() {
                for url in urls {
                    DeepLinksHandlerHelper.handleLinkQueryFrom(url: url)
                }
            } else {
                if let url = urls.first {
                    UserDefaults.Keys.linkQuery.set(url.absoluteString)
                }
            }
        }
    }
     
    func application(
        _ application: NSApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([NSUserActivityRestoring]) -> Void
    ) -> Bool {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb, 
                let url = userActivity.webpageURL,
                let _ = URLComponents(url: url, resolvingAgainstBaseURL: true) else
        {
            return false
        }
        
        if let _ = getDashboardWindow() {
            WindowsManager.sharedInstance.showCallWindow(link: url.absoluteString)
        } else {
            UserDefaults.Keys.linkQuery.set(url.absoluteString)
        }
         
        return true
    }
     
    func connectMQTT() {
        if let phoneSignerSetup: Bool = UserDefaults.Keys.setupPhoneSigner.get(), phoneSignerSetup {
            CrypterManager.sharedInstance.startMQTTSetup()
        }
    }

    
    func addStatusBarItem() {
        let statusBar = NSStatusBar.system
        statusBarItem = statusBar.statusItem(withLength: NSStatusItem.squareLength)
        statusBarItem.button?.image = NSImage(named: "extraIcon")
        statusBarItem.button?.imageScaling = .scaleProportionallyDown
        statusBarItem.button?.action = #selector(activateApp)
    }
    
    @objc func activateApp() {
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    
    func setAppSettings() {
        let savedAppearance = UserDefaults.Keys.appAppearance.get(defaultValue: 0)
        setAppearanceFrom(value: savedAppearance, shouldUpdate: false)
        
        let notificationType = UserDefaults.Keys.notificationType.get(defaultValue: 0)
        selectItemWith(tag: notificationType, in: notificationTypeMenu)
        
        let notificationSoundTag = notificationsHelper.getNotificationSoundTag()
        selectItemWith(tag: notificationSoundTag, in: notificationSoundMenu)
        
        let messagesSize = UserDefaults.Keys.messagesSize.get(defaultValue: MessagesSize.Medium.rawValue)
        setMessagesSizeFrom(value: messagesSize)
    }
    
    
    func setAppMenuVisibility(shouldEnableItems: Bool) {
        [
//            logoutMenuItem,
            removeAccountMenuItem,
        ]
        .forEach { $0?.isHidden = shouldEnableItems == false }
        
        logoutMenuItem.isHidden = true
    }
    
    
    func setInitialVC() {
        if let mainWindow = getDashboardWindow() {
            mainWindow.replaceContentBy(vc: DashboardViewController.instantiate())
        } else {
            if UserData.sharedInstance.isSignupCompleted() {
                ContactsService.sharedInstance.setSelectedChat()
                presentPIN()
            } else {
                let splashVC = SplashViewController.instantiate()
                let windowState = WindowsManager.sharedInstance.getWindowState()
                createKeyWindowWith(vc: splashVC, windowState: windowState, closeOther: false, hideBar: true)
            }
        }
    }
    
    func createKeyWindowWith(vc: NSViewController, windowState: WindowState, closeOther: Bool = false, hideBar: Bool = false) {
        if closeOther {
            for window in NSApplication.shared.windows {
                window.close()
            }
        }
        
        let storyboard = NSStoryboard(name: NSStoryboard.Name("Main"), bundle: Bundle.main)
        let window = storyboard.instantiateController(withIdentifier: "MainWindow") as! NSWindowController
        window.contentViewController = vc
        window.window?.title = "Sphinx"
        window.window?.styleMask = hideBar ? [.titled, .resizable, .miniaturizable, .fullSizeContentView] : [.titled, .resizable, .miniaturizable]
        window.window?.minSize = windowState.minSize
        window.window?.titlebarAppearsTransparent = hideBar
        window.window?.titleVisibility = hideBar ? .hidden : .visible
        window.window?.setFrame(windowState.frame, display: true)
        window.window?.makeKey()
        window.showWindow(self)
        
        // MARK: - For Testing Purpose
        let view = vc.view
        if let newWindow = window.window {
            newWindow.setAccessibilityEnabled(true)
            newWindow.setAccessibilityRole(.window)
            newWindow.setAccessibilityIdentifier("MainWindow")
        }
        window.window?.setAccessibilityChildren([view])
        view.setAccessibilityRole(.window)
        view.setAccessibilityIdentifier("MainView")
        // MARK: - End
        addStatusBarItem()
    }
    
    func getDashboardWindow() -> NSWindow? {
        for w in NSApplication.shared.windows {
            if let _ = w.contentViewController as? DashboardViewController {
                return w
            }
        }
        return nil
    }
     
     func getDashboardVC() -> DashboardViewController? {
         for w in NSApplication.shared.windows {
             if let vc = w.contentViewController as? DashboardViewController {
                 return vc
             }
         }
         return nil
     }
    
    func listenToSleepEvents() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(sleepListener(aNotification:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }
    
    @objc func sleepListener(aNotification: NSNotification) {
        if (aNotification.name == NSWorkspace.didWakeNotification) && UserData.sharedInstance.isUserLogged() {
            SDImageCache.shared.clearMemory()
            
            NotificationCenter.default.post(
                name: .onConnectionStatusChanged,
                object: nil
            )
            
            getDashboardVC()?.reconnectToServer()
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        WindowsManager.sharedInstance.saveWindowState()
        CoreDataManager.sharedManager.saveContext()
        ContactsService.sharedInstance.saveSelectedChat()
    }
    
    func applicationWillBecomeActive(_ notification: Notification) {
        if GroupsPinManager.sharedInstance.shouldAskForPin() {
            presentPIN()
            return
        }
        
        if UserData.sharedInstance.isUserLogged() {
            
            NotificationCenter.default.post(
                name: .onConnectionStatusChanged,
                object: nil
            )
            
            getDashboardVC()?.reconnectToServer()
            
            feedsManager.restoreContentFeedStatusInBackground()
        }
    }
    
    func presentPIN() {
        setAppMenuVisibility(shouldEnableItems: false)
        CoreDataManager.sharedManager.resetContext()
        SDImageCache.shared.clearMemory()
        
        let pinVC = EnterPinViewController.instantiate(mode: .Launch)
        pinVC.doneCompletion = { pin in
            UserDefaults.Keys.lastPinDate.set(Date())
            self.updateDefaultTribe()
            self.setAppMenuVisibility(shouldEnableItems: true)
            self.loadDashboard()
        }
        
        createKeyWindowWith(
            vc: pinVC,
            windowState: WindowsManager.sharedInstance.getWindowState(),
            closeOther: true,
            hideBar: true
        )
    }
     
    func updateDefaultTribe() {
        if !SphinxOnionManager.sharedInstance.isProductionEnv {
            return
        }

        if !UserData.sharedInstance.isUserLogged() {
            return
        }

        API.sharedInstance.updateDefaultTribe()
    }
    
    func loadDashboard() {
        createKeyWindowWith(
            vc: DashboardViewController.instantiate(),
            windowState: WindowsManager.sharedInstance.getWindowState(),
            closeOther: true
        )
        ContactsService.sharedInstance.forceUpdate()
    }
    
    func applicationWillResignActive(_ notification: Notification) {
        if UserData.sharedInstance.isUserLogged() {
            setBadge()
            
            podcastPlayerController.finishAndSaveContentConsumed()
            actionsManager.syncActionsInBackground()
            
            CoreDataManager.sharedManager.saveContext()
        }
    }
     
     func setBadge() {
         let backgroundContext = CoreDataManager.sharedManager.getBackgroundContext()
         
         backgroundContext.perform {
             let receivedUnseenCount = TransactionMessage.getReceivedUnseenMessagesCount(context: backgroundContext)
             
             DispatchQueue.main.async {
                 self.setBadge(count: receivedUnseenCount)
             }
         }
     }
    
    func setBadge(count: Int) {
        statusBarItem.button?.image = NSImage(named: count > 0 ? "extraIconBadge" : "extraIcon")
        
        let title = count > 0 ? "\(count)" : ""
        NSApp.dockTile.badgeLabel = title
    }
    
    func sendNotification(message: TransactionMessage) -> Void {
        notificationsHelper.sendNotification(message: message)
    }
     
     func sendNotification(
        title: String,
        subtitle: String? = nil,
        text: String
     ) -> Void {
         notificationsHelper.sendNotification(
            title: title,
            subtitle: subtitle,
            text: text
         )
     }
    
    @IBAction func appearenceButtonClicked(_ sender: NSMenuItem) {        
        setAppearanceFrom(value: sender.tag, shouldUpdate: true)
        UserDefaults.Keys.appAppearance.set(sender.tag)
    }
    
    @IBAction func notificationTypeButtonClicked(_ sender: NSMenuItem) {
        notificationsHelper.setNotificationType(tag: sender.tag)
        selectItemWith(tag: sender.tag, in: notificationTypeMenu)
    }
    
    @IBAction func notificationSoundButtonClicked(_ sender: NSMenuItem) {
        notificationsHelper.setNotificationSound(tag: sender.tag)
        selectItemWith(tag: sender.tag, in: notificationSoundMenu)
        SoundsPlayer.playSound(name: notificationsHelper.getNotificationSoundFile())
    }
    
    @IBAction func messagesSizeButtonClicked(_ sender: NSMenuItem) {
        UserDefaults.Keys.messagesSize.set(sender.tag)
        setMessagesSizeFrom(value: sender.tag, reloadViews: true)
    }
    
    @IBAction func sphinxMenuButtonClicked(_ sender: NSMenuItem) {
        switch(sender.tag) {
        case SphinxMenuButton.Logout.rawValue:
            logoutButtonClicked()
        case SphinxMenuButton.RemoveAccount.rawValue:
            removeAccountButtonClicked()
        default:
            break
        }
    }
    
    func removeAccountButtonClicked() {
        setBadge(count: 0)
        
        AlertHelper.showTwoOptionsAlert(title: "logout".localized, message: "logout.text".localized, confirm: {
            self.stopListeningToMessages()
            
            SphinxOnionManager.sharedInstance.disconnectMqtt() {
                SphinxOnionManager.resetSharedInstance()
                ContactsService.sharedInstance.reset()
                UserData.sharedInstance.clearData()
                SphinxCache().removeAll()
                
                DispatchQueue.main.async {
                    let frame = WindowsManager.sharedInstance.getCenteredFrameFor(size: CGSize(width: 800, height: 500))
                    let keyWindow = NSApplication.shared.keyWindow
                    keyWindow?.styleMask = [.titled, .miniaturizable, .fullSizeContentView]
                    keyWindow?.titleVisibility = .hidden
                    keyWindow?.titlebarAppearsTransparent = true
                    keyWindow?.replaceContentBy(vc: SplashViewController.instantiate())
                    keyWindow?.setFrame(frame, display: true, animate: true)
                }
            }
        })
    }
     
     func stopListeningToMessages() {
         if let dashboard = NSApplication.shared.keyWindow?.contentViewController as? DashboardViewController {
             dashboard.newDetailViewController?.resetVC()
         }
     }
    
    func logoutButtonClicked() {
//        ContactsService.sharedInstance.reset()
//        GroupsPinManager.sharedInstance.logout()
//        presentPIN()
    }
    
    func selectItemWith(tag: Int, in menu: NSMenu) {
        for item in menu.items {
            if item.tag == tag {
                item.state = .on
            } else {
                item.state = .off
            }
        }
    }
    
    func setAppearanceFrom(value: Int, shouldUpdate: Bool) {
        selectItemWith(tag: value, in: appearanceMenu)
        
        if #available(OSX 10.14, *) {
            if value <= 0 {
                NSApp.appearance = nil
            } else if value == 1 {
                NSApp.appearance = NSAppearance(named: .aqua)
            } else if value == 2 {
                NSApp.appearance = NSAppearance(named: .darkAqua)
            }
        }
        
        if shouldUpdate {
            DistributedNotificationCenter.default().post(name: .onInterfaceThemeChanged, object: nil)
        }
    }
    
    func setMessagesSizeFrom(value: Int, reloadViews: Bool = false) {
        selectItemWith(tag: value, in: messagesSizeMenu)
        Constants.setSize()
        
        if reloadViews {
            NotificationCenter.default.post(name: .shouldReloadViews, object: nil)
        }
    }
     
     func askForNotificationsPermission() {
         notificationsHelper.askForNotificationsPermission()
     }
}

//extension AppDelegate : SphinxOnionConnectorDelegate {
//    func onionConnecting() {
//        newMessageBubbleHelper.showGenericMessageView(text: "establishing.tor.circuit".localized)
//    }
//    
//    func onionConnectionFinished() {
//        newMessageBubbleHelper.hideLoadingWheel()
//        
//        NotificationCenter.default.post(name: .shouldUpdateDashboard, object: nil)
//    }
//    
//    func onionConnectionFailed() {
//        newMessageBubbleHelper.hideLoadingWheel()
//        newMessageBubbleHelper.showGenericMessageView(text: "tor.connection.failed".localized)
//    }
//}


