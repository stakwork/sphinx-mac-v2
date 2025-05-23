//
//  WindowsManager.swift
//  com.stakwork.sphinx.desktop
//
//  Created by Tomas Timinskas on 12/05/2020.
//  Copyright © 2020 Sphinx. All rights reserved.
//

import Cocoa
import SwiftUI

class WindowsManager {
    
    class var sharedInstance : WindowsManager {
        struct Static {
            static let instance = WindowsManager()
        }
        return Static.instance
    }
    
    var controlsPanel: DraggablePanel? = nil
    var openedWindowIdentifiers: [String] = []
    
    func saveWindowState() {
        if let keyWindow = NSApplication.shared.keyWindow {
            //            let menuCollapsed = (keyWindow.contentViewController as? DashboardViewController)?.isLeftMenuCollapsed() ?? false
            let menuCollapsed = false
            let windowState = WindowState(frame: keyWindow.frame, minSize: keyWindow.minSize, menuCollapsed: menuCollapsed)
            
            let encoder = JSONEncoder()
            if let encoded = try? encoder.encode(windowState) {
                UserDefaults.Keys.windowRect.set(encoded)
            }
        }
    }
    
    func getWindowState() -> WindowState {
        var windowState: WindowState? = nil
        
        if let data: Data = UserDefaults.Keys.windowRect.get() {
            let decoder = JSONDecoder()
            if let decoded = try? decoder.decode(WindowState.self, from: data) {
                windowState = decoded
            }
        }
        
        if let windowState = windowState {
            return windowState
        }
        
        let isUserLogged = UserData.sharedInstance.isUserLogged()
        let initialSize = isUserLogged ? CGSize(width: 1100, height: 850) : CGSize(width: 800, height: 500)
        let minSize = isUserLogged ? CGSize(width: 950, height: 735) : CGSize(width: 800, height: 500)
        let initialFrame = getCenteredFrameFor(size: initialSize)
        
        return WindowState(frame: initialFrame, minSize: minSize, menuCollapsed: false)
    }
    
    func getLastTaggedWindows() -> TaggedWindow? {
        return NSApplication.shared.windows.filter({
            $0.isKind(of: TaggedWindow.self) && 
            ($0 as? TaggedWindow)?.windowIdentifier?.contains("web-app") == false &&
            ($0 as? TaggedWindow)?.windowIdentifier?.contains("rooms/sphinx.chat") == false &&
            ($0 as? TaggedWindow)?.windowIdentifier?.contains("rooms/sphinx.call") == false
        }).last as? TaggedWindow
    }
    
    func getLiveKitCallWindow() -> TaggedWindow? {
        return NSApplication.shared.windows.filter({
            $0.isKind(of: TaggedWindow.self) &&
            ($0 as? TaggedWindow)?.windowIdentifier?.contains("rooms/sphinx.call") == true
        }).last as? TaggedWindow
    }
    
    func getCenteredFrameFor(size: CGSize) -> CGRect {
        let mainScreen = NSScreen.main
        let centerPoint = CGPoint(x: ((mainScreen?.frame.width ?? 1000) / 2) - (size.width / 2), y: ((mainScreen?.frame.height ?? 735) / 2) - (size.height / 2))
        let initialFrame = CGRect(x: centerPoint.x, y: centerPoint.y, width: size.width, height: size.height)
        return initialFrame
    }
    
    func getWindowStateFor(size: CGSize) -> WindowState {
        let mainScreen = NSScreen.main
        let centerPoint = CGPoint(x: ((mainScreen?.frame.width ?? 1000) / 2) - (size.width / 2), y: ((mainScreen?.frame.height ?? 735) / 2) - (size.height / 2))
        let initialFrame = CGRect(x: centerPoint.x, y: centerPoint.y, width: size.width, height: size.height)
        return WindowState(frame: initialFrame, minSize: size, menuCollapsed: false)
    }
    
