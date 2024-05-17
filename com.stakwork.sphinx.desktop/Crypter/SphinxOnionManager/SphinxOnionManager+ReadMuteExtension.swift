//
//  SphinxOnionManager+ReadMuteExtension.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 13/05/2024.
//  Copyright © 2024 Tomas Timinskas. All rights reserved.
//

import Foundation

extension SphinxOnionManager {
    func processReadStatus(rr: RunReturn){
        if let lastRead = rr.lastRead {
            let lastReadIds = extractLastReadIds(jsonString: lastRead)
            print(lastReadIds)
            
            var chatListUnreadDict = [Int: Int]()
            for lastReadId in lastReadIds {
                if let message = TransactionMessage.getMessageWith(id: lastReadId), let chat = message.chat {
                    if let existingLastReadForChat = chatListUnreadDict[chat.id], lastReadId > existingLastReadForChat {
                        // Update the last read message ID if the new ID is greater than the existing one
                        chatListUnreadDict[chat.id] = lastReadId
                    } else if !chatListUnreadDict.keys.contains(chat.id) {
                        // Add the chat ID to the dictionary if it's not already there
                        chatListUnreadDict[chat.id] = lastReadId
                    }
                }
            }
            updateChatReadStatus(chatListUnreadDict: chatListUnreadDict)
        }
    }

    func processMuteLevels(rr: RunReturn) {
        if let muteLevels = rr.muteLevels {
            let muteDict = extractMuteIds(jsonString: muteLevels)
            updateMuteLevels(pubkeyToMuteLevelDict: muteDict)
        }
    }

    func updateChatReadStatus(chatListUnreadDict: [Int: Int]) {
        for (chatId, lastReadId) in chatListUnreadDict {
            Chat.updateMessageReadStatus(
                chatId: chatId,
                lastReadId: lastReadId
            )
        }
        ContactsService.sharedInstance.forceUpdate()
    }

    func updateMuteLevels(pubkeyToMuteLevelDict: [String: Any]) {
        for (pubkey, muteLevel) in pubkeyToMuteLevelDict {
            let chat = UserContact.getContactWith(pubkey: pubkey)?.getChat() ?? Chat.getTribeChatWithOwnerPubkey(ownerPubkey: pubkey)
            
            if let level = muteLevel as? Int, (chat?.notify ?? -1) != level {
                chat?.notify = level
                chat?.managedObjectContext?.saveContext()
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
