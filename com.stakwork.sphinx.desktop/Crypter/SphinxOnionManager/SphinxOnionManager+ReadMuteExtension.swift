//
//  SphinxOnionManager+ReadMuteExtension.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 13/05/2024.
//  Copyright © 2024 Tomas Timinskas. All rights reserved.
//

import Foundation

extension SphinxOnionManager {
    func handleReadStatus(rr: RunReturn) {
        var chatListUnreadDict = [Int: Int]()
        
        if let lastRead = rr.lastRead {
            let lastReadMap = parse(jsonString: lastRead)
            
            let pubKeys = lastReadMap.compactMap({ $0.key })
            
            backgroundContext.perform { [weak self] in
                guard let self = self else {
                    return
                }
                let tribes = Chat.getChatTribesFor(ownerPubkeys: pubKeys, context: self.backgroundContext)
                let contacts = UserContact.getContactsWith(pubkeys: pubKeys, context: self.backgroundContext)
                
                for (pubKey, lastReadId) in lastReadMap {
                    guard let lastReadId = lastReadId as? Int else {
                        continue
                    }
                    if let tribe = tribes.filter({ $0.ownerPubkey == pubKey }).first {
                        updateLastReadIndex(
                            chatId: tribe.id,
                            lastReadId: lastReadId
                        )
                    } else if let contact = contacts.filter({ $0.publicKey == pubKey }).first, let chat = contact.getChat() {
                        updateLastReadIndex(
                            chatId: chat.id,
                            lastReadId: lastReadId
                        )
                    }
                }
                self.updateChatReadStatus(chatListUnreadDict: chatListUnreadDict)
            }
        }
        
        func updateLastReadIndex(
            chatId: Int,
            lastReadId: Int
        ) {
            if let existingLastReadForChat = chatListUnreadDict[chatId], lastReadId > existingLastReadForChat {
                chatListUnreadDict[chatId] = lastReadId
            } else if !chatListUnreadDict.keys.contains(chatId) {
                chatListUnreadDict[chatId] = lastReadId
            }
        }
    }

    func handleMuteLevels(rr: RunReturn) {
        if let muteLevels = rr.muteLevels {
            let muteDict = extractMuteIds(jsonString: muteLevels)
            updateMuteLevels(pubkeyToMuteLevelDict: muteDict)
        }
    }

    func updateChatReadStatus(chatListUnreadDict: [Int: Int]) {
        for (chatId, lastReadId) in chatListUnreadDict {
            Chat.updateMessageReadStatus(
                chatId: chatId,
                lastReadId: lastReadId,
                context: backgroundContext
            )
        }
        backgroundContext.saveContext()
        setAppBadgeCount()
    }

    func updateMuteLevels(pubkeyToMuteLevelDict: [String: Any]) {
        backgroundContext.perform { [weak self] in
            guard let self = self else {
                return
            }
            for (pubkey, muteLevel) in pubkeyToMuteLevelDict {
                let chat = UserContact.getContactWith(
                    pubkey: pubkey,
                    managedContext: self.backgroundContext
                )?.getContactChat(context: self.backgroundContext) ?? Chat.getTribeChatWithOwnerPubkey(
                    ownerPubkey: pubkey,
                    context: self.backgroundContext
                )
                
                if let level = muteLevel as? Int, (chat?.notify ?? -1) != level {
                    chat?.notify = level
                    self.backgroundContext.saveContext()
                }
            }
        }
    }


    func extractLastReadIds(jsonString: String) -> [Int] {
        let values = parse(jsonString: jsonString)
        return values.values.compactMap({ $0 as? Int })
    }

    func extractMuteIds(jsonString: String) -> [String: Any] {
        let values = parse(jsonString: jsonString)
        return values
    }
    
    func parse(jsonString: String) -> [String: Any] {
        if let jsonData = jsonString.data(using: .utf8) {
            do {
                // Parse the JSON data into a dictionary
                if let jsonDict = try JSONSerialization.jsonObject(
                    with: jsonData,
                    options: []
                ) as? [String: Any] {
                    // Collect all values
                    return jsonDict
                }
            } catch {
                print("Error parsing JSON: \(error)")
            }
        } else {
            print("Error creating Data from jsonString")
        }

        return [:]
    }
}
