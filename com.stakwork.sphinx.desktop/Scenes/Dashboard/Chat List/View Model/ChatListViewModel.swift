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
