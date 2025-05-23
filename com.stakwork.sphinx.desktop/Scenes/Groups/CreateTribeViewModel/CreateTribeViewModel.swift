//
//  CreateTribeViewModel.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 04/10/2022.
//  Copyright © 2022 Tomas Timinskas. All rights reserved.
//

import Cocoa
import SDWebImage
import SwiftyJSON

class CreateTribeViewModel {
    
    let groupsManager = GroupsManager.sharedInstance
    let messageBubbleHelper = NewMessageBubbleHelper()
    
    var chat: Chat? = nil
    var errorCallback: (() -> ())? = nil
    var successCallback: (() -> ())? = nil
    
    init(
        chat: Chat? = nil,
        successCallback: @escaping () -> (),
        errorCallback: @escaping () -> ()
    ) {
        self.chat = chat
        self.successCallback = successCallback
        self.errorCallback = errorCallback
        
        groupsManager.resetNewGroupInfo()
        
        if let tribeInfo = chat?.tribeInfo {
            groupsManager.newGroupInfo = tribeInfo
        }
    }
    
    func setInfo(
        name: String? = nil,
        description: String? = nil,
        img: String? = nil,
        priceToJoin: Int? = nil,
        pricePerMessage: Int? = nil,
        amountToStake: Int? = nil,
        timeToStake: Int? = nil,
        appUrl: String? = nil,
        secondBrainUrl: String? = nil,
        feedUrl: String? = nil,
        feedType: FeedContentType? = nil,
        listInTribes: Bool,
        privateTribe: Bool
    ) {
        groupsManager.setInfo(
            name: name,
            description: description,
            img: img,
            priceToJoin: priceToJoin,
            pricePerMessage: pricePerMessage,
            amountToStake: amountToStake,
            timeToStake: timeToStake,
            appUrl: appUrl,
            secondBrainUrl: secondBrainUrl,
            feedUrl: feedUrl,
            feedType: feedType,
            listInTribes: listInTribes,
            privateTribe: privateTribe
        )
    }
    
    func updateTag(index: Int, selected: Bool) {
        if (groupsManager.newGroupInfo.tags.count >  index) {
            var tag = groupsManager.newGroupInfo.tags[index]
            tag.selected = selected
            groupsManager.newGroupInfo.tags[index] = tag
        }
    }
    
    func updateFeedType(type: FeedContentType) {
        groupsManager.newGroupInfo.feedContentType = type
    }
    
    func tribeInfo() -> GroupsManager.TribeInfo? {
        return groupsManager.newGroupInfo
    }
    
    func isEditing() -> Bool {
        return chat?.id != nil
    }
    
    func saveChanges(_ image: NSImage? = nil) {
        if let image = image, let imgData = image.sd_imageData(as: .JPEG, compressionQuality: 0.5) {

            let attachmentsManager = AttachmentsManager.sharedInstance
            attachmentsManager.delegate = self
            
            let attachmentObject = AttachmentObject(data: imgData, type: AttachmentsManager.AttachmentType.Photo)
            attachmentsManager.uploadPublicImage(attachmentObject: attachmentObject)
        } else {
            editOrCreateGroup()
        }
    }
    
    func editOrCreateGroup() {
//        if !NetworkMonitor.shared.isNetworkConnected() {
//            AlertHelper.showAlert(
//                title: "generic.error.title".localized,
//                message: SphinxOnionManagerError.SOMNetworkError.localizedDescription
//            )
//            return
//        }
        
        let params = groupsManager.getNewGroupParams()
        
        if let chat = chat {
            editGroup(id: chat.id, params: params)
        } else {
            createGroup(params: params)
        }
    }
    
    func mapChatJSON(
        rawTribeJSON:[String:Any]
    ) -> JSON?
    {
        guard let name = rawTribeJSON["name"] as? String,
              let ownerPubkey = rawTribeJSON["pubkey"] as? String,
              ownerPubkey.isPubKey else
        {
            self.didFailSavingTribe()
            return nil
        }
        var chatDict = rawTribeJSON
        
        let mappedFields : [String:Any] = [
            "id": SphinxOnionManager.sharedInstance.generateCryptographicallySecureRandomInt(upperBound: Int(1e5)) as Any,
            "owner_pubkey": ownerPubkey,
            "name" : name,
            "is_tribe_i_created": true,
            "type": Chat.ChatType.publicGroup.rawValue
        ]
        
        for key in mappedFields.keys {
            chatDict[key] = mappedFields[key]
        }
        
        let chatJSON = JSON(chatDict)
        return chatJSON
    }
    
    func createGroup(params: [String: AnyObject]) {
        guard let _ = params["name"] as? String,
              let _ = params["description"] as? String else
        {
            self.didFailSavingTribe()
            return
        }
        
        let _ = SphinxOnionManager.sharedInstance.createTribe(
            params: params,
            callback: handleNewTribeNotification, 
            errorCallback: { error in
                AlertHelper.showAlert(
                    title: "generic.error.title".localized,
                    message: error?.localizedDescription ?? ""
                )
            }
        )
    }
    

    func handleNewTribeNotification(tribeJSONString: String) {
        if let tribeJSON = try? tribeJSONString.toDictionary(),
           let chatJSON = mapChatJSON(rawTribeJSON: tribeJSON),
           let chat = Chat.insertChat(chat: chatJSON)
        {
            chat.managedObjectContext?.saveContext()
            self.didSuccessSavingTribe()
            return
        }
        self.didFailSavingTribe()
    }
    
    func editGroup(id: Int, params: [String: AnyObject]) {
        errorCallback?()

        guard let chat = Chat.getChatWith(id: id),
              let pubkey = chat.ownerPubkey else
        {
            self.didFailSavingTribe()
            return
        }

        let success = SphinxOnionManager.sharedInstance.updateTribe(
            params: params,
            pubkey: pubkey
        )
        
        if success {
            updateChat(
                chat: chat,
                withParams: params
            )
        }
        
        DelayPerformedHelper.performAfterDelay(
            seconds: 0.5,
            completion: {
                self.didSuccessSavingTribe()
            }
        )
    }
    
    func updateChat(
        chat: Chat,
        withParams params: [String: AnyObject]
    ) {
        chat.tribeInfo = GroupsManager.sharedInstance.getTribesInfoFrom(json: JSON(params))
        chat.updateChatFromTribesInfo()
        chat.managedObjectContext?.saveContext()
    }
    
    func didFailSavingTribe() {
        self.errorCallback?()
        self.messageBubbleHelper.showGenericMessageView(text: "generic.error.message".localized, delay: 3, textColor: NSColor.white, backColor: NSColor.Sphinx.BadgeRed, backAlpha: 1.0)
    }
    
    func didSuccessSavingTribe() {
        NotificationCenter.default.post(name: .shouldReloadTribeData, object: nil)
        self.successCallback?()
    }
    
}

extension CreateTribeViewModel : AttachmentsManagerDelegate {
    func didUpdateUploadProgress(progress: Int) {}
    
    func didSuccessUploadingImage(url: String) {
        groupsManager.newGroupInfo.img = url
        
        editOrCreateGroup()
    }
}
