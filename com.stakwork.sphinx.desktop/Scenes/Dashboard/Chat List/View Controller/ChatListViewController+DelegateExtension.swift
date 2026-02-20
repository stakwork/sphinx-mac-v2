//
//  ChatListViewControllerExtension.swift
//  com.stakwork.sphinx.desktop
//
//  Created by Tomas Timinskas on 14/05/2020.
//  Copyright © 2020 Sphinx. All rights reserved.
//

import Cocoa
import CoreData

public let balanceDidChange = "balanceDidChange"

extension ChatListViewController {
    
    func configureHeaderAndBottomBar() {
        NSAppearance.current = view.effectiveAppearance
        
        bottomBar.addShadow(location: VerticalLocation.top, color: NSColor.black, opacity: 0.2, radius: 5.0)

        searchFieldContainer.wantsLayer = true
        searchFieldContainer.layer?.cornerRadius = searchFieldContainer.frame.height / 2
    }
    
    func resetSearchField() {
        searchField?.stringValue = ""
        
        NotificationCenter.default.post(
            name: NSControl.textDidChangeNotification,
            object: searchField
        )
        
        DelayPerformedHelper.performAfterDelay(seconds: 1.0, completion: {
            self.searchField?.isEnabled = true
        })
    }
}

extension ChatListViewController : ChildVCDelegate, ActionsDelegate {
    func handleReceiveClick() {
        let vc = CreateInvoiceViewController.instantiate(
            childVCDelegate: self,
            viewModel: PaymentViewModel(mode: .Request),
            delegate: self,
            mode: .Window
        )
        
        WindowsManager.sharedInstance.showOnCurrentWindow(
            with: "create.invoice".localized,
            identifier: "payment-window",
            contentVC: vc,
            height: 500
        )
    }
    
    func handleSentClick() {
        let vc = SendPaymentForInvoiceVC.instantiate()
        
        WindowsManager.sharedInstance.showOnCurrentWindow(
            with: "pay.invoice".localized,
            identifier: "send-payment-window",
            contentVC: vc,
            height: 447
        )
    }
    
    
    func handleInvoiceCreation(invoice:String, amount:Int){
        let vc = DisplayInvoiceVC.instantiate(
            qrCodeString: invoice,
            amount: amount
        )
        
        WindowsManager.sharedInstance.showOnCurrentWindow(
            with: "payment.request".localized,
            identifier: "show-invoice-window",
            contentVC: vc,
            hideDivider: true,
            hideBackButton: true,
            replacingVC: true,
            height: 766
        )
    }
    
    func shouldShowAttachmentsPopup() {}
    func didDismissView() {}
    func didCreateMessage() {}
    func didFailInvoiceOrPayment() {}
    func shouldCreateCall(mode: VideoCallHelper.CallMode) {}
    func shouldSendPaymentFor(paymentObject: PaymentViewModel.PaymentObject, callback: ((Bool) -> ())?) {}
    func shouldReloadMuteState() {}
    func shouldDimiss() {}
    func shouldGoForward(paymentViewModel: PaymentViewModel) {}
    func shouldGoBack(paymentViewModel: PaymentViewModel) {}
    func shouldSendPaymentFor(paymentObject: PaymentViewModel.PaymentObject) {}
}

extension ChatListViewController : NewChatListViewControllerDelegate {
    func shouldResetContactView() {
        delegate?.shouldResetContactView()
    }
    
    func didClickRowAt(
        chatId: Int?,
        contactId: Int?
    ) {
        contactChatsContainerViewController.updateSnapshot()
        tribeChatsContainerViewController.updateSnapshot()
        
        delegate?.didClickOnChatRow(
            chatId: chatId,
            contactId: contactId
        )
    }
}

extension ChatListViewController : NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        let _ = searchField?.resignFirstResponder()
        feedContainerViewController.toggleSearchFieldActive(false)
    }
    
    func controlTextDidChange(_ obj: Notification) {
        if (obj.object as? NSTextField) == searchField {
            let currentString = (searchField?.stringValue ?? "")
            searchClearButton.isHidden = currentString.isEmpty
            searchIcon.isHidden = !currentString.isEmpty
            
            if contactsService.selectedTab == .feed {
                feedContainerViewController.searchWith(searchQuery: currentString)
            } else if contactsService.selectedTab == .workspaces {
                workspacesContainerViewController.filterWorkspaces(term: currentString)
            } else {
                contactsService.updateChatListWith(term: currentString)
            }
        }
    }
}

