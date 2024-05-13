//
//  NewChatViewModel+MessageMenuActionsExtension.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 19/09/2023.
//  Copyright © 2023 Tomas Timinskas. All rights reserved.
//

import Foundation

extension NewChatViewModel {
    func shouldBoostMessage(message: TransactionMessage) {
        guard let params = TransactionMessage.getBoostMessageParams(
            contact: contact,
            chat: chat,
            replyingMessage: message
        ),
        let chat = chat else {
            return
        }
        
        let _ = SphinxOnionManager.sharedInstance.sendBoostReply(params: params, chat: chat)
    }
    
    func shouldResendMessage(message: TransactionMessage) {
        sendMessage(
            provisionalMessage: message,
            text: message.messageContent ?? "",
            isResend: true,
            completion: { (_, _) in }
        )
    }
    
    func shouldTogglePinState(
        message: TransactionMessage,
        pin: Bool,
        callback: @escaping (Bool) -> ()
    ) {
        guard let chat = self.chat else {
            return
        }
        
//        API.sharedInstance.pinChatMessage(
//            messageUUID: (pin ? message.uuid : "_"),
//            chatId: chat.id,
//            callback: { pinnedMessageUUID in
//                self.chat?.pinnedMessageUUID = pinnedMessageUUID
//                self.chat?.saveChat()
//                
//                callback(true)
//            },
//            errorCallback: {
//                callback(false)
//            }
//        )
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
