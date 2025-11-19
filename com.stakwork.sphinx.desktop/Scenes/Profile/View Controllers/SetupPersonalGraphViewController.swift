//
//  SetupPersonalGraphViewController.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 10/11/2025.
//  Copyright © 2025 Tomas Timinskas. All rights reserved.
//

import Cocoa

class SetupPersonalGraphViewController: NSViewController {
    
    @IBOutlet weak var graphUrlField: SignupFieldView!
    @IBOutlet weak var tokenFieldView: SignupFieldView!
    @IBOutlet weak var workflowFieldView: SignupFieldView!
    @IBOutlet weak var confirmButtonView: SignupButtonView!
    
    let userData = UserData.sharedInstance
    
    var newMessageBubbleHelper = NewMessageBubbleHelper()
        
    public enum Fields: Int {
        case GraphUrl
        case Token
        case Workflow
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
            delegate: self
        )
        
        workflowFieldView.isHidden = true
        workflowFieldView.configureWith(
            placeHolder: "Workflow ID",
            placeHolderColor: NSColor.Sphinx.SecondaryText,
            label: "Workflow ID",
            textColor: NSColor.white,
            backgroundColor: NSColor(hex: "#101317"),
            field: Fields.Workflow.rawValue,
            value: userData.getPersonalGraphValue(with: KeychainManager.KeychainKeys.personalGraphWorkflowId),
            onlyNumbers: true,
            delegate: self
        )
    }
}

extension SetupPersonalGraphViewController : SignupButtonViewDelegate {
    func didClickButton(tag: Int) {
        let graphUrl = graphUrlField.getFieldValue()
        let token = tokenFieldView.getFieldValue()
//        let workflowIDString = workflowFieldView.getFieldValue()
        
//        guard let _ = Int(workflowIDString) else {
//            valueNotValid(field: "Media Workflow ID")
//            return
//        }
        
        guard token.isNotEmpty else {
            valueNotValid(field: "Token")
            return
        }
        
        guard graphUrl.isNotEmpty, graphUrl.isValidURL else {
            valueNotValid(field: "Graph Url")
            return
        }

        userData.save(personalGraphValue: graphUrl, for: KeychainManager.KeychainKeys.personalGraphUrl)
        userData.save(personalGraphValue: token, for: KeychainManager.KeychainKeys.personalGraphToken)
//        userData.save(personalGraphValue: workflowIDString, for: KeychainManager.KeychainKeys.personalGraphWorkflowId)
        
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
        return tokenFieldView.getFieldValue().length > 0 &&
        graphUrlField.getFieldValue().isValidURL
//        && workflowFieldView.getFieldValue().length > 0 && Int(workflowFieldView.getFieldValue()) != nil
    }
    
    func didUseTab(field: Int) {
        DispatchQueue.main.async {
            self.confirmButtonView.buttonDisabled = !self.isValid()
            
            let field = Fields(rawValue: field)
            switch (field) {
            case .GraphUrl:
                self.view.window?.makeFirstResponder(self.tokenFieldView.getTextField())
                break
//            case .Token:
//                self.view.window?.makeFirstResponder(self.workflowFieldView.getTextField())
//                break
            case .Workflow:
                self.view.window?.makeFirstResponder(self.graphUrlField.getTextField())
                break
            default:
                self.view.window?.makeFirstResponder(self.graphUrlField.getTextField())
                break
            }
        }
    }
}
