//
//  DisplayInvoiceVC.swift
//  Sphinx
//
//  Created by James Carucci on 4/7/23.
//  Copyright © 2023 Tomas Timinskas. All rights reserved.
//

import Foundation
import Cocoa

class DisplayInvoiceVC : NSViewController{
    
    @IBOutlet weak var qrCodeImageView: NSImageView!
    @IBOutlet weak var shareInvoiceStringButton: NSView!
    @IBOutlet weak var shareQRImageButton: NSView!
    @IBOutlet weak var invoiceStringDisplay: NSTextField!
    @IBOutlet weak var amountTextField: NSTextField!
    @IBOutlet weak var codeStringLabel: VerticallyCenteredButtonCell!
    @IBOutlet weak var codeImageLabel: VerticallyCenteredButtonCell!
    @IBOutlet weak var paidLabelContainer: NSBox!
    
    var qrString : String? = nil
    var amount : Int? = nil
    
    var currentInvoicePaymentHash: String? {
        if let invoice = qrString,
           let parsedInvoiceDetails = SphinxOnionManager.sharedInstance.getInvoiceDetails(invoice: invoice),
           let paymentHash = parsedInvoiceDetails.paymentHash
        {
            return paymentHash
        }
        return nil
    }
    
    static func instantiate(
        qrCodeString:String,
        amount:Int
    ) -> DisplayInvoiceVC {
        let viewController = StoryboardScene.Payments.displayInvoiceVC.instantiate()
        viewController.qrString = qrCodeString
        viewController.amount = amount
        return viewController
    }
    
    
    override func viewDidLoad() {
        paidLabelContainer.alphaValue = 0.0
        
        if let qrString = qrString {
            qrCodeImageView.image = NSImage.qrCode(from: qrString, size: qrCodeImageView.frame.size)
            
            self.shareInvoiceStringButton.addGestureRecognizer(
                NSClickGestureRecognizer(target: self, action: #selector(self.copyInvoiceText))
            )
            
            self.shareQRImageButton.addGestureRecognizer(
                NSClickGestureRecognizer(target: self, action: #selector(self.copyInvoiceImage))
            )
            
            self.invoiceStringDisplay.stringValue = qrString
            
            var amountText = ""
            
            if let amount = self.amount {
                amountText = "\("notification.amount".localized) \(String(amount)) sats"
                self.view.bringSubviewToFront(self.amountTextField)
            }
            
            self.amountTextField.stringValue = amountText
            
        }
        
        self.addLocalization()
        
        NotificationCenter.default.removeObserver(
            self,
            name: .sentInvoiceSettled,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePaidInvoiceNotification),
            name: .sentInvoiceSettled,
            object: nil
        )
    }
    
    override func viewDidDisappear() {
        NotificationCenter.default.removeObserver(
            self,
            name: .sentInvoiceSettled,
            object: nil
        )
    }
    
    func addLocalization() {
        codeStringLabel.title = "copy.invoice.string".localized
        codeImageLabel.title = "copy.invoice.image".localized
    }
    
    @objc func handlePaidInvoiceNotification(n: Notification) {
        if let receivedPaymentHash = n.userInfo?["paymentHash"] as? String,
           let currentInvoicePaymentHash = currentInvoicePaymentHash,
           currentInvoicePaymentHash == receivedPaymentHash
        {
            togglePaidContainer()
        }
    }
    
    func togglePaidContainer() {
        AnimationHelper.animateViewWith(duration: 0.1, animationsBlock: {
            self.paidLabelContainer.alphaValue = 1.0
        }, completion: {})
    }
    
    @objc func copyInvoiceImage() {
        if let image = self.view.bitmapImage() {
            ClipboardHelper.addImageToClipboard(image: image)
        }
    }
    
    @objc func copyInvoiceText() {
        if let qrString = qrString {
            ClipboardHelper.copyToClipboard(text: qrString)
        }
    }
}
