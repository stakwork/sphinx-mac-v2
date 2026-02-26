//
//  ChatsSegmentedControl.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 05/07/2023.
//  Copyright © 2023 Tomas Timinskas. All rights reserved.
//

import Cocoa

protocol ChatsSegmentedControlDelegate: AnyObject {

    func segmentedControlDidSwitch(
        _ segmentedControl: ChatsSegmentedControl,
        to index: Int
    )
}

class ChatsSegmentedControl: NSView {

    private var buttonContainers: [NSView]!
    private var buttons: [NSButton]!
    private var buttonTitles: [String]!
    private var buttonTitleBadges: [NSView]!
    private var selectorView: NSView!

    public let buttonBackgroundColor: NSColor = .Sphinx.HeaderBG
    public let buttonTextColor: NSColor = .Sphinx.SecondaryText
    public let activeTextColor: NSColor = .Sphinx.PrimaryText

    public var buttonTitleFont = NSFont(
        name: "Roboto-Medium",
        size: 13.0
    )!

    public var selectorViewColor: NSColor = .Sphinx.PrimaryBlue
    public var selectorWidthRatio: CGFloat = 1.0

    let kButtonHeight: CGFloat = 48.0
    let kLeftPadding: CGFloat = 12.0
    let kTotalWidth: CGFloat = 310.0  // Fixed total width for all tabs

    /// Computed widths based on ratios
    private var buttonWidths: [CGFloat] {
        guard let buttonTitles = buttonTitles else { return [] }

        // Friends 19%, Tribes 19%, Feed 16%, Graph 16%, Workspaces 30%
        let defaultRatios: [CGFloat] = [0.19, 0.19, 0.16, 0.16, 0.30]

        // Use default ratios if count matches, otherwise distribute equally
        let ratios: [CGFloat]
        if buttonTitles.count == defaultRatios.count {
            ratios = defaultRatios
        } else {
            let equalRatio = 1.0 / CGFloat(buttonTitles.count)
            ratios = Array(repeating: equalRatio, count: buttonTitles.count)
        }

        return ratios.map { $0 * kTotalWidth }
    }

    let kGraphButtonTag = 100


    /// Indices for tabs that should have a circular badge displayed next to their title.
    public var indicesOfTitlesWithBadge: [Int] = [] {
        didSet {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                self.updateTitleBadges()
            }
        }
    }


    public weak var delegate: ChatsSegmentedControlDelegate?

    let contactsService = ContactsService.sharedInstance
    
    /// The currently selected index - defaults to contactsService.selectedTabIndex for dashboard tabs,
    /// but can be overridden when used in other contexts (e.g., WorkspaceTasksDashboard)
    private var currentSelectedIndex: Int = 0

    convenience init(
        frame: CGRect,
        buttonTitles: [String]
    ) {
        self.init(frame: frame)

        self.buttonTitles = buttonTitles

        setupInitialViews()
    }
}

// MARK: - Lifecycle
extension ChatsSegmentedControl {

    override func draw(_ rect: CGRect) {
        super.draw(rect)

        self.wantsLayer = true
        self.layer?.masksToBounds = true
        self.layer?.backgroundColor = buttonBackgroundColor.cgColor
    }
}

// MARK: - Action Handling
extension ChatsSegmentedControl {

    @objc func buttonAction(sender: NSButton) {

        for (buttonIndex, button) in buttons.enumerated() {

            resetButton(button)

            if button == sender {
                currentSelectedIndex = buttonIndex
                delegate?.segmentedControlDidSwitch(self, to: buttonIndex)
                updateButtonsOnIndexChange()
            }
        }
    }

    func resetButton(_ button: NSButton) {
        button.attributedTitle = NSAttributedString(
            string: button.attributedTitle.string,
            attributes:
                [
                    NSAttributedString.Key.foregroundColor : buttonTextColor,
                    NSAttributedString.Key.font: buttonTitleFont
                ]
        )
    }
}

// MARK: - Public Methods
extension ChatsSegmentedControl {

    public func configureFromOutlet(
        buttonTitles: [String],
        indicesOfTitlesWithBadge: [Int] = [],
        delegate: ChatsSegmentedControlDelegate?,
        initialSelectedIndex: Int? = nil
    ) {
        self.buttonTitles = buttonTitles
        self.delegate = delegate
        
        // Use provided index or default to contactsService for dashboard tabs
        self.currentSelectedIndex = initialSelectedIndex ?? contactsService.selectedTabIndex

        setupInitialViews()
        updateButtonsOnIndexChange()
    }

    public func updateGraphTabLabel() {
        let newLabel = UserData.sharedInstance.getPersonalGraphValue(with: KeychainManager.KeychainKeys.personalGraphLabel) ?? "Graph"
        let graphIndex = ChatListViewController.DashboardTab.graph.rawValue
        
        guard graphIndex < buttonTitles.count && graphIndex < buttons.count else { return }
        
        buttonTitles[graphIndex] = newLabel
        let graphButton = buttons[graphIndex]

        let attributedTitle = graphButton.attributedTitle

        let color = attributedTitle.attribute(
            .foregroundColor,
            at: 0,
            effectiveRange: nil
        ) as? NSColor

        graphButton.attributedTitle = NSAttributedString(
            string: newLabel,
            attributes:
                [
                    NSAttributedString.Key.foregroundColor : color ?? buttonTextColor,
                    NSAttributedString.Key.font: buttonTitleFont
                ]
        )
    }
}

// MARK: -  View Configuration
extension ChatsSegmentedControl {

    private func setupInitialViews() {
        createButtons()
        configureSelectorView()
        configureStackView()
    }

