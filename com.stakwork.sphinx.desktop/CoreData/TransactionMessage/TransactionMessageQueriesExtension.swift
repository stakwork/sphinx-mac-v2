//
//  TransactionMessageQueriesExtension.swift
//  com.stakwork.sphinx.desktop
//
//  Created by Tomas Timinskas on 11/05/2020.
//  Copyright © 2020 Sphinx. All rights reserved.
//

import Foundation
import CoreData

extension TransactionMessage {    
    static func getAll() -> [TransactionMessage] {
        let messages:[TransactionMessage] = CoreDataManager.sharedManager.getAllOfType(entityName: "TransactionMessage")
        return messages
    }
    
    static func getAllMesagesCount() -> Int {
        let messagesCount:Int = CoreDataManager.sharedManager.getObjectsCountOfTypeWith(entityName: "TransactionMessage")
        return messagesCount
    }
    
    static func getMessageWith(id: Int) -> TransactionMessage? {
        let message: TransactionMessage? = CoreDataManager.sharedManager.getObjectOfTypeWith(id: id, entityName: "TransactionMessage")
        return message
    }
    
    static func getMessageWith(
        tag: String,
        context: NSManagedObjectContext? = nil
    ) -> TransactionMessage? {
        let predicate = NSPredicate(format: "tag == %@", tag)
        let sortDescriptors = [NSSortDescriptor(key: "id", ascending: false)]
        
        let message: TransactionMessage? = CoreDataManager.sharedManager.getObjectOfTypeWith(
            predicate: predicate,
            sortDescriptors: sortDescriptors,
            entityName: "TransactionMessage",
            managedContext: context
        )
        
        return message
    }
    
    static func getAllPayment() -> [TransactionMessage] {
        let predicate = NSPredicate(format: "type == %d", TransactionMessage.TransactionMessageType.payment.rawValue)
        let sortDescriptors = [NSSortDescriptor(key: "id", ascending: false)]
        
        let messages: [TransactionMessage] = CoreDataManager.sharedManager.getObjectsOfTypeWith(
            predicate: predicate,
            sortDescriptors: sortDescriptors,
            entityName: "TransactionMessage"
        )
        
        return messages
    }
    
    static func getAllNotConfirmed() -> [TransactionMessage] {
        let predicate = NSPredicate(
            format: "senderId == %d AND (status == %d OR status == %d)",
            UserData.sharedInstance.getUserId(),
            TransactionMessage.TransactionMessageStatus.confirmed.rawValue,
            TransactionMessage.TransactionMessageStatus.pending.rawValue
        )
        let sortDescriptors = [NSSortDescriptor(key: "id", ascending: false)]
        
        let messages: [TransactionMessage] = CoreDataManager.sharedManager.getObjectsOfTypeWith(
            predicate: predicate,
            sortDescriptors: sortDescriptors,
            entityName: "TransactionMessage",
            fetchLimit: 1000
        )
        
        return messages
    }
    
    static func getAllInvoices() -> [TransactionMessage] {
        let predicate = NSPredicate(format: "type == %d", TransactionMessage.TransactionMessageType.invoice.rawValue)
        let sortDescriptors = [NSSortDescriptor(key: "id", ascending: false)]
        
        let messages: [TransactionMessage] = CoreDataManager.sharedManager.getObjectsOfTypeWith(
            predicate: predicate,
            sortDescriptors: sortDescriptors,
            entityName: "TransactionMessage"
        )
        
        return messages
    }
    
    static func getAllStillEncrypted() -> [TransactionMessage] {
        let predicate = NSPredicate(format: "type == %d AND mediaToken != nil AND mediaKey == nil", TransactionMessage.TransactionMessageType.attachment.rawValue)
        
        let sortDescriptors = [NSSortDescriptor(key: "id", ascending: false)]
        
        let messages: [TransactionMessage] = CoreDataManager.sharedManager.getObjectsOfTypeWith(
            predicate: predicate,
            sortDescriptors: sortDescriptors,
            entityName: "TransactionMessage"
        )
        
        return messages
    }
    
