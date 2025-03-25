//
//  DashboardSplittedViewController.swift
//  com.stakwork.sphinx.desktop
//
//  Created by Tomas Timinskas on 15/05/2020.
//  Copyright © 2020 Sphinx. All rights reserved.
//

import Cocoa

protocol DashboardVCDelegate: AnyObject {
    func didClickOnChatRow(chatId: Int?, contactId: Int?)
    func shouldReloadChatRowWith(chatId: Int)
    func shouldShowRestoreModal(with progress: Int, label: String, buttonEnabled: Bool)
    func shouldHideRetoreModal()
    func shouldShowFullMediaFor(message: TransactionMessage)
    func shouldShowFullMediaFor(url: String)
    func shouldToggleLeftView(show: Bool?)
    func didSwitchToTab()
    func shouldResetContactView()
    func shouldResetTribeView()
}

class DashboardSplittedViewController: NSViewController {
    
    weak var delegate: DashboardVCDelegate?
    
    var chatListViewModel = ChatListViewModel()
    
}
