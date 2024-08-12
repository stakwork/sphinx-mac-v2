//
//  SphinxOnionManager+StructsAndHelpersExtension.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 22/05/2024.
//  Copyright © 2024 Tomas Timinskas. All rights reserved.
//

import Foundation
import ObjectMapper
import SwiftyJSON

//MARK: Helper Structs & Functions:

struct SphinxOnionBrokerResponse: Mappable {
    var scid: String?
    var serverPubkey: String?
    var myPubkey: String?

    init?(map: Map) {}

    mutating func mapping(map: Map) {
        scid <- map["scid"]
        serverPubkey <- map["server_pubkey"]
    }
}

enum SphinxMsgError: Error {
    case encodingError
    case credentialsError //can't get access to my Private Keys/other data!
    case contactDataError // not enough data about contact!
}

struct ContactServerResponse: Mappable {
    var pubkey: String?
    var routeHint: String?
    var alias: String?
    var host:String?
    var photoUrl: String?
    var person: String?
    var code: String?
    var role: Int?
    var fullContactInfo: String?
    var recipientAlias: String?
    var confirmed: Bool?

    init?(map: Map) {}

    mutating func mapping(map: Map) {
        pubkey          <- map["pubkey"]
        routeHint       <- map["route_hint"]
        alias           <- map["alias"]
        photoUrl        <- map["photo_url"]
        person          <- map["person"]
        code            <- map["code"]
        host            <- map["host"]
        role            <- map["role"]
        fullContactInfo <- map["fullContactInfo"]
        recipientAlias  <- map["recipientAlias"]
        confirmed       <- map["confirmed"]
    }
    
    func isTribeMessage() -> Bool {
        if let _ = role {
            return true
        }
        return false
    }
}

struct ListContactResponse: Mappable {
    var version: Int?
    var my_idx: Int?
    var pubkey: String?
    var lsp: String?
    var scid: Int?
    var contact_key: String?
    var highest_msg_idx: Int?

    init?(map: Map) {}

    mutating func mapping(map: Map) {
        version           <- map["version"]
        my_idx            <- map["my_idx"]
        pubkey            <- map["pubkey"]
        lsp               <- map["lsp"]
        scid              <- map["scid"]
        contact_key       <- map["contact_key"]
        highest_msg_idx   <- map["highest_msg_idx"]
    }
    
    func isConfirmed() -> Bool {
        return contact_key != nil
    }
}

struct MessageInnerContent: Mappable {
    var content: String?
    var replyUuid: String? = nil
    var threadUuid: String? = nil
    var mediaKey: String? = nil
    var mediaToken: String? = nil
    var mediaType: String? = nil
    var muid: String? = nil
    var originalUuid: String? = nil
    var date: Int? = nil
    var invoice: String? = nil
    var paymentHash: String? = nil
    var amount: Int? = nil
    var fullContactInfo: String? = nil
    var recipientAlias: String? = nil

    init?(map: Map) {}
    
    mutating func mapping(map: Map) {
        content         <- map["content"]
        replyUuid       <- map["replyUuid"]
        threadUuid      <- map["threadUuid"]
        mediaToken      <- map["mediaToken"]
        mediaType       <- map["mediaType"]
        mediaKey        <- map["mediaKey"]
        muid            <- map["muid"]
        date            <- map["date"]
        originalUuid    <- map["originalUuid"]
        invoice         <- map["invoice"]
        paymentHash     <- map["paymentHash"]
        amount          <- map["amount"]
        fullContactInfo <- map["fullContactInfo"]
        recipientAlias  <- map["recipientAlias"]
    }
    
    func getRouteHint() -> String? {
        if let contactInfo = self.fullContactInfo, let (_, recipLspPubkey, scid) = contactInfo.parseContactInfoString() {
            return "\(recipLspPubkey)_\(scid)"
        }
        return nil
    }
}

struct MessageStatusMap: Mappable {
    var ts: Int?
    var status: String?
    var tag: String?

    init?(map: Map) {}

    mutating func mapping(map: Map) {
        ts          <- map["ts"]
        status      <- map["status"]
        tag         <- map["tag"]
    }
    
    func isReceived() -> Bool {
        return self.status == SphinxOnionManager.kCompleteStatus
    }
    
    func isFailed() -> Bool {
        return self.status == SphinxOnionManager.kFailedStatus
    }
}


struct GenericIncomingMessage: Mappable {
    var content: String?
    var amount: Int?
    var senderPubkey: String? = nil
    var uuid: String? = nil
    var originalUuid: String? = nil
    var index: String? = nil
    var replyUuid: String? = nil
    var threadUuid: String? = nil
    var mediaKey: String? = nil
    var mediaToken: String? = nil
    var mediaType: String? = nil
    var muid: String? = nil
    var timestamp: Int? = nil
    var invoice: String? = nil
    var paymentHash: String? = nil
    var alias: String? = nil
    var fullContactInfo: String? = nil
    var photoUrl: String? = nil
    var tag: String? = nil

    init?(map: Map) {}
    