    static func getAttachmentsBefore(
        date: Date,
        managedContext: NSManagedObjectContext? = nil
    ) -> [TransactionMessage] {
        let predicate = NSPredicate(
            format: "type == %d AND mediaToken != nil AND createdAt < %@",
            TransactionMessage.TransactionMessageType.attachment.rawValue,
            date as NSDate
        )
        
        let sortDescriptors = [NSSortDescriptor(key: "id", ascending: false)]
        
        let messages: [TransactionMessage] = CoreDataManager.sharedManager.getObjectsOfTypeWith(
            predicate: predicate,
            sortDescriptors: sortDescriptors,
            entityName: "TransactionMessage",
            managedContext: managedContext
        )
        
        return messages
    }
    
    static func getPurchaseAcceptWith(mediaToken: String) -> TransactionMessage? {
        // Corrected the format specifier for the integer type field
        let predicate = NSPredicate(format: "type == %d AND mediaToken == %@", TransactionMessage.TransactionMessageType.purchaseAccept.rawValue, mediaToken)
        let sortDescriptors = [NSSortDescriptor(key: "id", ascending: false)]
        
        let message: TransactionMessage? = CoreDataManager.sharedManager.getObjectOfTypeWith(
            predicate: predicate,
            sortDescriptors: sortDescriptors,
            entityName: "TransactionMessage"
        )
        
        return message
    }

    
    static func getAttachmentMessageWith(muid: String, managedContext:NSManagedObjectContext?=nil) -> TransactionMessage? {
        let predicate = NSPredicate(
            format: "type == %d AND muid == %@",
            TransactionMessage.TransactionMessageType.attachment.rawValue,
            muid
        )
        let sortDescriptors = [NSSortDescriptor(key: "id", ascending: false)]
        
        let message: TransactionMessage? = CoreDataManager.sharedManager.getObjectOfTypeWith(
            predicate: predicate,
            sortDescriptors: sortDescriptors,
            entityName: "TransactionMessage",
            managedContext: managedContext
        )
        
        return message
    }
    
    static func getMessageEncryptedMessageWith(mediaToken:String) -> TransactionMessage?{
        let predicate = NSPredicate(format: "mediaToken == %@", mediaToken)
        let sortDescriptors = [NSSortDescriptor(key: "id", ascending: false)]
        
        let message: TransactionMessage? = CoreDataManager.sharedManager.getObjectOfTypeWith(
            predicate: predicate,
            sortDescriptors: sortDescriptors,
            entityName: "TransactionMessage"
        )
        
        return message
    }
    
    static func getMessageWith(uuid: String) -> TransactionMessage? {
        let predicate = NSPredicate(format: "uuid == %@", uuid)
        let sortDescriptors = [NSSortDescriptor(key: "id", ascending: false)]
        let message: TransactionMessage? = CoreDataManager.sharedManager.getObjectOfTypeWith(predicate: predicate, sortDescriptors: sortDescriptors, entityName: "TransactionMessage")
        
        return message
    }
    
    static func getMessagesWith(uuids: [String]) -> [TransactionMessage] {
        let predicate = NSPredicate(format: "uuid IN %@", uuids)
        let sortDescriptors = [NSSortDescriptor(key: "id", ascending: false)]
        
        let messages: [TransactionMessage] = CoreDataManager.sharedManager.getObjectsOfTypeWith(
            predicate: predicate,
            sortDescriptors: sortDescriptors,
            entityName: "TransactionMessage"
        )
        
        return messages
    }
    
