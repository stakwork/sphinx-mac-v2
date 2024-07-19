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
    let som = SphinxOnionManager.sharedInstance
    
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
        
        som.inviteCreationCallback = handleInviteCodeAck
        let (success, errorMsg) = som.requestInviteCode(amountMsat: amountSats * 1000)
        
        if !success {
            inviteFailed(error: errorMsg)
        }
    }
    
    func inviteFailed(error: String?) {
        // Show an alert to the user
        loading = false
        
        AlertHelper.showAlert(
            title: "Invite Error",
            message: (error != nil) ? "Error: \(error!)" : "There was an error creating the invite"
        )
        
        // Remove the observer for invite code ACK
        som.inviteCreationCallback = nil
    }
    
    func handleInviteCodeAck(
        inviteCode: String?
    ){
        guard let inviteCode = inviteCode else {
            AlertHelper.showAlert(
                title: "generic.error.title".localized,
                message: "generic.error.message".localized
            )
            return
        }
        
        let nickname = nicknameField.stringValue
        som.createContactForInvite(code: inviteCode, nickname: nickname)
        ClipboardHelper.copyToClipboard(text: inviteCode)
        
        som.inviteCreationCallback = nil
        
        loading = false
        dismissDelegate?.shouldDismissView()
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
