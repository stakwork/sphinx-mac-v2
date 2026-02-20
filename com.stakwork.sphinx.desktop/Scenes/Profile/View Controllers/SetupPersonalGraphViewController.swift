//
//  SetupPersonalGraphViewController.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 10/11/2025.
//  Copyright © 2025 Tomas Timinskas. All rights reserved.
//

import Cocoa

class SetupPersonalGraphViewController: NSViewController {
    
    @IBOutlet weak var graphLabelField: SignupFieldView!
    @IBOutlet weak var graphUrlField: SignupFieldView!
    @IBOutlet weak var tokenFieldView: SignupFieldView!
    @IBOutlet weak var confirmButtonView: SignupButtonView!
    
    let userData = UserData.sharedInstance
    
    var newMessageBubbleHelper = NewMessageBubbleHelper()
        
    public enum Fields: Int {
        case GraphLabel
        case GraphUrl
        case Token
    }
    
    static func instantiate() -> SetupPersonalGraphViewController {
        let viewController = StoryboardScene.Profile.setupPersonalGraphViewController.instantiate()
        return viewController
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        configureView()
    }
    
    func configureView() {
        confirmButtonView.configureWith(title: "confirm".localized, icon: "", tag: -1, delegate: self)
        confirmButtonView.buttonDisabled = true
        
        graphUrlField.configureWith(
            placeHolder: "Personal Graph Url",
            placeHolderColor: NSColor.Sphinx.SecondaryText,
            label: "Personal Graph Url",
            textColor: NSColor.white,
            backgroundColor: NSColor(hex: "#101317"),
            field: Fields.GraphUrl.rawValue,
            value: userData.getPersonalGraphValue(with: KeychainManager.KeychainKeys.personalGraphUrl),
            validationType: .url,
            delegate: self
        )
        
        tokenFieldView.configureWith(
            placeHolder: "API Token",
            placeHolderColor: NSColor.Sphinx.SecondaryText,
            label: "API Token",
            textColor: NSColor.white,
            backgroundColor: NSColor(hex: "#101317"),
            field: Fields.Token.rawValue,
            value: userData.getPersonalGraphValue(with: KeychainManager.KeychainKeys.personalGraphToken),
            validationType: .alphanumericOnly,
            delegate: self
        )
        
        graphLabelField.configureWith(
            placeHolder: "Graph Label",
            placeHolderColor: NSColor.Sphinx.SecondaryText,
            label: "Graph Label",
            textColor: NSColor.white,
            backgroundColor: NSColor(hex: "#101317"),
            field: Fields.GraphLabel.rawValue,
            value: userData.getPersonalGraphValue(with: KeychainManager.KeychainKeys.personalGraphLabel),
            validationType: .alphanumericWithSpaces(maxLength: 12),
            delegate: self
        )
    }
}

extension SetupPersonalGraphViewController : SignupButtonViewDelegate {
    func didClickButton(tag: Int) {
        let graphUrl = graphUrlField.getFieldValue()
        let token = tokenFieldView.getFieldValue()
        let graphLabel = graphLabelField.getFieldValue()
        
        guard graphLabel.isNotEmpty && graphLabel.count <= 12 else {
            valueNotValid(field: "Graph Label")
            return
        }
        
        guard token.isNotEmpty else {
            valueNotValid(field: "Token")
            return
        }
        
        guard graphUrl.isNotEmpty, graphUrl.isValidURL else {
            valueNotValid(field: "Graph Url")
            return
        }
        
        let didChangeGraphLabel = graphLabel != userData.getPersonalGraphValue(with: KeychainManager.KeychainKeys.personalGraphLabel)

        userData.save(personalGraphValue: graphUrl, for: KeychainManager.KeychainKeys.personalGraphUrl)
        userData.save(personalGraphValue: token, for: KeychainManager.KeychainKeys.personalGraphToken)
        userData.save(personalGraphValue: graphLabel, for: KeychainManager.KeychainKeys.personalGraphLabel)
        
        if didChangeGraphLabel {
            NotificationCenter.default.post(name: .onGraphLabelChanged, object: nil)
        }
        
        WindowsManager.sharedInstance.backToProfile()
    }
    
    func valueNotValid(field: String) {
        newMessageBubbleHelper.showGenericMessageView(
            text: "Value for \(field) not valid",
            delay: 3,
            textColor: NSColor.white,
            backColor: NSColor.Sphinx.BadgeRed,
            backAlpha: 1.0
        )
    }
}

extension SetupPersonalGraphViewController : SignupFieldViewDelegate {
    func didChangeText(text: String) {
        confirmButtonView.buttonDisabled = !isValid()
    }
    
    func isValid() -> Bool {
        return tokenFieldView.getFieldValue().isNotEmpty &&
        graphUrlField.getFieldValue().isValidURL &&
        graphLabelField.getFieldValue().isNotEmpty && graphLabelField.getFieldValue().count <= 12
    }
    
    func didUseTab(field: Int) {
        DispatchQueue.main.async {
            self.confirmButtonView.buttonDisabled = !self.isValid()
            
            let field = Fields(rawValue: field)
            switch (field) {
            case .GraphLabel:
                self.view.window?.makeFirstResponder(self.graphUrlField.getTextField())
                break
            case .GraphUrl:
                self.view.window?.makeFirstResponder(self.tokenFieldView.getTextField())
                break
            default:
                self.view.window?.makeFirstResponder(self.graphLabelField.getTextField())
                break
            }
        }
    }
}