    static func getMessagesWith(
        tags: [String],
        context: NSManagedObjectContext? = nil
    ) -> [TransactionMessage] {
        let predicate = NSPredicate(format: "tag IN %@", tags)
        let sortDescriptors = [NSSortDescriptor(key: "id", ascending: false)]
        
        let messages: [TransactionMessage] = CoreDataManager.sharedManager.getObjectsOfTypeWith(
            predicate: predicate,
            sortDescriptors: sortDescriptors,
            entityName: "TransactionMessage",
            managedContext: context
        )
        
        return messages
    }
    
    static func getMessagesWith(ids: [Int]) -> [TransactionMessage] {
        let predicate = NSPredicate(format: "id IN %@", ids)
        let sortDescriptors = [NSSortDescriptor(key: "id", ascending: false)]
        
        let messages: [TransactionMessage] = CoreDataManager.sharedManager.getObjectsOfTypeWith(
            predicate: predicate,
            sortDescriptors: sortDescriptors,
            entityName: "TransactionMessage"
        )
        
        return messages
    }
    
    static func getAllMessagesFor(
        chat: Chat,
        limit: Int? = nil,
        context: NSManagedObjectContext? = nil,
        forceAllMsgs: Bool = false
    ) -> [TransactionMessage] {
        
        let fetchRequest = getChatMessagesFetchRequest(
            for: chat,
            with: limit,
            forceAllMsgs: forceAllMsgs
        )
        
        var messages: [TransactionMessage] = []
        let context = context ?? CoreDataManager.sharedManager.persistentContainer.viewContext
        
        context.performAndWait {
            do {
                try messages = context.fetch(fetchRequest)
            } catch let error as NSError {
                print("Error: " + error.localizedDescription)
            }
        }
        
        return messages
    }
    