    ///Dashboard modals
    func showOnCurrentWindow(
        with title: String,
        identifier: String? = nil,
        contentVC: NSViewController,
        hideDivider: Bool = true,
        hideBackButton: Bool = true,
        replacingVC: Bool = false,
        height: CGFloat? = nil,
        width: CGFloat? = nil,
        hideHeaderView: Bool = false,
        backHandler: (() -> ())? = nil
    ) {
        guard let keyWindow = NSApplication.shared.keyWindow, let dashboardVC = keyWindow.contentViewController as? DashboardViewController else {
            return
        }
        
        ///Set title, back button state and divider state
        dashboardVC.presenterTitleLabel.stringValue = title
        dashboardVC.presenterHeaderDivider.isHidden = hideDivider
        
        if let backHandler = backHandler {
            dashboardVC.presenterBackHandler = backHandler
            dashboardVC.presenterBackButton.isHidden = hideBackButton
        } else {
            dashboardVC.presenterBackButton.isHidden = true
        }
        
        ///Animate if replacing one VC by another
        if replacingVC {
            AnimationHelper.animateViewWith(duration: 0.25, animationsBlock: {
                dashboardVC.presenter?.view.alphaValue = 0.0
            }, completion: {
                self.showVCOnCurrentWindow(
                    with: title,
                    identifier: identifier,
                    contentVC: contentVC,
                    hideDivider: hideDivider,
                    hideBackButton: hideBackButton,
                    replacingVC: replacingVC,
                    height: height,
                    width: width,
                    hideHeaderView: hideHeaderView,
                    backHandler: backHandler
                )
            })
        } else {
            showVCOnCurrentWindow(
                with: title,
                identifier: identifier,
                contentVC: contentVC,
                hideDivider: hideDivider,
                hideBackButton: hideBackButton,
                replacingVC: replacingVC,
                height: height,
                width: width,
                hideHeaderView: hideHeaderView,
                backHandler: backHandler
            )
        }
    }
    
    func showVCOnCurrentWindow(
        with title: String,
        identifier: String? = nil,
        contentVC: NSViewController,
        hideDivider: Bool = true,
        hideBackButton: Bool = true,
        replacingVC: Bool = false,
        height: CGFloat? = nil,
        width: CGFloat? = nil,
        hideHeaderView: Bool = false,
        backHandler: (() -> ())? = nil
    ) {
        guard let keyWindow = NSApplication.shared.keyWindow, let dashboardVC = keyWindow.contentViewController as? DashboardViewController else {
            return
        }
        
        if replacingVC {
            ///show presenter Container since it won't animate
            dashboardVC.presenterContainerBGView.alphaValue = 1.0
        } else {
            ///hide presenter Container since it will animate
            dashboardVC.presenterContainerBGView.alphaValue = 0.0
        }
        dashboardVC.presenterContainerBGView.isHidden = false
        dashboardVC.presenter?.view.isHidden = false
        
        ///Set corner radius of container
        dashboardVC.presenterContentBox.layer?.cornerRadius = 12
        
        ///Set content height based on VC content size. 2000 exceeds the windows height so margins will apply
        if let height = height {
            dashboardVC.presenterViewHeightConstraint.constant = height
        } else {
            dashboardVC.presenterViewHeightConstraint.constant = 3000
        }
        
        if let width {
            dashboardVC.presenterViewWidthConstraint.constant = width
        } else {
            dashboardVC.presenterViewWidthConstraint.constant = 400
        }
        
        if hideHeaderView {
            dashboardVC.presenterHeaderView.isHidden = true
            dashboardVC.presenterContentBox.fillColor = .clear
        } else {
            dashboardVC.presenterHeaderView.isHidden = false
            dashboardVC.presenterContentBox.fillColor = NSColor.Sphinx.Body
        }
        
        if !replacingVC {
            ///show VC content so it's there when animates
            dashboardVC.presenterContentBox.layoutSubtreeIfNeeded()
            
            addVCIntoPopup(
                dashboardVC: dashboardVC,
                contentVC: contentVC,
                identifier: identifier
            )
        }
        
        AnimationHelper.animateViewWith(duration: 0.25, animationsBlock: {
            if replacingVC {
                ///Animates popup height since it's transitioning from one VC to the other
                dashboardVC.presenterContentBox.layoutSubtreeIfNeeded()
            } else {
                DispatchQueue.main.async {
                    ///Animates popup alpha since it's showing popup
                    dashboardVC.presenterContainerBGView.animator().alphaValue = 1.0
                }
            }
        }, completion: {
            if replacingVC {
                ///Add destination VC after heigh finnished animating
                dashboardVC.presenter?.view.alphaValue = 1.0
                
                self.addVCIntoPopup(
                    dashboardVC: dashboardVC,
                    contentVC: contentVC,
                    identifier: identifier
                )
            }
        })
    }
    
