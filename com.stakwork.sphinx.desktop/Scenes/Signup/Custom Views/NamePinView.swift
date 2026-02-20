//
//  NamePinView.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 11/02/2021.
//  Copyright © 2021 Tomas Timinskas. All rights reserved.
//

import Cocoa
import SwiftyJSON

class NamePinView: NSView, LoadableNib {
    
    weak var delegate: WelcomeEmptyViewDelegate?

    @IBOutlet var contentView: NSView!
    @IBOutlet weak var nameField: SignupFieldView!
    @IBOutlet weak var pinField: SignupSecureFieldView!
    @IBOutlet weak var confirmPinField: SignupSecureFieldView!
    @IBOutlet weak var continueButton: SignupButtonView!
    @IBOutlet weak var loadingWheel: NSProgressIndicator!
    
    let messageBubbleHelper = NewMessageBubbleHelper()
    let userData = UserData.sharedInstance
    
    var signupMode: SignupHelper.SignupMode = .NewUser
    var isRestore: Bool {
        get {
            return signupMode == .ExistingUser
        }
    }
    
    var loading = false {
        didSet {
            LoadingWheelHelper.toggleLoadingWheel(loading: loading, loadingWheel: loadingWheel, color: NSColor.white, controls: [continueButton.getButton()])
        }
    }
    
    public enum Fields: Int {
        case Code
        case Name
        case PIN
        case ConfirmPIN
        case OldPIN
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        loadViewFromNib()
    }
    
    init(
        frame frameRect: NSRect,
        delegate: WelcomeEmptyViewDelegate,
        signupMode: SignupHelper.SignupMode
    ) {
        super.init(frame: frameRect)
        
        self.signupMode = signupMode
        self.delegate = delegate
        
        loadViewFromNib()
        configureView()
    }
    
    func setInitialFirstResponder() {
        window?.initialFirstResponder = nameField.getTextField()
    }
    
    func configureView() {
        continueButton.configureWith(title: "continue".localized.capitalized, icon: "", tag: -1, delegate: self)
        continueButton.setSignupColors()
        continueButton.buttonDisabled = true
        
        nameField.isHidden = isRestore
        nameField.getTextField().nextKeyView = pinField.getTextField()
        pinField.getTextField().nextKeyView = confirmPinField.getTextField()
        
        nameField.configureWith(
            placeHolder: "set.nickname".localized,
            placeHolderColor: NSColor(hex: "#3B4755"),
            label: "Nickname",
            textColor: NSColor.white,
            backgroundColor: NSColor(hex: "#101317"),
            field: Fields.Name.rawValue,
            delegate: self
        )
        
        pinField.configureWith(
            placeHolder: "set.pin".localized,
            label: "set.pin".localized,
            field: NamePinView.Fields.PIN.rawValue,
            delegate: self
        )
        
        confirmPinField.configureWith(
            placeHolder: "confirm.pin".localized,
            label: "confirm.pin".localized,
            field: NamePinView.Fields.ConfirmPIN.rawValue,
            delegate: self
        )
    }
    
    func getNickname() -> String {
        return nameField.getFieldValue()
    }
}

extension NamePinView : SignupButtonViewDelegate {
    func didClickButton(tag: Int) {
        if getNickname().isEmpty && !isRestore {
            showError()
        }
        
        loading = true
        
        if let owner = UserContact.getOwner() {
            if isRestore {
                continueRestore()
            } else {
                owner.nickname = nameField.getFieldValue()
                
                goToProfilePictureView()
            }
        } else {
            showError()
        }
    }
    
    func showError() {
        loading = false
        messageBubbleHelper.showGenericMessageView(text: "generic.error.message".localized)
    }
    
    func continueRestore() {
        loading = false
        
        UserData.sharedInstance.save(pin: pinField.getFieldValue())
        UserData.sharedInstance.signupStep = SignupHelper.SignupStep.ImageSet.rawValue
        
        delegate?.shouldContinueTo?(mode: -1)
    }
    
    func goToProfilePictureView() {
        loading = false
        
        UserData.sharedInstance.save(pin: pinField.getFieldValue())
        UserData.sharedInstance.signupStep = SignupHelper.SignupStep.PINNameSet.rawValue
        
        delegate?.shouldContinueTo?(mode: WelcomeLightningViewController.FormViewMode.Image.rawValue)
    }
    
    func isValid() -> Bool {
        return (!nameField.getFieldValue().isEmpty || isRestore) &&
            pinField.getFieldValue().length == 6 &&
            confirmPinField.getFieldValue().length == 6 &&
            pinField.getFieldValue() == confirmPinField.getFieldValue()
    }
    
    func pinDoNotMatch() -> Bool {
        return (!nameField.getFieldValue().isEmpty || isRestore) &&
            pinField.getFieldValue().length == 6 &&
            confirmPinField.getFieldValue().length == 6 &&
            pinField.getFieldValue() != confirmPinField.getFieldValue()
    }
}

extension NamePinView : SignupFieldViewDelegate {
    func didChangeText(text: String) {
        continueButton.buttonDisabled = !isValid()
        
        if pinDoNotMatch() {
            messageBubbleHelper.showGenericMessageView(
                text: "pins.do.not.match".localized,
                delay: 3,
                textColor: NSColor.white,
                backColor: NSColor.Sphinx.BadgeRed,
                backAlpha: 1.0
            )
        }
    }
    
    func didUseTab(field: Int) {
        let field = NamePinView.Fields(rawValue: field)
        switch (field) {
        case .Name:
            self.window?.makeFirstResponder(pinField.getTextField())
            break
        case .PIN:
            self.window?.makeFirstResponder(confirmPinField.getTextField())
            break
        default:
            self.window?.makeFirstResponder(nameField.getTextField())
            break
        }
    }
}
