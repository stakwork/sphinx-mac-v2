//
//  ChatTrackingHandler.swift
//  Sphinx
//
//  Created by Rashid Mustafa on 25/01/2024.
//  Copyright © 2024 Tomas Timinskas. All rights reserved.
//

import Foundation

@MainActor 
class ChatTrackingHandler {
    
    static let shared = ChatTrackingHandler()
    
    var replyableMessages: [Int: Int] = [:]
    var ongoingMessages : [String: String] = [:]
    var draftTimestamps: [String: Date] = [:]
    var ongoingAttachments: [String: [AttachmentPreview]] = [:]
    
    func deleteReplyableMessage(with chatId: Int?) {
        guard let chatId = chatId else { return }
        
        replyableMessages.removeValue(forKey: chatId)
    }
    
    func saveReplyableMessage(
        with messageId: Int,
        chatId: Int?
    ) {
        guard let chatId = chatId else { return }
        
        replyableMessages[chatId] = messageId
    }
    
    func getReplyableMessageFor(chatId: Int?) -> TransactionMessage? {
        guard let chatId = chatId else { return nil }
        
        if let messageId = replyableMessages[chatId], let message = TransactionMessage.getMessageWith(id: messageId) {
            return message
        }
        
        return nil
    }
    
    func deleteOngoingMessage(
        with chatId: Int?,
        threadUUID: String?
    ) {
        guard let key = getComposedKeyFor(chatId: chatId, threadUUID: threadUUID) else { return }
        
        ongoingMessages.removeValue(forKey: key)
        draftTimestamps.removeValue(forKey: key)
    }
    
    func saveOngoingMessage(
        with message: String,
        chatId: Int?,
        threadUUID: String?
    ) {
        guard let key = getComposedKeyFor(chatId: chatId, threadUUID: threadUUID) else { return }
        
        ongoingMessages[key] = message
        
        if message.isEmpty {
            draftTimestamps.removeValue(forKey: key)
        } else {
            draftTimestamps[key] = Date()
        }
    }
    
    func getDraftTimestampFor(
        chatId: Int?,
        threadUUID: String?
    ) -> Date? {
        guard let key = getComposedKeyFor(chatId: chatId, threadUUID: threadUUID) else { return nil }
        return draftTimestamps[key]
    }
    
    func getOngoingMessageFor(
        chatId: Int?,
        threadUUID: String?
    ) -> String? {
        guard let key = getComposedKeyFor(chatId: chatId, threadUUID: threadUUID) else { return nil }
        
        if let message = ongoingMessages[key] {
            return message
        }
        
        return nil
    }
    
    func saveOngoingAttachments(
        _ attachments: [AttachmentPreview],
        chatId: Int?,
        threadUUID: String?
    ) {
        guard let key = getComposedKeyFor(chatId: chatId, threadUUID: threadUUID) else { return }
        if attachments.isEmpty {
            ongoingAttachments.removeValue(forKey: key)
        } else {
            ongoingAttachments[key] = attachments
        }
    }

    func getOngoingAttachmentsFor(
        chatId: Int?,
        threadUUID: String?
    ) -> [AttachmentPreview]? {
        guard let key = getComposedKeyFor(chatId: chatId, threadUUID: threadUUID) else { return nil }
        return ongoingAttachments[key]
    }

    func deleteOngoingAttachments(
        with chatId: Int?,
        threadUUID: String?
    ) {
        guard let key = getComposedKeyFor(chatId: chatId, threadUUID: threadUUID) else { return }
        ongoingAttachments.removeValue(forKey: key)
    }

    func getComposedKeyFor(
        chatId: Int?,
        threadUUID: String?
    ) -> String? {
        guard let chatId = chatId else { return nil }
        
        var key = "\(chatId)"
        
        if let threadUUID = threadUUID {
            key = "\(key)-\(threadUUID)"
        }
        
        return key
    }
}
