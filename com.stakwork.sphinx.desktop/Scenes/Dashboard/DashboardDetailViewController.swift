//
//  DashboardDetailViewController.swift
//  Sphinx
//
//  Created by Oko-osi Korede on 18/04/2024.
//  Copyright © 2024 Tomas Timinskas. All rights reserved.
//

import Cocoa
protocol DashboardDetailDismissDelegate: AnyObject {
    func closeButtonTapped()
}
class DashboardDetailViewController: NSViewController {

    weak var dismissDelegate: DashboardDetailDismissDelegate?
    
    @IBOutlet weak var headerView: DashboardDetailHeaderView!
    @IBOutlet weak var containerView: ThreadVCContainer!
    
    var addedVC: [NSViewController?]? = []
    var addedTitles: [String]? = []
    
    static func instantiate(delegate: DashboardDetailDismissDelegate? = nil) -> DashboardDetailViewController {
        let viewController = StoryboardScene.Dashboard.dashboardDetailViewController.instantiate()
        viewController.dismissDelegate = delegate
        return viewController
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
        headerView.delegate = self
    }
    
    func resizeSubviews(frame: NSRect) {
        view.frame = frame
        
        guard let currentVC = addedVC?.last else {
            return
        }
        currentVC?.view.frame = containerView.bounds
    }
    
    func updateCurrentVCFrame() {
        if let currentVC = addedVC?.last as? TribeMembersViewController {
            currentVC.groupChatDataSource?.updateFrame()
        }
        
        if let currentVC = addedVC?.last as? NewChatViewController {
            currentVC.chatTableDataSource?.updateFrame()
        }
    }
    
    func displayVC(
        _ vc: NSViewController,
        vcTitle: String,
        shouldReplace: Bool = true,
        fixedWidth: CGFloat? = nil
    ) {
        if shouldReplace {
            backButtonTapped()
        }
        
        if let fixedWidth = fixedWidth {
            containerView.frame.size.width = fixedWidth
        }
        
        containerView.isHidden = false
        addedVC?.append(vc)
        addedTitles?.append(vcTitle)
        updateVCTitle()
        showBackButton()
        showOpenInNWButton()
        
        for vc in self.children {
            removeChildVC(child: vc)
        }
        
        self.addChildVC(child: vc, container: containerView)
        guard let threadVC = vc as? NewChatViewController else { return }
        
        threadVC.chatBottomView.messageFieldView.setupForThread()
    }
    
    func updateVCTitle() {
        let title = addedTitles?.last ?? ""
        headerView.setHeaderTitle(title)
    }
    
    func showBackButton() {
        if addedVC?.count ?? 0 > 1 {
            headerView.hideBackButton(hide: false)
        } else {
            headerView.hideBackButton(hide: true)
        }
    }
    
    func showOpenInNWButton() {
        if let last = addedVC?.last, let last {
            let buttonVisible = last.isKind(of: ThreadsListViewController.self) || last.isKind(of: NewChatViewController.self) || last.isKind(of: NewPodcastPlayerViewController.self)
            headerView.setOpenNWButtonVisible(visible: buttonVisible)
        } else {
            headerView.setOpenNWButtonVisible(visible: false)
        }
    }
}

extension DashboardDetailViewController: DetailHeaderViewDelegate {
    func backButtonTapped() {
        if let last = addedVC?.last, let last {
            self.removeChildVC(child: last)
            self.addedTitles?.removeLast()
            
            if let addedVC, addedVC.count > 1,
                let currentVC = addedVC[addedVC.count - 2] {
                self.addChildVC(child: currentVC, container: containerView)
                updateVCTitle()
            }
            
            var _ = self.addedVC?.removeLast()
            
            showBackButton()
            showOpenInNWButton()
        }
    }
    
    func closeButtonTapped() {
        closeButtonTapped(isOpeningPodcastVC: false)
    }
    
    func closeButtonTapped(
        isOpeningPodcastVC: Bool = false
    ) {
        guard let addedVC else { return }
        for vc in addedVC {
            if let vc {
                self.removeChildVC(child: vc)
            }
        }
        self.addedVC?.removeAll()
        self.addedTitles?.removeAll()
        dismissDelegate?.closeButtonTapped()
        
        if isOpeningPodcastVC {
            return
        }
        
        NotificationCenter.default.post(name: .onPodcastPlayerClosed, object: nil, userInfo: nil)
    }
    
    func openInNSTapped() {
        if let last = addedVC?.last, let last {
            var newVC: NSViewController? = nil
            var resizable = true
            
            if let vc = last as? ThreadsListViewController, let chatId = vc.chat?.id {
                newVC = ThreadsListViewController.instantiate(
                    chatId: chatId,
                    delegate: vc.delegate
                )
                resizable = false
                
            } else if let vc = last as? NewChatViewController {
                newVC = NewChatViewController.instantiate(
                    contactId: vc.contact?.id,
                    chatId: vc.chat?.id,
                    delegate: vc.delegate,
                    chatVCDelegate: nil,
                    threadUUID: vc.threadUUID
                )
            } else if let vc = last as? NewPodcastPlayerViewController, let delegate = vc.delegate {
                if let podcast = vc.podcast {
                    newVC = NewPodcastPlayerViewController.instantiate(
                        chat: podcast.chat,
                        podcast: podcast,
                        delegate: delegate,
                        deepLinkData: vc.deepLinkData
                    )
                }
            }
            
            if let newVC = newVC {
                closeButtonTapped(
                    isOpeningPodcastVC: newVC.isKind(of: NewPodcastPlayerViewController.self)
                )
                
                WindowsManager.sharedInstance.presentWindowForRightPanelVC(
                    vc: newVC,
                    identifier: self.addedTitles?.last ?? "generic-windows",
                    title: self.addedTitles?.last ?? "",
                    minWidth: 450,
                    resizable: resizable
                )
            }
        }
    }
}
