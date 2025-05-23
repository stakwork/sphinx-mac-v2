//
//  GroupDetailsViewController.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 13/01/2021.
//  Copyright © 2021 Tomas Timinskas. All rights reserved.
//

import Cocoa

protocol GroupDetailsDelegate: AnyObject {
    func shouldExitTribeOrGroup(completion: @escaping () ->())
}

class GroupDetailsViewController: NSViewController {
    
    weak var delegate: GroupDetailsDelegate?
    
    @IBOutlet weak var groupImageView: AspectFillNSImageView!
    @IBOutlet weak var groupNameLabel: NSTextField!
    @IBOutlet weak var groupNameTopMargin: NSLayoutConstraint!
    @IBOutlet weak var groupDateLabel: NSTextField!
    @IBOutlet weak var groupPriceLabel: NSTextField!
    @IBOutlet weak var tribeMemberInfoView: TribeMemberInfoView!
    @IBOutlet weak var groupPinView: GroupPinView!
    @IBOutlet weak var tribeMemberInfoContainer: NSView!
    @IBOutlet weak var tribeMemberInfoContainerHeight: NSLayoutConstraint!
    @IBOutlet weak var saveButtonContainer: NSBox!
    @IBOutlet weak var saveButton: NSButton!
    @IBOutlet weak var saveLoadingWheel: NSProgressIndicator!
    @IBOutlet weak var uploadLabel: NSTextField!
    @IBOutlet weak var loadingContainer: NSBox!
    @IBOutlet weak var loadingWheel: NSProgressIndicator!
    @IBOutlet weak var optionsButton: CustomButton!
    @IBOutlet weak var adminAvatarImageView: AspectFillNSImageView!
    @IBOutlet weak var adminNameLabel: NSTextField!
    @IBOutlet weak var adminRoleLabel: NSTextField!
    @IBOutlet weak var adminInfoContainerView: NSView!
    @IBOutlet weak var timezoneSharingView: TimezoneSharingView!
    
    
    var chat: Chat! = nil
    
    let kGroupNameTop: CGFloat = 31
    let kGroupNameWithPricesTop: CGFloat = 18
    
    var loading = false {
        didSet {
            loadingContainer.isHidden = !loading
            LoadingWheelHelper.toggleLoadingWheel(loading: loading, loadingWheel: loadingWheel, color: NSColor.white, controls: [])
        }
    }
    
    var saveLoading = false {
        didSet {
            LoadingWheelHelper.toggleLoadingWheel(loading: saveLoading, loadingWheel: saveLoadingWheel, color: NSColor.white, controls: [saveButton])
        }
    }
    
    var uploading = false {
        didSet {
            uploadLabel.isHidden = !uploading
        }
    }
    
    static func instantiate(chat: Chat, delegate: GroupDetailsDelegate) -> GroupDetailsViewController {
        let viewController = StoryboardScene.Groups.groupDetailsViewController.instantiate()
        viewController.chat = chat
        viewController.delegate = delegate
        return viewController
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        groupImageView.wantsLayer = true
        groupImageView.rounded = true
        groupImageView.layer?.cornerRadius = groupImageView.frame.height / 2
        
        adminAvatarImageView.wantsLayer = true
        adminAvatarImageView.layer?.cornerRadius = adminAvatarImageView.frame.width / 2
        adminAvatarImageView.layer?.masksToBounds = true
        
        timezoneSharingView.configureViewWith(chat: chat)
        timezoneSharingView.isHidden = false
        
        loading = true
        
        optionsButton.cursor = .pointingHand
        view.window?.title = (chat.isPublicGroup() ? "tribe.details" : "group.details").localized
        
        checkOwnerRole()
        addObserver()
    }
    
