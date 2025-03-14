//
//  ContactDetailsViewController.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 20/12/2024.
//  Copyright © 2024 Tomas Timinskas. All rights reserved.
//

import Cocoa

protocol ContactDetailsViewDelegate: AnyObject {
    func didDeleteContact()
    func didTapOnAvatarImage(url: String)
}

class ContactDetailsViewController: NSCollectionViewItem {
    
    weak var delegate: ContactDetailsViewDelegate?

    @IBOutlet weak var contactAvatarView: ChatAvatarView!
    @IBOutlet weak var contactAvatarButton: CustomButton!
    @IBOutlet weak var contactName: NSTextField!
    @IBOutlet weak var contactDate: NSTextField!
    @IBOutlet weak var publicKeyLabel: NSTextField!
    @IBOutlet weak var publicKeyButton: CustomButton!
    @IBOutlet weak var routeHintLabel: NSTextField!
    @IBOutlet weak var removeContactButtonBack: NSBox!
    @IBOutlet weak var removeContactButton: CustomButton!
    @IBOutlet weak var timezoneSharingView: TimezoneSharingView!
    
    var contact: UserContact? = nil
    
    static func instantiate(
        contactId: Int,
        delegate: ContactDetailsViewDelegate?
    ) -> ContactDetailsViewController {
        
        let viewController = StoryboardScene.Contacts.contactDetailsViewController.instantiate()
        viewController.contact = UserContact.getContactWith(id: contactId)
        viewController.delegate = delegate

        return viewController
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupView()
        setupContactInfo()
    }
    
    func setupView() {
        contactAvatarButton.cursor = .pointingHand
        publicKeyButton.cursor = .pointingHand
        removeContactButton.cursor = .pointingHand
        
        removeContactButtonBack.wantsLayer = true
        removeContactButtonBack.layer?.backgroundColor = NSColor.Sphinx.PrimaryRed.withAlphaComponent(0.1).cgColor
        removeContactButtonBack.layer?.cornerRadius = 6
    }
    
    func setupContactInfo() {
        guard let contact = contact else {
            return
        }
        contactAvatarView.configureSize(width: 100, height: 100, fontSize: 25)
        contactAvatarView.loadWith(contact)
        
        contactName.stringValue = contact.getName()
        contactDate.stringValue = String.init(format: "contact.connected.since".localized, contact.createdAt?.getStringDate(format: "MMMM dd, YYYY") ?? "")
        publicKeyLabel.stringValue = contact.publicKey ?? ""
        routeHintLabel.stringValue = contact.routeHint ?? ""

        if let chat = contact.getChat() {
            timezoneSharingView.configure(
                enabled: chat.timezoneEnabled,
                identifier: chat.timezoneIdentifier
            )
        } else {
            timezoneSharingView.configure(enabled: false, identifier: nil)
        }
    }
    
    @IBAction func contactAvatarButtonClicked(_ sender: Any) {
        guard let contact = contact else {
            return
        }
        if let urlString = contact.getPhotoUrl()?.removeDuplicatedProtocol(), let _ = URL(string: urlString) {
            delegate?.didTapOnAvatarImage(url: urlString)
        }
    }
    
    @IBAction func publicKeyButtonClicked(_ sender: Any) {
        guard let address = contact?.getAddress(), !address.isEmpty else {
            return
        }
            
        let shareInviteCodeVC = ShareInviteCodeViewController.instantiate(qrCodeString: address, viewMode: .PubKey)
        
        WindowsManager.sharedInstance.showVCOnRightPanelWindow(
            with: "pubkey".localized,
            identifier: "pubkey-window",
            contentVC: shareInviteCodeVC,
            shouldReplace: false
        )
    }
    
    @IBAction func removeContactButtonClicked(_ sender: Any) {
        guard let contact = contact else {
            AlertHelper.showAlert(
                title: "generic.error.title".localized,
                message: "generic.error.message".localized
            )
            
            return
        }
        
        let confirmDeletionCallback: (() -> ()) = {
            self.shouldDeleteContact(contact: contact)
        }
            
        AlertHelper.showTwoOptionsAlert(
            title: "warning".localized,
            message: (contact.isInvite() ? "delete.invite.warning" : "delete.contact.warning").localized,
            confirm: confirmDeletionCallback
        )
    }
    
    func shouldDeleteContact(contact: UserContact) {
        let som = SphinxOnionManager.sharedInstance
        
        if let inviteCode = contact.invite?.inviteString, contact.isInvite() {
            if !som.cancelInvite(inviteCode: inviteCode) {
                AlertHelper.showAlert(
                    title: "generic.error.title".localized,
                    message: "generic.error.message".localized
                )
                return
            }
        }
        
        if let publicKey = contact.publicKey, publicKey.isNotEmpty {
            if som.deleteContactOrChatMsgsFor(contact: contact) {
                som.deleteContactFromState(pubkey: publicKey)
            }
        }
                
        CoreDataManager.sharedManager.deleteContactObjectsFor(contact)
        
        delegate?.didDeleteContact()
    }
}