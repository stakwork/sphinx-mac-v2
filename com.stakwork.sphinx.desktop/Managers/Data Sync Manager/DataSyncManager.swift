//
//  DataSyncManager.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 18/12/2025.
//  Copyright © 2025 Tomas Timinskas. All rights reserved.
//

import Foundation
import CoreData

// MARK: - DataSyncManager

class DataSyncManager: NSObject {

    // MARK: - Singleton

    static let sharedInstance = DataSyncManager()

    private override init() {
        super.init()
    }

    // MARK: - Typealias for backward compatibility

    typealias SettingKey = DataSyncSettingKey

    // MARK: - Properties

    /// Dedicated Core Data context for sync operations
    private lazy var syncContext: NSManagedObjectContext = {
        return CoreDataManager.sharedManager.getBackgroundContext()
    }()

    // MARK: - Sync Lock and Debouncing (Race Condition Fix)

    /// Lock to prevent concurrent sync operations
    private let syncLock = NSLock()

    /// Serial queue for sync operations
    private let syncQueue = DispatchQueue(label: "com.sphinx.datasync.queue")

    /// Debounce work item for sync
    private var syncWorkItem: DispatchWorkItem?

    /// Flag to track if sync is in progress
    private var isSyncing = false

    /// Debounce interval in seconds
    private let syncDebounceInterval: TimeInterval = 2.0

    // MARK: - Public Save Methods

    func saveTipAmount(value: String) {
        saveDataSyncItemWith(
            key: SettingKey.tipAmount.rawValue,
            identifier: "0",
            value: value
        )
    }

    func savePrivatePhoto(value: String) {
        saveDataSyncItemWith(
            key: SettingKey.privatePhoto.rawValue,
            identifier: "0",
            value: value
        )
    }

    func saveTimezoneFor(
        chatPubkey: String,
        timezone: TimezoneSetting
    ) {
        if let jsonString = timezone.toJSONString() {
            saveDataSyncItemWith(
                key: SettingKey.timezone.rawValue,
                identifier: chatPubkey,
                value: jsonString
            )
        }
    }

    func saveFeedStatusFor(
        feedId: String,
        feedStatus: FeedStatus
    ) {
        if let stringValue = feedStatus.toJSONString() {
            saveDataSyncItemWith(
                key: SettingKey.feedStatus.rawValue,
                identifier: feedId,
                value: stringValue
            )
        }
    }

    func saveFeedItemStatusFor(
        feedId: String,
        itemId: String,
        feedItemStatus: FeedItemStatus
    ) {
        if let jsonString = feedItemStatus.toJSONString() {
            saveDataSyncItemWith(
                key: SettingKey.feedItemStatus.rawValue,
                identifier: "\(feedId)-\(itemId)",
                value: jsonString
            )
        }
    }

    // MARK: - Core Data Operations

    private func saveDataSyncItemWith(
        key: String,
        identifier: String,
        value: String
    ) {
        syncContext.perform { [weak self] in
            guard let self = self else { return }

            let dataSyncItem = DataSync.getContentItemWith(
                key: key,
                identifier: identifier,
                context: self.syncContext
            ) ?? DataSync(context: self.syncContext)

            dataSyncItem.key = key
            dataSyncItem.identifier = identifier
            dataSyncItem.value = value
            dataSyncItem.date = Date()

            self.syncContext.saveContext()

            self.scheduleSyncWithServer()
        }
    }

    // MARK: - Sync Scheduling (Debouncing)

    private func scheduleSyncWithServer() {
        syncWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.syncWithServer()
        }

