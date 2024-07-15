//
//  NotificationsHelper.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 20/07/2020.
//  Copyright © 2020 Sphinx. All rights reserved.
//

import Foundation
import UserNotifications

class NotificationsHelper : NSObject {
    
    public enum NotificationType: Int {
        case BannerAndSound = 0
        case Banner = 1
        case Sound = 2
        case Off = 3
    }
    
    public struct Sound {
        var name : String
        var file : String
        var selected : Bool = false
        
        init(name: String, file: String, selected: Bool) {
            self.name = name
            self.file = file
            self.selected = selected
        }
    }
    
    var sounds = [Sound]()
    
    let cache = SphinxCache()
    
    override init() {
        super.init()
        
        sounds.append(Sound(name: "TriTone (default)", file: "tri-tone.caf", selected: true))
        sounds.append(Sound(name: "Aurora", file: "aurora.caf", selected: false))
        sounds.append(Sound(name: "Bamboo", file: "bamboo.caf", selected: false))
        sounds.append(Sound(name: "Bell", file: "bell.caf", selected: false))
        sounds.append(Sound(name: "Bells", file: "bells.caf", selected: false))
        sounds.append(Sound(name: "Glass", file: "glass.caf", selected: false))
        sounds.append(Sound(name: "Horn", file: "horn.caf", selected: false))
        sounds.append(Sound(name: "Note", file: "note.caf", selected: false))
        sounds.append(Sound(name: "Popcorn", file: "popcorn.caf", selected: false))
        sounds.append(Sound(name: "Synth", file: "synth.caf", selected: false))
        sounds.append(Sound(name: "Tweet", file: "tweet.caf", selected: false))
    }
    
    func getFileFor(name: String?) -> String {
        let soundsName = name ?? "TriTone (default)"
        
        for sound in sounds {
            if sound.name == soundsName {
                return sound.file
            }
        }
        
        return sounds[0].file
    }
    
    func getNotificationType() -> Int {
        if let type = UserDefaults.Keys.notificationType.get(defaultValue: 0) {
            return type
        }
        return NotificationType.Banner.rawValue
    }
    
    func getNotificationSoundFile() -> String {
        if let sound = UserDefaults.Keys.notificationSound.get(defaultValue: "tri-tone.caf") {
            return sound
        }
        return sounds[0].file
    }
    
    func getNotificationSoundTag() -> Int {
        let file = getNotificationSoundFile()
        
        for i in 0..<sounds.count {
            let sound = sounds[i]
            if sound.file == file {
                return i
            }
        }
        
        return 0
    }
    
    func sendNotification(
        title: String,
        subtitle: String? = nil,
        text: String
    ) -> Void {
        if let notification = createNotificationFrom(
            title: title,
            subtitle: subtitle,
            text: text
        ) {
            sendNotification(notification)
            
            if shouldPlaySound() {
                SoundsPlayer.playSound(name: getNotificationSoundFile())
            }
        }
    }
    
    func sendNotification(message: TransactionMessage) -> Void {
        if isOff() {
            return
        }
        
        if TransactionMessage.typesToExcludeFromChat.contains(message.type) {
            return
        }
        
        if !message.shouldSendNotification() {
            return
        }
        
        if let notification = createNotificationFrom(message) {
            sendNotification(notification)
        }
        
        if shouldPlaySound() {
            SoundsPlayer.playSound(name: getNotificationSoundFile())
        }
    }
    
    func setNotificationType(tag: Int) {
        UserDefaults.Keys.notificationType.set(tag)
    }
    
    func setNotificationSound(tag: Int) {
        let sound = sounds[tag]
        UserDefaults.Keys.notificationSound.set(sound.file)
    }
    
    func isOff() -> Bool {
        return UserDefaults.Keys.notificationType.get(defaultValue: 0) == NotificationType.Off.rawValue
    }
    
    func shouldPlaySound() -> Bool {
        return UserDefaults.Keys.notificationType.get(defaultValue: 0) == NotificationType.Sound.rawValue ||
               UserDefaults.Keys.notificationType.get(defaultValue: 0) == NotificationType.BannerAndSound.rawValue
    }
    
    func shouldShowBanner() -> Bool {
        return UserDefaults.Keys.notificationType.get(defaultValue: 0) == NotificationType.Banner.rawValue ||
               UserDefaults.Keys.notificationType.get(defaultValue: 0) == NotificationType.BannerAndSound.rawValue
    }
    