    private func configureStackView() {
        let stackView = NSStackView(views: buttonContainers)

        stackView.orientation = .horizontal
        stackView.distribution = .fill
        stackView.spacing = 0

        addSubview(stackView)

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.topAnchor.constraint(equalTo: self.topAnchor).isActive = true
        stackView.bottomAnchor.constraint(equalTo: self.bottomAnchor).isActive = true

        let leftConstraint = stackView.leftAnchor.constraint(equalTo: self.leftAnchor)
        leftConstraint.constant = kLeftPadding
        leftConstraint.isActive = true

        // Set width constraints for each button container
        for (index, container) in buttonContainers.enumerated() {
            container.translatesAutoresizingMaskIntoConstraints = false
            container.widthAnchor.constraint(equalToConstant: buttonWidths[index]).isActive = true
        }

        stackView.widthAnchor.constraint(equalToConstant: kTotalWidth).isActive = true
    }

    private var selectorPosition: CGFloat {
        guard currentSelectedIndex <= buttonWidths.count else { return 0 }
        var position: CGFloat = 0
        for i in 0..<currentSelectedIndex {
            position += buttonWidths[i]
        }
        return position
    }

    private var currentButtonWidth: CGFloat {
        guard currentSelectedIndex < buttonWidths.count else { return buttonWidths[0] }
        return buttonWidths[currentSelectedIndex]
    }

    private func configureSelectorView() {
        selectorView = NSView(
            frame: CGRect(
                x: kLeftPadding + selectorPosition,
                y: 0,
                width: currentButtonWidth,
                height: 3
            )
        )

        selectorView.wantsLayer = true
        selectorView.layer?.masksToBounds = true
        selectorView.layer?.backgroundColor = selectorViewColor.cgColor
        selectorView.layer?.cornerRadius = 1.5

        addSubview(selectorView)
    }


    private func createButtons() {
        buttonContainers = [NSView]()
        buttonContainers.removeAll()

        buttons = [NSButton]()
        buttons.removeAll()

        for (index, buttonTitle) in buttonTitles.enumerated() {
            let buttonWidth = buttonWidths[index]

            let view = NSView(
                frame: NSRect(
                    x: 0,
                    y: 0,
                    width: buttonWidth,
                    height: kButtonHeight
                )
            )

            let button = NSButton(
                frame: NSRect(
                    x: 0,
                    y: 0,
                    width: buttonWidth,
                    height: kButtonHeight
                )
            )

            let buttonCustomTitle = UserData.sharedInstance.getPersonalGraphValue(with: KeychainManager.KeychainKeys.personalGraphLabel) ?? buttonTitle
            let isGraphButton = (index == ChatListViewController.DashboardTab.graph.rawValue)

            button.attributedTitle = NSAttributedString(
                string: isGraphButton ? buttonCustomTitle : buttonTitle,
                attributes:
                    [
                        NSAttributedString.Key.foregroundColor : buttonTextColor,
                        NSAttributedString.Key.font: buttonTitleFont
                    ]
            )

            button.target = self
            button.action = #selector(ChatsSegmentedControl.buttonAction(sender:))

            button.wantsLayer = true
            button.layer?.backgroundColor = NSColor.clear.cgColor
            button.isBordered = false

            view.addSubview(button)

            buttonContainers.append(view)
            buttons.append(button)
        }

        guard currentSelectedIndex < buttons.count else { return }
        
        let selectedButton = buttons[currentSelectedIndex]

        selectedButton.attributedTitle = NSAttributedString(
            string: selectedButton.attributedTitle.string,
            attributes:
                [
                    NSAttributedString.Key.foregroundColor : activeTextColor,
                    NSAttributedString.Key.font: buttonTitleFont
                ]
        )

        createButtonTitleBadges()
    }

    func updateButtonsOnIndexChange() {
        for button in buttons {
            resetButton(button)
        }

        guard currentSelectedIndex < buttons.count else { return }

        AnimationHelper.animateViewWith(duration: 0.3, animationsBlock: {

            self.selectorView.frame.origin.x = self.kLeftPadding + self.selectorPosition
            self.selectorView.frame.size.width = self.currentButtonWidth

            let selectedButton = self.buttons[self.currentSelectedIndex]

            selectedButton.attributedTitle = NSAttributedString(
                string: selectedButton.attributedTitle.string,
                attributes:
                    [
                        NSAttributedString.Key.foregroundColor : self.activeTextColor,
                        NSAttributedString.Key.font: self.buttonTitleFont
                    ]
            )
        })
    }


    private func updateTitleBadges() {
        buttonTitleBadges.enumerated().forEach { (index, badge) in
            badge.isHidden = !indicesOfTitlesWithBadge.contains(index)
        }
    }

    private func createButtonTitleBadges() {
        buttonTitleBadges = buttonContainers!.enumerated().map { (index, view) in
            let buttonWidth = buttonWidths[index]
            let badgeView = NSView(
                frame: .init(
                    x: buttonWidth / 2 + 20,
                    y: kButtonHeight - 15,
                    width: 5.0,
                    height: 5.0
                )
            )

            badgeView.isHidden = false

            badgeView.wantsLayer = true
            badgeView.layer?.masksToBounds = true
            badgeView.layer?.backgroundColor = NSColor.Sphinx.PrimaryBlue.cgColor
            badgeView.makeCircular()

            return badgeView
        }

        buttonTitleBadges.enumerated().forEach { (index, badge) in
            buttonContainers[index].addSubview(badge)
            badge.isHidden = !indicesOfTitlesWithBadge.contains(index)
        }
    }
}
