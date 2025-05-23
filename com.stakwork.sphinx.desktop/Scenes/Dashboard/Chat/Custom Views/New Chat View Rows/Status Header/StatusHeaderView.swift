//
//  StatusHeaderView.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 19/07/2023.
//  Copyright © 2023 Tomas Timinskas. All rights reserved.
//

import Cocoa

class StatusHeaderView: NSView, LoadableNib {
    
    @IBOutlet var contentView: NSView!
    
    @IBOutlet weak var receivedStatusHeader: NSStackView!
    @IBOutlet weak var receivedSenderLabel: NSTextField!
    @IBOutlet weak var receivedDateLabel: NSTextField!
    @IBOutlet weak var receivedLockIcon: NSTextField!
    
    @IBOutlet weak var sentStatusHeader: NSStackView!
    @IBOutlet weak var sentScheduleIcon: NSTextField!
    @IBOutlet weak var sentDateLabel: NSTextField!
    @IBOutlet weak var sentLockIcon: NSTextField!
    @IBOutlet weak var sentLightningIcon: NSTextField!
    
    @IBOutlet weak var sentFailureHeader: NSStackView!
    @IBOutlet weak var sentErrorMessage: NSTextField!
    @IBOutlet weak var sentErrorIcon: NSTextField!
    
    @IBOutlet weak var uploadingHeader: NSStackView!
    @IBOutlet weak var uploadingLabel: NSTextField!
    
    @IBOutlet weak var expiredInvoiceSentHeader: NSStackView!
    @IBOutlet weak var expiredInvoiceSentLabel: NSTextField!
    
    @IBOutlet weak var expiredInvoiceReceivedHeader: NSStackView!
    @IBOutlet weak var expiredInvoiceReceivedLabel: NSTextField!
    
    @IBOutlet weak var remoteTimezoneIdentifier: NSTextField!
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        loadViewFromNib()
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        loadViewFromNib()
    }
    
    func configureWith(
        direction:  MessageTableCellState.MessageDirection
    ) {
        let outgoing = direction == .Outgoing
        
        receivedStatusHeader.isHidden = outgoing
        sentStatusHeader.isHidden = !outgoing
    }
    
    func configureWith(
        statusHeader: BubbleMessageLayoutState.StatusHeader,
        uploadProgressData: MessageTableCellState.UploadProgressData?
    ) {
        if let senderName = statusHeader.senderName {
            receivedSenderLabel.isHidden = false
            receivedSenderLabel.stringValue = senderName
        } else {
            receivedSenderLabel.isHidden = true
        }
        
        receivedSenderLabel.textColor = statusHeader.color
        
        sentLightningIcon.isHidden = !statusHeader.showBoltIcon && !statusHeader.showBoltGreyIcon
        sentLightningIcon.textColor = statusHeader.showBoltGreyIcon ? NSColor.Sphinx.SecondaryText : NSColor.Sphinx.PrimaryGreen
        
        sentLockIcon.isHidden = !statusHeader.showLockIcon
        receivedLockIcon.isHidden = !statusHeader.showLockIcon
        
        sentFailureHeader.isHidden = !statusHeader.showFailedContainer
        sentErrorMessage.stringValue = statusHeader.errorMessage
        
        receivedDateLabel.stringValue = statusHeader.timestamp
        sentDateLabel.stringValue = statusHeader.timestamp
        
        expiredInvoiceSentHeader.isHidden = !statusHeader.showExpiredSent
        expiredInvoiceReceivedHeader.isHidden = !statusHeader.showExpiredReceived
        
        configureWith(expirationTimestamp: statusHeader.expirationTimestamp)
        configureTimezoneWith(timezoneString: statusHeader.timezoneString)
        
        let thirtySecondsAgo = Date().addingTimeInterval(-30)
        let isScheduleVisible = statusHeader.showScheduleIcon && statusHeader.messageDate < thirtySecondsAgo
        sentScheduleIcon.isHidden = !isScheduleVisible
        
//        if !isScheduleVisible {
//            DelayPerformedHelper.performAfterDelay(seconds: 30, completion: { [weak self] in
//                guard let self = self else {
//                    return
//                }
//                        
//                let thirtySecondsAgo = Date().addingTimeInterval(-30)
//                let isScheduleVisible = !statusHeader.showBoltIcon && !statusHeader.showBoltGreyIcon && statusHeader.messageDate < thirtySecondsAgo
//                self.sentScheduleIcon.isHidden = !isScheduleVisible
//            })
//        }
        
        if let uploadProgressData = uploadProgressData {
            uploadingHeader.isHidden = false
            uploadingLabel.stringValue = String(format: "uploaded.progress".localized, uploadProgressData.progress)
        } else {
            uploadingHeader.isHidden = true
        }
    }
    
    func configureTimezoneWith(timezoneString: String?) {
        remoteTimezoneIdentifier.isHidden = true
        
        if let timezoneString = timezoneString {
            remoteTimezoneIdentifier.stringValue = "/  \(timezoneString)"
            remoteTimezoneIdentifier.isHidden = false
        }
    }
    
    func configureWith(
        expirationTimestamp: String?
    ) {
        if let expirationTimestamp = expirationTimestamp {
            expiredInvoiceSentLabel.stringValue = expirationTimestamp
            expiredInvoiceReceivedLabel.stringValue = expirationTimestamp
        } else {
            expiredInvoiceSentLabel.stringValue = "expired.invoice".localized
            expiredInvoiceReceivedLabel.stringValue = "expired.invoice".localized
        }
    }
    
}
