//
//  NewChatViewModel+SendMessageExtension.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 19/09/2023.
//  Copyright © 2023 Tomas Timinskas. All rights reserved.
//

import Cocoa

extension NewChatViewModel {
    func shouldSendGiphyMessage(
        text: String,
        type: Int,
        data: Data,
        completion: @escaping (Bool, String?) -> ()
    ) {
        chatDataSource?.setMediaDataForMessageWith(
            messageId: SphinxOnionManager.sharedInstance.uniqueIntHashFromString(stringInput: UUID().uuidString),
            mediaData: MessageTableCellState.MediaData(
                image: NSImage(data: data),
                data: data,
                failed: false
            )
        )
        
        shouldSendMessage(
            text: text,
            type: type,
            provisionalMessage: nil,
            completion: completion
        )
    }
    
    func shouldSendMessage(
        text: String,
        type: Int,
        provisionalMessage: TransactionMessage?,
        completion: @escaping (Bool, String?) -> ()
    ) {
        var messageText = text
        
        if messageText.isEmpty {
            return
        }
        
        if let podcastComment = podcastComment {
            messageText = podcastComment.getJsonString(withComment: text) ?? text
        }
        
        let (_, wrongAmount) = isWrongBotCommandAmount(text: messageText)
        
        if wrongAmount {
            completion(false, "Wrong Amount")
            return
        }
        guard let chat = chat else {
            completion(false, "Chat not found")
            return
        }
        
        let tuuid = threadUUID ?? replyingTo?.threadUUID ?? replyingTo?.uuid
        
        let (validMessage, errorMsg) = SphinxOnionManager.sharedInstance.sendMessage(
            to: contact,
            content: messageText,
            chat: chat,
            provisionalMessage: provisionalMessage,
            msgType: UInt8(type),
            threadUUID: tuuid,
            replyUUID: replyingTo?.uuid,
            forceIncludeTimezone: wasTimezoneNotSentRecently()
        )
        
        let message = validMessage?.makeProvisional(chat: self.chat)
        
        updateSnapshotWith(message: message)
        
        completion(validMessage != nil, errorMsg)
        
        if let message = validMessage {
            joinIfCallMessage(message: message)
        }
        
        resetReply()
    }
    
    func updateSnapshotWith(
        message: TransactionMessage?
    ) {
        guard let message = message else {
            return
        }
        
        chatDataSource?.updateSnapshotWith(message: message)
    }
    
    func deleteMessageWith(
        id: Int?
    ) {
        if let id = id {
            TransactionMessage.deleteMessageWith(id: id)
        }
    }

    func messageSent(
        message: TransactionMessage,
        chat: Chat? = nil,
        completion: @escaping (Bool, Chat?) -> ()
    ) {
        ChatTrackingHandler.shared.deleteOngoingMessage(with: chat?.id, threadUUID: threadUUID)
        
        joinIfCallMessage(message: message)
        showBoostErrorAlert(message: message)
        resetReply()
        
        completion(true, chat)
    }

    func joinIfCallMessage(
        message: TransactionMessage
    ) {
        if message.isCallMessageType() {
            if let link = message.messageContent {
                let linkUrl = VoIPRequestMessage.getFromString(link)?.link ?? link
                WindowsManager.sharedInstance.showCallWindow(
                    link: linkUrl,
                    shouldStartRecording: chat?.hasSecondBrainApp() == true || chat?.hasWebApp() == true,
                    tribeImage: (chat?.isPublicGroup() == true) ? (chat?.tribeInfo?.img ?? chat?.photoUrl) : nil
                )
            }
        }
    }
    
    func showBoostErrorAlert(
        message: TransactionMessage
    ) {
        if message.isMessageBoost() && message.isFailedOrMediaExpired() {
            AlertHelper.showAlert(title: "boost.error.title".localized, message: message.errorMessage ?? "generic.error.message".localized)
        }
    }

    func isWrongBotCommandAmount(
        text: String
    ) -> (Int, Bool) {
        let (botAmount, failureMessage) = GroupsManager.sharedInstance.calculateBotPrice(chat: chat, text: text)
        
        if let failureMessage = failureMessage {
            AlertHelper.showAlert(title: "generic.error.title".localized, message: failureMessage)
            return (botAmount, true)
        }
        
        return (botAmount, false)
    }
    
    func shouldSendTribePayment(
        amount: Int,
        message: String,
        messageUUID: String,
        callback: (() -> ())?
    ) {
//        guard let params = TransactionMessage.getTribePaymentParams(
//            chat: chat,
//            messageUUID: messageUUID,
//            amount: amount,
//            text: message
//        ) else {
//            callback?()
//            return
//        }
//        
//        sendMessage(provisionalMessage: nil, params: params, completion: { (_, _) in
//            callback?()
//        })
    }
    
    func sendCallMessage(link: String) {
        let voipRequestMessage = VoIPRequestMessage()
        voipRequestMessage.recurring = false
        voipRequestMessage.link = link
        voipRequestMessage.cron = ""
        
        let messageText = voipRequestMessage.getCallLinkMessage() ?? link
        
        self.shouldSendMessage(
            text: messageText,
            type: TransactionMessage.TransactionMessageType.call.rawValue,
            provisionalMessage: nil,
            completion: { _, _ in }
        )
    }
}
