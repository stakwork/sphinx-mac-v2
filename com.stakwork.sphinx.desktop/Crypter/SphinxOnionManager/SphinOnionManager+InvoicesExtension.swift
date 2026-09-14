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
        routeFetchCallCount += 1
        if let checkAndFetchRouteOverride = checkAndFetchRouteOverride {
            checkAndFetchRouteOverride(callback)
            return
        }
        if requiresManualRouting(
            publicKey: publicKey,
            routeHint: routeHint
        ) {
            do {
                let _ = try Sphinx.findRoute(
                    state: self.loadOnionStateAsData(),
                    toPubkey: publicKey,
                    routeHint: routeHint,
                    amtMsat: UInt64(amtMsat)
                )
                callback(true)
            } catch {
                fetchRoutingInfoFor(
                    pubkey: publicKey,
                    amtMsat: amtMsat,
                    completion: { success in
                        callback(success)
                    }
                )
            }
        } else {
            callback(true)
        }
    }
    
    //invoices related
    func createInvoice(
        amountMsat: Int,
        description: String? = nil,
        callback: @escaping (String?) -> Void
    ) {
        guard let seed = getAccountSeed(), let selfContact = UserContact.getOwner(), let _ = selfContact.nickname else {
            callback(nil)
            return
        }

        do {
            let rr = try Sphinx.requestInvoice(
                seed: seed,
                uniqueTime: getTimeWithEntropy(),
                state: loadOnionStateAsData(),
                amtMsat: UInt64(amountMsat),
                description: description
            )

            self.invoiceGeneratedCallback = callback
            let _ = handleRunReturn(rr: rr)

            self.invoiceGeneratedTimeoutTimer = Timer.scheduledTimer(
                withTimeInterval: 30.0,
                repeats: false
            ) { [weak self] _ in
                guard let self = self else { return }
                self.invoiceGeneratedCallback?(nil)
                self.invoiceGeneratedCallback = nil
                self.invoiceGeneratedTimeoutTimer = nil
            }
        } catch {
            callback(nil)
        }
    }
    
    func getInvoiceDetails(invoice: String) -> ParseInvoiceResult? {
        if let invoiceDetailsProvider = invoiceDetailsProvider {
            return invoiceDetailsProvider(invoice)
        }
        let normalizedInvoice = invoice.components(separatedBy: .whitespacesAndNewlines).joined()
        do {
            let rawInvoiceDetails = try parseInvoice(invoiceJson: normalizedInvoice)
            let parsedInvoiceDetails = ParseInvoiceResult(JSONString: rawInvoiceDetails)
            return parsedInvoiceDetails
        } catch {
            return nil
        }
    }
    
    /// TODO: confirm against mixer/server duplicate-payment fix.
    /// Matches only the confirmed mixer already-paid string. Empty until that
    /// wording is known — do not guess phrases like "invoice settled".
    func isInvoiceAlreadyPaidError(_ error: String?) -> Bool {
        guard let error = error, !error.isEmpty else {
            return false
        }
        return SphinxOnionManager.invoiceAlreadyPaidErrorMatchers.contains(where: { matcher in
            !matcher.isEmpty && error.contains(matcher)
        })
    }
    
    func isInvoiceAlreadyPaidSphinxError(_ error: Error) -> Bool {
        if case SphinxError.SendFailed(let r) = error {
            return isInvoiceAlreadyPaidError(r)
        }
        return false
    }
    
    var invoiceAlreadyPaidLocalizedMessage: String {
        "invoice.already.paid".localized
    }
    
    func insertInFlightPaymentHash(_ paymentHash: String) {
        paymentHashLock.lock()
        inFlightPaymentHashes.insert(paymentHash)
        paymentHashLock.unlock()
    }
    
    func removeInFlightPaymentHash(_ paymentHash: String?) {
        guard let paymentHash = paymentHash, !paymentHash.isEmpty else {
            return
        }
        paymentHashLock.lock()
        inFlightPaymentHashes.remove(paymentHash)
        paymentHashLock.unlock()
    }
    
    func markPaymentHashPaid(_ paymentHash: String?) {
        guard let paymentHash = paymentHash, !paymentHash.isEmpty else {
            return
        }
        paymentHashLock.lock()
        paidPaymentHashes.insert(paymentHash)
        inFlightPaymentHashes.remove(paymentHash)
        paymentHashLock.unlock()
    }
    
    func isPaymentHashInFlight(_ paymentHash: String) -> Bool {
        paymentHashLock.lock()
        defer { paymentHashLock.unlock() }
        return inFlightPaymentHashes.contains(paymentHash)
    }
    
    func isPaymentHashPaid(_ paymentHash: String) -> Bool {
        paymentHashLock.lock()
        defer { paymentHashLock.unlock() }
        return paidPaymentHashes.contains(paymentHash)
    }
    
    func hasLocalAlreadyPaidRecord(forPaymentHash paymentHash: String) -> Bool {
        if isPaymentHashInFlight(paymentHash) || isPaymentHashPaid(paymentHash) {
            return true
        }
        if let hasSettledPaymentOverride = hasSettledPaymentOverride {
            return hasSettledPaymentOverride(paymentHash)
        }
        return TransactionMessage.hasSettledPayment(forPaymentHash: paymentHash)
    }
    
    func handleLocalAlreadyPaid(
        paymentHash: String,
        callback: ((Bool, String?) -> ())? = nil,
        useAlert: Bool = false
    ) {
        print("Run return object error: already paid (local) payment_hash=\(paymentHash)")
        if useAlert {
            if let alreadyPaidAlertHandler = alreadyPaidAlertHandler {
                alreadyPaidAlertHandler(invoiceAlreadyPaidLocalizedMessage)
            } else {
                DispatchQueue.main.async {
                    AlertHelper.showAlert(
                        title: "generic.error.title".localized,
                        message: self.invoiceAlreadyPaidLocalizedMessage
                    )
                }
            }
        } else {
            callback?(false, invoiceAlreadyPaidLocalizedMessage)
        }
    }
    
    func executeSimulatedOrRealPay(_ real: () throws -> RunReturn) throws -> RunReturn {
        sphinxPayCallCount += 1
        if let simulatedPayError = simulatedPayError {
            throw simulatedPayError
        }
        if let simulatedPayRunReturn = simulatedPayRunReturn {
            return simulatedPayRunReturn
        }
        return try real()
    }
    
    func handleNetworkAlreadyPaid(
        paymentHash: String?,
        callback: ((Bool, String?) -> ())? = nil,
        useAlert: Bool = false
    ) {
        if let paymentHash = paymentHash, !paymentHash.isEmpty {
            print("Run return object error: already paid (network) payment_hash=\(paymentHash)")
            markPaymentHashPaid(paymentHash)
        } else {
            print("Run return object error: already paid (network)")
        }
        if useAlert {
            if let alreadyPaidAlertHandler = alreadyPaidAlertHandler {
                alreadyPaidAlertHandler(invoiceAlreadyPaidLocalizedMessage)
            } else {
                DispatchQueue.main.async {
                    AlertHelper.showAlert(
                        title: "generic.error.title".localized,
                        message: self.invoiceAlreadyPaidLocalizedMessage
                    )
                }
            }
        } else {
            callback?(false, invoiceAlreadyPaidLocalizedMessage)
        }
    }
    
    func payInvoice(
        invoice: String,
        overPayAmountMsat: UInt64? = nil,
        callback: ((Bool, String?) -> ())? = nil
    ){
        let invoice = invoice.components(separatedBy: .whitespacesAndNewlines).joined()
        guard let invoiceDict = getInvoiceDetails(invoice: invoice) else {
            callback?(false, "Pubkey not found")
            return
        }
        
        let paymentHash = invoiceDict.paymentHash
        if let paymentHash = paymentHash, hasLocalAlreadyPaidRecord(forPaymentHash: paymentHash) {
            handleLocalAlreadyPaid(paymentHash: paymentHash, callback: callback)
            return
        }
        
        guard let pubkey = invoiceDict.pubkey,
              let amount = invoiceDict.value else
        {
            callback?(false, "Pubkey not found")
            return
        }
        
        let hasRouteHint = invoiceDict.hopHints?.last != nil
        
        if let paymentHash = paymentHash {
            insertInFlightPaymentHash(paymentHash)
        }
        
        checkAndFetchRouteTo(
            publicKey: pubkey,
            routeHint: invoiceDict.hopHints?.last,
            amtMsat: Int(overPayAmountMsat ?? UInt64(amount))
        ) { success in
            if success {
                self.finalizePayInvoice(
                    invoice: invoice,
                    hasRouteHint: hasRouteHint,
                    amount: overPayAmountMsat ?? UInt64(amount),
                    paymentHash: paymentHash,
                    callback: callback
                )
            } else {
                if !hasRouteHint {
                    ///Standard invoice with no route hint
                    self.payInvoiceFromLSP(
                        invoice: invoice,
                        paymentHash: paymentHash,
                        callback: callback
                    )
                    return
                }
                self.removeInFlightPaymentHash(paymentHash)
                ///error getting route info
                callback?(false, "Could not find a route to the target. Please try again.")
            }
        }
    }
    
    func payInvoiceFromSB(
        invoice: String,
        overPayAmountMsat: UInt64? = nil,
        callback: ((Bool, String?) -> ())? = nil
    ){
        let invoice = invoice.components(separatedBy: .whitespacesAndNewlines).joined()
        guard let invoiceDict = getInvoiceDetails(invoice: invoice) else {
            callback?(false, "Pubkey not found")
            return
        }
        
        let paymentHash = invoiceDict.paymentHash
        if let paymentHash = paymentHash, hasLocalAlreadyPaidRecord(forPaymentHash: paymentHash) {
            handleLocalAlreadyPaid(paymentHash: paymentHash, callback: callback)
            return
        }
        
        guard let pubkey = invoiceDict.pubkey,
              let amount = invoiceDict.value else
        {
            callback?(false, "Pubkey not found")
            return
        }
        
        let hasRouteHint = invoiceDict.hopHints?.last != nil
        
        if let paymentHash = paymentHash {
            insertInFlightPaymentHash(paymentHash)
        }
        
        if !hasRouteHint {
            self.payInvoiceFromLSP(
                invoice: invoice,
                paymentHash: paymentHash,
                callback: callback
            )
            return
        } else {
            checkAndFetchRouteTo(
                publicKey: pubkey,
                routeHint: invoiceDict.hopHints?.last,
                amtMsat: Int(overPayAmountMsat ?? UInt64(amount))
            ) { success in
                if success {
                    self.finalizePayInvoice(
                        invoice: invoice,
                        hasRouteHint: hasRouteHint,
                        amount: overPayAmountMsat ?? UInt64(amount),
                        paymentHash: paymentHash,
                        callback: callback
                    )
                } else {
                    self.removeInFlightPaymentHash(paymentHash)
                    callback?(false, "Could not find a route to the target. Please try again.")
                }
            }
        }
    }
    
    func payInvoiceFromLSP(
        invoice: String,
        paymentHash: String? = nil,
        callback: ((Bool, String?) -> ())? = nil
    ) {
        let invoice = invoice.components(separatedBy: .whitespacesAndNewlines).joined()
        let paymentHash = paymentHash ?? getInvoiceDetails(invoice: invoice)?.paymentHash
        // Retry path: do not treat the current in-flight hash as already paid.
        if let paymentHash = paymentHash,
           isPaymentHashPaid(paymentHash) ||
            (hasSettledPaymentOverride?(paymentHash) ?? TransactionMessage.hasSettledPayment(forPaymentHash: paymentHash))
        {
            handleLocalAlreadyPaid(paymentHash: paymentHash, callback: callback)
            return
        }
        let seed = getAccountSeed()
        if seed == nil && simulatedPayRunReturn == nil && simulatedPayError == nil {
            removeInFlightPaymentHash(paymentHash)
            callback?(false, "Account seed not found")
            return
        }
        
        do {
            let rr = try executeSimulatedOrRealPay {
                try Sphinx.pay(
                    seed: seed ?? "",
                    uniqueTime: getTimeWithEntropy(),
                    state: loadOnionStateAsData(),
                    bolt11: invoice
                )
            }
            let _ = handleRunReturn(rr: rr)
            
            if isInvoiceAlreadyPaidError(rr.error) {
                handleNetworkAlreadyPaid(paymentHash: paymentHash, callback: callback)
                return
            }
            
            removeInFlightPaymentHash(paymentHash)
            callback?(true, nil)
        } catch let error {
            if isInvoiceAlreadyPaidSphinxError(error) {
                handleNetworkAlreadyPaid(paymentHash: paymentHash, callback: callback)
                return
            }
            removeInFlightPaymentHash(paymentHash)
            if case SphinxError.SendFailed(let r) = error {
                callback?(false, r)
            } else {
                callback?(false, (error as? SphinxError).debugDescription)
            }
        }
    }
    
    func finalizePayInvoice(
        invoice: String,
        hasRouteHint: Bool,
        amount: UInt64,
        paymentHash: String? = nil,
        callback: ((Bool, String?) -> ())? = nil
    ) {
        let invoice = invoice.components(separatedBy: .whitespacesAndNewlines).joined()
        let paymentHash = paymentHash ?? getInvoiceDetails(invoice: invoice)?.paymentHash
        let seed = getAccountSeed()
        if seed == nil && simulatedPayRunReturn == nil && simulatedPayError == nil {
            removeInFlightPaymentHash(paymentHash)
            callback?(false, "Account seed not found")
            return
        }
        do {
            let rr = try executeSimulatedOrRealPay {
                try Sphinx.payInvoice(
                    seed: seed ?? "",
                    uniqueTime: getTimeWithEntropy(),
                    state: loadOnionStateAsData(),
                    bolt11: invoice,
                    overpayMsat: amount
                )
            }
            let _ = handleRunReturn(rr: rr)
            
            if isInvoiceAlreadyPaidError(rr.error) {
                handleNetworkAlreadyPaid(paymentHash: paymentHash, callback: callback)
                return
            }
            
            if let tag = getMessageTag(messages: rr.msgs, isSendingMessage: true), !hasRouteHint {
                setupInvoicePaymentTimerFor(invoice: invoice, tag: tag)
            }
            removeInFlightPaymentHash(paymentHash)
            callback?(true, nil)
        } catch let error {
            if isInvoiceAlreadyPaidSphinxError(error) {
                handleNetworkAlreadyPaid(paymentHash: paymentHash, callback: callback)
                return
            }
            removeInFlightPaymentHash(paymentHash)
            if case SphinxError.SendFailed(let r) = error {
                callback?(false, r)
            } else {
                callback?(false, (error as? SphinxError).debugDescription)
            }
        }
    }
    
    func setupInvoicePaymentTimerFor(invoice: String, tag: String) {
        let paymentTimer = Timer.scheduledTimer(
            timeInterval: 60.0,
            target: self,
            selector: #selector(self.resetInvoicePaymentTimerFor(timer:)),
            userInfo: ["invoice": invoice, "tag": tag],
            repeats: false
        )
        
        paymentTimeoutTimers[tag] = paymentTimer
    }
    
    func onPaymentStatusReceivedFor(
        tag: String,
        status: String
    ) {
        DispatchQueue.main.async {
            if let timer = self.paymentTimeoutTimers[tag] {
                if status == SphinxOnionManager.kCompleteStatus {
                    AlertHelper.showAlert(
                        title: "Success",
                        message: "Your payment has been successfully processed"
                    )
                } else if let userInfo = timer.userInfo as? [String: String], let invoice = userInfo["invoice"] {
                    self.payInvoiceFromLSP(
                        invoice: invoice,
                        callback: { [weak self] success, errorMsg in
                            guard let self = self else { return }
                            if !success, errorMsg == self.invoiceAlreadyPaidLocalizedMessage {
                                AlertHelper.showAlert(
                                    title: "generic.error.title".localized,
                                    message: self.invoiceAlreadyPaidLocalizedMessage
                                )
                            }
                        }
                    )
                }
                self.resetInvoicePaymentTimerFor(tag: tag)
            }
        }
    }
    
    @objc func resetInvoicePaymentTimerFor(timer: Timer) {
        if let userInfo = timer.userInfo as? [String: String], let tag = userInfo["tag"] {
            resetInvoicePaymentTimerFor(tag: tag)
        }
    }
    
    func resetInvoicePaymentTimerFor(tag: String) {
        let timer = paymentTimeoutTimers[tag]
        timer?.invalidate()
        paymentTimeoutTimers[tag] = nil
    }
    
    ///Pyaing invoice message
    func payInvoiceMessage(
        message: TransactionMessage
    ) {
        payInvoiceMessage(
            invoice: message.invoice,
            paymentHash: message.paymentHash,
            message: message
        )
    }
    
    func payInvoiceMessage(
        invoice: String?,
        paymentHash: String? = nil,
        message: TransactionMessage? = nil
    ) {
        guard let invoiceDict = getInvoiceDetails(invoice: invoice ?? "") else {
            return
        }
        
        let paymentHash = invoiceDict.paymentHash ?? paymentHash
        if let paymentHash = paymentHash, hasLocalAlreadyPaidRecord(forPaymentHash: paymentHash) {
            handleLocalAlreadyPaid(paymentHash: paymentHash, useAlert: true)
            return
        }
        
        guard let owner = UserContact.getOwner(),
              let _ = owner.nickname,
              let pubkey = invoiceDict.pubkey,
              let amount = invoiceDict.value else
        {
            return
        }
        
        if let paymentHash = paymentHash {
            insertInFlightPaymentHash(paymentHash)
        }
        
        checkAndFetchRouteTo(
            publicKey: pubkey,
            routeHint: invoiceDict.hopHints?.last,
            amtMsat: Int(UInt64(amount))
        ) { success in
            if success {
                if let message = message {
                    self.finalizePayInvoiceMessage(message: message, paymentHash: paymentHash)
                } else {
                    self.removeInFlightPaymentHash(paymentHash)
                }
            } else {
                self.removeInFlightPaymentHash(paymentHash)
                ///error getting route info
                DispatchQueue.main.async {
                    AlertHelper.showAlert(
                        title: "Routing Error",
                        message: "Could not find a route to the target. Please try again."
                    )
                }
            }
        }
    }
    
    func finalizePayInvoiceMessage(
        message: TransactionMessage,
        paymentHash: String? = nil
    ) {
        guard message.type == TransactionMessage.TransactionMessageType.invoice.rawValue,
              let rawInvoice = message.invoice,
              let seed = getAccountSeed(),
              let owner = UserContact.getOwner(),
              let nickname = owner.nickname else
        {
            removeInFlightPaymentHash(paymentHash)
            return
        }

        let invoice = rawInvoice.components(separatedBy: .whitespacesAndNewlines).joined()
        let paymentHash = paymentHash ?? getInvoiceDetails(invoice: invoice)?.paymentHash ?? message.paymentHash

        do {
            let rr = try executeSimulatedOrRealPay {
                try Sphinx.payContactInvoice(
                    seed: seed,
                    uniqueTime: getTimeWithEntropy(),
                    state: loadOnionStateAsData(),
                    bolt11: invoice,
                    myAlias: nickname,
                    myImg: owner.avatarUrl ?? "",
                    isTribe: false
                )
            }
            let _ = handleRunReturn(rr: rr)
            
            if isInvoiceAlreadyPaidError(rr.error) {
                handleNetworkAlreadyPaid(paymentHash: paymentHash, useAlert: true)
                return
            }
            removeInFlightPaymentHash(paymentHash)
        } catch let error {
            if isInvoiceAlreadyPaidSphinxError(error) {
                handleNetworkAlreadyPaid(paymentHash: paymentHash, useAlert: true)
                return
            }
            removeInFlightPaymentHash(paymentHash)
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
        amt: Double,
        data: Data? = nil,
        completion: @escaping (Bool) -> ()
    ) {
        checkAndFetchRouteTo(
            publicKey: pubkey,
            routeHint: routeHint,
            amtMsat: Int(amt * 1000)
        ) { success in
            if success {
                if self.finalizeKeysend(
                    pubkey: pubkey,
                    routeHint: routeHint,
                    amt: Int(amt * 1000),
                    data: data
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
        amt: Int,
        data: Data? = nil
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
                data: data,
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
                since: sinceTimestamp,
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
