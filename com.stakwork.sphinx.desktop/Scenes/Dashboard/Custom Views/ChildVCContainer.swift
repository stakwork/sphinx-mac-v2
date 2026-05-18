//
//  ChildVCContainer.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 04/06/2020.
//  Copyright © 2020 Sphinx. All rights reserved.
//

import Cocoa

@MainActor
protocol ChildVCDelegate: AnyObject {
    func shouldDimiss()
    func shouldGoForward(paymentViewModel: PaymentViewModel)
    func shouldGoBack(paymentViewModel: PaymentViewModel)
    func shouldSendPaymentFor(paymentObject: PaymentViewModel.PaymentObject)
}

@MainActor protocol ActionsDelegate: AnyObject {
    func didCreateMessage()
    func didFailInvoiceOrPayment()
    func shouldCreateCall(mode: VideoCallHelper.CallMode)
    func shouldSendPaymentFor(paymentObject: PaymentViewModel.PaymentObject, callback: ((Bool) -> ())?)
    func shouldShowAttachmentsPopup()
    func shouldReloadMuteState()
    func didDismissView()
    func shouldOpenWebAppLinkInBrowser(url: String)
    func shouldOpenWebAppLinkInSphinx(url: String)
}

class ChildVCContainer: NSView, LoadableNib {
    
    weak var delegate: ActionsDelegate?
    
    @IBOutlet var contentView: NSView!
    
    @IBOutlet weak var contentBox: NSBox!
    @IBOutlet weak var optionsMenuContainer: NSView!
    @IBOutlet weak var callOptionsContainer: NSView!
    @IBOutlet weak var tribeMemberPopupView: TribeMemberPopupView!
    @IBOutlet weak var childVCContainer: NSView!
    @IBOutlet weak var requestOptionContainer: NSView!
    @IBOutlet weak var notificationLevelView: NotificationLevelView!
    
    @IBOutlet weak var containerHeight: NSLayoutConstraint!
    @IBOutlet weak var containerWidth: NSLayoutConstraint!
    
    // Web app link options popup (programmatic — not in XIB)
    var webAppLinkOptionsContainer: NSView? = nil
    
    let menuSize = CGSize(width: 300, height: 170)
    let chatMenuSize = CGSize(width: 300, height: 225)
    let oneOptionMenuSize = CGSize(width: 300, height: 115)
    let invoicePaymentSize = CGSize(width: 380, height: 500)
    let groupMembersSize = CGSize(width: 380, height: 620)
    let paymentTemplatesSize = CGSize(width: 560, height: 620)
    let tribeMemberPopupSize = CGSize(width: 280, height: 350)
    let notificationLevelPopupSize = CGSize(width: 300, height: 230)
    
    var parentVC : NSViewController? = nil
    var childVC : NSViewController? = nil
    
    var chat : Chat? = nil
    var message: TransactionMessage? = nil
    var deepLinkURL: String? = nil
    
    public enum ChildVCOptionsMenuButton: Int {
        case Request
        case Send
        case Audio
        case Video
        case Cancel
        case Attach
        case OpenInBrowser = 10
        case OpenInSphinx  = 11
    }
    
    enum ViewMode: Int {
        case RequestAmount
        case SendAmount
        case PaymentTemplates
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        loadViewFromNib()
        
        resetAllViews()
    }

    override func mouseDown(with event: NSEvent) {}

    func resetAllViews() {
        removeChildVC()
        
        optionsMenuContainer.isHidden = true
        callOptionsContainer.isHidden = true
        childVCContainer.isHidden = true
        tribeMemberPopupView.isHidden = true
        notificationLevelView.isHidden = true
        webAppLinkOptionsContainer?.isHidden = true
        
        alphaValue = 0.0
        isHidden = true
    }
    
    func prepareMenuViewSize() {
        let menuSize = getMenuSize()
        containerWidth.constant = menuSize.width
        containerHeight.constant = menuSize.height
        requestOptionContainer.isHidden = false
        
        layoutSubtreeIfNeeded()
    }
    
    func prepareChatMenuViewSize() {
        let menuSize = chatMenuSize
        containerWidth.constant = menuSize.width
        containerHeight.constant = menuSize.height
        requestOptionContainer.isHidden = false
        
        layoutSubtreeIfNeeded()
    }
    
    func prepareTribeMemberPopupSize() {
        containerWidth.constant = tribeMemberPopupSize.width
        containerHeight.constant = tribeMemberPopupSize.height
        
        layoutSubtreeIfNeeded()
    }
    