    func checkOwnerRole() {
        // Create a watchdog timer as a DispatchWorkItem.
        let watchdogTimer = DispatchWorkItem { [weak self] in
            self?.setGroupInfo()
        }
        
        // Schedule the watchdog timer to run after 5 seconds.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: watchdogTimer)
        
        SphinxOnionManager.sharedInstance.getTribeMembers(tribeChat: chat, completion: { [weak self] tribeMembers in
            guard let self = self else { return }
            
            watchdogTimer.cancel()
            
            if let _ = tribeMembers["confirmedMembers"] as? [TribeMembersRRObject] {
                self.chat?.isTribeICreated = true
                self.chat?.managedObjectContext?.saveContext()
                self.setGroupInfo()
            }
        })
    }
    
    func addObserver() {
        NotificationCenter.default.addObserver(
            forName: .shouldReloadTribeData,
            object: nil,
            queue: .main
        ) { [weak self] (n: Notification) in
            self?.setGroupInfo()
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(
            self,
            name: .shouldReloadTribeData,
            object: nil
        )
    }
    
    @objc func setGroupInfo() {
        groupPinView.configureWith(view: view, chat: chat)
        
        let placeHolderImage = NSImage(named: chat.isPublicGroup() ? "tribePlaceHolder" : "profileAvatar")?.image(withTintColor: NSColor.Sphinx.SecondaryText)
        
        if let urlString = chat.photoUrl, let nsUrl = URL(string: urlString) {
            MediaLoader.asyncLoadImage(imageView: groupImageView, nsUrl: nsUrl, placeHolderImage: placeHolderImage)
        } else {
            groupImageView.image = placeHolderImage
        }
        
        if #available(OSX 10.14, *) {
            groupImageView.contentTintColor = NSColor.Sphinx.SecondaryText
        }
        
        groupNameLabel.stringValue = chat.name ?? "unknown.group".localized
        
        let date = chat.createdAt ?? Date()
        let createdOn = String(format: "created.on".localized, date.getStringDate(format: "EEE MMM dd HH:mm"))
        groupDateLabel.stringValue = createdOn
        
        updateTribePrices()
        configureTribeMemberView()
        
        loading = false
        
        if let chat = self.chat, !chat.isTribeICreated {
            adminNameLabel.stringValue = chat.tribeInfo?.ownerAlias ?? "Unknown".localized
            adminRoleLabel.stringValue = "admin".localized
            
            let placeHolderImage = NSImage(named: "profileAvatar")?.image(withTintColor: NSColor.Sphinx.SecondaryText)
            adminAvatarImageView.image = placeHolderImage
            
            adminAvatarImageView.image = NSImage(named: "profileAvatar")?.image(withTintColor: NSColor.Sphinx.SecondaryText)
            
            adminInfoContainerView.isHidden = false
        } else {
            adminInfoContainerView.isHidden = true
        }
        
        if adminInfoContainerView.isHidden {
            NSLayoutConstraint.deactivate(adminInfoContainerView.constraints)
            
            let topConstraint = NSLayoutConstraint(item: tribeMemberInfoContainer, attribute: .top, relatedBy: .equal, toItem: view, attribute: .top, multiplier: 1, constant: 100)
            NSLayoutConstraint.activate([topConstraint])
            
            view.layoutSubtreeIfNeeded()
        }
    }
    
    func updateTribePrices() {
        if chat?.isPublicGroup() ?? false {
            if let prices = chat?.getTribePrices() {
                self.groupPriceLabel.stringValue = String(format: "group.price.text".localized, "\(prices.0)", "\(prices.1)")
                self.groupNameTopMargin.constant = self.kGroupNameWithPricesTop
                self.groupNameLabel.layoutSubtreeIfNeeded()
            }
        }
    }
    
    func configureTribeMemberView() {
        if let chat = chat, let owner = UserContact.getOwner(), chat.isPublicGroup() {
            let alias = (chat.myAlias?.isNotEmpty == true) ? chat.myAlias : owner.nickname
            let photoUrl = (chat.myPhotoUrl?.isNotEmpty == true) ? chat.myPhotoUrl : owner.getPhotoUrl()
            
            tribeMemberInfoContainerHeight.constant = 160
            
            tribeMemberInfoView.configureWith(
                vc: self,
                alias: alias,
                picture: photoUrl
            )
            
            tribeMemberInfoContainer.isHidden = false
        }
    }
    
