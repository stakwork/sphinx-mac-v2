//
//  HiveNotificationPreferencesViewController.swift
//  Sphinx
//
//  Created on 2026-07-01.
//  Copyright © 2026 Sphinx. All rights reserved.
//

import Cocoa

private class FlippedClipView: NSClipView {
    override var isFlipped: Bool { return true }
}

class HiveNotificationPreferencesViewController: NSViewController {

    // Notification metadata is defined in HiveNotificationConstants

    // MARK: - State

    /// Merged preference values keyed by notification key
    private var preferences: [String: Bool] = [:]

    // MARK: - UI

    private let kSwitchOnLeading: CGFloat = 25
    private let kSwitchOffLeading: CGFloat = 2

    private lazy var scrollView: NSScrollView = {
        let sv = NSScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.hasVerticalScroller = true
        sv.drawsBackground = false
        sv.borderType = .noBorder
        return sv
    }()

    private lazy var stackView: NSStackView = {
        let sv = NSStackView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.orientation = .vertical
        sv.alignment = .leading
        sv.spacing = 8
        return sv
    }()

    private lazy var loadingWheel: NSProgressIndicator = {
        let pi = NSProgressIndicator()
        pi.translatesAutoresizingMaskIntoConstraints = false
        pi.style = .spinning
        pi.controlSize = .regular
        pi.isIndeterminate = true
        pi.isHidden = true
        return pi
    }()

    private lazy var errorLabel: NSTextField = {
        let tf = NSTextField(labelWithString: "Could not load preferences. Please check your connection.")
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.textColor = NSColor.systemRed
        tf.font = NSFont.systemFont(ofSize: 13)
        tf.alignment = .center
        tf.isHidden = true
        tf.lineBreakMode = .byWordWrapping
        tf.maximumNumberOfLines = 0
        return tf
    }()

    private lazy var saveButtonContainer: NSBox = {
        let box = NSBox()
        box.translatesAutoresizingMaskIntoConstraints = false
        box.boxType = .custom
        box.borderType = .noBorder
        box.wantsLayer = true
        box.fillColor = NSColor.Sphinx.PrimaryBlue
        box.layer?.cornerRadius = 8
        return box
    }()

    private lazy var saveButton: CustomButton = {
        let btn = CustomButton()
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.title = "Save"
        btn.isBordered = false
        btn.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        btn.contentTintColor = .white
        btn.cursor = .pointingHand
        btn.target = self
        btn.action = #selector(saveButtonClicked(_:))
        return btn
    }()

    private lazy var saveLoadingWheel: NSProgressIndicator = {
        let pi = NSProgressIndicator()
        pi.translatesAutoresizingMaskIntoConstraints = false
        pi.style = .spinning
        pi.controlSize = .small
        pi.isIndeterminate = true
        pi.isHidden = true
        return pi
    }()

    /// Maps a notification key → its toggle container box (for colour changes)
    private var switchContainersByKey: [String: NSBox] = [:]
    /// Maps a notification key → its circle box (for position changes)
    private var switchCirclesByKey: [String: NSBox] = [:]
    /// Maps a notification key → its leading constraint
    private var switchCircleLeadingByKey: [String: NSLayoutConstraint] = [:]

    // MARK: - Lifecycle