    func prepareNotificationLevelPopupSize() {
        containerWidth.constant = notificationLevelPopupSize.width
        containerHeight.constant = notificationLevelPopupSize.height
        
        layoutSubtreeIfNeeded()
    }
    
    func preparePopupOn(
        parentVC: NSViewController,
        with chat: Chat?,
        and message: TransactionMessage?,
        delegate: ActionsDelegate
    ) {
        self.parentVC = parentVC
        self.chat = chat
        self.message = message
        self.delegate = delegate
        
        resetAllViews()
    }

    func showPmtOptionsMenuOn(
        parentVC: NSViewController,
        with chat: Chat?,
        delegate: ActionsDelegate
    ) {
        prepareChatMenuViewSize()
        preparePopupOn(parentVC: parentVC, with: chat, and: nil, delegate: delegate)
        optionsMenuContainer.isHidden = false
        showView()
    }
    
    func showPaymentModeWith(
        parentVC: NSViewController,
        with chat: Chat?,
        delegate: ActionsDelegate,
        mode: ChildVCContainer.ChildVCOptionsMenuButton
    ) {
        switch (mode) {
        case ChildVCOptionsMenuButton.Request:
            showChildVC(
                mode: ViewMode.RequestAmount
            )
        case ChildVCOptionsMenuButton.Send:
            showChildVC(
                mode: ViewMode.SendAmount
            )
        default:
            break
        }
        
        showView()
    }
    
    func showCallOptionsMenuOn(parentVC: NSViewController, with chat: Chat?, delegate: ActionsDelegate) {
        prepareMenuViewSize()
        preparePopupOn(parentVC: parentVC, with: chat, and: nil, delegate: delegate)
        callOptionsContainer.isHidden = false
        showView()
    }
    
    func showTribeMemberPopupViewOn(parentVC: NSViewController, with message: TransactionMessage, delegate: ActionsDelegate) {
        prepareTribeMemberPopupSize()
        preparePopupOn(parentVC: parentVC, with: chat, and: message, delegate: delegate)
        
        tribeMemberPopupView.configureFor(message: message, with: self)
        tribeMemberPopupView.isHidden = false
        
        showView()
    }
    
    func showWebAppLinkOptionsMenuOn(
        parentVC: NSViewController,
        deepLinkURL: String,
        delegate: ActionsDelegate
    ) {
        self.deepLinkURL = deepLinkURL
        prepareChatMenuViewSize()
        preparePopupOn(parentVC: parentVC, with: nil, and: nil, delegate: delegate)

        if webAppLinkOptionsContainer == nil {
            let container = NSView()
            container.translatesAutoresizingMaskIntoConstraints = false

            let rows: [(String, String, Int)] = [
                ("safari", "open.in.browser".localized, ChildVCOptionsMenuButton.OpenInBrowser.rawValue),
                ("chevron.left.forwardslash.chevron.right", "open.inside.sphinx".localized, ChildVCOptionsMenuButton.OpenInSphinx.rawValue),
            ]

            var previousRow: NSView? = nil

            for (iconName, labelText, tag) in rows {
                let row = makeOptionRow(sfSymbol: iconName, label: labelText, tag: tag, showDivider: true)
                container.addSubview(row)
                NSLayoutConstraint.activate([
                    row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 30),
                    row.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -30),
                    row.heightAnchor.constraint(equalToConstant: 55),
                ])
                if let prev = previousRow {
                    row.topAnchor.constraint(equalTo: prev.bottomAnchor).isActive = true
                } else {
                    row.topAnchor.constraint(equalTo: container.topAnchor, constant: 10).isActive = true
                }
                previousRow = row
            }