    @IBAction func optionsButtonClicked(_ sender: Any) {
        MessageOptionsHelper.sharedInstance.showMenuFor(chat: self.chat, in: self.view, from: optionsButton, with: self)
    }
    
    @IBAction func saveButtonClicked(_ sender: Any) {
        saveLoading = true
        
        tribeMemberInfoView.uploadImage(completion: { (name, image) in
            self.updateChat(alias: name, photoUrl: image)
        })
    }
    
    func updateChat(alias: String?, photoUrl: String?) {
        guard let alias = alias, !alias.isEmpty else {
            AlertHelper.showAlert(title: "generic.error.title".localized, message: "alias.cannot.empty".localized)
            return
        }
        
        let didChangeAlias = self.chat.myAlias != alias
        
        if didChangeAlias && self.chat.timezoneEnabled {
            self.chat.timezoneUpdated = true
        }
        
        self.chat.myAlias = alias
        self.chat.myPhotoUrl = photoUrl ?? self.chat.myPhotoUrl
        self.chat.saveChat()
        self.finishUpdating()
    }
    
    func finishUpdating() {
        saveLoading = false
        uploading = false
        toggleSaveButton(enable: false)
    }
}

extension GroupDetailsViewController : TribeMemberInfoDelegate {
    func didUpdateUploadProgress(uploadString: String) {
        uploading = true
        uploadLabel.stringValue = uploadString
    }
    
    func didChangeName(newValue: String) {
        toggleSaveButton(enable: true)
    }
    
    func didChangeImage() {
        toggleSaveButton(enable: true)
    }
    
    func toggleSaveButton(enable: Bool) {
        saveButtonContainer.isHidden = !enable
        saveButton.isEnabled = enable
    }
}
extension GroupDetailsViewController : MessageOptionsDelegate {
    func shouldDeleteMessage(message: TransactionMessage) {}
    func shouldReplyToMessage(message: TransactionMessage) {}
    func shouldBoostMessage(message: TransactionMessage) {}
    
    func shouldPerformChatAction(action: Int) {
        if let action = MessageOptionsHelper.ChatActionsItem(rawValue: action) {
            switch(action) {
            case .Share:
                goToTribeQRCode()
                break
            case .Delete, .Exit:
                delegate?.shouldExitTribeOrGroup(completion: {
                    NotificationCenter.default.post(
                        name: .shouldCloseRightPanel,
                        object: nil,
                        userInfo: nil
                    )
                })
                break
            case .Edit:
                let createTribeVC = CreateTribeViewController.instantiate(chat: chat)
                WindowsManager.sharedInstance.showVCOnRightPanelWindow(
                    with: "edit.tribe".localized,
                    identifier: "edit-tribe-window",
                    contentVC: createTribeVC,
                    shouldReplace: false
                )
                break
            case .TribeMembers:
                let tribeMembers = TribeMembersViewController.instantiate(chat: chat)
                WindowsManager.sharedInstance.showVCOnRightPanelWindow(
                    with: "tribe.member".localized,
                    identifier: "tribe-members-window",
                    contentVC: tribeMembers,
                    shouldReplace: false
                )
                break
            }
        }
    }
    
    func goToTribeQRCode() {
        if let link = chat.getJoinChatLink() {
            let shareTribeQRVC = ShareInviteCodeViewController.instantiate(qrCodeString: link, viewMode: .TribeQR)
            
            WindowsManager.sharedInstance.showVCOnRightPanelWindow(
                with: "share".localized,
                identifier: "share-window",
                contentVC: shareTribeQRVC,
                shouldReplace: false
            )
        }
    }
}