    static func instantiate() -> HiveNotificationPreferencesViewController {
        return HiveNotificationPreferencesViewController()
    }

    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 500))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadPreferences()
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.wantsLayer = true

        // Scroll content — use a flipped clip view so the stack view starts at the visual top
        let clipView = FlippedClipView()
        clipView.drawsBackground = false
        clipView.documentView = stackView
        scrollView.contentView = clipView
        view.addSubview(scrollView)
        view.addSubview(loadingWheel)
        view.addSubview(errorLabel)
        saveButtonContainer.addSubview(saveButton)
        view.addSubview(saveButtonContainer)
        view.addSubview(saveLoadingWheel)

        NSLayoutConstraint.activate([
            // Save button container pinned to bottom
            saveButtonContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            saveButtonContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            saveButtonContainer.widthAnchor.constraint(equalToConstant: 120),
            saveButtonContainer.heightAnchor.constraint(equalToConstant: 32),

            // Save button fills the container
            saveButton.leadingAnchor.constraint(equalTo: saveButtonContainer.leadingAnchor),
            saveButton.trailingAnchor.constraint(equalTo: saveButtonContainer.trailingAnchor),
            saveButton.topAnchor.constraint(equalTo: saveButtonContainer.topAnchor),
            saveButton.bottomAnchor.constraint(equalTo: saveButtonContainer.bottomAnchor),

            // Save loading wheel aligned with save button container
            saveLoadingWheel.centerYAnchor.constraint(equalTo: saveButtonContainer.centerYAnchor),
            saveLoadingWheel.leadingAnchor.constraint(equalTo: saveButtonContainer.trailingAnchor, constant: 8),

            // Scroll view fills remaining space above save button
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: saveButtonContainer.topAnchor, constant: -12),

            // Stack view width matches scroll view; top-alignment is handled by FlippedClipView
            stackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            // Loading wheel centred in scroll area
            loadingWheel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            loadingWheel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),

            // Error label centred in scroll area
            errorLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            errorLabel.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -32)
        ])

        buildToggleRows()
    }

    /// Creates one labelled toggle row per notification type and adds them to the stack view.
    /// The rows are hidden initially; they are shown once preferences have loaded.
    private func buildToggleRows() {
        for entry in HiveNotificationConstants.notificationKeys {
            let row = makeToggleRow(key: entry.key, label: entry.label)
            row.isHidden = true
            stackView.addArrangedSubview(row)
            // Width constraint must be activated after the row is in the stack view hierarchy
            row.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
        }
    }

    private func makeToggleRow(key: String, label: String) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.wantsLayer = true

        // Label
        let textField = NSTextField(labelWithString: label)
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.font = NSFont.systemFont(ofSize: 13)
        textField.textColor = NSColor.labelColor
        textField.lineBreakMode = .byTruncatingTail

        // Toggle container (pill background)
        let container = NSBox()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.boxType = .custom
        container.borderType = .noBorder
        container.wantsLayer = true
        container.fillColor = NSColor.Sphinx.MainBottomIcons

        // Toggle circle
        let circle = NSBox()
        circle.translatesAutoresizingMaskIntoConstraints = false
        circle.boxType = .custom
        circle.borderType = .noBorder
        circle.wantsLayer = true
        circle.fillColor = NSColor.white

        // Transparent button over the toggle
        let button = CustomButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.title = ""
        button.isBordered = false
        button.cursor = .pointingHand
        button.target = self
        button.action = #selector(toggleButtonClicked(_:))
        button.identifier = NSUserInterfaceItemIdentifier(key)

        container.addSubview(circle)
        container.addSubview(button)
        row.addSubview(textField)
        row.addSubview(container)

        // Store references for state updates
        switchContainersByKey[key] = container
        switchCirclesByKey[key] = circle

        // Layout within container
        let circleLeading = circle.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: kSwitchOffLeading)
        circleLeading.isActive = true
        switchCircleLeadingByKey[key] = circleLeading

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 51),
            container.heightAnchor.constraint(equalToConstant: 25),
            circle.widthAnchor.constraint(equalToConstant: 21),
            circle.heightAnchor.constraint(equalToConstant: 21),
            circle.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            button.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            button.topAnchor.constraint(equalTo: container.topAnchor),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            row.heightAnchor.constraint(equalToConstant: 44),
            textField.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 4),
            textField.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            textField.trailingAnchor.constraint(lessThanOrEqualTo: container.leadingAnchor, constant: -8),
            container.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -4),
            container.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])

        // Corner radii — apply after constraints are in place
        container.layer?.cornerRadius = 12.5
        circle.layer?.cornerRadius = 10.5

        return row
    }

    // MARK: - Load & Save

    private func loadPreferences() {
        showLoadingState()

        API.sharedInstance.fetchNotificationPreferencesWithAuth(
            callback: { [weak self] fetched in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.preferences = HiveNotificationConstants.merged(fetched: fetched)
                    self.populateToggles()
                    self.showContentState()
                }
            },
            errorCallback: { [weak self] in
                DispatchQueue.main.async {
                    self?.showErrorState()
                }
            }
        )
    }

    private func populateToggles() {
        for (index, entry) in HiveNotificationConstants.notificationKeys.enumerated() {
            let isOn = preferences[entry.key] ?? (HiveNotificationConstants.defaultPreferences[entry.key] ?? false)
            applyToggleState(key: entry.key, on: isOn, animated: false)
            stackView.arrangedSubviews[index].isHidden = false
        }
    }

    @objc private func saveButtonClicked(_ sender: Any) {
        setSaveButtonEnabled(false)
        saveLoadingWheel.isHidden = false
        saveLoadingWheel.startAnimation(nil)

        API.sharedInstance.updateNotificationPreferencesWithAuth(
            preferences: preferences,
            callback: { [weak self] in
                DispatchQueue.main.async {
                    self?.saveLoadingWheel.stopAnimation(nil)
                    self?.saveLoadingWheel.isHidden = true
                    WindowsManager.sharedInstance.dismissViewFromCurrentWindow()
                }
            },
            errorCallback: { [weak self] in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.setSaveButtonEnabled(true)
                    self.saveLoadingWheel.stopAnimation(nil)
                    self.saveLoadingWheel.isHidden = true
                    AlertHelper.showAlert(
                        title: "Error",
                        message: "Could not save preferences. Please try again."
                    )
                }
            }
        )
    }

    // MARK: - Toggle interaction

    @objc private func toggleButtonClicked(_ sender: CustomButton) {
        let key = sender.identifier?.rawValue ?? ""
        guard !key.isEmpty else { return }
        let current = preferences[key] ?? false
        let newValue = !current
        preferences[key] = newValue
        applyToggleState(key: key, on: newValue, animated: true)
    }

    private func applyToggleState(key: String, on: Bool, animated: Bool) {
        guard let container = switchContainersByKey[key],
              let leadingConstraint = switchCircleLeadingByKey[key] else { return }

        let targetLeading: CGFloat = on ? kSwitchOnLeading : kSwitchOffLeading
        let targetColor: NSColor = on ? NSColor.Sphinx.PrimaryBlue : NSColor.Sphinx.MainBottomIcons

        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.15
                leadingConstraint.animator().constant = targetLeading
            })
        } else {
            leadingConstraint.constant = targetLeading
        }
        container.fillColor = targetColor
    }

    // MARK: - UI state helpers

    private func setSaveButtonEnabled(_ enabled: Bool) {
        saveButton.isEnabled = enabled
        saveButtonContainer.alphaValue = enabled ? 1.0 : 0.5
    }

    private func showLoadingState() {
        loadingWheel.isHidden = false
        loadingWheel.startAnimation(nil)
        errorLabel.isHidden = true
        stackView.arrangedSubviews.forEach { $0.isHidden = true }
        setSaveButtonEnabled(false)
    }

    private func showContentState() {
        loadingWheel.stopAnimation(nil)
        loadingWheel.isHidden = true
        errorLabel.isHidden = true
        setSaveButtonEnabled(true)
    }

    private func showErrorState() {
        loadingWheel.stopAnimation(nil)
        loadingWheel.isHidden = true
        errorLabel.isHidden = false
        setSaveButtonEnabled(false)
    }
}
