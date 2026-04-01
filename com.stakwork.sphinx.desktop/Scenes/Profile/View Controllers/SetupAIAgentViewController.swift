//
//  SetupAIAgentViewController.swift
//  sphinx
//
//  Created by Sphinx on 01/04/2026.
//  Copyright © 2026 sphinx. All rights reserved.
//

import Cocoa

class SetupAIAgentViewController: NSViewController {

    // MARK: - Outlets

    @IBOutlet weak var providerFieldView: SignupFieldView!
    @IBOutlet weak var apiKeyFieldView: SignupFieldView!
    @IBOutlet weak var confirmButtonView: SignupButtonView!

    // MARK: - State

    let userData = UserData.sharedInstance
    var newMessageBubbleHelper = NewMessageBubbleHelper()

    private var selectedProvider: AIAgentManager.AIProvider = .anthropic

    public enum Fields: Int {
        case provider = 0
        case apiKey   = 1
    }

    // MARK: - Instantiate

    static func instantiate() -> SetupAIAgentViewController {
        return StoryboardScene.Profile.setupAIAgentViewController.instantiate()
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        loadSavedValues()
    }

    // MARK: - Setup

    func configureView() {
        confirmButtonView.configureWith(
            title: "confirm".localized,
            icon: "",
            tag: -1,
            delegate: self
        )
        confirmButtonView.buttonDisabled = true

        // Provider — same style as other fields but non-editable; tap to pick
        providerFieldView.configureWith(
            placeHolder: "Select Provider",
            placeHolderColor: NSColor.Sphinx.SecondaryText,
            label: "Provider",
            textColor: NSColor.white,
            backgroundColor: NSColor(hex: "#101317"),
            field: Fields.provider.rawValue,
            value: nil,
            validationType: nil,
            delegate: self
        )
        let tf = providerFieldView.getTextField()
        tf.isEditable   = false
        tf.isSelectable = false

        // Intercept mouse-down on the provider field to show picker
        let click = NSClickGestureRecognizer(target: self, action: #selector(providerFieldTapped))
        providerFieldView.addGestureRecognizer(click)

        // API Key field
        apiKeyFieldView.configureWith(
            placeHolder: "API Key",
            placeHolderColor: NSColor.Sphinx.SecondaryText,
            label: "API Key",
            textColor: NSColor.white,
            backgroundColor: NSColor(hex: "#101317"),
            field: Fields.apiKey.rawValue,
            value: nil,
            validationType: nil,
            delegate: self
        )
    }

    // MARK: - Provider picker

    @objc private func providerFieldTapped() {
        let menu = NSMenu()
        for provider in AIAgentManager.AIProvider.allCases {
            let item = NSMenuItem(
                title: provider.rawValue,
                action: #selector(providerSelected(_:)),
                keyEquivalent: ""
            )
            item.representedObject = provider
            item.state = (provider == selectedProvider) ? .on : .off
            menu.addItem(item)
        }
        let origin = NSPoint(x: 0, y: providerFieldView.bounds.height)
        menu.popUp(positioning: nil, at: origin, in: providerFieldView)
    }

    @objc private func providerSelected(_ sender: NSMenuItem) {
        guard let provider = sender.representedObject as? AIAgentManager.AIProvider else { return }
        selectedProvider = provider
        providerFieldView.set(fieldValue: provider.rawValue)
        updateConfirmButton()
    }

    // MARK: - Load saved values

    private func loadSavedValues() {
        if let raw = userData.getAIAgentValue(with: .aiAgentProvider),
           let saved = AIAgentManager.AIProvider(rawValue: raw) {
            selectedProvider = saved
        }
        providerFieldView.set(fieldValue: selectedProvider.rawValue)

        if let key = userData.getAIAgentValue(with: .aiAgentApiKey) {
            apiKeyFieldView.set(fieldValue: key)
        }

        updateConfirmButton()
    }

    // MARK: - Validation

    private func isValid() -> Bool {
        return apiKeyFieldView.getFieldValue().isNotEmpty
    }

    private func updateConfirmButton() {
        confirmButtonView.buttonDisabled = !isValid()
    }
}

// MARK: - Actions

extension SetupAIAgentViewController: SignupButtonViewDelegate {
    func didClickButton(tag: Int) {
        let key = apiKeyFieldView.getFieldValue()

        guard key.isNotEmpty else {
            newMessageBubbleHelper.showGenericMessageView(
                text: "API key cannot be empty",
                delay: 3,
                textColor: NSColor.white,
                backColor: NSColor.Sphinx.BadgeRed,
                backAlpha: 1.0
            )
            return
        }

        userData.save(aiAgentValue: selectedProvider.rawValue, for: .aiAgentProvider)
        userData.save(aiAgentValue: key, for: .aiAgentApiKey)

        AIAgentManager.sharedInstance.reconfigure()
        WindowsManager.sharedInstance.backToProfile()
    }
}

// MARK: - SignupFieldViewDelegate

extension SetupAIAgentViewController: SignupFieldViewDelegate {
    func didChangeText(text: String) {
        updateConfirmButton()
    }

    func didUseTab(field: Int) {
        DispatchQueue.main.async {
            self.updateConfirmButton()
            if Fields(rawValue: field) == .provider {
                self.view.window?.makeFirstResponder(self.apiKeyFieldView.getTextField())
            } else {
                self.view.window?.makeFirstResponder(self.providerFieldView.getTextField())
            }
        }
    }
}
