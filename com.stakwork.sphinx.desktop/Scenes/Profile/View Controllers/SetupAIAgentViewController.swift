//
//  SetupAIAgentViewController.swift
//  sphinx
//
//  Created by Sphinx on 31/03/2026.
//  Copyright © 2026 sphinx. All rights reserved.
//

import Cocoa

class SetupAIAgentViewController: NSViewController {

    // MARK: - UI Elements

    private let containerBox = NSBox()

    private let providerLabel  = NSTextField(labelWithString: "Provider")
    private let providerCombo  = NSComboBox()

    private let apiKeyLabel    = NSTextField(labelWithString: "API Key")
    private let apiKeyField    = NSTextField()

    private let confirmButtonView = SignupButtonView(frame: .zero)

    private var newMessageBubbleHelper = NewMessageBubbleHelper()

    // MARK: - Lifecycle

    static func instantiate() -> SetupAIAgentViewController {
        return SetupAIAgentViewController()
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadSavedValues()
    }

    // MARK: - Setup UI

    private func setupUI() {
        view.wantsLayer = true

        // Container box (matches SetupPersonalGraphViewController style)
        containerBox.boxType    = .custom
        containerBox.borderType = .noBorder
        containerBox.fillColor  = NSColor(named: "Body") ?? NSColor.windowBackgroundColor
        containerBox.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerBox)

        NSLayoutConstraint.activate([
            containerBox.topAnchor.constraint(equalTo: view.topAnchor),
            containerBox.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerBox.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerBox.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let content = containerBox.contentView!
        content.translatesAutoresizingMaskIntoConstraints = false

        // ── Provider label ──
        styleLabel(providerLabel, text: "Provider")
        content.addSubview(providerLabel)

        // ── Provider combo ──
        providerCombo.translatesAutoresizingMaskIntoConstraints = false
        providerCombo.isEditable = false
        providerCombo.font = NSFont(name: "Roboto-Regular", size: 14) ?? NSFont.systemFont(ofSize: 14)
        for p in AIAgentManager.AIProvider.allCases {
            providerCombo.addItem(withObjectValue: p.rawValue)
        }
        providerCombo.selectItem(at: 0)
        content.addSubview(providerCombo)

        // ── API Key label ──
        styleLabel(apiKeyLabel, text: "API Key")
        content.addSubview(apiKeyLabel)

        // ── API Key field ──
        apiKeyField.translatesAutoresizingMaskIntoConstraints = false
        apiKeyField.placeholderString = "Enter API key…"
        apiKeyField.font = NSFont(name: "Roboto-Regular", size: 14) ?? NSFont.systemFont(ofSize: 14)
        apiKeyField.backgroundColor = NSColor(hex: "#101317")
        apiKeyField.textColor        = .white
        apiKeyField.isBordered       = true
        apiKeyField.bezelStyle       = .roundedBezel
        apiKeyField.delegate         = self
        content.addSubview(apiKeyField)

        // ── Confirm button ──
        confirmButtonView.translatesAutoresizingMaskIntoConstraints = false
        confirmButtonView.configureWith(title: "confirm".localized, icon: "", tag: -1, delegate: self)
        confirmButtonView.buttonDisabled = true
        content.addSubview(confirmButtonView)

        // ── Layout ──
        NSLayoutConstraint.activate([
            providerLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 32),
            providerLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            providerLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),

            providerCombo.topAnchor.constraint(equalTo: providerLabel.bottomAnchor, constant: 6),
            providerCombo.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            providerCombo.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            providerCombo.heightAnchor.constraint(equalToConstant: 32),

            apiKeyLabel.topAnchor.constraint(equalTo: providerCombo.bottomAnchor, constant: 24),
            apiKeyLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            apiKeyLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),

            apiKeyField.topAnchor.constraint(equalTo: apiKeyLabel.bottomAnchor, constant: 6),
            apiKeyField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            apiKeyField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            apiKeyField.heightAnchor.constraint(equalToConstant: 32),

            confirmButtonView.topAnchor.constraint(equalTo: apiKeyField.bottomAnchor, constant: 32),
            confirmButtonView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            confirmButtonView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            confirmButtonView.heightAnchor.constraint(equalToConstant: 50),
            confirmButtonView.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -24)
        ])
    }

    private func styleLabel(_ label: NSTextField, text: String) {
        label.translatesAutoresizingMaskIntoConstraints = false
        label.stringValue = text
        label.font        = NSFont(name: "Roboto-Medium", size: 12) ?? NSFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor   = NSColor.Sphinx.SecondaryText
        label.isBordered  = false
        label.isEditable  = false
        label.backgroundColor = .clear
    }

    // MARK: - Load saved values

    private func loadSavedValues() {
        let userData = UserData.sharedInstance
        if let providerRaw = userData.getAIAgentValue(with: .aiAgentProvider),
           let idx = AIAgentManager.AIProvider.allCases.firstIndex(where: { $0.rawValue == providerRaw }) {
            providerCombo.selectItem(at: idx)
        }
        if let key = userData.getAIAgentValue(with: .aiAgentApiKey) {
            apiKeyField.stringValue = key
        }
        updateConfirmButton()
    }

    // MARK: - Validation

    private func isValid() -> Bool {
        return !apiKeyField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func updateConfirmButton() {
        confirmButtonView.buttonDisabled = !isValid()
    }
}

// MARK: - SignupButtonViewDelegate

extension SetupAIAgentViewController: SignupButtonViewDelegate {
    func didClickButton(tag: Int) {
        let key           = apiKeyField.stringValue.trimmingCharacters(in: .whitespaces)
        let providerRaw   = (providerCombo.objectValueOfSelectedItem as? String) ?? AIAgentManager.AIProvider.anthropic.rawValue

        guard !key.isEmpty else {
            newMessageBubbleHelper.showGenericMessageView(
                text: "API key cannot be empty",
                delay: 3,
                textColor: .white,
                backColor: NSColor.Sphinx.BadgeRed,
                backAlpha: 1.0
            )
            return
        }

        let userData = UserData.sharedInstance
        userData.save(aiAgentValue: providerRaw, for: .aiAgentProvider)
        userData.save(aiAgentValue: key,         for: .aiAgentApiKey)

        // Reconfigure the manager with the new credentials
        AIAgentManager.sharedInstance.reconfigure()

        WindowsManager.sharedInstance.backToProfile()
    }
}

// MARK: - NSTextFieldDelegate

extension SetupAIAgentViewController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        updateConfirmButton()
    }
}