    func dismissViewFromCurrentWindow()  {
        guard let keyWindow = NSApplication.shared.keyWindow, let dashboardVC = keyWindow.contentViewController as? DashboardViewController else {
            return
        }
        
        AnimationHelper.animateViewWith(duration: 0.25, animationsBlock: {
            DispatchQueue.main.async {
                dashboardVC.presenterContainerBGView.animator().alphaValue = 0.0
            }
        }, completion: {
            dashboardVC.presenterContainerBGView.isHidden = true
            dashboardVC.presenter?.view.isHidden = true
            dashboardVC.presenterIdentifier = nil
            dashboardVC.presenter?.dismissVC()
            
            dashboardVC.newDetailViewController?.setMessageFieldActive()
        })
    }
    
    func showProfileWindow() {
        showOnCurrentWindow(
            with: "profile".localized,
            identifier: "profile-window",
            contentVC: ProfileViewController.instantiate(),
            hideDivider: false
        )
    }
    
    func showTransationsListWindow() {
        showOnCurrentWindow(
            with: "transactions".localized,
            identifier: "transactions-window",
            contentVC: TransactionsListViewController.instantiate(),
            hideDivider: false
        )
    }
    
    func addVCIntoPopup(
        dashboardVC: DashboardViewController,
        contentVC: NSViewController,
        identifier: String? = nil
    ) {
        ///Set content height based on VC content size
        if let presenter = dashboardVC.presenter {
            if let bounds = dashboardVC.presenterContainerView?.bounds {
                presenter.view.frame = bounds
            }
        }
        
        ///Present new VC
        if dashboardVC.presenterIdentifier != identifier {
            dashboardVC.presenter?.dismissVC()
            dashboardVC.presenter?.contentVC = nil
            dashboardVC.presenter?.configurePresenterVC(contentVC)
            dashboardVC.presenterIdentifier = identifier
        }
    }
    
    func backToAddFriend() {
        if let keyWindow = NSApplication.shared.keyWindow {
            if let dashboardVC = keyWindow.contentViewController as? DashboardViewController {
                dashboardVC.presenterContainerBGView.isHidden = false
                
                let addFriendVC = AddFriendViewController.instantiate(delegate: dashboardVC.listViewController.self, dismissDelegate: dashboardVC)
                
                dashboardVC.presenterBackButton.isHidden = true
                
                showOnCurrentWindow(
                    with: "new.contact".localized,
                    identifier: "contact-custom-window",
                    contentVC: addFriendVC,
                    hideDivider: true,
                    hideBackButton: true,
                    replacingVC: true,
                    height: 500,
                    backHandler: backToAddFriend
                )
            }
        }
    }
    