            // Cancel row — same style as existing cancel (smaller, red label, no icon)
            let cancelRow = makeCancelRow(tag: ChildVCOptionsMenuButton.Cancel.rawValue)
            container.addSubview(cancelRow)
            NSLayoutConstraint.activate([
                cancelRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 30),
                cancelRow.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -30),
                cancelRow.heightAnchor.constraint(equalToConstant: 50),
                cancelRow.topAnchor.constraint(equalTo: previousRow!.bottomAnchor),
            ])

            contentBox.addSubview(container)
            NSLayoutConstraint.activate([
                container.topAnchor.constraint(equalTo: contentBox.topAnchor),
                container.bottomAnchor.constraint(equalTo: contentBox.bottomAnchor),
                container.leadingAnchor.constraint(equalTo: contentBox.leadingAnchor),
                container.trailingAnchor.constraint(equalTo: contentBox.trailingAnchor),
            ])

            webAppLinkOptionsContainer = container
        }

        webAppLinkOptionsContainer?.isHidden = false
        showView()
    }

    private func makeOptionRow(sfSymbol: String, label labelText: String, tag: Int, showDivider: Bool) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        // Icon
        let config = NSImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.image = NSImage(systemSymbolName: sfSymbol, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        icon.contentTintColor = NSColor(named: "Text")
        icon.imageScaling = .scaleProportionallyDown

        // Label
        let label = NSTextField(labelWithString: labelText)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont(name: "Roboto-Regular", size: 17) ?? NSFont.systemFont(ofSize: 17)
        label.textColor = NSColor(named: "Text")

        // Divider
        let divider = NSBox()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.boxType = .custom
        divider.borderType = .noBorder
        divider.fillColor = NSColor(named: "LightDivider") ?? NSColor.separatorColor
        divider.titlePosition = .noTitle

        // Transparent hit-target button (same pattern as XIB)
        let button = NSButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.title = ""
        button.bezelStyle = .rounded
        button.isBordered = false
        button.tag = tag
        button.target = self
        button.action = #selector(optionButtonClicked(_:))

        row.addSubview(icon)
        row.addSubview(label)
        row.addSubview(divider)
        row.addSubview(button)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            icon.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 30),
            icon.heightAnchor.constraint(equalToConstant: 30),

            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor),

            divider.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            divider.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),

            button.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            button.topAnchor.constraint(equalTo: row.topAnchor),
            button.bottomAnchor.constraint(equalTo: row.bottomAnchor),
        ])

        return row
    }

    private func makeCancelRow(tag: Int) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: "cancel".localized.uppercased())
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont(name: "Montserrat-Regular", size: 12) ?? NSFont.systemFont(ofSize: 12)
        label.textColor = NSColor(named: "PrimaryRed") ?? NSColor.systemRed

        let button = NSButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.title = ""
        button.bezelStyle = .rounded
        button.isBordered = false
        button.tag = tag
        button.target = self
        button.action = #selector(optionButtonClicked(_:))

        row.addSubview(label)
        row.addSubview(button)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: row.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            button.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            button.topAnchor.constraint(equalTo: row.topAnchor),
            button.bottomAnchor.constraint(equalTo: row.bottomAnchor),
        ])

        return row
    }

    func showNotificaionLevelViewOn(parentVC: NSViewController, with chat: Chat, delegate: ActionsDelegate) {
        prepareNotificationLevelPopupSize()
        preparePopupOn(parentVC: parentVC, with: chat, and: message, delegate: delegate)
        
        notificationLevelView.configureWith(chat: chat) {
            self.shouldDimiss()
            self.delegate?.shouldReloadMuteState()
        }
        notificationLevelView.isHidden = false
        
        showView()
    }
    
    func showView() {
        isHidden = false

        AnimationHelper.animateViewWith(duration: 0.3, animationsBlock: {
            self.alphaValue = 1.0
        })
    }
    
    func hideView() {
        AnimationHelper.animateViewWith(duration: 0.3, animationsBlock: {
            self.alphaValue = 0.0
        }, completion: {
            self.isHidden = true
            self.delegate?.didDismissView()
        })
    }
    
    func animateSizeTo(size: CGSize, completion: @escaping () -> ()) {
        optionsMenuContainer.isHidden = true
        tribeMemberPopupView.isHidden = true
        childVCContainer.isHidden = true
        
        AnimationHelper.animateViewWith(duration: 0.3, animationsBlock: {
            self.containerWidth.constant = size.width
            self.containerHeight.constant = size.height
            self.layoutSubtreeIfNeeded()
        }, completion: {
            completion()
        })
    }
    
    func getMenuSize() -> CGSize {
        return CGSize(
            width: menuSize.width,
            height: menuSize.height
        )
    }
    
    func getSizeFor(mode: ViewMode) -> CGSize {
        switch(mode) {
        case ViewMode.RequestAmount, ViewMode.SendAmount:
            return invoicePaymentSize
        case ViewMode.PaymentTemplates:
            return paymentTemplatesSize
        }
    }
    
    func getVCFor(mode: ViewMode, paymentVM: PaymentViewModel) -> NSViewController {
        switch(mode) {
        case ViewMode.RequestAmount:
            return CreateInvoiceViewController.instantiate(
                childVCDelegate: self,
                viewModel: paymentVM,
                delegate: delegate
            )
        case ViewMode.SendAmount:
            return SendPaymentViewController.instantiate(
                childVCDelegate: self,
                viewModel: paymentVM,
                delegate: delegate
            )
        case ViewMode.PaymentTemplates:
            return PaymentTemplatesViewController.instantiate(
                childVCDelegate: self,
                viewModel: paymentVM,
                delegate: delegate
            )
        }
        
    }
    
    func showChildVC(mode: ViewMode) {
        removeChildVC()
        
        animateSizeTo(size: getSizeFor(mode: mode), completion: {
            self.addViewController(for: mode)
        })
    }

    func addViewController(for mode: ViewMode) {
        let contact: UserContact? = self.chat?.getContact()
        let paymentMode: PaymentViewModel.PaymentMode = (mode == .SendAmount) ? .Payment : .Request
        let paymentViewModel = PaymentViewModel(chat: chat, contact: contact, message: message, mode: paymentMode)
        let vc = getVCFor(mode: mode, paymentVM: paymentViewModel)
        addChildVC(vc: vc)
    }
    
    func addChildVC(vc: NSViewController) {
        childVC = vc
        parentVC?.addChild(vc)
        vc.view.frame = childVCContainer.frame
        childVCContainer.addSubview(vc.view)
        
        childVCContainer.isHidden = false
    }

    func removeChildVC() {
        if let childVC = childVC {
            childVC.view.removeFromSuperview()
            childVC.removeFromParent()
            self.childVC = nil
        }
        parentVC = nil
    }

    @IBAction func optionButtonClicked(_ sender: Any) {
        if let sender = sender as? NSButton {
            switch(sender.tag) {
            case ChildVCOptionsMenuButton.Request.rawValue:
                showChildVC(mode: ViewMode.RequestAmount)
                break
            case ChildVCOptionsMenuButton.Send.rawValue:
                showChildVC(mode: ViewMode.SendAmount)
                break
            case ChildVCOptionsMenuButton.Attach.rawValue:
                delegate?.shouldShowAttachmentsPopup()
                hideView()
                break
            case ChildVCOptionsMenuButton.Audio.rawValue:
                delegate?.shouldCreateCall(mode: .Audio)
                hideView()
                break
            case ChildVCOptionsMenuButton.Video.rawValue:
                delegate?.shouldCreateCall(mode: .All)
                hideView()
                break
            case ChildVCOptionsMenuButton.Cancel.rawValue:
                hideView()
                break
            case ChildVCOptionsMenuButton.OpenInBrowser.rawValue:
                delegate?.shouldOpenWebAppLinkInBrowser(url: deepLinkURL ?? "")
                hideView()
                break
            case ChildVCOptionsMenuButton.OpenInSphinx.rawValue:
                delegate?.shouldOpenWebAppLinkInSphinx(url: deepLinkURL ?? "")
                hideView()
                break
            default:
                break
            }
        }
    }
}

