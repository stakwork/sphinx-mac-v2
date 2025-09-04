//
//  ShareInviteCodeViewController.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 09/06/2020.
//  Copyright © 2020 Sphinx. All rights reserved.
//

import Cocoa

class ShareInviteCodeViewController: NSViewController {
    
    var qrCodeString = ""
    
    @IBOutlet weak var qrCodeImageView: NSImageView!
    @IBOutlet weak var inviteCodeLabel: NSTextField!
    @IBOutlet weak var copyButton: CustomButton!
    
    public enum ViewMode: Int {
        case Invite = 0
        case PubKey = 1
        case TribeQR = 2
        case RouteHint = 3
        case Invoice = 4
        case Mnemonic = 5
    }
    
    var viewMode = ViewMode.Invite
    var copiedStrind = "code.copied.clipboard".localized
    
    static func instantiate(qrCodeString: String, viewMode: ViewMode) -> ShareInviteCodeViewController {
        let viewController = StoryboardScene.Invite.shareInviteCodeViewController.instantiate()
        viewController.qrCodeString = qrCodeString
        viewController.viewMode = viewMode
        return viewController
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        copyButton.cursor = .pointingHand
        qrCodeImageView.image = NSImage.qrCode(from: qrCodeString, size: qrCodeImageView.frame.size)
        inviteCodeLabel.stringValue = qrCodeString
        setViewTitle()
    }
    
    func setViewTitle() {
        switch (viewMode) {
        case .Invite:
            copiedStrind = "code.copied.clipboard".localized
        case .PubKey:
            copiedStrind = "pubkey.copied.clipboard".localized
        case .TribeQR:
            copiedStrind = "link.copied.clipboard".localized
        case .RouteHint:
            copiedStrind = "route.hint.copied.clipboard".localized
        case .Invoice:
            copiedStrind = "invoice.copied.clipboard".localized
        case .Mnemonic:
            copiedStrind = "profile.mnemonic-copied".localized
        }
    }
    
    @IBAction func copyButtonClicked(_ sender: Any) {
        ClipboardHelper.copyToClipboard(text: inviteCodeLabel.stringValue, message: copiedStrind)
    }
}