    func backToProfile() {
        if let keyWindow = NSApplication.shared.keyWindow {
            if let dashboardVC = keyWindow.contentViewController as? DashboardViewController {
                dashboardVC.presenterContainerBGView.isHidden = false
                
                let profileVC = ProfileViewController.instantiate()
                
                dashboardVC.presenterBackButton.isHidden = true
                
                showOnCurrentWindow(
                    with: "profile".localized,
                    identifier: "profile-window",
                    contentVC: profileVC,
                    hideDivider: false,
                    hideBackButton: true,
                    replacingVC: true
                )
            }
        }
    }
    
    ///Right Panel
    func showVCOnRightPanelWindow(
        with title: String,
        identifier: String? = nil,
        contentVC: NSViewController,
        shouldReplace: Bool = true,
        panelFixedWidth: Bool = false
    ) {
        guard let appDelegate = NSApplication.shared.delegate as? AppDelegate, let dashboardVC = appDelegate.getDashboardVC() else {
            return
        }
        
        dashboardVC.rightDetailViewMinWidth.constant = panelFixedWidth ? DashboardViewController.kRightPanelMaxWidth : DashboardViewController.kRightPanelMinWidth
        dashboardVC.rightDetailViewMaxWidth.constant = DashboardViewController.kRightPanelMaxWidth
        
        dashboardVC.rightDetailSplittedView.isHidden = false
        
        if let detailVC = dashboardVC.dashboardDetailViewController {
            detailVC.displayVC(
                contentVC,
                vcTitle: title,
                vcIdentifier: identifier,
                shouldReplace: shouldReplace,
                fixedWidth: panelFixedWidth ? DashboardViewController.kRightPanelMaxWidth : nil
            )
        }
    }
    
    ///New Windows
    func showNewWindow(
        with title: String,
        size: CGSize,
        minSize: CGSize? = nil,
        centeredIn w: NSWindow? = nil,
        position: CGPoint? = nil,
        identifier: String? = nil,
        chatIdentifier: Int? = nil,
        delegate: NSWindowDelegate? = nil,
        styleMask: NSWindow.StyleMask = [.closable, .titled, .resizable],
        backgroundColor: NSColor? = nil,
        contentVC: NSViewController
    ) {
        
        let newWindow = TaggedWindow(contentRect: .init(origin: .zero, size: size),
                                     styleMask: styleMask,
                                     backing: .buffered,
                                     defer: false)
        
        newWindow.title = title
        newWindow.minSize = minSize ?? size
        newWindow.isMovableByWindowBackground = false
        newWindow.contentViewController = contentVC
        newWindow.makeKeyAndOrderFront(nil)
        newWindow.isReleasedWhenClosed = false
        newWindow.windowIdentifier = identifier
        newWindow.chatIdentifier = chatIdentifier
        newWindow.backgroundColor = backgroundColor ?? NSColor.Sphinx.Body
        newWindow.isOpaque = false
        newWindow.toolbarStyle = .unifiedCompact
        newWindow.titlebarAppearsTransparent = true
        newWindow.delegate = delegate
        
        if let w = w {
            let position = CGPoint(x: w.frame.origin.x + (w.frame.width - size.width) / 2, y: w.frame.origin.y + (w.frame.height - size.height) / 2)
            newWindow.setFrame(.init(origin: position, size: size), display: true)
        } else if let position = position {
            newWindow.setFrame(.init(origin: position, size: size), display: true)
        } else {
            newWindow.center()
        }
    }
    
