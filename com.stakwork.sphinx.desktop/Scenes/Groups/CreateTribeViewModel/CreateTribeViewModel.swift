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
            "id": CrypterManager.sharedInstance.generateCryptographicallySecureRandomInt(upperBound: Int(1e5)) as Any,
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
        
        SphinxOnionManager.sharedInstance.createTribe(
            params: params,
            callback: handleNewTribeNotification
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

        SphinxOnionManager.sharedInstance.updateTribe(
            params: params,
            pubkey: pubkey,
            id: id
        )
        
        updateChat(
            chat: chat,
            withParams: params
        )
        
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
        if let escrowAmount = params["escrow_amount"] as? Int {
            chat.escrowAmount = NSDecimalNumber(value: escrowAmount)
        }
        if let name = params["name"] as? String {
            chat.name = name
        }
        if let tags = params["tags"] as? [String] {
            // Assuming `tags` should be handled accordingly
            // chat.tags = tags
        }
        if let privateTribe = params["private"] as? Int {
            chat.privateTribe = privateTribe == 1
        }
        if let feedUrl = params["feed_url"] as? String,
            let url = URL(string: feedUrl){
            chat.contentFeed?.feedURL = url
        }

        if let escrowMillis = params["escrow_millis"] as? Int {
            // Assuming you have an `escrowMillis` property in `Chat`
            // chat.escrowMillis = escrowMillis
        }
        if let unlisted = params["unlisted"] as? Int {
            chat.unlisted = unlisted == 0
        }
        if let appUrl = params["app_url"] as? String {
            chat.tribeInfo?.appUrl = appUrl
        }
        if let img = params["img"] as? String {
            chat.photoUrl = img
        }
        if let isTribe = params["is_tribe"] as? Int {
            chat.isTribeICreated = isTribe == 1
        }
        if let priceToJoin = params["price_to_join"] as? Int {
            chat.priceToJoin = NSDecimalNumber(value: priceToJoin)
        }

        if let pricePerMessage = params["price_per_message"] as? Int {
            chat.pricePerMessage = NSDecimalNumber(value: pricePerMessage)
        }

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
