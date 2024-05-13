//
//  NewInviteViewController.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 11/09/2020.
//  Copyright © 2020 Sphinx. All rights reserved.
//

import Cocoa

class NewInviteViewController: NSViewController {
    
    weak var delegate: NewContactChatDelegate?
    weak var dismissDelegate: NewContactDismissDelegate?
    
    @IBOutlet weak var nicknameField: NSTextField!
    @IBOutlet weak var amountField: NSTextField!
    @IBOutlet var messageTextView: PlaceHolderTextView!
    @IBOutlet weak var saveButtonContainer: NSView!
    @IBOutlet weak var saveButton: CustomButton!
    @IBOutlet weak var loadingWheel: NSProgressIndicator!
    
    let walletBalanceService = WalletBalanceService()
    
    var inviteRequestWatchdogTimer: Timer?
    
    static func instantiate(
        delegate: NewContactChatDelegate? = nil,
        dismissDelegate: NewContactDismissDelegate? = nil
    ) -> NewInviteViewController {
        
        let viewController = StoryboardScene.Contacts.newInviteViewController.instantiate()
        viewController.delegate = delegate
        viewController.dismissDelegate = dismissDelegate
        
        return viewController
    }
    
    var loading = false {
        didSet {
            LoadingWheelHelper.toggleLoadingWheel(loading: loading, loadingWheel: loadingWheel, color: NSColor.Sphinx.Text, controls: [saveButton])
        }
    }
    
    var saveEnabled = false {
        didSet {
            saveButtonContainer.alphaValue = saveEnabled ? 1.0 : 0.7
            saveButton.isEnabled = saveEnabled
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.view.alphaValue = 0.0
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        
        configureView()
        
        AnimationHelper.animateViewWith(duration: 0.2, animationsBlock: {
            self.view.alphaValue = 1.0
        })
    }
    
    func configureView() {
        saveEnabled = false
        
        nicknameField.delegate = self
        
        amountField.delegate = self
        amountField.formatter = IntegerValueFormatter()
        
        messageTextView.isEditable = true
        messageTextView.setPlaceHolder(color: NSColor.Sphinx.PlaceholderText, font: NSFont(name: "Roboto-Regular", size: 17.0)!, string: "welcome.to.sphinx".localized, alignment: .center)
        messageTextView.font = NSFont(name: "Roboto-Regular", size: 17.0)!
        messageTextView.alignment = .center
    }
    
    @IBAction func createInvitationButtonClicked(_ sender: Any) {
        let amount = amountField.stringValue
        
        guard let amountSats = Int(amount) else {
            return
        }
        
        loading = true
        inviteRequestWatchdogTimer = Timer.scheduledTimer(
            timeInterval: 10,
            target: self,
            selector: #selector(watchdogTimerFired),
            userInfo: nil,
            repeats: false
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInviteCodeAck(n:)),
            name: .inviteCodeAckReceived,
            object: nil
        )
        
        SphinxOnionManager.sharedInstance.requestInviteCode(amountMsat: amountSats * 1000)
    }
    
    @objc func watchdogTimerFired() {
        // Show an alert to the user
        loading = false
        
        AlertHelper.showAlert(title: "Timeout", message: "The operation has timed out. Please try again.")
        
        // Invalidate the timer
        inviteRequestWatchdogTimer?.invalidate()
        
        // Remove the observer for invite code ACK
        NotificationCenter.default.removeObserver(self, name: .inviteCodeAckReceived, object: nil)
        
        // Optionally, dismiss the view or handle the timeout appropriately
        // self.dismiss(animated: true, completion: nil)
    }
    
    @objc func handleInviteCodeAck(
        n: Notification
    ){
        guard let inviteCode = n.userInfo?["inviteCode"] as? String else{
            AlertHelper.showAlert(
                title: "generic.error.title".localized,
                message: "generic.error.message".localized
            )
            return
        }
        
        loading = false
        self.dismissDelegate?.shouldDismissView()
        
        let nickname = nicknameField.stringValue
        SphinxOnionManager.sharedInstance.createContactForInvite(code: inviteCode, nickname: nickname)
        ClipboardHelper.copyToClipboard(text: inviteCode)
        
        NotificationCenter.default.removeObserver(self, name: .inviteCodeAckReceived, object: nil)
    }
}

extension NewInviteViewController : NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        saveEnabled = shouldEnableSaveButton()
    }
    
    func shouldEnableSaveButton() -> Bool {
        return nicknameField.stringValue.isNotEmpty && amountField.stringValue.isNotEmpty
    }
}
