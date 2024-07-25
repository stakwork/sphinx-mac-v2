//
//  SphinOnionManager+InvoicesExtension.swift
//
//
//  Created by James Carucci on 3/5/24.
//


import Foundation
import SwiftyJSON

extension SphinxOnionManager{
    //Routing
    func updateRoutingInfo() {
        API.sharedInstance.fetchRoutingInfo(
            callback: { result, pubkey in
                guard let result = result else {
                    return
                }
                do {
                    let rr = try Sphinx.addNode(node: result)
                    let _ = self.handleRunReturn(rr: rr)
                    
                    if let pubkey = pubkey {
                        UserDefaults.Keys.routerPubkey.set(pubkey)
                    }
                } catch {}
            }
        )
    }
    
    func fetchRoutingInfoFor(
        pubkey: String,
        amtMsat: Int,
        completion: @escaping (Bool) -> ()
    ) {
        if let routerPubkey = self.routerPubkey {
            API.sharedInstance.fetchRoutingInfoFor(
                pubkey: pubkey,
                amtMsat: amtMsat,
                callback: { results in
                    if let results = results {
                        var resultsArray = []
                        do {
                            resultsArray = try results.toArray()
                        } catch {}
                            
                        if resultsArray.isEmpty {
                            completion(true)
                            return
                        }
                        
                        do {
                            let rr =  try Sphinx.concatRoute(
                                state: self.loadOnionStateAsData(),
                                endHops: results,
                                routerPubkey: routerPubkey,
                                amtMsat: UInt64(amtMsat)
                            )
                            let _ = self.handleRunReturn(rr: rr)
                            completion(true)
                        } catch {
                            completion(false)
                        }
                    } else {
                        completion(false)
                    }
                }
            )
        }
    }
    
    func checkAndFetchRouteTo(
        publicKey: String,
        routeHint: String? = nil,
        amtMsat: Int,
        callback: @escaping (Bool) -> ()
    ) {
        if requiresManualRouting(
            publicKey: publicKey,
            routeHint: routeHint
        ) {
            fetchRoutingInfoFor(
                pubkey: publicKey,
                amtMsat: amtMsat,
                completion: { success in
                    callback(success)
                }
            )
        } else {
            callback(true)
        }
    }
    
    //invoices related
    func createInvoice(
        amountMsat: Int,
        description: String? = nil
    ) -> String? {
            
        guard let seed = getAccountSeed(), let selfContact = UserContact.getOwner(), let _ = selfContact.nickname else {
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
    
    func getInvoiceDetails(invoice: String) -> ParseInvoiceResult? {
        do {
            let rawInvoiceDetails = try parseInvoice(invoiceJson: invoice)
            let parsedInvoiceDetails = ParseInvoiceResult(JSONString: rawInvoiceDetails)
            return parsedInvoiceDetails
        } catch {
            return nil
        }
    }
    
    func payInvoice(
        invoice: String,
        overPayAmountMsat: UInt64? = nil,
        callback: ((Bool, String?) -> ())? = nil
    ){
        guard let invoiceDict = getInvoiceDetails(invoice: invoice),
              let pubkey = invoiceDict.pubkey,
              let amount = invoiceDict.value else
        {
            callback?(false, "Pubkey not found")
            return
        }
        
        checkAndFetchRouteTo(
            publicKey: pubkey,
            routeHint: invoiceDict.hopHints?.last,
            amtMsat: Int(overPayAmountMsat ?? UInt64(amount))
        ) { success in
            if success {
                let (success, errorMsg) = self.finalizePayInvoice(
                    invoice: invoice,
                    amount: overPayAmountMsat ?? UInt64(amount)
                )
                callback?(success, errorMsg)
            } else {
                ///error getting route info
                AlertHelper.showAlert(
                    title: "Routing Error",
                    message: "Could not find a route to the target. Please try again."
                )
                callback?(false, "Could not find a route to the target. Please try again.")
            }
        }
    }
    
    func finalizePayInvoice(
        invoice: String,
        amount: UInt64
    ) -> (Bool, String?) {
        guard let seed = getAccountSeed() else{
            return (false, "Account seed not found")
        }
        do {
            let rr = try Sphinx.payInvoice(
                seed: seed,
                uniqueTime: getTimeWithEntropy(),
                state: loadOnionStateAsData(),
                bolt11: invoice,
                overpayMsat: amount
            )
            let _ = handleRunReturn(rr: rr)
            return (true, nil)
        } catch let error {
            return (false, (error as? SphinxError).debugDescription)
        }
    }
    
    func payInvoiceMessage(
        message: TransactionMessage
    ) {
        guard let invoiceDict = getInvoiceDetails(invoice: message.invoice ?? ""),
              let owner = UserContact.getOwner(),
              let _ = owner.nickname,
              let pubkey = invoiceDict.pubkey,
              let amount = invoiceDict.value else
        {
            return
        }
        
        checkAndFetchRouteTo(
            publicKey: pubkey,
            routeHint: invoiceDict.hopHints?.last,
            amtMsat: Int(UInt64(amount))
        ) { success in
            if success {
                self.finalizePayInvoiceMessage(message: message)
            } else {
                ///error getting route info
                AlertHelper.showAlert(
                    title: "Routing Error",
                    message: "Could not find a route to the target. Please try again."
                )
            }
        }
    }
    
    func finalizePayInvoiceMessage(
        message: TransactionMessage
    ) {
        guard message.type == TransactionMessage.TransactionMessageType.invoice.rawValue,
              let invoice = message.invoice,
              let seed = getAccountSeed(),
              let owner = UserContact.getOwner(),
              let nickname = owner.nickname else
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
                myImg: owner.avatarUrl ?? "",
                isTribe: false
            )
            let _ = handleRunReturn(rr: rr)
        } catch {
            return
        }
    }
    
