//
//  SendPaymentVC.swift
//  Sphinx
//
//  Created by James Carucci on 4/11/23.
//  Copyright © 2023 Tomas Timinskas. All rights reserved.
//

import Foundation
import Cocoa
import AVFoundation

class SendPaymentForInvoiceVC: NSViewController {
    
    @IBOutlet weak var titleLabel: NSTextField!
    @IBOutlet weak var addressField: NSTextField!
    @IBOutlet weak var confirmButton: NSView!
    @IBOutlet weak var paymentContainerView: NSView!
    @IBOutlet weak var paymentContainerAmountField: NSTextField!
    @IBOutlet weak var paymentContainerExpirationField: NSTextField!
    @IBOutlet weak var paymentContainerMemoField: NSTextField!
    @IBOutlet weak var payInvoiceButton: NSView!
    @IBOutlet weak var closeButton: NSButton!
    @IBOutlet weak var invoiceStringTitle: NSTextField!
    @IBOutlet weak var loadingWheel: NSProgressIndicator!
    
    @IBOutlet weak var verifyButton: CustomButton!
    @IBOutlet weak var payButton: CustomButton!
    @IBOutlet weak var invoiceDetailsCloseButton: CustomButton!
    
    @IBOutlet weak var invoiceAmountTitle: NSTextField!
    @IBOutlet weak var expirationDateTitle: NSTextField!
    @IBOutlet weak var memoTitle: NSTextField!
    
    @IBOutlet weak var paymentContainerBottomConstraint: NSLayoutConstraint!
    
    let prDecoder = PaymentRequestDecoder()
    var paymentTag: String? = nil
    var paymentTimer : Timer? = nil
    
    var loading = false {
        didSet {
            LoadingWheelHelper.toggleLoadingWheel(loading: loading, loadingWheel: loadingWheel, color: NSColor.Sphinx.Text, controls: [payButton])
        }
    }
    
    static func instantiate() -> SendPaymentForInvoiceVC {
        let viewController = StoryboardScene.Payments.sendPaymentVC.instantiate()
        return viewController
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        verifyButton.cursor = .pointingHand
        payButton.cursor = .pointingHand
        invoiceDetailsCloseButton.cursor = .pointingHand
    }
    
    @IBAction func verifyButtonClicked(_ sender: Any) {
        let code = addressField.stringValue
        let fixedCode = code.fixInvoiceString().trim()
        confirmButton.isHidden = fixedCode == ""
        
        validateQRString(string: fixedCode)
    }
    
    @IBAction func payButtonClicked(_ sender: Any) {
        if let invoice = prDecoder.paymentRequestString {
            payInvoice(invoice: invoice)
        }
    }
    
    func validateQRString(string: String) {
        if validateInvoice(string: string) {
            return
        }
        
        confirmButton.isHidden = false
        
        AlertHelper.showAlert(
            title: "sorry".localized,
            message: "code.not.recognized".localized
        )
    }
    
    func validateInvoice(string: String) -> Bool {
        prDecoder.decodePaymentRequest(paymentRequest: string)
        
        if prDecoder.isPaymentRequest() {
            DispatchQueue.main.async {
                self.showConfirmDetailsView()
            }
            return true
        }
        return false
    }
    
    func showConfirmDetailsView(){
        if let amount = self.prDecoder.getAmount(){
            paymentContainerAmountField.stringValue = "\(String(describing: amount))"
        }
        
        if let expirationDate = prDecoder.getExpirationDate() {
            if Date().timeIntervalSince1970 > expirationDate.timeIntervalSince1970 {
                paymentContainerExpirationField.stringValue = "expired".localized
                
                payInvoiceButton.alphaValue = 0.5
                payButton.isEnabled = false
                
            } else {
                payInvoiceButton.alphaValue = 1.0
                payButton.isEnabled = true
                
                let expirationDateString = expirationDate.getStringFromDate(
                    format:"EEE dd MMM HH:mm:ss",
                    timeZone: TimeZone.current
                )
                
                paymentContainerExpirationField.stringValue = expirationDateString
            }
        }
        
        if let memo = prDecoder.getMemo() {
            paymentContainerMemoField.stringValue = memo
        }
        
        self.animatePaymentContainer()
    }
    
    func animatePaymentContainer(show: Bool = true){
        paymentContainerBottomConstraint.constant = show ? 0 : -200
        
        AnimationHelper.animateViewWith(duration: 0.2, animationsBlock: {
            self.paymentContainerView.layoutSubtreeIfNeeded()
        })
    }
    
    func payInvoice(invoice: String) {
        if invoice.isEmpty {
            return
        }
        
        loading = true
        
        let prd = PaymentRequestDecoder()
        prd.decodePaymentRequest(paymentRequest: invoice)
        
        SphinxOnionManager.sharedInstance.payInvoice(invoice: invoice) { (success, errorMsg, tag) in
            if success {
                self.paymentTag = tag
                self.addPaymentObserver()
            } else {
                self.showErrorAlertAndDismiss(errorMsg: errorMsg)
            }
        }
    }
    
    func addPaymentObserver() {
        NotificationCenter.default.removeObserver(
            self,
            name: .onKeysendStatusReceived,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onKeysendStatusReceived),
            name: .onKeysendStatusReceived,
            object: nil
        )
        
        paymentTimer = Timer.scheduledTimer(
            timeInterval: 5.0,
            target: self,
            selector: #selector(self.showErrorAlertAndDismiss),
            userInfo: nil,
            repeats: false
        )
    }
    
    @objc func onKeysendStatusReceived(n: Notification) {
        if let tag = n.userInfo?["tag"] as? String,
           let status = n.userInfo?["status"] as? String {
            
            if tag == paymentTag {
                if status == SphinxOnionManager.kCompleteStatus {
                    resetTimerAndObserver()
                    dismissView()
                } else {
                    showErrorAlertAndDismiss()
                }
            }
        }
    }
    
    func resetTimerAndObserver() {
        paymentTag = nil
        
        paymentTimer?.invalidate()
        paymentTimer = nil
        
        NotificationCenter.default.removeObserver(
            self,
            name: .onKeysendStatusReceived,
            object: nil
        )
    }
    
    @objc func showErrorAlertAndDismiss(errorMsg: String? = nil) {
        resetTimerAndObserver()
        
        DispatchQueue.main.async {
            AlertHelper.showAlert(
                title: "generic.error.title".localized,
                message: errorMsg ?? "generic.error.message".localized
            ) {
                self.dismissView()
            }
        }
    }
    
    func dismissView() {
        resetTimerAndObserver()
        
        DispatchQueue.main.async {
            self.animatePaymentContainer(show: false)
            WindowsManager.sharedInstance.dismissViewFromCurrentWindow()
        }
    }
    
    @IBAction func closeTapped(_ sender: Any) {
        dismissView()
    }
    
}