    func askForNotificationsPermission() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) {
            (_, _) in
        }
        
        setMessageNotificationCategory()
    }
    
    func setMessageNotificationCategory() {
        let replyAction = UNTextInputNotificationAction(
            identifier: "REPLY_ACTION",
            title: "Reply",
            options: [],
            textInputButtonTitle: "Send",
            textInputPlaceholder: "message.placeholder".localized
        )
        
        let category = UNNotificationCategory(
            identifier: "MESSAGE_CATEGORY",
            actions: [replyAction],
            intentIdentifiers: [],
            options: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
    
    func createNotificationFrom(
        title: String,
        subtitle: String? = nil,
        text: String
    ) -> UNMutableNotificationContent? {
        let notification = UNMutableNotificationContent()
        notification.title = title
        if let subtitle = subtitle {
            notification.subtitle = subtitle
        }
        notification.body = text
        notification.sound = UNNotificationSound.default
        
        return notification
    }
    
    func createNotificationFrom(
        _ message: TransactionMessage
    ) -> UNMutableNotificationContent? {
        
        setMessageNotificationCategory()
        
        guard let owner = UserContact.getOwner() else {
            return nil
        }
        
        if shouldShowBanner() {
            let notification = UNMutableNotificationContent()
            
            let chatName = message.chat?.name ?? ""
            let chatId = message.chat?.id ?? -1
            
            let sender = message.getMessageSender()
            
            let senderNickName = message.getMessageSenderNickname(
                owner: owner,
                contact: sender
            )
            
            let messageDescription = message.getMessageContentPreview(
                owner: owner,
                contact: sender,
                includeSender: false
            )
            
            if message.chat?.isPublicGroup() ?? false {
                notification.title = chatName
                notification.subtitle = senderNickName
            } else {
                notification.title = senderNickName
            }
            
            notification.body = messageDescription
            notification.userInfo = ["chat-id" : chatId]
//            notification.categoryIdentifier = "MESSAGE_CATEGORY"

            if let sender = sender, let cachedImage = sender.getCachedImage(), let url = saveImageToDisk(image: cachedImage, name: "notificationImage") {
                do {
                    let attachment = try UNNotificationAttachment(
                        identifier: "image",
                        url: url,
                        options: [UNNotificationAttachmentOptionsTypeHintKey: kUTTypePNG as String]
                    )
                    notification.attachments = [attachment]
                } catch let error {
                    print("The attachment was not loaded.")
                }
            } else if let chat = message.chat, let cachedImage = chat.getCachedImage(), let url = saveImageToDisk(image: cachedImage, name: "notificationImage") {
                do {
                    let attachment = try UNNotificationAttachment(
                        identifier: "image",
                        url: url,
                        options: [UNNotificationAttachmentOptionsTypeHintKey: kUTTypePNG as String]
                    )
                    notification.attachments = [attachment]
                } catch {
                    print("The attachment was not loaded.")
                }
            }
            
            return notification
        }
        return nil
    }
    
    func saveImageToDisk(image: NSImage, name: String) -> URL? {
        guard let resizedImage = resizeImage(image: image, maxSize: CGSize(width: 512, height: 512)),
                  let tiffData = resizedImage.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmap.representation(using: .png, properties: [:]) else { return nil }
        
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).png")
        do {
            try pngData.write(to: fileURL)
            print("Image saved to \(fileURL)")
            return fileURL
        } catch {
            print("Failed to write image data to disk: \(error)")
            return nil
        }
    }
    
    func resizeImage(image: NSImage, maxSize: CGSize) -> NSImage? {
        let aspectRatio = image.size.width / image.size.height
        var newSize = maxSize
        
        if aspectRatio > 1 {
            newSize.height = maxSize.width / aspectRatio
        } else {
            newSize.width = maxSize.height * aspectRatio
        }
        
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize), from: NSRect(origin: .zero, size: image.size), operation: .copy, fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }
    
    func sendNotification(_ notification: UNMutableNotificationContent) {
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: notification, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error adding notification: \(error)")
            }
        }
    }
}

extension NotificationsHelper : UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let notification = response.notification.request.content
        
        if let chatId = notification.userInfo["chat-id"] as? Int {
            if response.actionIdentifier == "REPLY_ACTION" {
                if let textResponse = response as? UNTextInputNotificationResponse {
                    let replyText = textResponse.userText
                    let userInfo: [String: Any] = ["chat-id" : chatId, "message" : replyText.trunc(length: 500)]
                    NotificationCenter.default.post(name: .chatNotificationClicked, object: nil, userInfo: userInfo)
                }
            } else {
                let userInfo: [String: Any] = ["chat-id" : chatId]
                NotificationCenter.default.post(name: .chatNotificationClicked, object: nil, userInfo: userInfo)
            }
        }
    }
}
