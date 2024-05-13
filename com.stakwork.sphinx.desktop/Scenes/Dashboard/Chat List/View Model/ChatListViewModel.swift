//
//  ChatListViewModel.swift
//  com.stakwork.sphinx.desktop
//
//  Created by Tomas Timinskas on 14/05/2020.
//  Copyright © 2020 Sphinx. All rights reserved.
//

import Foundation
import SwiftyJSON

final class ChatListViewModel: NSObject {
    
    public static var restoreRunning = false
    
    public static func isRestoreRunning() -> Bool {
        return restoreRunning
    }
    
    func saveObjects(
        contacts: [JSON],
        chats: [JSON],
        subscriptions: [JSON],
        invites: [JSON]
    ) {
        UserContactsHelper.insertObjects(
            contacts: contacts,
            chats: chats,
            subscriptions: subscriptions,
            invites: invites
        )
    }
    
    func authenticateWithMemesServer() {
        AttachmentsManager.sharedInstance.runAuthentication()
    }
    
    var syncMessagesTask: DispatchWorkItem? = nil
    var syncMessagesDate = Date()
    var newMessagesChatIds = [Int]()
    
    func finishRestoring() {
        SignupHelper.completeSignup()
    }
}
