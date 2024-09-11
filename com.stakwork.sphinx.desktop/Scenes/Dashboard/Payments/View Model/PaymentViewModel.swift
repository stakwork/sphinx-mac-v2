//
//  PaymentViewModel.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 06/06/2020.
//  Copyright © 2020 Sphinx. All rights reserved.
//

import Foundation
import SwiftyJSON

class PaymentViewModel : NSObject {
    
    public struct PaymentObject {
        var memo: String?
        var encryptedMemo: String?
        var remoteEncryptedMemo: String?
        var amount: Int?
        var destinationKey: String?
        var message: String?
        var encryptedMessage: String?
        var remoteEncryptedMessage: String?
        var muid: String?
        var dim: String?
        var transactionMessage: TransactionMessage?
        var chat: Chat?
        var contacts = [UserContact]()
        var mode: PaymentMode?
    }
    
    enum PaymentMode: Int {
        case Request
        case Payment
    }
    
    var currentPayment : PaymentObject!
    
    init(
        chat: Chat? = nil,
        contact: UserContact? = nil,
        message: TransactionMessage? = nil,
        mode: PaymentMode
    ) {
        super.init()
        
        self.currentPayment = PaymentObject()
        self.currentPayment.chat = chat
        self.currentPayment.transactionMessage = message
        self.currentPayment.mode = mode
        
        if let contact = contact {
            setContacts(contacts: [contact])
        }
    }
    
    func setContacts(contacts: [UserContact]? = nil) {
        self.currentPayment.contacts = []
        
        if let contacts = contacts, contacts.count > 0 {
            self.currentPayment.contacts = contacts
        } else if let chat = currentPayment.chat, let contact = chat.getContact() {
            self.currentPayment.contacts = [contact]
        }
    }
    
    func isTribePayment() -> Bool {
        return currentPayment.transactionMessage != nil
    }
    
    func validateInvoice() -> Bool {
        guard let memo = currentPayment.memo else {
            return true
        }
        
        return memo.isValidLengthMemo()
    }
    
    func validatePayment() -> Bool {
        guard let _ = currentPayment.transactionMessage else {
            return true
        }
        
        guard let _ = currentPayment.message else {
            return true
        }
        
        if currentPayment.contacts.count < 1 {
            return false
        }
        
        return true
    }
    
    func shouldSendDirectPayment(
        callback: @escaping () -> (),
        errorCallback: @escaping (String?) -> ()
    ) {
        guard let chat = currentPayment.chat else {
            errorCallback("generic.error.message".localized)
            return
        }
        
        guard let amount = currentPayment.amount else {
            errorCallback("generic.error.message".localized)
            return
        }
        
        SphinxOnionManager.sharedInstance.sendDirectPaymentMessage(
            amount: amount * 1000,
            muid: currentPayment.muid,
            content: currentPayment.message,
            chat: chat,
            completion: { success, _ in
                if (success){
                    callback()
                } else {
                    errorCallback("generic.error.message".localized)
                }
            }
        )
    }
    
    func shouldCreateInvoice(
        callback: @escaping (String?) -> (),
        shouldDisplayAsQR: Bool = false,
        errorCallback: @escaping (String?) -> ()
    ) {
        if !validateInvoice() {
            errorCallback("memo.too.large".localized)
            return
        }
        
        if let paymentAmount = currentPayment.amount,
           let invoice = SphinxOnionManager.sharedInstance.createInvoice(
                amountMsat: paymentAmount * 1000,
                description: currentPayment.memo ?? ""
           )
        {
            if let contact = currentPayment.contacts.first, let chat = currentPayment.chat {
                SphinxOnionManager.sharedInstance.sendInvoiceMessage(
                    contact: contact,
                    chat: chat,
                    invoiceString: invoice,
                    memo: currentPayment.memo ?? ""
                )
                callback(nil)
            } else {
                callback(invoice)
            }
        } else {
            errorCallback("generic.error.message".localized)
        }
    }
    
    func createLocalMessages(message: JSON?) -> (TransactionMessage?, Bool) {
        if let message = message {
            if let messageObject = TransactionMessage.insertMessage(
                m: message,
                existingMessage: TransactionMessage.getMessageWith(id: message["id"].intValue)
            ).0 {
                messageObject.setPaymentInvoiceAsPaid()
                return (messageObject, true)
            }
        }
        return (nil, false)
    }
    
    func getParams() -> [String: AnyObject] {
        var parameters = [String : AnyObject]()
        
        if let amount = currentPayment.amount {
            parameters["amount"] = amount as AnyObject?
        }
        
        if let encryptedMemo = currentPayment.encryptedMemo, let remoteEncryptedMemo = currentPayment.remoteEncryptedMemo {
            parameters["memo"] = encryptedMemo as AnyObject?
            parameters["remote_memo"] = remoteEncryptedMemo as AnyObject?
        } else if let memo = currentPayment.memo {
            parameters["memo"] = memo as AnyObject?
        }
        
        if let publicKey = currentPayment.destinationKey {
            parameters["destination_key"] = publicKey as AnyObject?
        }
        
        if let muid = currentPayment.muid {
            parameters["muid"] = muid as AnyObject?
            parameters["media_type"] = "image/png" as AnyObject?
        }
        
        if let dim = currentPayment.dim {
            parameters["dimensions"] = dim as AnyObject?
        }
        
        if let message = currentPayment.message {
            parameters["text"] = message as AnyObject?
        }
        
        return parameters
    }
}
