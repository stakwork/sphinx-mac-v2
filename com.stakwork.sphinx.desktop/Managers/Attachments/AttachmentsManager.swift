//
//  AttachmentsManager.swift
//  com.stakwork.sphinx.desktop
//
//  Created by Tomas Timinskas on 11/05/2020.
//  Copyright © 2020 Sphinx. All rights reserved.
//

import Foundation
import SwiftyJSON
import AVFoundation

@objc protocol AttachmentsManagerDelegate: AnyObject {
    @objc optional func didUpdateUploadProgress(progress: Int, provisionalMessageId: Int)
    @objc optional func didFailSendingMessage(provisionalMessage: TransactionMessage?)
    @objc optional func didFailSendingAttachment(provisionalMessage: TransactionMessage?, errorMessage: String)
    @objc optional func didSuccessSendingAttachment(message: TransactionMessage, image: NSImage?, provisionalMessageId: Int)
    @objc optional func didSuccessUploadingImage(url: String)
}

class AttachmentsManager {
    
    class var sharedInstance : AttachmentsManager {
        struct Static {
            static let instance = AttachmentsManager()
        }
        return Static.instance
    }
    
    public enum AttachmentType: Int {
        case Photo
        case Video
        case Audio
        case Gif
        case Text
        case PDF
        case GenericFile
    }
    
    var uploading = false
    var provisionalMessage: TransactionMessage? = nil
    var contact: UserContact? = nil
    var chat: Chat? = nil
    var uploadedImage: NSImage? = nil
    
    weak var delegate: AttachmentsManagerDelegate?
    
    func setData(delegate: AttachmentsManagerDelegate, contact: UserContact?, chat: Chat?, provisionalMessage: TransactionMessage? = nil) {
        self.delegate = delegate
        self.contact = contact
        self.chat = chat
        self.uploadedImage = nil
    }
    
    func authenticate(
        completion: @escaping (String) -> (),
        errorCompletion: @escaping () -> ()
    ) {
        if let token: String = UserDefaults.Keys.attachmentsToken.get() {
            let expDate: Date? = UserDefaults.Keys.attachmentsTokenExpDate.get()
            
            if let expDate = expDate, expDate > Date() {
                completion(token)
                return
            }
        }
        
        guard let pubkey = UserContact.getOwner()?.publicKey else {
            errorCompletion()
            return
        }
        
        API.sharedInstance.askAuthentication(callback: { id, challenge in
            if let id = id, let challenge = challenge {
                
                self.delegate?.didUpdateUploadProgress?(progress: 10, provisionalMessageId: self.provisionalMessage?.id ?? -1)
                
                guard let sig = SphinxOnionManager.sharedInstance.signChallenge(challenge: challenge) else{
                    errorCompletion()
                    return
                }
                
                self.delegate?.didUpdateUploadProgress?(progress: 15, provisionalMessageId: self.provisionalMessage?.id ?? -1)
                
                API.sharedInstance.verifyAuthentication(id: id, sig: sig, pubkey: pubkey, callback: { token in
                    if let token = token {
                        UserDefaults.Keys.attachmentsToken.set(token)
                        
                        if let ts = token.decodeJWT().payload?["exp"] as? Int64 {
                            let timestamp = TimeInterval(integerLiteral: ts)
                            let date = Date(timeIntervalSince1970: timestamp)
                            UserDefaults.Keys.attachmentsTokenExpDate.set(date)
                        }
                        
                        completion(token)
                    } else {
                        errorCompletion()
                    }
                })
                
            } else {
                errorCompletion()
            }
        })
    }
    
    func cancelUpload() {
        API.sharedInstance.cancelUploadRequest()
        uploading = false
        provisionalMessage = nil
        delegate = nil
        uploadedImage = nil
    }
    
    func isAuthenticated() -> (Bool, String?) {
        if let token: String = UserDefaults.Keys.attachmentsToken.get() {
            let expDate: Date? = UserDefaults.Keys.attachmentsTokenExpDate.get()
            
            if let expDate = expDate, expDate > Date() {
                return (true, token)
            }
        }
        return (false, nil)
    }
    