        syncWorkItem = workItem
        syncQueue.asyncAfter(deadline: .now() + syncDebounceInterval, execute: workItem)
    }

    func syncWithServerInBackground() {
        Task.detached(priority: .background) {
            self.scheduleSyncWithServer()
        }
    }

    // MARK: - Main Sync Logic

    private func syncWithServer() {
        // Prevent concurrent syncs
        syncLock.lock()
        
        guard !isSyncing else {
            syncLock.unlock()
            #if DEBUG
            print("DataSync: Sync already in progress, skipping")
            #endif
            return
        }
        isSyncing = true
        syncLock.unlock()

        Task {
            defer {
                syncLock.lock()
                isSyncing = false
                syncLock.unlock()
            }

            let serverDataString = await getFileFromServer()
            let parsedResponse = parseFileText(text: serverDataString ?? "")

            // CRITICAL: If we couldn't retrieve or parse server data, don't proceed with sync.
            // Proceeding with an empty itemsResponse would overwrite server data and cause data loss.
            guard serverDataString != nil || parsedResponse != nil else {
                #if DEBUG
                print("DataSync: Could not retrieve server data, skipping sync to prevent data loss")
                #endif
                return
            }

            var itemsResponse = parsedResponse ?? ItemsResponse(items: [])

            // Track items to delete after successful upload
            var itemsToDelete: [DataSync] = []

            // Collect all items that need to be restored from server
            var itemsToRestore: [SettingItem] = []

            await syncContext.perform { [weak self] in
                guard let self = self else { return }

                let dbItems = DataSync.getAllDataSync(context: self.syncContext)
                let missingItems = self.findMissingItems(firstArray: dbItems, secondArray: itemsResponse.items)

                // Add missing items (items in server but not in local DB)
                itemsToRestore.append(contentsOf: missingItems)

                for item in dbItems {
                    if let index = itemsResponse.getItemIndex(key: item.key, identifier: item.identifier) {
                        let serverItem = itemsResponse.items[index]

                        if serverItem.date.timeIntervalSince1970 < item.date.timeIntervalSince1970 {
                            if let key = DataSyncSettingKey(rawValue: item.key),
                               let settingValue = SettingValue.from(string: item.value, forKey: key) {
                                let newItem = SettingItem(
                                    key: item.key,
                                    identifier: item.identifier,
                                    dateString: "\(Int(item.date.timeIntervalSince1970))",
                                    value: settingValue
                                )
                                itemsResponse.items[index] = newItem
                                itemsToDelete.append(item)
                            }
                        } else {
                            // Server has newer data, add to restore list
                            itemsToRestore.append(serverItem)
                            itemsToDelete.append(item)
                        }
                    } else {
                        if let key = DataSyncSettingKey(rawValue: item.key),
                           let settingValue = SettingValue.from(string: item.value, forKey: key) {
                            let newItem = SettingItem(
                                key: item.key,
                                identifier: item.identifier,
                                dateString: "\(Int(item.date.timeIntervalSince1970))",
                                value: settingValue
                            )
                            itemsResponse.items.append(newItem)
                            itemsToDelete.append(item)
                        }
                    }
                }
            }

            // Sort items so feed_status are restored before feed_item_status
            // This ensures feeds are available when their item statuses are applied
            let sortedItemsToRestore = sortItemsForRestore(itemsToRestore)

            for item in sortedItemsToRestore {
                await restoreDataFrom(serverItem: item)
            }

            // MARK: - Chat Colors Sync (First One Wins Logic)
            // Colors in server but not local are already handled above via restoreDataFrom
            // Now add local colors that don't exist in server
            await MainActor.run {
                itemsResponse = self.syncChatColors(itemsResponse: itemsResponse)
            }

            // Only delete items after successful upload (Data Loss Prevention)
            let uploadSuccess = await saveFileToServer(itemResponse: itemsResponse)

            if uploadSuccess {
                await syncContext.perform { [weak self] in
                    guard let self = self else { return }

                    for item in itemsToDelete {
                        self.syncContext.delete(item)
                    }
                    self.syncContext.saveContext()

                    #if DEBUG
                    print("DataSync: Successfully synced and deleted \(itemsToDelete.count) local items")
                    #endif
                }
            } else {
                #if DEBUG
                print("DataSync: Upload failed, preserving \(itemsToDelete.count) local items for retry")
                #endif
            }
        }
    }

    // MARK: - Restore Data from Server

    private func restoreDataFrom(serverItem: SettingItem) async {
        guard let key = DataSyncSettingKey(rawValue: serverItem.key) else { return }

        await MainActor.run {
            switch key {
            case .tipAmount:
                if let intValue = serverItem.value.asInt {
                    UserContact.kTipAmount = intValue
                }

            case .privatePhoto:
                if let boolValue = serverItem.value.asBool {
                    if let owner = UserContact.getOwner() {
                        owner.privatePhoto = boolValue
                        owner.managedObjectContext?.saveContext()
                    }
                }

            case .timezone:
                if let chat = Chat.getChatWithOwnerPubkey(ownerPubkey: serverItem.identifier) {
                    chat.timezoneEnabled = serverItem.value.asTimezone?.timezoneEnabled ?? chat.timezoneEnabled
                    chat.timezoneIdentifier = serverItem.value.asTimezone?.timezoneIdentifier
                    chat.timezoneUpdated = true
                    chat.managedObjectContext?.saveContext()
                }

            case .feedStatus:
                if let feedStatus = serverItem.value.asFeedStatus {
                    if let feed = ContentFeed.getFeedById(feedId: serverItem.identifier) {
                        let podFeed = PodcastFeed.convertFrom(contentFeed: feed)
                        feed.chat = Chat.getChatWithOwnerPubkey(ownerPubkey: feedStatus.chatPubkey)
                        feed.feedURL = URL(string: feedStatus.feedUrl)
                        feed.subscribed = feedStatus.subscribed

                        podFeed.satsPerMinute = feedStatus.satsPerMinute
                        podFeed.playerSpeed = Float(feedStatus.playerSpeed)
                        
                        if feedStatus.itemId.isNotEmpty, podFeed.currentEpisodeId != feedStatus.itemId {
                            podFeed.currentEpisodeId = feedStatus.itemId
                            
                            if feed.dateLastConsumed == nil {
                                feed.dateLastConsumed = Date()
                            }
                        }
                        feed.managedObjectContext?.saveContext()

                        // Refresh the feed UI to show in Recently Played
                        FeedsManager.sharedInstance.refreshFeedUI()
                    } else {
                        FeedsManager.sharedInstance.getContentFeedFor(
                            feedId: feedStatus.feedId,
                            feedUrl: feedStatus.feedUrl,
                            chat: Chat.getChatWithOwnerPubkey(ownerPubkey: feedStatus.chatPubkey),
                            context: self.syncContext,
                            shouldSaveFeedStatus: false,  // Don't save - we're restoring from server
                            completion: { contentFeed in
                                guard let feed = contentFeed else { return }

                                let podFeed = PodcastFeed.convertFrom(contentFeed: feed)

                                // Set feed properties from restored status
                                feed.subscribed = feedStatus.subscribed
                                podFeed.satsPerMinute = feedStatus.satsPerMinute
                                podFeed.playerSpeed = Float(feedStatus.playerSpeed)

                                // Set current episode and date if itemId is present
                                if feedStatus.itemId.isNotEmpty {
                                    podFeed.currentEpisodeId = feedStatus.itemId

                                    if feed.dateLastConsumed == nil {
                                        feed.dateLastConsumed = Date()
                                    }
                                }

                                feed.managedObjectContext?.saveContext()

                                // Refresh the feed UI
                                FeedsManager.sharedInstance.refreshFeedUI()
                            }
                        )
                    }
                }

            case .feedItemStatus:
                guard let parsed = parseFeedItemIdentifier(serverItem.identifier),
                      let feedItem = ContentFeedItem.getItemWith(itemID: parsed.itemId),
                      let feedItemStatus = serverItem.value.asFeedItemStatus else {
                    return
                }

                let podEpisode = PodcastEpisode.convertFrom(contentFeedItem: feedItem)
                podEpisode.feedID = parsed.feedId
                podEpisode.duration = feedItemStatus.duration
                podEpisode.currentTime = feedItemStatus.currentTime
                feedItem.managedObjectContext?.saveContext()

            case .chatColor:
                // Chat colors are restored directly to ColorsManager and UserDefaults
                if let colorHex = serverItem.value.asString {
                    ColorsManager.sharedInstance.setColorFor(
                        colorHex: colorHex,
                        key: serverItem.identifier
                    )
                }
            }
        }
    }

    // MARK: - FeedItemStatus Identifier Parsing Fix

    /// Parses feedItemStatus identifier in format "feedId-itemId"
    /// Handles feedIds that may contain hyphens by splitting on the last hyphen
    private func parseFeedItemIdentifier(_ identifier: String) -> (feedId: String, itemId: String)? {
        guard let lastHyphenIndex = identifier.lastIndex(of: "-") else {
            return nil
        }

        let feedId = String(identifier[..<lastHyphenIndex])
        let itemId = String(identifier[identifier.index(after: lastHyphenIndex)...])

        guard !feedId.isEmpty, !itemId.isEmpty else {
            return nil
        }

        return (feedId, itemId)
    }

    // MARK: - Chat Colors Sync

    /// Syncs chat colors with "first one wins" logic.
    /// Colors from server are already applied to local via restoreDataFrom.
    /// This method adds local colors that don't exist on server to the items response.
    private func syncChatColors(itemsResponse: ItemsResponse) -> ItemsResponse {
        var updatedResponse = itemsResponse

        // Get all server color identifiers
        let serverColorIdentifiers = Set(
            itemsResponse.items
                .filter { $0.key == SettingKey.chatColor.rawValue }
                .map { $0.identifier }
        )

        // Get all local colors from ColorsManager
        let localColors = ColorsManager.sharedInstance.getAllColors()

        // Add local colors that don't exist on server
        for (colorKey, colorHex) in localColors {
            if !serverColorIdentifiers.contains(colorKey) {
                let newItem = SettingItem(
                    key: SettingKey.chatColor.rawValue,
                    identifier: colorKey,
                    dateString: "\(Int(Date().timeIntervalSince1970))",
                    value: .string(colorHex)
                )
                updatedResponse.items.append(newItem)

                #if DEBUG
                print("DataSync: Adding local chat color to server: \(colorKey) = \(colorHex)")
                #endif
            }
        }

        return updatedResponse
    }

    // MARK: - Helper Methods

    private func findMissingItems(firstArray: [DataSync], secondArray: [SettingItem]) -> [SettingItem] {
        // Create a Set of combined key-identifier strings from the first array
        let firstArraySet = Set(firstArray.map { "\($0.key)-\($0.identifier)" })

        // Filter items from second array that are not in first array
        let missingItems = secondArray.filter { item in
            let combinedKey = "\(item.key)-\(item.identifier)"
            return !firstArraySet.contains(combinedKey)
        }

        return missingItems
    }

    /// Sorts items so feed_status items are processed before feed_item_status items.
    /// This ensures feeds are created/fetched before their item statuses are applied.
    private func sortItemsForRestore(_ items: [SettingItem]) -> [SettingItem] {
        return items.sorted { item1, item2 in
            let isFeedStatus1 = item1.key == SettingKey.feedStatus.rawValue
            let isFeedStatus2 = item2.key == SettingKey.feedStatus.rawValue

            // feed_status items come first
            if isFeedStatus1 && !isFeedStatus2 {
                return true
            }
            if !isFeedStatus1 && isFeedStatus2 {
                return false
            }
            // Maintain original order for items of the same type
            return false
        }
    }

    // MARK: - JSON Parsing

    private func parseFileText(text: String) -> ItemsResponse? {
        guard let data = text.data(using: .utf8) else {
            #if DEBUG
            print("DataSync: Failed to convert text to data")
            #endif
            return nil
        }

        do {
            let decoder = JSONDecoder()
            let response = try decoder.decode(ItemsResponse.self, from: data)

            #if DEBUG
            printParsedItems(response)
            #endif

            return response
        } catch {
            #if DEBUG
            print("DataSync: Error parsing JSON: \(error)")
            if let decodingError = error as? DecodingError {
                printDecodingError(decodingError)
            }
            #endif
            return nil
        }
    }

    #if DEBUG
    private func printParsedItems(_ response: ItemsResponse) {
        print("DataSync: Successfully parsed \(response.items.count) items\n")

        // Create formatter once outside the loop (DateFormatter Optimization)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        formatter.timeZone = TimeZone.current

        for item in response.items {
            print("DataSync: ----------------------------------------")
            print("DataSync: Key: \(item.key)")
            print("DataSync: Identifier: \(item.identifier)")
            print("DataSync: Date: \(formatter.string(from: item.date))")

            switch item.value {
            case .string(let value):
                print("DataSync: Value (String): \(value)")
            case .int(let value):
                print("DataSync: Value (Int): \(value)")
            case .bool(let value):
                print("DataSync: Value (Bool): \(value)")
            case .timezone(let timezone):
                print("DataSync: Value (Timezone):")
                print("DataSync:    - Enabled: \(timezone.timezoneEnabled)")
                print("DataSync:    - Identifier: \(timezone.timezoneIdentifier ?? "nil (device timezone)")")
            case .feedStatus(let feedStatus):
                print("DataSync: Value (Feed Status):")
                print("DataSync:    - Chat Pubkey: \(feedStatus.chatPubkey)")
                print("DataSync:    - Feed URL: \(feedStatus.feedUrl)")
                print("DataSync:    - Subscribed: \(feedStatus.subscribed)")
                print("DataSync:    - Sats/Minute: \(feedStatus.satsPerMinute)")
                print("DataSync:    - Player Speed: \(feedStatus.playerSpeed)x")
                print("DataSync:    - Item ID: \(feedStatus.itemId)")
            case .feedItemStatus(let itemStatus):
                print("DataSync: Value (Feed Item Status):")
                print("DataSync:    - Duration: \(itemStatus.duration)s")
                print("DataSync:    - Current Time: \(itemStatus.currentTime)s")
                print("DataSync:    - Progress: \(String(format: "%.1f", itemStatus.progressPercentage))%")
                print("DataSync:    - Remaining: \(itemStatus.remainingTime)s")
                print("DataSync:    - Completed: \(itemStatus.isCompleted ? "Yes" : "No")")
            }
            print()
        }
    }

    private func printDecodingError(_ error: DecodingError) {
        switch error {
        case .dataCorrupted(let context):
            print("DataSync:    Context: \(context.debugDescription)")
            print("DataSync:    Path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
        case .keyNotFound(let key, let context):
            print("DataSync:    Key '\(key.stringValue)' not found")
            print("DataSync:    Context: \(context.debugDescription)")
        case .typeMismatch(let type, let context):
            print("DataSync:    Type '\(type)' mismatch")
            print("DataSync:    Context: \(context.debugDescription)")
        case .valueNotFound(let type, let context):
            print("DataSync:    Value '\(type)' not found")
            print("DataSync:    Context: \(context.debugDescription)")
        @unknown default:
            print("DataSync:    Unknown decoding error")
        }
    }
    #endif

    // MARK: - Server Communication

    /// Authenticates with the memes server if needed
    /// Returns true if authentication succeeded or was already authenticated
    private func authenticateWithServer() async -> Bool {
        let attachmentsManager = AttachmentsManager.sharedInstance
        let isAuthenticated = attachmentsManager.isAuthenticated()

        if isAuthenticated.0 {
            return true
        }

        return await withCheckedContinuation { continuation in
            attachmentsManager.authenticate(
                completion: {
                    continuation.resume(returning: true)
                },
                errorCompletion: {
                    #if DEBUG
                    print("DataSync: Error authenticating with memes server")
                    #endif
                    continuation.resume(returning: false)
                }
            )
        }
    }

    private func getFileFromServer() async -> String? {
        // Handle authentication if needed
        guard await authenticateWithServer() else {
            return nil
        }

        let attachmentsManager = AttachmentsManager.sharedInstance
        let isAuthenticated = attachmentsManager.isAuthenticated()

        guard let token = isAuthenticated.1 else {
            return nil
        }

        // Call the API with continuation
        return await withCheckedContinuation { continuation in
            API.sharedInstance.getPersonalPreferencesFile(
                token: token,
                callback: { data in
                    if let string = String(data: data, encoding: .utf8),
                       let decrypted = self.decrypt(value: string) {
                        continuation.resume(returning: decrypted)
                    } else {
                        continuation.resume(returning: nil)
                    }
                },
                errorCallback: {
                    continuation.resume(returning: nil)
                }
            )
        }
    }

    /// Saves item response to server
    /// Returns true on success, false on failure (Error Handling Improved)
    private func saveFileToServer(itemResponse: ItemsResponse) async -> Bool {
        if itemResponse.items.isEmpty {
            return true // Nothing to save is considered success
        }

        guard let text = itemResponse.toOriginalFormatJSON(),
              let encrypted = encrypt(value: text) else {
            return false
        }

        guard let pubkey = UserContact.getOwner()?.publicKey,
              let base64URLPubkey = hexToBase64URL(pubkey) else {
            return false
        }

        // Handle authentication
        guard await authenticateWithServer() else {
            return false
        }

        let attachmentsManager = AttachmentsManager.sharedInstance
        let isAuthenticated = attachmentsManager.isAuthenticated()

        guard let token = isAuthenticated.1 else {
            return false
        }

        // Convert to data safely (Force Unwrap Fixed)
        guard let data = encrypted.data(using: .utf8) else {
            #if DEBUG
            print("DataSync: Failed to convert encrypted string to data")
            #endif
            return false
        }

        return await withCheckedContinuation { continuation in
            API.sharedInstance.uploadPersonalPreferences(
                data: data,
                pubkey: base64URLPubkey,
                token: token,
                progressCallback: { progress in
                    #if DEBUG
                    print("DataSync: Upload progress: \(progress)")
                    #endif
                },
                callback: { (success, _) in
                    #if DEBUG
                    print("DataSync: Upload completed with success: \(success)")
                    #endif
                    continuation.resume(returning: success)
                },
                errorCallback: { error in
                    #if DEBUG
                    print("DataSync: Upload error: \(error)")
                    #endif
                    continuation.resume(returning: false)
                }
            )
        }
    }

    // MARK: - Encryption

    private func encrypt(value: String) -> String? {
        if let keys = SphinxOnionManager.sharedInstance.getPersonalKeys() {
            return SymmetricEncryptionManager.sharedInstance.encryptString(text: value, key: keys.secret)
        }
        return nil
    }

    private func decrypt(value: String) -> String? {
        if let keys = SphinxOnionManager.sharedInstance.getPersonalKeys() {
            return SymmetricEncryptionManager.sharedInstance.decryptString(text: value, key: keys.secret)
        }
        return nil
    }

    // MARK: - Utility

    private func hexToBase64URL(_ hex: String) -> String? {
        var data = Data()
        var hex = hex
        while hex.count > 0 {
            let index = hex.index(hex.startIndex, offsetBy: 2)
            let byteString = String(hex[..<index])
            hex = String(hex[index...])
            if let byte = UInt8(byteString, radix: 16) {
                data.append(byte)
            }
        }

        let base64 = data.base64EncodedString()

        let base64URL = base64
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        return base64URL
    }

    // MARK: - File Management

    func deleteFile() {
        let fileName = "datasync.txt"
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsURL.appendingPathComponent(fileName)

        do {
            try fileManager.removeItem(at: fileURL)
            #if DEBUG
            print("DataSync: File deleted successfully")
            #endif
        } catch {
            #if DEBUG
            print("DataSync: Error deleting file: \(error)")
            #endif
        }
    }
}