    func sendInvoiceMessage(
        contact: UserContact,
        chat: Chat,
        invoiceString: String,
        memo: String = ""
    ) {
        let _ = sendMessage(
            to: contact,
            content: memo,
            chat: chat,
            provisionalMessage: nil,
            msgType: UInt8(TransactionMessage.TransactionMessageType.invoice.rawValue),
            threadUUID: nil,
            replyUUID: nil,
            invoiceString: invoiceString
        )
    }
    
    func keysend(
        pubkey: String,
        routeHint: String? = nil,
        amt: Int,
        completion: @escaping (Bool) -> ()
    ) {
        checkAndFetchRouteTo(
            publicKey: pubkey,
            routeHint: routeHint,
            amtMsat: amt * 1000
        ) { success in
            if success {
                if self.finalizeKeysend(
                    pubkey: pubkey,
                    routeHint: routeHint,
                    amt: amt * 1000
                ) {
                    completion(true)
                } else {
                    completion(false)
                }
            } else {
                completion(false)
            }
        }
        
    }
    
    func finalizeKeysend(
        pubkey: String,
        routeHint: String? = nil,
        amt: Int
    ) -> Bool {
        guard let seed = getAccountSeed() else{
            return false
        }
        do {
            let rr = try Sphinx.keysend(
                seed: seed,
                uniqueTime: getTimeWithEntropy(),
                to: pubkey,
                state: loadOnionStateAsData(),
                amtMsat: UInt64(amt),
                data: nil,
                routeHint: routeHint
            )
            let _ = handleRunReturn(rr: rr)
            return true
        } catch {
            return false
        }
    }
    
    func getTransactionsHistory(
        paymentsHistoryCallback: @escaping ((String?, String?) -> ()),
        itemsPerPage: UInt32,
        sinceTimestamp: UInt64
    ) {
        do {
            let rr = try fetchPayments(
                seed: getAccountSeed()!,
                uniqueTime: getTimeWithEntropy(),
                state: loadOnionStateAsData(),
                since: sinceTimestamp * 1000,
                limit: itemsPerPage,
                scid: nil,
                remoteOnly: false,
                minMsat: 0,
                reverse: true
            )
            
            self.paymentsHistoryCallback = paymentsHistoryCallback
            
            let _ = handleRunReturn(rr: rr)
        } catch let error {
            paymentsHistoryCallback(
                nil,
                "Error fetching transactions history: \(error.localizedDescription)"
            )
        }
    }
    
    func getIdFromMacaroon(macaroon: String) -> (String?, String?) {
        do {
            let identifier = try idFromMacaroon(macaroon: macaroon)
            return (identifier, nil)
        } catch let error {
            return (nil, (error as? SphinxError).debugDescription)
        }
    }

}