    func getMediaItemInfo(message: TransactionMessage, callback: @escaping MediaInfoCallback) {
        let isAuthenticated = isAuthenticated()
        
        if !isAuthenticated.0 {
            self.authenticate(completion: { _ in
                self.getMediaItemInfo(message: message, callback: callback)
            }, errorCompletion: {
                UserDefaults.Keys.attachmentsToken.removeValue()
            })
            return
        }
        
        guard let token = isAuthenticated.1 else {
            return
        }
        
        API.sharedInstance.getMediaItemInfo(message: message, token: token, callback: callback)
    }
    
    func uploadPublicImage(attachmentObject: AttachmentObject) {
        delegate?.didUpdateUploadProgress?(
            progress: 5,
            provisionalMessageId: provisionalMessage?.id ?? -1
        )
        
        let isAuthenticated = isAuthenticated()
        
        if !isAuthenticated.0 {
            self.authenticate(completion: { token in
                self.uploadPublicImage(attachmentObject: attachmentObject)
            }, errorCompletion: {
                UserDefaults.Keys.attachmentsToken.removeValue()
                self.uploadFailed(errorMessage: "Could not authenticate with Memes server")
            })
            return
        }
        
        delegate?.didUpdateUploadProgress?(
            progress: 10,
            provisionalMessageId: provisionalMessage?.id ?? -1
        )
        
        guard let token = isAuthenticated.1 else {
            return
        }
        
        if let _ = attachmentObject.data {
            uploadData(attachmentObject: attachmentObject, route: "public", token: token) { fileJSON, _ in
                if let muid = fileJSON["muid"] as? String {
                    self.delegate?.didSuccessUploadingImage?(url: "\(API.kAttachmentsServerUrl)/public/\(muid)")
                }
            }
        }
    }
    
    func uploadAndSendAttachments(
        attachmentObjects: [AttachmentObject],
        index: Int,
        chat: Chat?,
        replyingMessage: TransactionMessage? = nil,
        threadUUID: String? = nil
    ) {
        if index == attachmentObjects.count {
            return
        }
        
        uploading = true
        
        let attachmentObject = attachmentObjects[index]
        
        if let _ = attachmentObject.data, let provisionalMsg = attachmentObject.provisionalMsg {
            self.provisionalMessage = provisionalMsg
            
            delegate?.didUpdateUploadProgress?(
                progress: 5,
                provisionalMessageId: provisionalMessage?.id ?? -1
            )
            
            let isAuthenticated = isAuthenticated()
            
            if !isAuthenticated.0 {
                self.authenticate(completion: { token in
                    self.uploadAndSendAttachments(
                        attachmentObjects: attachmentObjects,
                        index: index,
                        chat: chat,
                        replyingMessage: replyingMessage,
                        threadUUID: threadUUID
                    )
                }, errorCompletion: {
                    UserDefaults.Keys.attachmentsToken.removeValue()
                    self.uploadFailed(errorMessage: "Could not authenticate with Memes server")
                })
                return
            }
            
            delegate?.didUpdateUploadProgress?(
                progress: 10,
                provisionalMessageId: provisionalMessage?.id ?? -1
            )
            
            guard let token = isAuthenticated.1 else {
                return
            }
            
            uploadData(attachmentObject: attachmentObject, token: token) { fileJSON, AttachmentObject in
                let (msg, errorMessage) = self.sendAttachment(
                    file: fileJSON,
                    chat: chat,
                    attachmentObject: attachmentObject,
                    provisionalMessage: provisionalMsg,
                    replyingMessage: (index == attachmentObjects.count - 1) ? replyingMessage : nil, //Adding reply just on last attachment
                    threadUUID: threadUUID
                )
                
                if let errorMessage = errorMessage, msg == nil {
                    self.uploadFailed(errorMessage: errorMessage)
                }
                
                self.uploadAndSendAttachments(
                    attachmentObjects: attachmentObjects,
                    index: index + 1,
                    chat: chat,
                    replyingMessage: replyingMessage,
                    threadUUID: threadUUID
                )
            }
        }
    }
    
    func uploadData(attachmentObject: AttachmentObject, route: String = "file", token: String, completion: @escaping (NSDictionary, AttachmentObject) -> ()) {
        API.sharedInstance.uploadData(attachmentObject: attachmentObject, route: route, token: token, progressCallback: { progress in
            let totalProgress = (progress * 85) / 100 + 10
            self.delegate?.didUpdateUploadProgress?(
                progress: totalProgress,
                provisionalMessageId: self.provisionalMessage?.id ?? -1
            )
        }, callback: { success, fileJSON in
            AttachmentsManager.sharedInstance.uploading = false
            
            if let fileJSON = fileJSON, success {
                self.uploadedImage = attachmentObject.image
                completion(fileJSON, attachmentObject)
            } else {
                self.uploadFailed(errorMessage: "Failed to upload data to Memes server")
            }
        })
    }
    