    ///New Windows
    func showControlsPanel(
        with title: String,
        size: CGSize,
        minSize: CGSize? = nil,
        centeredIn w: NSWindow? = nil,
        position: CGPoint? = nil,
        identifier: String? = nil,
        chatIdentifier: Int? = nil,
        backgroundColor: NSColor? = nil,
        contentVC: NSViewController
    ) {
        
        let newWindow = NSPanel(
            contentRect: .init(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        
        newWindow.title = title
        newWindow.minSize = minSize ?? size
        newWindow.isMovableByWindowBackground = false
        newWindow.contentViewController = contentVC
        newWindow.makeKeyAndOrderFront(nil)
        newWindow.isReleasedWhenClosed = false
        newWindow.backgroundColor = backgroundColor ?? NSColor.Sphinx.Body
        newWindow.isOpaque = false
        newWindow.toolbarStyle = .unifiedCompact
        newWindow.titlebarAppearsTransparent = true
        newWindow.styleMask = [.nonactivatingPanel, .borderless]
        newWindow.level = .mainMenu
        newWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        if let w = w {
            let position = CGPoint(x: w.frame.origin.x + (w.frame.width - size.width) / 2, y: w.frame.origin.y + (w.frame.height - size.height) / 2)
            newWindow.setFrame(.init(origin: position, size: size), display: true)
        } else if let position = position {
            newWindow.setFrame(.init(origin: position, size: size), display: true)
        } else {
            newWindow.center()
        }
    }
    
    func showWebAppWindow(chat: Chat?, view: NSView, isAppURL: Bool = true) {
        if let chat = chat, let tribeInfo = chat.tribeInfo, let appURL = isAppURL ? tribeInfo.appUrl : tribeInfo.secondBrainUrl, !appURL.isEmpty && appURL.isValidURL,
           let webAppVC = WebAppViewController.instantiate(chat: chat, isAppURL: isAppURL) {
            
            let appTitle = chat.name ?? ""
            let screen = NSApplication.shared.keyWindow
            let frame : CGRect = screen?.frame ?? view.frame
            
            let position = (screen?.frame.origin) ?? CGPoint(x: 0.0, y: 0.0)
            
            showNewWindow(with: appTitle,
                          size: CGSize(width: frame.width, height: frame.height),
                          minSize: CGSize(width: 350, height: 550),
                          position: position,
                          identifier: chat.getWebAppIdentifier(),
                          styleMask: [.titled, .resizable, .closable],
                          contentVC: webAppVC)
        } else {
            AlertHelper.showAlert(title: "generic.error.title".localized, message: "generic.error.message".localized)
        }
    }
    
    func showWebAppWindow(url: String, isAppURL: Bool = true) {
        if !url.isEmpty && url.isValidURL, let webAppVC = WebAppViewController.instantiate(appURL: url) {
            
            let appTitle = "Web App"
            
            guard let screen = NSApplication.shared.keyWindow else {
                return
            }
            
            let frame: CGRect = screen.frame
            let position = screen.frame.origin
            
            showNewWindow(with: appTitle,
                          size: CGSize(width: frame.width, height: frame.height),
                          minSize: CGSize(width: 350, height: 550),
                          position: position,
                          identifier: url,
                          styleMask: [.titled, .resizable, .closable],
                          contentVC: webAppVC)
        } else {
            AlertHelper.showAlert(title: "generic.error.title".localized, message: "generic.error.message".localized)
        }
    }
    
    func startLiveKitCall(
        link: String,
        audioOnly: Bool,
        shouldStartRecording: Bool = false,
        tribeImage: String? = nil
    ) {
        guard let owner = UserContact.getOwner() else {
            return
        }
        
        if openedWindowIdentifiers.contains(link) {
            return
        }
        
        if let room = link.liveKitRoomName {
            openedWindowIdentifiers.append(link)
            
            API.sharedInstance.getLiveKitToken(
                room: room,
                alias: owner.nickname ?? "",
                profilePicture: owner.avatarUrl,
                callback: { url, token in
                    DispatchQueue.main.async {
                        let appCtx = AppContext(store: sync)
                        let roomCtx = RoomContext(store: sync, delegate: self)
                        
                        roomCtx.url = url
                        roomCtx.startRecording = link.contains("record=true")
                        roomCtx.token = token
                        roomCtx.tribeImage = tribeImage
                        
                        let roomContextView = RoomContextView(
                            audioOnly: audioOnly,
                            shouldStartRecording: shouldStartRecording,
                            onCallEnded: {
                                Task { @MainActor in
                                    self.openedWindowIdentifiers.removeAll(where: { $0 == link })
                                    self.hideCallControlWindow()
                                    self.closeIfExists(identifier: link)
                                }
                        }).environmentObject(appCtx).environmentObject(roomCtx)
                        
                        let hostingController = NSHostingController(rootView: roomContextView)
                        self.presentWindowForCallVC(vc: hostingController, link: link, delegate: roomCtx)
                    }
                },
                errorCallback: { error in
                    self.openedWindowIdentifiers.removeAll(where: { $0 == link })
                    AlertHelper.showAlert(title: "error.getting.token.title".localized, message: error)
                }
            )
        }
    }
    
    func showCallWindow(
        link: String,
        audioOnly: Bool = false,
        shouldStartRecording: Bool = false,
        tribeImage: String? = nil
    ) {
        
        if link.isJitsiCallLink {
            var linkUrl = link
            
            if audioOnly && !link.contains("startAudioOnly") {
                linkUrl = "\(link)#config.startAudioOnly=true"
            }
            
            if let jitsiCallVC = JitsiCallWebViewController.instantiate(link: linkUrl) {
                presentWindowForCallVC(vc: jitsiCallVC, link: linkUrl)
                return
            }
        } else if link.isLiveKitCallLink {
            startLiveKitCall(
                link: link,
                audioOnly: audioOnly || link.contains("startAudioOnly"),
                shouldStartRecording: shouldStartRecording,
                tribeImage: tribeImage
            )
            return
        }
        
        if let url = URL(string: link) {
            NSWorkspace.shared.open(url)
        }
    }
    
    func presentWindowForCallVC(
        vc: NSViewController,
        link: String,
        delegate: NSWindowDelegate? = nil
    ) {
        let screen = NSApplication.shared.keyWindow
        let frame : CGRect = screen?.frame ?? CGRect(x: 0, y: 0, width: 400, height: 400)
        
        let position = (screen?.frame.origin) ?? CGPoint(x: 0.0, y: 0.0)
        
        showNewWindow(
            with: "",
            size: CGSize(width: frame.width, height: frame.height),
            minSize: CGSize(width: 350, height: 550),
            position: position,
            identifier: link,
            delegate: delegate,
            styleMask: [.fullSizeContentView, .titled, .closable, .miniaturizable, .resizable],
            contentVC: vc
        )
    }
    
    func showInviteCodeWindow(vc: NSViewController, window: NSWindow?) {
        showOnCurrentWindow(
            with: "share.invite.code".localized,
            identifier: "invite-code-window",
            contentVC: vc,
            hideDivider: false,
            height: 600
        )
    }
    
    func presentWindowForRightPanelVC(
        vc: NSViewController,
        identifier: String,
        title: String,
        minWidth: CGFloat,
        resizable: Bool
    ) {
        let screen = NSApplication.shared.keyWindow
        let frame : CGRect = screen?.frame ?? CGRect(x: 0, y: 0, width: minWidth, height: 600)
        var position = (screen?.frame.origin) ?? CGPoint(x: 0.0, y: 0.0)
        
        if let mainScreen = NSScreen.main {
            position = CGPoint(x: (mainScreen.frame.width - minWidth) / 2, y: (mainScreen.frame.height - frame.height) / 2)
        }
        
        showNewWindow(
            with: title,
            size: CGSize(width: minWidth, height: frame.height),
            minSize: CGSize(width: minWidth, height: 550),
            position: position,
            identifier: identifier,
            styleMask: resizable ? [.titled, .resizable, .closable] : [.titled, .closable],
            contentVC: vc
        )
    }
    
    func bringToFrontIfExists(identifier: String, chatIdentifier: Int? = nil) -> Bool {
        for window in NSApplication.shared.windows {
            if let window = window as? TaggedWindow {
                if window.windowIdentifier == identifier {
                    if let chatIdentifier = chatIdentifier, let wChatI = window.chatIdentifier, chatIdentifier != wChatI {
                        return false
                    }
                    window.orderedIndex = 0
                    return true
                }
            }
        }
        return false
    }
    
    func closeIfExists(identifier: String) {
        for window in NSApplication.shared.windows {
            if let window = window as? TaggedWindow {
                if window.windowIdentifier == identifier {
                    window.close()
                }
            }
        }
    }
}

extension WindowsManager : RoomContextDelegate {
    func presentCallControlWindowWith(roomCtx: RoomContext) {
        DispatchQueue.main.async {
            let mainScreen = NSScreen.main
            let position = CGPoint(x: (mainScreen?.frame.size.width ?? 166) / 2 - 155, y: 15)
            
            let shareControlView = CallControlView()
                .environmentObject(roomCtx)
                .environmentObject(roomCtx.room)
            
            let hostingController = NSHostingController(rootView: shareControlView)
            
            self.showControlsPanel(
                with: "",
                size: CGSize(width: 332, height: 100),
                minSize: CGSize(width: 332, height: 100),
                position: position,
                identifier: "share-panel",
                backgroundColor: NSColor.clear,
                contentVC: hostingController
            )
        }
    }
    
    func showControlsPanel(
        with title: String,
        size: CGSize,
        minSize: CGSize? = nil,
        position: CGPoint? = nil,
        identifier: String? = nil,
        chatIdentifier: Int? = nil,
        backgroundColor: NSColor? = nil,
        contentVC: NSViewController
    ) {
        let storedPosition = controlsPanel?.frame.origin ?? position
        
        controlsPanel = DraggablePanel(
            contentRect: .init(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        
        controlsPanel?.title = title
        controlsPanel?.minSize = minSize ?? size
        controlsPanel?.isMovableByWindowBackground = false
        controlsPanel?.contentViewController = contentVC
        controlsPanel?.orderFront(nil)
        controlsPanel?.isReleasedWhenClosed = false
        controlsPanel?.backgroundColor = backgroundColor ?? NSColor.Sphinx.BadgeRed
        controlsPanel?.isOpaque = false
        controlsPanel?.toolbarStyle = .unifiedCompact
        controlsPanel?.titlebarAppearsTransparent = true
        controlsPanel?.styleMask = [.nonactivatingPanel, .borderless]
        controlsPanel?.level = .mainMenu
        controlsPanel?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        controlsPanel?.becomesKeyOnlyIfNeeded = false
        
        if let storedPosition = storedPosition {
            controlsPanel?.setFrame(.init(origin: storedPosition, size: size), display: true)
        } else {
            controlsPanel?.center()
        }
    }
    
    func hideCallControlWindow() {
        DispatchQueue.main.async {
            self.controlsPanel?.close()
        }
    }
}

class DraggablePanel: NSPanel {
    private var initialLocation: CGPoint?

    override func mouseDown(with event: NSEvent) {
        // Record the initial click location
        initialLocation = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let initialLocation = initialLocation else { return }

        // Get the new window frame position
        let currentLocation = event.locationInWindow
        let deltaX = currentLocation.x - initialLocation.x
        let deltaY = currentLocation.y - initialLocation.y

        // Update the window's frame origin
        var newFrame = frame
        newFrame.origin.x += deltaX
        newFrame.origin.y += deltaY
        setFrame(newFrame, display: true)
    }
}

struct WindowState: Codable {
    
    var frame: CGRect
    var minSize: CGSize
    var menuCollapsed: Bool
    
    init(frame: CGRect, minSize: CGSize, menuCollapsed: Bool) {
        self.frame = frame
        self.minSize = minSize
        self.menuCollapsed = menuCollapsed
    }
}

class TaggedWindow : NSWindow {
    var windowIdentifier: String? = nil
    var chatIdentifier: Int? = nil
}