extension ChildVCContainer : ChildVCDelegate {
    
    func shouldDimiss() {
        removeChildVC()
        hideView()
    }
    
    func shouldGoBack(paymentViewModel: PaymentViewModel) {
        if childVC?.isKind(of: PaymentTemplatesViewController.self) ?? false {
            replaceChildVCFor(mode: .SendAmount, paymentViewModel: paymentViewModel)
        }
    }
    
    func shouldGoForward(paymentViewModel: PaymentViewModel) {
        replaceChildVCFor(mode: .PaymentTemplates, paymentViewModel: paymentViewModel)
    }
    
    func replaceChildVCFor(mode: ViewMode, paymentViewModel: PaymentViewModel) {
        let vc = getVCFor(mode: mode, paymentVM: paymentViewModel)
        let size = getSizeFor(mode: mode)
        
        animateSizeTo(size: size, completion: {
            self.replaceChildVC(by: vc)
        })
    }
    
    func replaceChildVC(by vc: NSViewController) {
        self.removeChildVC()
        self.addChildVC(vc: vc)
    }
    
    func shouldSendPaymentFor(paymentObject: PaymentViewModel.PaymentObject) {
        delegate?.shouldSendPaymentFor(paymentObject: paymentObject, callback: { success in
            self.shouldDismissTribeMemberPopup()
        })
    }
}

extension ChildVCContainer : TribeMemberPopupViewDelegate {
    func shouldGoToSendPayment() {
        guard let _ = message else {
            return
        }
        showChildVC(mode: ViewMode.SendAmount)
    }
    
    func shouldDismissTribeMemberPopup() {
        removeChildVC()
        hideView()
    }
}
