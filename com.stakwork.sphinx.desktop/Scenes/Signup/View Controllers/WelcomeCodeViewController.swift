//
//  WelcomeCodeViewController.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 10/02/2021.
//  Copyright © 2021 Tomas Timinskas. All rights reserved.
//

import Cocoa

class WelcomeCodeViewController: NSViewController {
    
    @IBOutlet weak var leftContainer: NSView!
    @IBOutlet weak var leftContainerLabel: NSTextField!
    @IBOutlet weak var leftImageView: AspectFillNSImageView!
    @IBOutlet weak var rightContainer: NSView!
    @IBOutlet weak var rightContainerWidth: NSLayoutConstraint!
    @IBOutlet weak var titleLabel: NSTextField!
    @IBOutlet weak var backButton: CustomButton!
    @IBOutlet weak var pinBackButtonContainer: NSView!
    @IBOutlet weak var pinBackButton: CustomButton!
    @IBOutlet weak var codeField: SignupFieldView!
    @IBOutlet weak var submitButton: SignupButtonView!
    @IBOutlet weak var loadingWheel: NSProgressIndicator!
    @IBOutlet weak var pinView: PinView!
    @IBOutlet weak var importSeedView: ImportSeedView!
    
    var loading = false {
        didSet {
            LoadingWheelHelper.toggleLoadingWheel(loading: loading, loadingWheel: loadingWheel, color: NSColor.white, controls: [submitButton.getButton()])
        }
    }
    
    var mode = SignupHelper.SignupMode.NewUser
    
    let messageBubbleHelper = NewMessageBubbleHelper()
    let userData = UserData.sharedInstance
    let som = SphinxOnionManager.sharedInstance
    
    static func instantiate(
        mode: SignupHelper.SignupMode
    ) -> WelcomeCodeViewController {
        let viewController = StoryboardScene.Signup.welcomeCodeViewController.instantiate()
        viewController.mode = mode
        return viewController
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        pinView.alphaValue = 0.0
        pinView.configureForSignup()
        pinView.bringSubviewToFront(pinBackButtonContainer)
        
        backButton.cursor = .pointingHand
        pinBackButton.cursor = .pointingHand
        
        leftContainer.alphaValue = 0.0
        rightContainer.alphaValue = 0.0
        
        titleLabel.stringValue = (isNewUser ? "new.user" : "connect").localized.uppercased()
        
        submitButton.configureWith(title: "submit".localized, icon: "", tag: -1, delegate: self)
        submitButton.setSignupColors()
        submitButton.buttonDisabled = true
        
        let placeholder = isNewUser ? "paste.invitation.code" : "paste.keys"
        codeField.configureWith(placeHolder: placeholder.localized, label: "", backgroundColor: NSColor.white, field: .Code, delegate: self)
        
        let label = (isNewUser ? "signup.label" : "restore.label").localized
        let boldLabels = isNewUser ? ["signup.label.bold.1".localized, "signup.label.bold.2".localized] : ["restore.label.bold".localized]
        
        leftContainerLabel.attributedStringValue = String.getAttributedText(
            string: label,
            boldStrings: boldLabels,
            font: NSFont(name: "Roboto-Light", size: 15.0)!,
            boldFont: NSFont(name: "Roboto-Bold", size: 15.0)!
        )
        
        leftImageView.image = NSImage(named: isNewUser ? "newUserImage" : "existingUserImage")
    }
    
    var isNewUser: Bool {
        get {
            return mode == .NewUser
        }
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        
        AnimationHelper.animateViewWith(duration: 0.3, animationsBlock: {
            self.leftContainer.alphaValue = 1.0
            self.rightContainer.alphaValue = 1.0
        })
    }
    
    @IBAction func backButtonClicked(_ sender: NSButton) {
        self.view.window?.replaceContentBy(vc: WelcomeInitialViewController.instantiate())
    }
    
    @IBAction func pinBackButtonClicked(_ sender: NSButton) {
        loading = false
        animatePinContainer(expanded: false, completion: {
            self.pinView.isHidden = true
        })
    }
}

extension WelcomeCodeViewController : SignupButtonViewDelegate {
    func didClickButton(tag: Int) {
        let code = codeField.getFieldValue()
        
        if validateCode(code: code) {
            loading = true
            
            if code.isV2InviteCode {
                startSignup(code: code)
            } else {
                showPINView(encryptedKeys: code)
            }
        }
    }
    
    func startSignup(code: String) {
        signupWith(sphinxV2Code: code)
    }
    
    func signupWith(
        sphinxV2Code: String
    ) {
        som.vc = self
        som.chooseImportOrGenerateSeed(completion: {success in
            if (success) {
                self.handleInviteCodeV2SignUp(code: sphinxV2Code)
            } else {
                AlertHelper.showAlert(title: "Error redeeming invite", message: "Please try again or ask for another invite.")
            }
            self.som.vc = nil
        })
    }
    
