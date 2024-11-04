//
//  WebAppHelper.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 19/08/2020.
//  Copyright © 2020 Sphinx. All rights reserved.
//

import Foundation
import WebKit
import SwiftyJSON
import ObjectMapper

protocol WebAppHelperDelegate : NSObject{
    func setBudget(budget:Int)
}

struct LSatInProgress {
    var paymentRequest: String
    var issuer: String
    var macaroon: String
    var identifier: String?
    var paymentHash: String?
    var publicKey: String?
    var preimage: String?
    var metadata: String?
    var paths: String?
    var dict: [String: AnyObject]
    
    init(
        paymentRequest: String,
        issuer: String,
        macaroon: String,
        dict: [String: AnyObject]
    ) {
        self.paymentRequest = paymentRequest
        self.issuer = issuer
        self.macaroon = macaroon
        self.dict = dict
    }
    
    func isValid() -> Bool {
        return
            identifier != nil && identifier!.isNotEmpty &&
            paymentHash != nil && paymentHash!.isNotEmpty &&
            publicKey != nil && publicKey!.isNotEmpty &&
            preimage != nil && preimage!.isNotEmpty
    }
}

class WebAppHelper : NSObject {
    
    public let messageHandler = "sphinx"
    
    var webView : WKWebView! = nil
    var authorizeHandler: (([String: AnyObject]) -> ())! = nil
    var authorizeBudgetHandler: (([String: AnyObject]) -> ())! = nil
    
    var persistingValues: [String: AnyObject] = [:]
    weak var delegate : WebAppHelperDelegate? = nil
    
    var lsatList = [LSATObject]()
    
    var lsatInProgress: LSatInProgress? = nil
    var lsatTimer: Timer? = nil
    
    func setWebView(
        _ webView: WKWebView,
        authorizeHandler: @escaping (([String: AnyObject]) -> ()),
        authorizeBudgetHandler: @escaping (([String: AnyObject]) -> ())
    ) {
        self.webView = webView
        self.authorizeHandler = authorizeHandler
        self.authorizeBudgetHandler = authorizeBudgetHandler
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: .invoiceIPaidSettled, object: nil)
    }
}

extension WebAppHelper : WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == messageHandler {
            guard let dict = message.body as? [String: AnyObject] else {
                return
            }
    
