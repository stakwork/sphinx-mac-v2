//
//  NewChatViewModel+MessageMenuActionsExtension.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 19/09/2023.
//  Copyright © 2023 Tomas Timinskas. All rights reserved.
//

import Foundation
import SwiftyJSON

extension NewChatViewModel {
    func shouldBoostMessage(message: TransactionMessage) {
        guard let params = TransactionMessage.getBoostMessageParams(
            contact: contact,
            chat: chat,
            replyingMessage: message
        ), let chat = chat else {
            return
        }
        
        SphinxOnionManager.sharedInstance.sendBoostReply(
            params: params,
            chat: chat,
            completion: { _ in}
        )
    }
    
    func shouldResendMessage(message: TransactionMessage) {
        guard let chat = message.chat else{
            return
        }
        
        let _ = SphinxOnionManager.sharedInstance.sendMessage(
            to: message.chat?.getContact(),
            content: message.messageContent ?? "",
            chat: chat, provisionalMessage: message,
            threadUUID: message.threadUUID,
            replyUUID: message.replyUUID
        )
    }
    
    func shouldTogglePinState(
        message: TransactionMessage,
        pin: Bool,
        callback: @escaping (Bool) -> ()
    ) {
        guard let chat = self.chat,
              let pubkey = chat.ownerPubkey else 
        {
            return
        }
        
        let groupsManager = GroupsManager()
        
        guard let tribeInfo = chat.tribeInfo else {
            return
        }
        groupsManager.newGroupInfo = tribeInfo
        groupsManager.newGroupInfo.pin = pin ? message.uuid : nil
        
        let params = groupsManager.getNewGroupParams()
        
        let success = SphinxOnionManager.sharedInstance.updateTribe(
            params: params,
            pubkey: pubkey
        )
        
        if success {
            updateChat(
                chat: chat,
                withParams: params
            )
        }
        
        callback(success)
    }

    func updateChat(
        chat: Chat,
        withParams params: [String: AnyObject]
    ) {
        chat.tribeInfo = GroupsManager.sharedInstance.getTribesInfoFrom(json: JSON(params))
        chat.updateChatFromTribesInfo()
        chat.managedObjectContext?.saveContext()
    }
}

extension NewChatViewModel {
    func shouldDeleteMessage(message: TransactionMessage) {
        DelayPerformedHelper.performAfterDelay(seconds: 0.1, completion: {
            AlertHelper.showTwoOptionsAlert(
                title: "alert-confirm.delete-message-title".localized,
                message: "alert-confirm.delete-message-message".localized,
                confirm: {
                    self.deleteMessage(message)
                })
        })
    }
    
    private func deleteMessage(_ message: TransactionMessage) {
        if message.id < 0 {
            CoreDataManager.sharedManager.deleteObject(object: message)
            return
        }
        
        SphinxOnionManager.sharedInstance.sendDeleteRequest(message: message)
    }
}
