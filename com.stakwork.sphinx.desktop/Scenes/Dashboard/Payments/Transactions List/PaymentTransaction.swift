//
//  PaymentTransaction.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 22/11/2023.
//  Copyright © 2023 Tomas Timinskas. All rights reserved.
//

import Foundation
import SwiftyJSON
import ObjectMapper

class PaymentTransaction {
    
    var type : Int?
    var amount : Int?
    var date : Date?
    var senderId : Int?
    var receiverId : Int?
    var chatId : Int?
    var originalMessageUUID : String?
    var paymentRequest : String?
    var paymentHash : String?
    var errorMessage : String?
    var content : String?
    
    var expanded: Bool = false
    
    public enum TransactionDirection: Int {
        case Incoming
        case Outgoing
    }
    
    init(
        fromTransactionMessage transactionMessage: TransactionMessage,
        ts: Int64? = nil
    ) {
        // Initialize properties using values from `TransactionMessage`
        self.type = transactionMessage.type
        self.amount = transactionMessage.amount?.intValue
        self.senderId = transactionMessage.senderId
        self.receiverId = transactionMessage.receiverId
        self.chatId = transactionMessage.chat?.id
        self.originalMessageUUID = transactionMessage.uuid
        self.paymentRequest = transactionMessage.invoice
        self.paymentHash = transactionMessage.paymentHash
        self.errorMessage = transactionMessage.errorMessage
        self.content = transactionMessage.messageContent?.replacingOccurrences(of: "+", with: " ").removingPercentEncoding
        
        if let ts = ts {
            self.date = Date(timeIntervalSince1970: TimeInterval(ts) / 1000)
        } else {
            self.date = transactionMessage.date ?? Date()
        }
    }
    
    init(fromFetchedParams fetchedParams: PaymentTransactionFromServer) {
        // Initialize properties using values from `PaymentTransactionFromServer`
        self.type = nil
        self.amount = (fetchedParams.amt_msat ?? 0) / 1000
        
        if let ts = fetchedParams.ts {
            self.date = Date(timeIntervalSince1970: TimeInterval(ts) / 1000)
        } else {
            self.date = Date()
        }
        
        let isIncoming = fetchedParams.msg_idx != nil //only incoming payments have an index
        
        self.paymentHash = fetchedParams.rhash
        self.senderId = (isIncoming) ? -1 : 0
        self.receiverId = (isIncoming) ? 0 : -1
        self.paymentRequest = "unknown"
        self.errorMessage = fetchedParams.error
    }
    
    func getDirection() -> TransactionDirection {
        if senderId == 0 && receiverId == 0 {
            return TransactionDirection.Incoming
        }
        
        let userId = UserData.sharedInstance.getUserId()
        
        if let senderId = senderId {
            if senderId == userId {
                return TransactionDirection.Outgoing
            }
        }
        return TransactionDirection.Incoming
    }
    
    func isIncoming() -> Bool {
        return getDirection() == TransactionDirection.Incoming
    }
    
    func isFailed() -> Bool {
        return !((errorMessage ?? "").isEmpty)
    }
    
    func isBountyPayment() -> Bool {
        return !((content ?? "").isEmpty) && senderId == 0 && receiverId == 0
    }
    
    func getDate() -> Date {
        return date ?? Date()
    }
    
    func getUsers() -> String? {
        var chat : Chat? = nil
        
        if let chatId = self.chatId, let foundChat = Chat.getChatWith(id: chatId) {
            chat = foundChat
        }
        
        guard let _ = ContactsService.sharedInstance.owner else {
            return nil
        }
        
        if chat == nil && senderId == 0 && receiverId == 0 && (content ?? "").isNotEmpty {
            ///Incoming bounty pmts
            return self.content
        }
        
        if let senderId = senderId, let sender = UserContact.getContactWith(id: senderId), isIncoming() {
            if let nickname = sender.nickname, !nickname.isEmpty {
                return nickname
            } else {
                return "-"
            }
        } else if let receivedId = receiverId, let receiver = UserContact.getContactWith(id: receivedId), !isIncoming() {
            guard let chat = chat else {
                return self.content
            }
            if !chat.isGroup(), let nickname = receiver.nickname, !nickname.isEmpty {
                return nickname
            } else {
                return "-"
            }
        }
        
        if let chat = chat, chat.isGroup(), let message = TransactionMessage.getMessageWith(uuid: self.originalMessageUUID ?? "") {
            if !self.isIncoming(),
              let replyUUID = message.replyUUID,
              let replyMessage = TransactionMessage.getMessageWith(uuid: replyUUID),
              let originalAlias = replyMessage.senderAlias
            {
                return originalAlias
            }
            return message.senderAlias
        }
        return "-"
    }
}

class PaymentTransactionFromServer: Mappable {
    var scid: Int64?
    var amt_msat: Int?
    var rhash: String?
    var ts: Int64?
    var remote: Bool?
    var msg_idx: Int?
    var error: String?
    
    required init?(map: Map) {}
    
    func mapping(map: Map) {
        scid     <- map["scid"]
        amt_msat <- map["amt_msat"]
        rhash    <- map["rhash"]
        ts       <- map["ts"]
        remote   <- map["remote"]
        msg_idx  <- map["msg_idx"]
        error    <- map["error"]
    }
}