extension ChatListViewController : NewContactChatDelegate {
    func shouldReloadContacts() {
//        updateBalanceAndCheckVersion()
    }
}

extension ChatListViewController: ChatsSegmentedControlDelegate {
    
    func segmentedControlDidSwitch(
        _ segmentedControl: ChatsSegmentedControl,
        to index: Int
    ) {
        if let tab = DashboardTab(rawValue: index) {
            resetFeedSearch(tab: tab)
            contactsService.selectedTab = tab
            setActiveTab(tab)
            
            // Apply existing search term to the newly active tab
            if tab == .workspaces, let currentSearch = searchField.stringValue, !currentSearch.isEmpty {
                workspacesContainerViewController.filterWorkspaces(term: currentSearch)
            }
        }
    }
    
    func resetFeedSearch(tab: DashboardTab) {
        let fromFeed = contactsService.selectedTab == .feed
        let toFeed = tab == .feed
        
        if (fromFeed || toFeed) && searchField.stringValue.isNotEmpty {
            searchField.stringValue = ""
            searchClearButton.isHidden = true
            searchIcon.isHidden = false
            contactsService.resetSearches()
        }
        
        if fromFeed {
            feedContainerViewController.resetSearch()
        }
    }
}

extension ChatListViewController: FeedListViewControllerDelegate {
    func didClickRowWith(contentFeedId: String?) {
        if let contentFeedId = contentFeedId, let contentFeed = ContentFeed.getFeedById(feedId: contentFeedId) {
            let podcast = PodcastFeed.convertFrom(contentFeed: contentFeed)
            
            let podcastPlayerVC = NewPodcastPlayerViewController.instantiate(
                chat: podcast.chat,
                podcast: podcast,
                delegate: nil
            )
            
            WindowsManager.sharedInstance.showVCOnRightPanelWindow(
                with: "Podcast",
                identifier: "podcast-window-\(contentFeedId)",
                contentVC: podcastPlayerVC,
                shouldReplace: false,
                panelFixedWidth: true
            )
        }
    }
    
    func didClick(item: FeedListViewController.DataSourceItem) {
        let existingFeedsFetchRequest: NSFetchRequest<ContentFeed> = ContentFeed
            .FetchRequests
            .matching(feedID: item.feedId)
        
        var fetchRequestResult: [ContentFeed] = []
        
        let managedObjectContext = CoreDataManager.sharedManager.persistentContainer.viewContext
        
        managedObjectContext.performAndWait {
            do {
                fetchRequestResult = try managedObjectContext.fetch(existingFeedsFetchRequest)
            } catch {
                print("Error fetching content feed: \(error)")
            }
        }
            
        if let existingFeed = fetchRequestResult.first {
            didClickRowWith(contentFeedId: existingFeed.feedID)
        } else {
            self.newMessageBubbleHelper.showLoadingWheel()
            
            ContentFeed.fetchContentFeed(
                at: item.feedUrl,
                chat: nil,
                searchResultDescription: item.feedDescription,
                searchResultImageUrl: item.imageUrl,
                persistingIn: managedObjectContext,
                then: { result in
                    
                    if case .success(let contentFeed) = result {
                        managedObjectContext.saveContext()
                        
                        let podcast = PodcastFeed.convertFrom(contentFeed: contentFeed)
                        
                        DataSyncManager.sharedInstance.saveFeedStatusFor(
                            feedId: contentFeed.feedID,
                            feedStatus: FeedStatus(
                                chatPubkey: "",
                                feedUrl: item.feedUrl,
                                feedId: contentFeed.feedID,
                                subscribed: true,
                                satsPerMinute: podcast.satsPerMinute ?? 0,
                                playerSpeed: Double(podcast.playerSpeed),
                                itemId: podcast.currentEpisodeId
                            )
                        )
                        
                        self.newMessageBubbleHelper.hideLoadingWheel()
                        
                        self.didClickRowWith(contentFeedId: contentFeed.feedID)
                    } else {
                        self.newMessageBubbleHelper.hideLoadingWheel()
                        
                        AlertHelper.showAlert(title: "generic.error.title".localized, message: "generic.error.message".localized)
                    }
            })
        }
    }
}