    init(msg: Msg) {
        
        if let sender = msg.sender, let csr = ContactServerResponse(JSONString: sender) {
            if let fromMe = msg.fromMe, fromMe == true, let sentTo = msg.sentTo {
                self.senderPubkey = sentTo
            } else {
                self.senderPubkey = csr.pubkey
            }
            self.photoUrl = csr.photoUrl
            self.alias = csr.alias
        }
        
        var innerContentAmount : UInt64? = nil
        
        if let message = msg.message,
           let innerContent = MessageInnerContent(JSONString: message)
        {
            self.content = innerContent.content
            self.replyUuid = innerContent.replyUuid
            self.threadUuid = innerContent.threadUuid
            self.mediaKey = innerContent.mediaKey
            self.mediaToken = innerContent.mediaToken
            self.mediaType = innerContent.mediaType
            self.muid = innerContent.muid
            self.originalUuid = innerContent.originalUuid
            self.invoice = innerContent.invoice
            self.paymentHash = innerContent.paymentHash
            
            innerContentAmount = UInt64(innerContent.amount ?? 0)
            
            if msg.type == UInt8(TransactionMessage.TransactionMessageType.unknown.rawValue) {
                self.alias = innerContent.recipientAlias
                self.fullContactInfo = innerContent.fullContactInfo
            }
            
            let isTribe = SphinxOnionManager.sharedInstance.isTribeMessage(senderPubkey: senderPubkey ?? "")
            
            if let timestamp = msg.timestamp, isTribe == false {
                self.timestamp = Int(timestamp)
            } else {
                self.timestamp = innerContent.date
            }
        }
        
        if let invoice = self.invoice {
            let prd = PaymentRequestDecoder()
            prd.decodePaymentRequest(paymentRequest: invoice)
            
            let amount = prd.getAmount() ?? 0
            self.amount = amount * 1000 // convert to msat
        } else {
            self.amount = (msg.fromMe == true) ? Int((innerContentAmount) ?? 0) : Int((msg.msat ?? innerContentAmount) ?? 0)
        }
        
        self.uuid = msg.uuid
        self.index = msg.index
        self.tag = msg.tag
    }

    mutating func mapping(map: Map) {
        content    <- map["content"]
        amount     <- map["amount"]
        replyUuid  <- map["replyUuid"]
        threadUuid <- map["threadUuid"]
        mediaToken <- map["mediaToken"]
        mediaType  <- map["mediaType"]
        mediaKey   <- map["mediaKey"]
        muid       <- map["muid"]
        
    }
    
}

struct TribeMembersRRObject: Mappable {
    var pubkey: String? = nil
    var routeHint: String? = nil
    var alias: String? = nil
    var contactKey: String? = nil
    var is_owner: Bool = false
    var status: String? = nil

    init?(map: Map) {}

    mutating func mapping(map: Map) {
        pubkey       <- map["pubkey"]
        alias        <- map["alias"]
        routeHint    <- map["route_hint"]
        contactKey   <- map["contact_key"]
    }
    
}


class SentStatus: Mappable {
    var tag: String?
    var status: String?
    var preimage: String?
    var paymentHash: String?

    required init?(map: Map) {
    }

    func mapping(map: Map) {
        tag         <- map["tag"]
        status      <- map["status"]
        preimage    <- map["preimage"]
        paymentHash <- map["payment_hash"]
    }
}

extension SphinxOnionManager {
    func timestampToDate(
        timestamp: UInt64
    ) -> Date? {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
        return date
    }
    
    func timestampToInt(
        timestamp: UInt64
    ) -> Int? {
        let dateInSeconds = Double(timestamp) / 1000.0
        return Int(dateInSeconds)
    }


    func isGroupAction(
        type: UInt8
    ) -> Bool {
        let intType = Int(type)
        return intType == TransactionMessage.TransactionMessageType.groupJoin.rawValue ||
                intType == TransactionMessage.TransactionMessageType.groupLeave.rawValue ||
                intType == TransactionMessage.TransactionMessageType.groupKick.rawValue ||
                intType == TransactionMessage.TransactionMessageType.groupDelete.rawValue ||
                intType == TransactionMessage.TransactionMessageType.memberRequest.rawValue ||
                intType == TransactionMessage.TransactionMessageType.memberApprove.rawValue ||
                intType == TransactionMessage.TransactionMessageType.memberReject.rawValue
    }
    
    func isBoostOrPayment(
        type: UInt8
    ) -> Bool {
        let intType = Int(type)
        return intType == TransactionMessage.TransactionMessageType.boost.rawValue ||
                intType == TransactionMessage.TransactionMessageType.directPayment.rawValue ||
                intType == TransactionMessage.TransactionMessageType.payment.rawValue
    }
    
    func isMessageCallOrAttachment(
        type: UInt8
    ) -> Bool {
        let intType = Int(type)
        return intType == TransactionMessage.TransactionMessageType.message.rawValue ||
                intType == TransactionMessage.TransactionMessageType.call.rawValue ||
                intType == TransactionMessage.TransactionMessageType.attachment.rawValue
    }
    
    func isDelete(
        type: UInt8
    ) -> Bool {
        let intType = Int(type)
        return intType == TransactionMessage.TransactionMessageType.delete.rawValue
    }
    
    func isInvoice(
        type: UInt8
    ) -> Bool {
        let intType = Int(type)
        return intType == TransactionMessage.TransactionMessageType.invoice.rawValue
    }
        

    func isMyMessageNeedingIndexUpdate(msg: Msg) -> Bool {
        if let _ = msg.uuid,
           let _ = msg.index {
            return true
        }
        return false
    }
}

struct ParseInvoiceResult: Mappable {
    var value: Int?
    var paymentHash: String?
    var pubkey: String?
    var hopHints: [String]?
    var description: String?
    var expiry: Int?
    
    init?(map: Map) {}

    mutating func mapping(map: Map) {
        value          <- map["value"]
        paymentHash    <- map["payment_hash"]
        pubkey         <- map["pubkey"]
        hopHints       <- map["hop_hints"]
        description    <- map["description"]
        expiry         <- map["expiry"]
    }
}

enum SphinxOnionManagerError: Error {
    case SOMNetworkError
    case SOMTimeoutError
    
    var localizedDescription: String {
        switch self {
        case .SOMNetworkError:
            return "error.network".localized
        case .SOMTimeoutError:
            return "Timeout Error"
        }
    }
}
