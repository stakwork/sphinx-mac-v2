//
//  SphinOnionManager+InvoicesExtension.swift
//
//
//  Created by James Carucci on 3/5/24.
//


import Foundation

extension SphinxOnionManager{//invoices related
    
    func createInvoice(
        amountMsat: Int,
        description: String? = nil
    ) -> String? {
            
        guard let seed = getAccountSeed(), let selfContact = UserContact.getSelfContact(), let _ = selfContact.nickname else {
            return nil
        }
            
        do {
            let rr = try Sphinx.makeInvoice(
                seed: seed,
                uniqueTime: getTimeWithEntropy(),
                state: loadOnionStateAsData(),
                amtMsat: UInt64(amountMsat),
                description: description ?? ""
            )
            
            let _ = handleRunReturn(rr: rr)
                
            return rr.invoice
        } catch {
            return nil
        }
    }
    
    func payInvoice(invoice: String) {
        guard let seed = getAccountSeed() else{
            return
        }
        do {
            let rr = try Sphinx.payInvoice(
                seed: seed,
                uniqueTime: getTimeWithEntropy(),
                state: loadOnionStateAsData(),
                bolt11: invoice,
                overpayMsat: nil
            )
            let _ = handleRunReturn(rr: rr)
        } catch {
            return
        }
    }
    
    func sendPaymentOfInvoiceMessage(message: TransactionMessage) {
        guard message.type == TransactionMessage.TransactionMessageType.payment.rawValue,
              let invoice = message.invoice,
              let seed = getAccountSeed(),
              let selfContact = UserContact.getSelfContact(),
              let chat = message.chat,
              let nickname = selfContact.nickname ?? chat.name else
        {
            return
        }
        
        do {
            let rr = try Sphinx.payContactInvoice(
                seed: seed,
                uniqueTime: getTimeWithEntropy(),
                state: loadOnionStateAsData(),
                bolt11: invoice,
                myAlias: nickname,
                myImg: selfContact.avatarUrl ?? "",
                isTribe: false
            )
            let _ = handleRunReturn(rr: rr)
        } catch {
            return
        }
    }
    
    
    func sendInvoiceMessage(
        contact:UserContact,
        chat:Chat,
        invoiceString:String
    ) {
        let _ = sendMessage(
            to: contact,
            content: "",
            chat: chat,
            msgType: UInt8(TransactionMessage.TransactionMessageType.invoice.rawValue),
            threadUUID: nil,
            replyUUID: nil,
            invoiceString: invoiceString
        )
    }
    
    func getTransactionHistory() -> [PaymentTransaction] {
        let context = CoreDataManager.sharedManager.persistentContainer.viewContext
        var history = [PaymentTransaction]()

        let messages = TransactionMessage.fetchTransactionMessagesForHistory()
        
        for message in messages{
            history.append(PaymentTransaction(fromTransactionMessage: message))
        }
        
        return history
    }

}
