//
//  ProfileViewControllerExtension.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 24/08/2020.
//  Copyright © 2020 Sphinx. All rights reserved.
//

import Cocoa

extension ProfileViewController {
    func shouldChangePIN() {
        let changePinCodeVC = ChangePinViewController.instantiate(mode: .ChangeStandard)
        changePinCodeVC.doneCompletion = { pin in
            AlertHelper.showTwoOptionsAlert(title: "pin.change".localized, message: "confirm.pin.change".localized, confirm: {
                UserData.sharedInstance.save(pin: pin)
                
                self.newMessageBubbleHelper.showGenericMessageView(
                    text: "pin.changed".localized,
                    in: self.view,
                    delay: 6,
                    backAlpha: 1.0
                )
                
                WindowsManager.sharedInstance.backToProfile()
            }, cancel: {
                WindowsManager.sharedInstance.backToProfile()
            })
        }
        advanceTo(
            vc: changePinCodeVC,
            identifier: "pin-change-window",
            title: "pin.change".localized,
            height: 500
        )
    }
    
    func uploadImage() {
        if let imgData = self.profileImage?.sd_imageData(as: .JPEG, compressionQuality: 0.5) {
            uploadingLabel.stringValue = String(format: "uploaded.progress".localized, 0)
            
            let attachmentsManager = AttachmentsManager.sharedInstance
            attachmentsManager.delegate = self
            
            let attachmentObject = AttachmentObject(data: imgData, type: AttachmentsManager.AttachmentType.Photo)
            attachmentsManager.uploadPublicImage(attachmentObject: attachmentObject)
        } else {
            updateProfile()
        }
    }
}

extension ProfileViewController : NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        saveEnabled = shouldEnableSaveButton()
    }
}

extension ProfileViewController : SettingsTabsDelegate {
    func didChangeSettingsTab(tag: Int) {
        let basicSelected = tag == SettingsTabsView.Tabs.Basic.rawValue
        basicSettingsView.isHidden = !basicSelected
        advancedSettingsView.isHidden = basicSelected
    }
}

extension ProfileViewController : DraggingViewDelegate {
    func imageDragged(image: NSImage) {
        profileImage = image
        profileImageView.image = image
        saveEnabled = shouldEnableSaveButton()
    }
}

extension ProfileViewController : AttachmentsManagerDelegate {
    func didUpdateUploadProgress(progress: Int) {
        let uploadedMessage = String(format: "uploaded.progress".localized, progress)
        uploadingLabel.stringValue = uploadedMessage
    }
    
    func didSuccessUploadingImage(url: String) {
        uploadingLabel.stringValue = ""
        
        if let image = profileImage {
            MediaLoader.storeImageInCache(img: image, url: url)
        }
        profileImageUrl = url
        updateProfile()
    }
}

extension ProfileViewController : PinTimeoutViewDelegate {
    func shouldEnableSave() {
        saveEnabled = true
    }
}