            if let type = dict["type"] as? String {
                switch(type) {
                case "AUTHORIZE":
                    authorizeHandler(dict)
                    break
                case "SETBUDGET":
                    saveValue(dict["amount"] as AnyObject, for: "budget")
                    authorizeBudgetHandler(dict)
                    break
                case "KEYSEND":
                    sendKeySend(dict)
                    break
                case "UPDATED":
                    sendUpdatedMessage(dict)
                    NotificationCenter.default.post(name: .onBalanceDidChange, object: nil)
                    break
                case "RELOAD":
                    sendReloadMessage(dict)
                    break
                case "PAYMENT":
                    sendPayment(dict)
                    break
                case "LSAT":
                    saveLSAT(dict)
                    break
                case "SAVEDATA":
                    saveGraphData(dict)
                case "GETLSAT":
                    getActiveLsat(dict)
                    break
                case "UPDATELSAT":
                    updateLsat(dict)
                    break
                case "GETPERSONDATA":
                    getPersonData(dict)
                    break
                case "SIGN":
                    signMessage(dict)
                    break
                case "GETBUDGET":
                    getBudget(dict)
                    break
                case "GETSIGNEDTOKEN":
                    getSignedToken(dict)
                case "GETSECONDBRAINLIST​​":
                    getSecondBrainList(dict)
                    break
                default:
                    defaultAction(dict)
                    break
                }
            }
        }
    }
    
    func getSecondBrainList(_ dict: [String: AnyObject]) {
        var params: [String: AnyObject] = [:]
        setTypeApplicationAndPassword(params: &params, dict: dict)
        let sbTribes = Chat.getAllSecondBrainTribes()
        
        if sbTribes.count > 0 {
            params["second_brain_list"] = sbTribes.filter({
                $0.secondBrainUrl != nil && $0.secondBrainUrl?.isNotEmpty == true
            }).compactMap({
                $0.secondBrainUrl ?? ""
            }) as? AnyObject
        }

        sendMessage(dict: params)
    }
    
    func getSignedToken(_ dict: [String: AnyObject]) {
        if let token = SphinxOnionManager.sharedInstance.getSignedToken() {
            var newDict = dict
            newDict["token"] = token as AnyObject

            self.getSignedTokenResponse(dict: newDict, success: true)
        } else {
            self.getSignedTokenResponse(dict: dict, success: false)
        }
    }
    
    func getSignedTokenResponse(dict: [String: AnyObject], success: Bool) {
        var params: [String: AnyObject] = [:]
        setTypeApplicationAndPassword(params: &params, dict: dict)
        params["success"] = success as AnyObject

        sendMessage(dict: params)
    }
    
    func jsonStringWithObject(obj: AnyObject) -> String? {
        let jsonData  = try? JSONSerialization.data(withJSONObject: obj, options: JSONSerialization.WritingOptions(rawValue: 0))
        
        if let jsonData = jsonData {
            return String(data: jsonData, encoding: .utf8)
        }
        
        return nil
    }
    
    func sendMessage(dict: [String: AnyObject]) {
        if let string = jsonStringWithObject(obj: dict as AnyObject) {
            let javascript = "window.sphinxMessage('\(string)')"
            webView.evaluateJavaScript(javascript, completionHandler: nil)
        }
    }
    
    func setTypeApplicationAndPassword(params: inout [String: AnyObject], dict: [String: AnyObject]) {
        let password = SymmetricEncryptionManager.randomString(length: 16)
        saveValue(password as AnyObject, for: "password")
        
        params["type"] = dict["type"] as AnyObject
        params["application"] = dict["application"] as AnyObject
        params["password"] = password as AnyObject
    }
    
    //AUTHORIZE
    func authorizeWebApp(amount: Int, dict: [String: AnyObject], completion: @escaping () -> ()) {
        if let challenge = dict["challenge"] as? String {
            signChallenge(amount: amount, challenge: challenge, dict: dict, completion: completion)
        } else {
            sendAuthorizeMessage(amount: amount, dict: dict, completion: completion)
        }
    }
    
    // AUTHORIZE Without Budget
    func authorizeNoBudget( dict: [String: AnyObject], completion: @escaping () -> ()) {
        sendAuthorizeMessage( dict: dict, completion: completion)
    }
    
    func sendAuthorizeMessage(amount: Int? = nil, signature: String? = nil, dict: [String: AnyObject], completion: @escaping () -> ()) {
        if let pubKey = UserData.sharedInstance.getUserPubKey() {
            var params: [String: AnyObject] = [:]
            setTypeApplicationAndPassword(params: &params, dict: dict)
            
            params["pubkey"] = pubKey as AnyObject
            
            saveValue(pubKey as AnyObject, for: "pubkey")
            
            if let signature = signature {
                params["signature"] = signature as AnyObject
            }
            
            if let amount = amount {
                params["budget"] = amount as AnyObject
                saveValue(amount as AnyObject, for: "budget")
            }
            
            sendMessage(dict: params)
            completion()
        }
    }
    
    func signChallenge(amount: Int, challenge: String, dict: [String: AnyObject], completion: @escaping () -> ()) {
        guard let sig = SphinxOnionManager.sharedInstance.signChallenge(challenge: challenge) else{
            return
        }
        self.sendAuthorizeMessage(amount: amount, signature: sig, dict: dict, completion: completion)
    }
    
    //UPDATED
    func sendUpdatedMessage(_ dict: [String: AnyObject]) {
        var params: [String: AnyObject] = [:]
        setTypeApplicationAndPassword(params: &params, dict: dict)
        sendMessage(dict: params)
    }
    
    //RELOAD
    func sendReloadMessage(_ dict: [String: AnyObject]) {
        let (success, budget, pubKey) = getReloadParams(dict: dict)
        var params: [String: AnyObject] = [:]
        params["success"] = success as AnyObject
        params["budget"] = budget as AnyObject
        params["pubkey"] = pubKey as AnyObject
        
        setTypeApplicationAndPassword(params: &params, dict: dict)
        sendMessage(dict: params)
    }
    
    func getReloadParams(dict: [String: AnyObject]) -> (Bool, Int, String) {
        let password: String? = getValue(withKey: "password")
        var budget = 0
        var pubKey = ""
        var success = false
        
        if let pass = dict["password"] as? String, pass == password {
            let savedBudget: Int? = getValue(withKey: "budget")
            let savedPubKey: String? = getValue(withKey: "pubkey")
            
            success = true
            budget = savedBudget ?? 0
            pubKey = savedPubKey ?? ""
        }
        
        return (success, budget, pubKey)
    }
    
    //KEYSEND
    func sendKeySendResponse(dict: [String: AnyObject], success: Bool) {
        var params: [String: AnyObject] = [:]
        setTypeApplicationAndPassword(params: &params, dict: dict)
        params["success"] = success as AnyObject
        
        sendMessage(dict: params)
    }
    
    func sendKeySend(_ dict: [String: AnyObject]) {
        if let dest = dict["dest"] as? String, let amt = dict["amt"] as? Int {
            if !checkCanPay(amount: amt) {
                self.sendKeySendResponse(dict: dict, success: false)
                return
            }
            
            SphinxOnionManager.sharedInstance.keysend(
                pubkey: dest,
                amt: Double(amt)
            ) { success in
                if success {
                    self.sendKeySendResponse(dict: dict, success: true)
                } else {
                    self.sendKeySendResponse(dict: dict, success: false)
                }
            }
        }
    }
    
    //Payment
    func sendPaymentResponse(dict: [String: AnyObject], success: Bool) {
        var params: [String: AnyObject] = [:]
        setTypeApplicationAndPassword(params: &params, dict: dict)
        params["success"] = success as AnyObject
        
        sendMessage(dict: params)
    }
    
    func defaultActionResponse(dict: [String: AnyObject]) {
        var params: [String: AnyObject] = [:]
        setTypeApplicationAndPassword(params: &params, dict: dict)
        params["msg"] = "Invalid Action" as AnyObject
        
        sendMessage(dict: params)
    }
    
    func sendPayment(_ dict: [String: AnyObject]) {
        if let paymentRequest = dict["paymentRequest"] as? String {
            
            let prDecoder = PaymentRequestDecoder()
            prDecoder.decodePaymentRequest(paymentRequest: paymentRequest)
            
            let amount = prDecoder.getAmount()
            
            if let amount = amount {
                
                if !checkCanPay(amount: amount) {
                    self.sendPaymentResponse(dict: dict, success: false)
                    return
                }
                
                SphinxOnionManager.sharedInstance.payInvoice(
                    invoice: paymentRequest,
                    callback: { success, errorMsg in
                        if success {
                            self.sendPaymentResponse(dict: dict, success: true)
                        } else {
                            self.sendPaymentResponse(dict: dict, success: false)
                        }
                    }
                )
            } else {
                self.sendPaymentResponse(dict: dict, success: false)
            }
        }
    }
    
    //Payment
    func sendLsatResponse(dict: [String: AnyObject], success: Bool) {
        var params: [String: AnyObject] = [:]
        setTypeApplicationAndPassword(params: &params, dict: dict)
        params["lsat"] = dict["lsat"] as AnyObject
        params["success"] = success as AnyObject
        
        let savedBudget: Int? = getValue(withKey: "budget")
        if let budget = savedBudget {
            params["budget"] = budget as AnyObject
            delegate?.setBudget(budget: budget)
        }
        sendMessage(dict: params)
    }
    
    func getLsatResponse(dict: [String: AnyObject], success: Bool) {
        var params: [String: AnyObject] = [:]
        setTypeApplicationAndPassword(params: &params, dict: dict)
        params["macaroon"] = dict["macaroon"] as AnyObject
        params["paymentRequest"] = dict["paymentRequest"] as AnyObject
        params["preimage"] = dict["preimage"] as AnyObject
        params["identifier"] = dict["identifier"] as AnyObject
        params["issuer"] = dict["issuer"] as AnyObject
        params["success"] = success as AnyObject
        params["status"] = dict["status"] as AnyObject
        params["paths"] = dict["paths"] as AnyObject
        sendMessage(dict: params)
    }
    
    func getPersonDataResponse(dict: [String: AnyObject], success: Bool) {
        var params: [String: AnyObject] = [:]
        setTypeApplicationAndPassword(params: &params, dict: dict)
        params["alias"] = dict["alias"] as AnyObject
        params["photoUrl"] = dict["photoUrl"] as AnyObject
        params["publicKey"] = dict["publicKey"] as AnyObject
    
        sendMessage(dict: params)
    }
    
    func updateLsatResponse(dict: [String: AnyObject], success: Bool) {
        var params: [String: AnyObject] = [:]
        setTypeApplicationAndPassword(params: &params, dict: dict)
        params["lsat"] = dict["lsat"] as AnyObject
        params["success"] = success as AnyObject
        sendMessage(dict: params)
    }
    
    func saveLSAT(_ dict: [String: AnyObject]) {
        if let paymentRequest = dict["paymentRequest"] as? String, let _ = dict["macaroon"] as? String {
            
            let prDecoder = PaymentRequestDecoder()
            prDecoder.decodePaymentRequest(paymentRequest: paymentRequest)
            
            let amount = prDecoder.getAmount()
            
            if let amount = amount {
                if !checkCanPay(amount: amount) {
                    sendLsatResponse(dict: dict, success: false)
                    return
                }
                saveLSatFrom(dict: dict)
            } else {
                sendLsatResponse(dict: dict, success: false)
            }
        }
    }
    
    func saveLSatFrom(
        dict: [String: AnyObject]
    ){
        guard let paymentRequest = dict["paymentRequest"] as? String,
              let macaroon = dict["macaroon"] as? String,
              let issuer = dict["issuer"] as? String else
        {
            self.sendLsatResponse(dict: dict, success: false)
            print("Missing required LSAT data.")
            return
        }
        
        lsatInProgress = LSatInProgress(
            paymentRequest: paymentRequest,
            issuer: issuer,
            macaroon: macaroon,
            dict: dict
        )
        
        let (identifier, error) = SphinxOnionManager.sharedInstance.getIdFromMacaroon(macaroon: macaroon)
        
        guard let identifier = identifier else {
            self.sendLsatResponse(dict: dict, success: false)
            print("Error getting identifier from Macarron: \(error ?? "").")
            return
        }
        
        lsatInProgress?.identifier = identifier
        
        if let _ = LSat.getLSatWith(identifier: identifier) {
            self.sendLsatResponse(dict: dict, success: false)
            print("Could not save LSat. LSat already exists.")
            return
        }
        
        guard let parsedInvoise = SphinxOnionManager.sharedInstance.getInvoiceDetails(invoice: paymentRequest) else {
            self.sendLsatResponse(dict: dict, success: false)
            print("Error parsing payment request")
            return
        }
        
        guard let paymentH = parsedInvoise.paymentHash, let pubkey = parsedInvoise.pubkey else {
            self.sendLsatResponse(dict: dict, success: false)
            print("Payment hash or Public Key couldn't be parsed.")
            return
        }
        
        lsatInProgress?.paymentHash = paymentH
        lsatInProgress?.publicKey = pubkey
        
        NotificationCenter.default.removeObserver(self, name: .invoiceIPaidSettled, object: nil)
        
        NotificationCenter.default.addObserver(
            forName: .invoiceIPaidSettled,
            object: nil,
            queue: OperationQueue.main
        ) { [weak self] (n: Notification) in
            self?.handlePaidInvoiceNotification(n: n)
        }
        
        startLsatTimer()
        
        SphinxOnionManager.sharedInstance.payInvoice(
            invoice: paymentRequest,
            callback: { success, errorMsg in
                if let _ = errorMsg, !success {
                    self.endLsatTime()
                }
            }
        )
    }
    
    func endLsatTime() {
        lsatTimer?.invalidate()
        lsatTimer = nil
    }
    
    func startLsatTimer() {
        lsatTimer?.invalidate()
        
        lsatTimer = Timer.scheduledTimer(
            timeInterval: 7.0,
            target: self,
            selector: #selector(lsatTimerFired),
            userInfo: nil,
            repeats: false
        )
    }
    
    @objc func lsatTimerFired() {
        NotificationCenter.default.removeObserver(self, name: .invoiceIPaidSettled, object: nil)
        
        if let dict = lsatInProgress?.dict {
            sendLsatResponse(dict: dict, success: false)
        }
        
        endLsatTime()
        lsatInProgress = nil
    }
    
    @objc func handlePaidInvoiceNotification(n: Notification) {
        if let paymentHash = n.userInfo?["payment_hash"] as? String,
           let preimage = n.userInfo?["preimage"] as? String,
           paymentHash == lsatInProgress?.paymentHash
        {
            lsatInProgress?.preimage = preimage
            
            if let lsatInProgress = lsatInProgress, lsatInProgress.isValid() {
                LSat.saveObjectFrom(lsatIP: lsatInProgress)
                
                var newDict = lsatInProgress.dict
                newDict["lsat"] = "LSAT \(lsatInProgress.macaroon):\(lsatInProgress.preimage ?? "")" as AnyObject

                self.sendLsatResponse(dict: newDict, success: true)
                
                self.lsatInProgress = nil
            }
        }
    }
    
    func sendSaveGraphResponse(dict: [String: AnyObject], success: Bool) {
        var params: [String: AnyObject] = [:]
        setTypeApplicationAndPassword(params: &params, dict: dict)
        params["lsat"] = dict["lsat"] as AnyObject
        params["success"] = success as AnyObject
        let savedBudget: Int? = getValue(withKey: "budget")
        if let budget = savedBudget {
            params["budget"] = budget as AnyObject
        }
        sendMessage(dict: params)
    }
    
    func saveGraphData(_ dict: [String: AnyObject]) {
        if let data = dict["data"] {
            if let type = data["type"] as? Int, let metaData = data["metaData"] as? AnyObject {
                
                let params = [
                    "type": type as AnyObject,
                    "meta_data": metaData as AnyObject
                ]
                
//                API.sharedInstance.saveGraphData(parameters: params, callback: { graphData in
//                    let newDict = dict
//                    self.sendLsatResponse(dict: newDict, success: true)
//                }, errorCallback: {
//                    self.sendLsatResponse(dict: dict, success: false)
//                })
                
                self.sendLsatResponse(dict: dict, success: false)
            }
        }
    }
    
    func signMessageResponse(dict: [String: AnyObject], success: Bool) {
        var params: [String: AnyObject] = [:]
        setTypeApplicationAndPassword(params: &params, dict: dict)
        params["signature"] = dict["signature"] as AnyObject
        params["success"] = success as AnyObject
        sendMessage(dict: params)
    }
    
    func signMessage(_ dict: [String: AnyObject]){
        if let message = dict["message"] as? String {
            guard let signature = SphinxOnionManager.sharedInstance.signChallenge(
                challenge: message
            ) else {
                self.signMessageResponse(dict: dict, success: false)
                return
            }
            
            var newDict = dict
            newDict["signature"] = signature as AnyObject
            self.signMessageResponse(dict: newDict, success: true)
        }
    }
    
    func updateLsat(_ dict: [String: AnyObject]) {
        if let identifier = dict["identifier"] as? String, let status = dict["status"] as? String {
            
            guard let lsat = LSat.getLSatWith(identifier: identifier) else {
                updateLsatResponse(dict: dict, success: false)
                return
            }
            
            if status == "expired" {
                lsat.status = LSat.LSatStatus.expired.rawValue
                lsat.managedObjectContext?.saveContext()
                
                var newDict = dict
                newDict["lsat"] = "LSAT \(lsat.macaroon):\(lsat.preimage ?? "")" as AnyObject
                
                updateLsatResponse(dict: newDict, success: true)
            }
        }
    }
    
    func decodeLsat(
        lsat: LSat,
        dict: [String: AnyObject]
    ) -> [String: AnyObject] {
        var newDict = dict
        
        if let preimage = lsat.preimage {
            newDict["macaroon"] = lsat.macaroon as AnyObject
            newDict["identifier"] = lsat.identifier as AnyObject
            newDict["preimage"] = preimage as AnyObject
            newDict["paymentRequest"] = lsat.paymentRequest as AnyObject
            newDict["issuer"] = (lsat.issuer ?? "") as AnyObject
            newDict["status"] = lsat.status as AnyObject
            
            if let paths = lsat.paths {
                newDict["paths"] = paths as AnyObject
            } else {
                newDict["paths"] = "" as AnyObject
            }
        }
        return newDict
    }
    
    func getActiveLsat(_ dict: [String: AnyObject]) {
        if let issuer = dict["issuer"] as? String {
            if let activeLSat = LSat.getActiveLSat(issuer: issuer) {
                let newDict = decodeLsat(lsat: activeLSat, dict: dict)
                getLsatResponse(dict: newDict, success: true)
            } else {
                print("failed to retrieve and active LSAT")
                getLsatResponse(dict: dict, success: false)
            }
        } else {
            if let activeLSat = LSat.getActiveLSat() {
                let newDict = decodeLsat(lsat: activeLSat, dict: dict)
                getLsatResponse(dict: newDict, success: true)
            } else {
                print("failed to retrieve and active LSAT")
                getLsatResponse(dict: dict, success: false)
            }
        }
    }
    
    func getPersonData(_ dict: [String: AnyObject]) {
        func getPersonData(_ dict: [String: AnyObject]) {
            if let ownerContact = UserContact.getOwner() {
                var newDict = dict
                newDict["alias"] = ownerContact.nickname as AnyObject
                newDict["publicKey"] = ownerContact.publicKey as AnyObject
                newDict["photoUrl"] = ownerContact.getPhotoUrl() as AnyObject
                getPersonDataResponse(dict: newDict, success: true)
            } else {
                getPersonDataResponse(dict: dict, success: false)
            }
        }
    }
    
    func getBudgetResponse(dict: [String: AnyObject], success: Bool) {
        var params: [String: AnyObject] = [:]
        setTypeApplicationAndPassword(params: &params, dict: dict)
        params["budget"] = dict["budget"] as AnyObject
        params["success"] = success as AnyObject

        sendMessage(dict: params)
    }

    func getBudget(_ dict: [String: AnyObject]) {
        let savedBudget: Int? = getValue(withKey: "budget")
        var newDict = dict
        newDict["budget"] = savedBudget as AnyObject

        self.getBudgetResponse(dict: newDict, success: true)
    }
    
    func defaultAction(_ dict: [String: AnyObject]){
        self.defaultActionResponse(dict: dict)
    }

    
    func getParams(pubKey: String, amount: Int) -> [String: AnyObject] {
        var parameters = [String : AnyObject]()
        parameters["amount"] = amount as AnyObject?
        parameters["destination_key"] = pubKey as AnyObject?
            
        return parameters
    }
    
    func saveValue(_ value: AnyObject, for key: String) {
        persistingValues[key] = value
    }
    
    func getValue<T>(withKey key: String) -> T? {
        if let value = persistingValues[key] as? T {
            return value
        }
        return nil
    }
    
    
    func checkCanPay(amount: Int) -> Bool {
        let savedBudget: Int? = getValue(withKey: "budget")
        
        if ((savedBudget ?? 0) < amount || amount == -1) {
            return false
        }
        
        if let savedBudget = savedBudget {
            let newBudget = savedBudget - amount
            saveValue(newBudget as AnyObject, for: "budget")
            return true
        }
        
        return false
    }

}