    static func getMaxIndex(
        context: NSManagedObjectContext? = nil
    ) -> Int? {
        let context = context ?? CoreDataManager.sharedManager.persistentContainer.viewContext
        let fetchRequest: NSFetchRequest<TransactionMessage> = TransactionMessage.fetchRequest()
        ///Not consider group join since those messages could be restored during contacts/tribes restore
        fetchRequest.predicate = NSPredicate(format: "id >= 0")
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "id", ascending: false)]
        fetchRequest.fetchLimit = 1

        do {
            let results = try context.fetch(fetchRequest)
            return results.first?.id
        } catch let error as NSError {
            print("Error fetching message with max ID: \(error), \(error.userInfo)")
            return nil
        }
    }
    
    static func getMaxIndexFor(chat: Chat) -> Int? {
        let context = CoreDataManager.sharedManager.persistentContainer.viewContext
        let fetchRequest: NSFetchRequest<TransactionMessage> = TransactionMessage.fetchRequest()
        ///Not consider group join since those messages could be restored during contacts/tribes restore
        fetchRequest.predicate = NSPredicate(
            format: "NOT (status IN %@) AND chat = %@",
            [
                TransactionMessage.TransactionMessageStatus.failed.rawValue,
                TransactionMessage.TransactionMessageStatus.pending.rawValue
            ],
            chat
        )
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "id", ascending: false)]
        fetchRequest.fetchLimit = 1

        do {
            let results = try context.fetch(fetchRequest)
            return results.first?.id
        } catch let error as NSError {
            print("Error fetching message with max ID: \(error), \(error.userInfo)")
            return nil
        }
    }
    
    static func getMessageDeletionRequests() -> [TransactionMessage] {
        let context = CoreDataManager.sharedManager.persistentContainer.viewContext
        let fetchRequest: NSFetchRequest<TransactionMessage> = TransactionMessage.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "type == %d", TransactionMessage.TransactionMessageType.delete.rawValue) // Replace '17' with the actual type if it differs.
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "id", ascending: true)] // Sorting by 'id', adjust as needed.

        do {
            let results = try context.fetch(fetchRequest)
            return results
        } catch let error as NSError {
            print("Error fetching messages of type 17: \(error), \(error.userInfo)")
            return []
        }
    }
    
    static func getPredicate(
        chat: Chat,
        threadUUID: String?,
        typesToExclude: [Int],
        pinnedMessageId: Int? = nil
    ) -> NSPredicate {
        if let tuid = threadUUID {
            return NSPredicate(
                format: "chat == %@ AND (NOT (type IN %@) || (type == %d && replyUUID = nil)) AND threadUUID == %@",
                chat,
                typesToExclude,
                TransactionMessageType.boost.rawValue,
                tuid,
                tuid
            )
        } else {
            if let pinnedMessageId = pinnedMessageId {
                return NSPredicate(
                    format: "chat == %@ AND id >= %d AND (NOT (type IN %@) || (type == %d && replyUUID = nil))",
                    chat,
                    pinnedMessageId - 200,
                    typesToExclude,
                    TransactionMessageType.boost.rawValue
                )
            } else {
                return NSPredicate(
                    format: "chat == %@ AND (NOT (type IN %@) || (type == %d && replyUUID = nil))",
                    chat,
                    typesToExclude,
                    TransactionMessageType.boost.rawValue
                )
            }
        }
    }
    
    static func getChatMessagesFetchRequest(
        for chat: Chat,
        threadUUID: String? = nil,
        with limit: Int? = nil,
        pinnedMessageId: Int? = nil,
        forceAllMsgs: Bool = false
    ) -> NSFetchRequest<TransactionMessage> {
        
        var typesToExclude = typesToExcludeFromChat
        typesToExclude.append(TransactionMessageType.boost.rawValue)
        
//        if chat.isMyPublicGroup() {
//            typesToExclude.append(TransactionMessageType.memberApprove.rawValue)
//            typesToExclude.append(TransactionMessageType.memberReject.rawValue)
//        }

        if forceAllMsgs {
            typesToExclude = []
        }
        
        let predicate = TransactionMessage.getPredicate(
            chat: chat,
            threadUUID: threadUUID,
            typesToExclude: typesToExclude,
            pinnedMessageId: pinnedMessageId
        )
        
        let sortDescriptors = [
            NSSortDescriptor(key: "date", ascending: false),
            NSSortDescriptor(key: "id", ascending: false)
        ]
        
        let fetchRequest = NSFetchRequest<TransactionMessage>(entityName: "TransactionMessage")
        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = sortDescriptors
        
        if let limit = limit, pinnedMessageId == nil {
            fetchRequest.fetchLimit = limit
        }
        
        return fetchRequest
    }
    
    ///This method returns fetch request for:
    ///Boost
    ///Puchase items
    ///Member requests responses if you are the admin
    static func getSecondaryMessagesFetchRequestOn(
        chat: Chat
    ) -> NSFetchRequest<TransactionMessage> {
        
        var types = [
            TransactionMessageType.boost.rawValue,
            TransactionMessageType.purchase.rawValue,
            TransactionMessageType.purchaseAccept.rawValue,
            TransactionMessageType.purchaseDeny.rawValue,
        ]
        
        if chat.isMyPublicGroup() {
            types = [
                TransactionMessageType.boost.rawValue,
                TransactionMessageType.purchase.rawValue,
                TransactionMessageType.purchaseAccept.rawValue,
                TransactionMessageType.purchaseDeny.rawValue,
                TransactionMessageType.memberReject.rawValue,
                TransactionMessageType.memberApprove.rawValue,
            ]
        }
        
        let predicate = NSPredicate(
            format: "chat == %@ AND type IN %@",
            chat,
            types
        )
        
        let sortDescriptors = [
            NSSortDescriptor(key: "date", ascending: false),
            NSSortDescriptor(key: "id", ascending: false)
        ]
        
        let fetchRequest = NSFetchRequest<TransactionMessage>(entityName: "TransactionMessage")
        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = sortDescriptors
        
        return fetchRequest
    }
    
    static func getThreadsFetchRequestOn(
        chat: Chat
    ) -> NSFetchRequest<TransactionMessage> {
        
        let predicate = NSPredicate(
            format: "chat == %@ AND threadUUID != nil",
            chat
        )
        
        let sortDescriptors = [
            NSSortDescriptor(key: "id", ascending: true)
        ]
        
        let fetchRequest = NSFetchRequest<TransactionMessage>(entityName: "TransactionMessage")
        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = sortDescriptors
        
        return fetchRequest
    }
    
    static func getAllMessagesCountFor(chat: Chat) -> Int {
        return CoreDataManager.sharedManager.getObjectsCountOfTypeWith(predicate: NSPredicate(format: "chat == %@ AND NOT (type IN %@)", chat, typesToExcludeFromChat), entityName: "TransactionMessage")
    }
    
    static func getInvoicePaymentWith(paymentHash: String) -> TransactionMessage? {
        let predicate = NSPredicate(format: "type == %d AND paymentHash == %@", TransactionMessageType.payment.rawValue, paymentHash)
        let sortDescriptors = [NSSortDescriptor(key: "id", ascending: false)]
        let invoice: TransactionMessage? = CoreDataManager.sharedManager.getObjectOfTypeWith(predicate: predicate, sortDescriptors: sortDescriptors, entityName: "TransactionMessage")
        
        return invoice
    }
    
    static func getInvoiceWith(paymentHash: String) -> TransactionMessage? {
        let predicate = NSPredicate(format: "type == %d AND paymentHash == %@", TransactionMessageType.invoice.rawValue, paymentHash)
        let sortDescriptors = [NSSortDescriptor(key: "id", ascending: false)]
        let invoice: TransactionMessage? = CoreDataManager.sharedManager.getObjectOfTypeWith(predicate: predicate, sortDescriptors: sortDescriptors, entityName: "TransactionMessage")
        
        return invoice
    }
    
    static func getInvoiceWith(paymentRequestString: String) -> TransactionMessage? {
        let predicate = NSPredicate(format: "type == %d AND invoice == %@", TransactionMessageType.invoice.rawValue, paymentRequestString)
        let sortDescriptors = [NSSortDescriptor(key: "id", ascending: false)]
        let invoice: TransactionMessage? = CoreDataManager.sharedManager.getObjectOfTypeWith(predicate: predicate, sortDescriptors: sortDescriptors, entityName: "TransactionMessage")
        
        return invoice
    }
    
    static func getMessagesFor(userId: Int, contactId: Int) -> [TransactionMessage] {
        let predicate = NSPredicate(format: "((senderId == %d AND receiverId == %d) OR (senderId == %d AND receiverId == %d)) AND id >= 0 AND NOT (type IN %@)", contactId, userId, userId, contactId, typesToExcludeFromChat)
        let sortDescriptors = [NSSortDescriptor(key: "id", ascending: false)]
        let messages: [TransactionMessage] = CoreDataManager.sharedManager.getObjectsOfTypeWith(predicate: predicate, sortDescriptors: sortDescriptors, entityName: "TransactionMessage")
        
        return messages
    }
    
        static func getLastGroupRequestFor(senderAlias: String, in chat: Chat) -> TransactionMessage? {
        let predicate = NSPredicate(format: "senderAlias == %@ AND chat == %@ AND type == %d", senderAlias, chat, TransactionMessageType.memberRequest.rawValue)
        let sortDescriptors = [NSSortDescriptor(key: "id", ascending: false)]
        let messages: [TransactionMessage] = CoreDataManager.sharedManager.getObjectsOfTypeWith(predicate: predicate, sortDescriptors: sortDescriptors, entityName: "TransactionMessage", fetchLimit: 1)
        
        return messages.first
    }
    
    static func getReceivedUnseenMessagesCount(
        context: NSManagedObjectContext? = nil
    ) -> Int {
        let userId = UserData.sharedInstance.getUserId(context: context)

        let predicate = NSPredicate(
            format: "(senderId != %d || type == %d) AND NOT (type IN %@) AND seen == %@ AND chat != nil AND id >= 0 AND chat.seen == %@ AND (chat.notify == %d OR (chat.notify == %d AND push == %@))",
            userId,
            TransactionMessage.TransactionMessageType.groupJoin.rawValue,
            [
                TransactionMessage.TransactionMessageType.unknown.rawValue,
                TransactionMessage.TransactionMessageType.contactKey.rawValue,
                TransactionMessage.TransactionMessageType.contactKeyConfirmation.rawValue
            ],
            NSNumber(booleanLiteral: false),
            NSNumber(booleanLiteral: false),
            Chat.NotificationLevel.SeeAll.rawValue,
            Chat.NotificationLevel.OnlyMentions.rawValue,
            NSNumber(booleanLiteral: true)
        )

        let messagesCount: Int = CoreDataManager.sharedManager.getObjectsCountOfTypeWith(
            predicate: predicate,
            entityName: "TransactionMessage",
            context: context
        )

        return messagesCount
    }
    
    static func getRecentGiphyMessages() -> [TransactionMessage] {
        let userId = UserData.sharedInstance.getUserId()
        let messageType = TransactionMessageType.message.rawValue
        let predicate = NSPredicate(format: "(senderId == %d) AND (type == %d) AND (messageContent BEGINSWITH[c] %@)", userId, messageType, "giphy::")
        let sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        let messages: [TransactionMessage] = CoreDataManager.sharedManager.getObjectsOfTypeWith(predicate: predicate, sortDescriptors: sortDescriptors, entityName: "TransactionMessage", fetchLimit: 50)

        return messages
    }
    
    static func getPaymentsFor(feedId: String) -> [TransactionMessage] {
        let feedIDString1 = "{\"feedID\":\"\(feedId)"
        let feedIDString2 = "{\"feedID\":\(feedId)"
        
        let predicate = NSPredicate(
            format: "chat == nil && (messageContent BEGINSWITH[c] %@ OR messageContent BEGINSWITH[c] %@)",
            feedIDString1,
            feedIDString2
        )
        
        let sortDescriptors = [NSSortDescriptor(key: "id", ascending: false)]
        let payments: [TransactionMessage] = CoreDataManager.sharedManager.getObjectsOfTypeWith(
            predicate: predicate,
            sortDescriptors: sortDescriptors,
            entityName: "TransactionMessage"
        )
        
        return payments
    }
    
    static func getLiveMessagesFor(chat: Chat, episodeId: String) -> [TransactionMessage] {
        let episodeString = "\"itemID\":\(episodeId)"
        let episodeString2 = "\"itemID\" : \(episodeId)"
        let predicate = NSPredicate(format: "chat == %@ && ((type == %d && (messageContent BEGINSWITH[c] %@ OR messageContent BEGINSWITH[c] %@)) || (type == %d && replyUUID == nil)) && (messageContent CONTAINS[c] %@ || messageContent CONTAINS[c] %@)", chat, TransactionMessageType.message.rawValue, PodcastFeed.kClipPrefix, PodcastFeed.kBoostPrefix, TransactionMessageType.boost.rawValue, episodeString, episodeString2)
        let sortDescriptors = [NSSortDescriptor(key: "id", ascending: false)]
        let boostAndClips: [TransactionMessage] = CoreDataManager.sharedManager.getObjectsOfTypeWith(predicate: predicate, sortDescriptors: sortDescriptors, entityName: "TransactionMessage")
        
        return boostAndClips
    }
    
    static func getReactionsOn(chat: Chat, for messages: [String]) -> [TransactionMessage] {
        let boostType = TransactionMessageType.boost.rawValue
        let predicate = NSPredicate(format: "chat == %@ AND type == %d AND replyUUID != nil AND (replyUUID IN %@)", chat, boostType, messages)
        let sortDescriptors = [NSSortDescriptor(key: "id", ascending: false)]
        let reactions: [TransactionMessage] = CoreDataManager.sharedManager.getObjectsOfTypeWith(predicate: predicate, sortDescriptors: sortDescriptors, entityName: "TransactionMessage")
        
        return reactions
    }
    
    static func getBoostMessagesFor(
        _ messages: [String],
        on chat: Chat
    ) -> [TransactionMessage] {
        let boostType = TransactionMessageType.boost.rawValue
        let failedStatus = TransactionMessage.TransactionMessageStatus.failed.rawValue
        
        let predicate = NSPredicate(
            format: "chat == %@ AND type == %d AND replyUUID != nil AND (replyUUID IN %@) AND status != %d",
            chat,
            boostType,
            messages,
            failedStatus
        )
        let sortDescriptors = [NSSortDescriptor(key: "id", ascending: false)]
        let reactions: [TransactionMessage] = CoreDataManager.sharedManager.getObjectsOfTypeWith(predicate: predicate, sortDescriptors: sortDescriptors, entityName: "TransactionMessage")
        
        return reactions
    }
    
    static func getMemberRequestsResponsesFor(
        _ messages: [String],
        on chat: Chat
    ) -> [TransactionMessage] {
        let types = [
            TransactionMessageType.memberReject.rawValue,
            TransactionMessageType.memberApprove.rawValue
        ]
        
        let failedStatus = TransactionMessage.TransactionMessageStatus.failed.rawValue

        let predicate = NSPredicate(
            format: "chat == %@ AND type IN %@ AND replyUUID IN %@",
            chat,
            types,
            messages
        )
        
        let sortDescriptors = [NSSortDescriptor(key: "id", ascending: false)]
        
        let reactions: [TransactionMessage] = CoreDataManager.sharedManager.getObjectsOfTypeWith(
            predicate: predicate,
            sortDescriptors: sortDescriptors,
            entityName: "TransactionMessage"
        )
        
        return reactions
    }
    
    static func getThreadMessagesFor(
        _ messages: [String],
        on chat: Chat
    ) -> [TransactionMessage] {
        let boostType = TransactionMessageType.boost.rawValue
        
        let deletedStatus = TransactionMessage.TransactionMessageStatus.deleted.rawValue

        let predicate = NSPredicate(
            format: "chat == %@ AND type != %d AND (threadUUID != nil AND (threadUUID IN %@)) AND status != %d AND id > -1",
            chat,
            boostType,
            messages,
            deletedStatus
        )
        
        let sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
        
        let threadMessages: [TransactionMessage] = CoreDataManager.sharedManager.getObjectsOfTypeWith(
            predicate: predicate,
            sortDescriptors: sortDescriptors,
            entityName: "TransactionMessage"
        )
        
        return threadMessages
    }
    
    static func getOriginalMessagesFor(
        _ threadMessages: [String],
        on chat: Chat
    ) -> [TransactionMessage] {
        let deletedStatus = TransactionMessage.TransactionMessageStatus.deleted.rawValue
        let predicate = NSPredicate(format: "chat == %@ AND uuid != nil AND (uuid IN %@) AND status != %d", chat, threadMessages, deletedStatus)
        let sortDescriptors = [NSSortDescriptor(key: "id", ascending: false)]
        let reactions: [TransactionMessage] = CoreDataManager.sharedManager.getObjectsOfTypeWith(predicate: predicate, sortDescriptors: sortDescriptors, entityName: "TransactionMessage")
        
        return reactions
    }
    
    static func getPurchaseItemsFor(
        _ muids: [String],
        on chat: Chat
    ) -> [TransactionMessage] {

        let attachmentType = TransactionMessageType.attachment.rawValue
        
        let predicate = NSPredicate(
            format: "chat == %@ AND (muid IN %@ || originalMuid IN %@) AND type != %d",
            chat,
            muids,
            muids,
            attachmentType
        )
        let sortDescriptors = [NSSortDescriptor(key: "id", ascending: true)]
        
        let messages: [TransactionMessage] = CoreDataManager.sharedManager.getObjectsOfTypeWith(
            predicate: predicate,
            sortDescriptors: sortDescriptors,
            entityName: "TransactionMessage"
        )
        
        return messages
    }
    
    static func getMessagePreviousTo(
        messageId: Int,
        on chat: Chat
    ) -> TransactionMessage? {
        
        var typesToExclude = typesToExcludeFromChat
        typesToExclude.append(TransactionMessageType.boost.rawValue)
        
        let predicate = NSPredicate(
            format: "(chat == %@ AND (NOT (type IN %@) || (type == %d && replyUUID = nil))) AND id < %d",
            chat,
            typesToExclude,
            TransactionMessageType.boost.rawValue,
            messageId
        )
        
        let sortDescriptors = [
            NSSortDescriptor(key: "date", ascending: false),
            NSSortDescriptor(key: "id", ascending: false)
        ]
        
        let message: TransactionMessage? = CoreDataManager.sharedManager.getObjectOfTypeWith(
            predicate: predicate,
            sortDescriptors: sortDescriptors,
            entityName: "TransactionMessage"
        )
        
        return message
    }
    
    static func fetchTransactionMessagesForHistory() -> [TransactionMessage] {
        let context = CoreDataManager.sharedManager.persistentContainer.viewContext
        
        // Predicate to get transaction messages with a positive amount and not of type 'invoice'
        let predicate = NSPredicate(
            format: "amount > 0 AND type != %d AND (senderId == 0 OR receiverId == 0)",
            TransactionMessage.TransactionMessageType.invoice.rawValue
        )
        
        // Sort descriptors to order by date in descending order
        let sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        
        let fetchRequest = NSFetchRequest<TransactionMessage>(entityName: "TransactionMessage")
        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = sortDescriptors
        
        do {
            let fetchedMessages = try context.fetch(fetchRequest)
            return fetchedMessages
        } catch {
            print("Error fetching transaction messages for history: \(error)")
            return []
        }
    }
    
    static func fetchTransactionMessagesForHistoryWith(
        msgIndexes: [Int],
        msgPmtHashes: [String]
    ) -> [TransactionMessage] {
        let context = CoreDataManager.sharedManager.persistentContainer.viewContext
        let predicate = NSPredicate(format: "id IN %@ OR paymentHash IN %@", msgIndexes, msgPmtHashes)
        
        // Sort descriptors to order by date in descending order
        let sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        
        let fetchRequest = NSFetchRequest<TransactionMessage>(entityName: "TransactionMessage")
        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = sortDescriptors
        
        do {
            let fetchedMessages = try context.fetch(fetchRequest)
            return fetchedMessages
        } catch {
            print("Error fetching transaction messages for history: \(error)")
            return []
        }
    }
    
    static func getTimezonesByAlias(
        for senderAliases: [String],
        in chat: Chat,
        context: NSManagedObjectContext? = nil
    ) -> [String: String] {
        let context = context ?? CoreDataManager.sharedManager.persistentContainer.viewContext

        let predicate = NSPredicate(
            format: "chat == %@ && senderAlias IN %@ AND remoteTimezoneIdentifier != nil",
            chat,
            senderAliases
        )

        // Sort by senderAlias and then by date (descending)
        let sortDescriptors = [
            NSSortDescriptor(key: "date", ascending: false)
        ]

        let messages: [TransactionMessage] = CoreDataManager.sharedManager.getObjectsOfTypeWith(
            predicate: predicate,
            sortDescriptors: sortDescriptors,
            entityName: "TransactionMessage",
            managedContext: context
        )

        var groupedMessages: [String: String] = [:]

        for message in messages {
            if let sender = message.senderAlias, sender.isNotEmpty {
                if groupedMessages[sender] == nil {
                    groupedMessages[sender] = message.remoteTimezoneIdentifier
                }
            }
        }
        return groupedMessages
    }
}
