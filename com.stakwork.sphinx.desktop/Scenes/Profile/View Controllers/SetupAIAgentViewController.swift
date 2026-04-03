//
//  SetupAIAgentViewController.swift
//  sphinx
//
//  Created by Sphinx on 31/03/2026.
//  Copyright © 2026 sphinx. All rights reserved.
//

import Cocoa

class SetupAIAgentViewController: NSViewController {

    // MARK: - IBOutlets

    @IBOutlet weak var providerFieldView: SignupFieldView!
    @IBOutlet weak var apiKeyFieldView: SignupFieldView!
    @IBOutlet weak var confirmButtonView: SignupButtonView!

    // MARK: - Private

    let userData = UserData.sharedInstance
    var newMessageBubbleHelper = NewMessageBubbleHelper()

    public enum Fields: Int {
        case Provider = 0
        case APIKey   = 1
    }

    // MARK: - Instantiate

    static func instantiate() -> SetupAIAgentViewController {
        return StoryboardScene.Profile.setupAIAgentViewController.instantiate()
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
    }

    // MARK: - Configure

    private func configureView() {
        // Confirm button
        confirmButtonView.configureWith(title: "confirm".localized, icon: "", tag: -1, delegate: self)
        confirmButtonView.buttonDisabled = true

        // Provider field – display-only; opens menu on click
        let savedProvider = userData.getAIAgentValue(with: .aiAgentProvider)
            ?? AIAgentManager.AIProvider.anthropic.rawValue

        providerFieldView.configureWith(
            placeHolder: "Provider",
            placeHolderColor: NSColor.Sphinx.SecondaryText,
            label: "Provider",
            textColor: NSColor.white,
            backgroundColor: NSColor(hex: "#101317"),
            field: Fields.Provider.rawValue,
            value: savedProvider,
            validationType: nil,
            delegate: self
        )
        // Make provider field read-only — user picks via popup menu
        providerFieldView.getTextField().isEditable = false
        providerFieldView.getTextField().isSelectable = false

        // Add click gesture to show provider menu
        let click = NSClickGestureRecognizer(target: self, action: #selector(providerFieldTapped))
        providerFieldView.addGestureRecognizer(click)

        // API Key field
        apiKeyFieldView.configureWith(
            placeHolder: "API Key",
            placeHolderColor: NSColor.Sphinx.SecondaryText,
            label: "API Key",
            textColor: NSColor.white,
            backgroundColor: NSColor(hex: "#101317"),
            field: Fields.APIKey.rawValue,
            value: userData.getAIAgentValue(with: .aiAgentApiKey) ?? "",
            validationType: nil,
            delegate: self
        )

        updateConfirmButton()
    }

    // MARK: - Provider Popup Menu

    @objc private func providerFieldTapped() {
        let menu = NSMenu()
        for provider in AIAgentManager.AIProvider.allCases {
            let item = NSMenuItem(
                title: provider.rawValue,
                action: #selector(providerSelected(_:)),
                keyEquivalent: ""
            )
            item.target = self
            menu.addItem(item)
        }

        let fieldFrame = providerFieldView.convert(providerFieldView.bounds, to: nil)
        let origin = NSPoint(x: fieldFrame.minX, y: fieldFrame.minY)
        menu.popUp(positioning: nil, at: origin, in: self.view.window?.contentView)
    }

    @objc private func providerSelected(_ sender: NSMenuItem) {
        providerFieldView.set(fieldValue: sender.title)
        updateConfirmButton()
    }

    // MARK: - Validation

    private func isValid() -> Bool {
        return apiKeyFieldView.getFieldValue().trimmingCharacters(in: .whitespaces).isNotEmpty
    }

    private func updateConfirmButton() {
        confirmButtonView.buttonDisabled = !isValid()
    }
}

// MARK: - SignupButtonViewDelegate

extension SetupAIAgentViewController: SignupButtonViewDelegate {
    func didClickButton(tag: Int) {
        let apiKey = apiKeyFieldView.getFieldValue().trimmingCharacters(in: .whitespaces)
        let providerRaw = providerFieldView.getFieldValue().trimmingCharacters(in: .whitespaces)

        guard apiKey.isNotEmpty else {
            newMessageBubbleHelper.showGenericMessageView(
                text: "API key cannot be empty",
                delay: 3,
                textColor: .white,
                backColor: NSColor.Sphinx.BadgeRed,
                backAlpha: 1.0
            )
            return
        }

        let resolvedProvider = providerRaw.isEmpty
            ? AIAgentManager.AIProvider.anthropic.rawValue
            : providerRaw

        userData.save(aiAgentValue: resolvedProvider, for: .aiAgentProvider)
        userData.save(aiAgentValue: apiKey, for: .aiAgentApiKey)

        AIAgentManager.sharedInstance.reconfigure()

        Task { @MainActor in
            AIAgentManager.sharedInstance.createAgentContactAndChatIfNeeded()
        }

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
            let f = Fields(rawValue: field)
            switch f {
            case .Provider:
                self.view.window?.makeFirstResponder(self.apiKeyFieldView.getTextField())
            default:
                self.view.window?.makeFirstResponder(self.providerFieldView.getTextField())
            }
        }
    }
}