    func handleInviteCodeV2SignUp(code: String){
        guard let mnemonic = UserData.sharedInstance.getMnemonic() else {
            return
        }
        
        if som.createMyAccount(mnemonic: mnemonic) {
            som.redeemInvite(inviteCode: code, mnemonic: mnemonic)
            signup_v2_with_test_server()
        }
    }
    
    func signup_v2_with_test_server(){
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: {
            if let contact = self.som.pendingContact, contact.isOwner == true {
                self.som.isV2InitialSetup = true
                self.continueToConnectingView(mode: .NewUser)
            } else {
                AlertHelper.showAlert(title: "Error", message: "Unable to connect to Sphinx V2 Test Server")
            }
        })
        
    }
    
    func showPINView(encryptedKeys: String) {
        UserDefaults.Keys.defaultPIN.removeValue()
        pinView.doneCompletion = { pin in
            
        }
        pinView.isHidden = false
        animatePinContainer(expanded: true)
    }
    
    func animatePinContainer(expanded: Bool, completion: (() -> ())? = nil) {
        let windowsWidth = (view.window ?? NSApplication.shared.keyWindow)?.frame.width
        let expectedWidth = expanded ? ((windowsWidth ?? 800) / 2) : 0
        
        if expectedWidth == rightContainerWidth.constant {
            return
        }
        pinView.reset()
        pinView.alphaValue = 0.0
        rightContainer.alphaValue = 0.0
        
        rightContainerWidth.constant = expectedWidth
        AnimationHelper.animateViewWith(duration: 0.5, animationsBlock: {
            self.view.layoutSubtreeIfNeeded()
        }, completion: {
            AnimationHelper.animateViewWith(duration: 0.2, animationsBlock: {
                self.rightContainer.alphaValue = expanded ? 0.0 : 1.0
                self.pinView.alphaValue = expanded ? 1.0 : 0.0
            }, completion: {
                self.pinView.makeFieldFirstResponder()
                completion?()
            })
        })
    }
    
    func continueToConnectingView(
        mode: SignupHelper.SignupMode
    ) {
        UserDefaults.Keys.lastPinDate.set(Date())
        view.window?.replaceContentBy(
            vc: WelcomeEmptyViewController.instantiate(
                mode: mode,
                viewMode: .Connecting
            )
        )
    }
}

extension WelcomeCodeViewController : SignupFieldViewDelegate {
    func didChangeText(text: String) {
        if text == NSPasteboard.general.string(forType: .string) {
            let valid = validateCode(code: text)
            submitButton.buttonDisabled = !valid
            return
        }
        submitButton.buttonDisabled = text.isEmpty
    }
    
    func validateCode(code: String) -> Bool {
        if code.isV2InviteCode {
            return true
        }
        
        if code.isPubKey {
            messageBubbleHelper.showGenericMessageView(text: "invalid.code.pubkey".localized, position: .Bottom, delay: 7, textColor: NSColor.white, backColor: NSColor.Sphinx.BadgeRed, backAlpha: 1.0, withLink: "https://sphinx.chat")
            return false
        } else if code.isLNDInvoice {
            messageBubbleHelper.showGenericMessageView(text: "invalid.code.invoice".localized, position: .Bottom, delay: 7, textColor: NSColor.white, backColor: NSColor.Sphinx.BadgeRed, backAlpha: 1.0, withLink: "https://sphinx.chat")
            return false
        }

        let errorMessage = (isNewUser ? "invalid.code" : "invalid.restore.code").localized
        messageBubbleHelper.showGenericMessageView(text: errorMessage, position: .Bottom, delay: 7, textColor: NSColor.white, backColor: NSColor.Sphinx.BadgeRed, backAlpha: 1.0, withLink: "https://sphinx.chat")
        return false
    }
}

extension WelcomeCodeViewController : ImportSeedViewDelegate {
    func showImportSeedView() {
        importSeedView.delegate = self
        importSeedView.isHidden = false
    }
    
    func showImportSeedView(
        network: String,
        host: String,
        relay: String
    ){
        importSeedView.showWith(
            delegate: self,
            network: network,
            host: host,
            relay: relay
        )
        importSeedView.isHidden = false
    }
    
    func didTapCancelImportSeed() {
        importSeedView.isHidden = true
    }
    
    func didTapConfirm() {
        importSeedView.isHidden = true
        UserData.sharedInstance.save(walletMnemonic: importSeedView.getMnemonicWords())
        
        let code = codeField.getFieldValue()
        
        if validateCode(code: code) {
            handleInviteCodeV2SignUp(code: code)
        }
    }
    
}
