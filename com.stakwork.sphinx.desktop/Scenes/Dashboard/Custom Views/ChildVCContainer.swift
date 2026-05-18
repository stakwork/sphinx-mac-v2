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

        // Build the web app link options container programmatically if needed
        if webAppLinkOptionsContainer == nil {
            let container = NSView()
            container.translatesAutoresizingMaskIntoConstraints = false

            let browserButton = NSButton()
            browserButton.title = "open.in.browser".localized
            browserButton.bezelStyle = .rounded
            browserButton.tag = ChildVCOptionsMenuButton.OpenInBrowser.rawValue
            browserButton.target = self
            browserButton.action = #selector(optionButtonClicked(_:))
            browserButton.translatesAutoresizingMaskIntoConstraints = false

            let sphinxButton = NSButton()
            sphinxButton.title = "open.inside.sphinx".localized
            sphinxButton.bezelStyle = .rounded
            sphinxButton.tag = ChildVCOptionsMenuButton.OpenInSphinx.rawValue
            sphinxButton.target = self
            sphinxButton.action = #selector(optionButtonClicked(_:))
            sphinxButton.translatesAutoresizingMaskIntoConstraints = false

            let cancelButton = NSButton()
            cancelButton.title = "cancel".localized
            cancelButton.bezelStyle = .rounded
            cancelButton.tag = ChildVCOptionsMenuButton.Cancel.rawValue
            cancelButton.target = self
            cancelButton.action = #selector(optionButtonClicked(_:))
            cancelButton.translatesAutoresizingMaskIntoConstraints = false

            container.addSubview(browserButton)
            container.addSubview(sphinxButton)
            container.addSubview(cancelButton)

            NSLayoutConstraint.activate([
                browserButton.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
                browserButton.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                browserButton.widthAnchor.constraint(equalToConstant: 220),

                sphinxButton.topAnchor.constraint(equalTo: browserButton.bottomAnchor, constant: 10),
                sphinxButton.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                sphinxButton.widthAnchor.constraint(equalToConstant: 220),

                cancelButton.topAnchor.constraint(equalTo: sphinxButton.bottomAnchor, constant: 10),
                cancelButton.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                cancelButton.widthAnchor.constraint(equalToConstant: 220),
                cancelButton.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -16)
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