    func sendAttachment(
        file: NSDictionary,
        chat: Chat?,
        attachmentObject: AttachmentObject,
        provisionalMessage: TransactionMessage? = nil,
        replyingMessage: TransactionMessage? = nil,
        threadUUID: String? = nil
    ) -> (TransactionMessage?, String?) {
        return SphinxOnionManager.sharedInstance.sendAttachment(
            file: file,
            attachmentObject: attachmentObject,
            chat: chat,
            provisionalMessage: provisionalMessage,
            replyingMessage: replyingMessage,
            threadUUID: threadUUID
        )
    }
    
    func payAttachment(message: TransactionMessage, chat: Chat?, callback: @escaping (TransactionMessage?) -> ()) {
        guard let price = message.getAttachmentPrice() else {
            return
        }
        SphinxOnionManager.sharedInstance.payAttachment(message: message, price: price)
    }
    
    func createLocalMessage(
        message: JSON,
        attachmentObject: AttachmentObject
    ) {
        let provisionalMessageId = provisionalMessage?.id
        
        if let message = TransactionMessage.insertMessage(
            m: message,
            existingMessage: provisionalMessage
        ).0 {
            delegate?.didUpdateUploadProgress?(
                progress: 100,
                provisionalMessageId: self.provisionalMessage?.id ?? -1
            )
            cacheImageAndMediaData(message: message, attachmentObject: attachmentObject)
            uploadSucceed(message: message)
            deleteMessageWith(id: provisionalMessageId)
        }
    }
    
    func deleteMessageWith(id: Int?) {
        if let id = id {
            TransactionMessage.deleteMessageWith(id: id)
        }
    }
    
    func cacheImageAndMediaData(message: TransactionMessage, attachmentObject: AttachmentObject) {
        if let mediaUrl = message.getMediaUrl()?.absoluteString {
            if let data = attachmentObject.data, message.shouldCacheData() {
                if let mediaKey = message.mediaKey {
                    if let decryptedData = SymmetricEncryptionManager.sharedInstance.decryptData(data: data, key: mediaKey) {
                        MediaLoader.storeMediaDataInCache(data: decryptedData, url: mediaUrl)
                    }
                }
            }
            
            if let image = uploadedImage {
                MediaLoader.storeImageInCache(img: image, url: mediaUrl)
            }
        }
    }
    
    func uploadFailed(errorMessage: String) {
        uploading = false
        delegate?.didFailSendingAttachment?(provisionalMessage: provisionalMessage, errorMessage: errorMessage)
    }
    
    func uploadSucceed(message: TransactionMessage) {
        uploading = false
        delegate?.didSuccessSendingAttachment?(
            message: message,
            image: self.uploadedImage,
            provisionalMessageId: provisionalMessage?.id ?? -1
        )
    }
    
    func getThumbnailFromVideo(videoURL: URL) -> NSImage? {
        var thumbnailImage: NSImage? = nil
        do {
            let asset = AVURLAsset(url: videoURL, options: nil)
            let imgGenerator = AVAssetImageGenerator(asset: asset)
            imgGenerator.appliesPreferredTrackTransform = true
            let cgImage = try imgGenerator.copyCGImage(at: CMTimeMake(value: 0, timescale: 1), actualTime: nil)
            thumbnailImage = NSImage(cgImage: cgImage, size: NSSize(width: 220, height: 220))
        } catch _ {}
        
        return thumbnailImage
    }
    
    func getDataAndType(image: NSImage?, video: Data?, videoUrl: URL?) -> (Data?, AttachmentsManager.AttachmentType, NSImage?) {
        if let videoData = video {
            if let videoUrl = videoUrl , let thumbnail = getThumbnailFromVideo(videoURL: videoUrl) {
                return (videoData, AttachmentsManager.AttachmentType.Video, thumbnail)
            } else {
                return (videoData, AttachmentsManager.AttachmentType.Video, nil)
            }
        } else if let imageData = image?.tiffRepresentation(using: .jpeg, factor: 0.5) {
            return (imageData, AttachmentsManager.AttachmentType.Photo, image)
        }
        return (nil, AttachmentsManager.AttachmentType.Photo, nil)
    }
}
