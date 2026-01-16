//
//  DataSyncManager.swift
//  sphinx
//
//  Created by Tomas Timinskas on 18/12/2025.
//  Copyright © 2025 Tomas Timinskas. All rights reserved.
//

class DataSyncManager : NSObject {
    
    class var sharedInstance : DataSyncManager {
        struct Static {
            static let instance = DataSyncManager()
        }
        return Static.instance
    }
    
    let backgroundContext = CoreDataManager.sharedManager.getBackgroundContext()
    
    enum SettingKey: String, CaseIterable {
        case tipAmount = "tip_amount"
        case privatePhoto = "private_photo"
        case timezone = "timezone"
        case feedStatus = "feed_status"
        case feedItemStatus = "feed_item_status"
    }
    
    func parseFileText(text: String) -> ItemsResponse? {
        var response: ItemsResponse! = nil
        
        do {
            let data = text.data(using: .utf8)!
            let decoder = JSONDecoder()
            response = try decoder.decode(ItemsResponse.self, from: data)
            
            print("✅ Successfully parsed \(response.items.count) items\n")
            
            for item in response.items {
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                print("📋 Key: \(item.key)")
                print("🆔 Identifier: \(item.identifier)")
                
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .medium
                formatter.timeZone = TimeZone.current
                print("📆 Date: \(formatter.string(from: item.date))")
                
                switch item.value {
                case .string(let value):
                    print("📝 Value (String): \(value)")
                    
                case .int(let value):
                    print("🔢 Value (Int): \(value)")
                    
                case .bool(let value):
                    print("✓ Value (Bool): \(value)")
                    
                case .timezone(let timezone):
                    print("🌍 Value (Timezone):")
                    print("   - Enabled: \(timezone.timezoneEnabled)")
                    print("   - Identifier: \(timezone.timezoneIdentifier)")
                    
                case .feedStatus(let feedStatus):
                    print("📻 Value (Feed Status):")
                    print("   - Chat Pubkey: \(feedStatus.chatPubkey)")
                    print("   - Feed URL: \(feedStatus.feedUrl)")
                    print("   - Subscribed: \(feedStatus.subscribed)")
                    print("   - Sats/Minute: \(feedStatus.satsPerMinute)")
                    print("   - Player Speed: \(feedStatus.playerSpeed)x")
                    print("   - Item ID: \(feedStatus.itemId)")
                    
                case .feedItemStatus(let itemStatus):
                    print("▶️ Value (Feed Item Status):")
                    print("   - Duration: \(itemStatus.duration)s")
                    print("   - Current Time: \(itemStatus.currentTime)s")
                    print("   - Progress: \(String(format: "%.1f", itemStatus.progressPercentage))%")
                    print("   - Remaining: \(itemStatus.remainingTime)s")
                    print("   - Completed: \(itemStatus.isCompleted ? "Yes" : "No")")
                }
                print()
            }
        } catch {
            print("❌ Error parsing JSON: \(error)")
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .dataCorrupted(let context):
                    print("   Context: \(context.debugDescription)")
                    print("   Path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
                case .keyNotFound(let key, let context):
                    print("   Key '\(key.stringValue)' not found")
                    print("   Context: \(context.debugDescription)")
                case .typeMismatch(let type, let context):
                    print("   Type '\(type)' mismatch")
                    print("   Context: \(context.debugDescription)")
                case .valueNotFound(let type, let context):
                    print("   Value '\(type)' not found")
                    print("   Context: \(context.debugDescription)")
                @unknown default:
                    print("   Unknown decoding error")
                }
            }
        }
        
        return response
    }
    
    func saveTipAmount(
        value: String,
        context: NSManagedObjectContext? = nil
    ) {
        saveDataSyncItemWith(
            key: SettingKey.tipAmount.rawValue,
            identifier: "0",
            value: value
        )
    }
    
    func savePrivatePhoto(
        value: String,
        context: NSManagedObjectContext? = nil
    ) {
        saveDataSyncItemWith(
            key: SettingKey.privatePhoto.rawValue,
            identifier: "0",
            value: value
        )
    }
    
    func saveTimezoneFor(
        chatPubkey: String,
        timezone: TimezoneSetting,
        context: NSManagedObjectContext? = nil
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
        feedStatus: FeedStatus,
        context: NSManagedObjectContext? = nil
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
        feedItemStatus: FeedItemStatus,
        context: NSManagedObjectContext? = nil
    ) {
        if let jsonString = feedItemStatus.toJSONString() {
            saveDataSyncItemWith(
                key: SettingKey.feedItemStatus.rawValue,
                identifier: "\(feedId)-\(itemId)",
                value: jsonString
            )
        }
    }
    
    func saveDataSyncItemWith(
        key: String,
        identifier: String,
        value: String,
        context: NSManagedObjectContext? = nil
    ) {
        let managedContext = context ?? backgroundContext
        let dataSyncItem = DataSync.getContentItemWith(key: key, identifier: identifier) ?? DataSync(context: managedContext) as DataSync
        
        dataSyncItem.key = key
        dataSyncItem.identifier = identifier
        dataSyncItem.value = value
        dataSyncItem.date = Date()
        
        managedContext.saveContext()
        
        syncWithServer()
    }
    
    func findMissingItems(firstArray: [DataSync], secondArray: [SettingItem]) -> [SettingItem] {
        // Create a Set of combined key-identifier strings from the first array
        let firstArraySet = Set(firstArray.map { "\($0.key)-\($0.identifier)" })
        
        // Filter items from second array that are not in first array
        let missingItems = secondArray.filter { item in
            let combinedKey = "\(item.key)-\(item.identifier)"
            return !firstArraySet.contains(combinedKey)
        }
        
        return missingItems
    }
    
    func syncWithServer() {
        let serverDataString = getFileFromServer()
        var itemsResponse = parseFileText(text: serverDataString ?? "") ?? ItemsResponse(items: [])
        let dbItems = DataSync.getAllDataSync(context: backgroundContext)
        let missingItems = findMissingItems(firstArray: dbItems, secondArray: itemsResponse.items)
        
        for item in missingItems {
            restoreDataFrom(serverItem: item)
        }
        
        for item in dbItems {
            if let index = itemsResponse.getItemIndex(key: item.key, identifier: item.identifier) {
                let serverItem = itemsResponse.items[index]
                
                if serverItem.date.timeIntervalSince1970 < item.date.timeIntervalSince1970 {
                    if let key = DataSyncManager.SettingKey(rawValue: item.key), let settingValue = SettingValue.from(string: item.value, forKey: key) {
                        let newItem = SettingItem(key: item.key, identifier: item.identifier, dateString: "\(item.date.timeIntervalSince1970)", value: settingValue)
                        itemsResponse.items[index] = newItem
                        
                        backgroundContext.delete(item)
                    }
                } else {
                    restoreDataFrom(serverItem: serverItem)
                }
            } else {
                if let key = DataSyncManager.SettingKey(rawValue: item.key), let settingValue = SettingValue.from(string: item.value, forKey: key) {
                    let newItem = SettingItem(key: item.key, identifier: item.identifier, dateString: "\(item.date.timeIntervalSince1970)", value: settingValue)
                    itemsResponse.items.append(newItem)
                }
            }
            
            backgroundContext.delete(item)
        }
        
        backgroundContext.saveContext()
        
        saveFileFrom(itemReponse: itemsResponse)
    }
    
    func restoreDataFrom(serverItem: SettingItem) {
        if let key = DataSyncManager.SettingKey(rawValue: serverItem.key) {
            switch(key) {
            case .tipAmount:
                if let intValue = serverItem.value.asInt {
                    UserContact.kTipAmount = intValue
                }
                break
            case .privatePhoto:
                if let boolValue = serverItem.value.asBool {
                    if let owner = UserContact.getOwner() {
                        owner.privatePhoto = boolValue
                    }
                }
                break
            case .timezone:
                if let chat = Chat.getChatWithOwnerPubkey(ownerPubkey: serverItem.identifier) {
                    chat.timezoneEnabled = serverItem.value.asTimezone?.timezoneEnabled ?? chat.timezoneEnabled
                    chat.timezoneIdentifier = serverItem.value.asTimezone?.timezoneIdentifier
                    chat.timezoneUpdated = true
                }
                break
            case .feedStatus:
                if let feedStatus = serverItem.value.asFeedStatus {
                    if let feed = ContentFeed.getFeedById(feedId: serverItem.identifier) {
                        let podFeed = PodcastFeed.convertFrom(contentFeed: feed)
                        feed.chat = Chat.getChatWithOwnerPubkey(ownerPubkey: feedStatus.chatPubkey)
                        feed.feedURL = URL(string: feedStatus.feedUrl)
                        feed.subscribed = feedStatus.subscribed
                        
                        podFeed.satsPerMinute = feedStatus.satsPerMinute
                        podFeed.playerSpeed = Float(feedStatus.playerSpeed)
                        podFeed.currentEpisodeId = feedStatus.itemId
                    } else {
                        FeedsManager.sharedInstance.getContentFeedFor(
                            feedId: feedStatus.feedId,
                            feedUrl: feedStatus.feedUrl,
                            chat: Chat.getChatWithOwnerPubkey(ownerPubkey: feedStatus.chatPubkey),
                            context: backgroundContext,
                            completion: { _ in }
                        )
                    }
                }
                break
            case .feedItemStatus:
                if let feedItem = ContentFeedItem.getItemWith(itemID: serverItem.identifier) {
                    if let feedItemStatus = serverItem.value.asFeedItemStatus {
                        let podEpisode = PodcastEpisode.convertFrom(contentFeedItem: feedItem)
                        podEpisode.duration = feedItemStatus.duration
                        podEpisode.currentTime = feedItemStatus.currentTime
                    }
                }
            }
        }
    }
    
    func deleteFile() {
        let fileName = "datasync.txt"
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsURL.appendingPathComponent(fileName)

        do {
            try fileManager.removeItem(at: fileURL)
            print("✅ File deleted successfully")
        } catch {
            print("❌ Error deleting file: \(error)")
        }
    }
    
    func getFileFromServer() -> String? {
        let fileName = "datasync.txt"
            
        // Get Documents directory
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsURL.appendingPathComponent(fileName)
        
        // CHECK IF FILE ALREADY EXISTS
        if fileManager.fileExists(atPath: fileURL.path) {
            print("✅ File already exists at: \(fileURL.path)")
            
            // Read and return existing content
            do {
                let fileContent = try String(contentsOf: fileURL, encoding: .utf8)
                if let decrypted = decrypt(value: fileContent) {
                    return decrypted
                }
                print("❌ Error decrypting existing file")
                return nil
            } catch {
                print("❌ Error reading existing file: \(error)")
                return nil
            }
        }
        
        // FILE DOESN'T EXIST - CREATE DEFAULT FILE
        print("📝 File doesn't exist, creating default file...")
        
        let date = Int(Date().addingTimeInterval(TimeInterval(-3600)).timeIntervalSince1970)
        
        let text = """
        {"items": [
            {"key": "tip_amount", "identifier": "0", "date": "\(date)", "value": "12"},
        ]}
        """
        
        if let encrypted = encrypt(value: text) {
            do {
                try encrypted.write(to: fileURL, atomically: true, encoding: .utf8)
                print("✅ File created at: \(fileURL.path)")
            } catch {
                print("❌ Error: \(error)")
            }
        }
        
        do {
            let fileContent = try String(contentsOf: fileURL, encoding: .utf8)
            if let decrypted = decrypt(value: fileContent) {
                return decrypted
            }
            print("❌ Error decrypting existing file")
        } catch {
            print("❌ Error reading existing file: \(error)")
            return nil
        }
        
        return nil
    }
    
    func saveFileFrom(itemReponse: ItemsResponse) {
        let fileName = "datasync.txt"
        
        guard let text = itemReponse.toOriginalFormatJSON(), let encrypted = encrypt(value: text) else {
            return
        }
            
        // Get Documents directory
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsURL.appendingPathComponent(fileName)
        
        do {
            try encrypted.write(to: fileURL, atomically: true, encoding: .utf8)
            print("✅ File saved at: \(fileURL.path)")
        } catch {
            print("❌ Error: \(error)")
        }
        
        ///Send file to memes server
    }
    
    func encrypt(value: String) -> String? {
        if let mnemonic = UserData.sharedInstance.getMnemonic() {
            if let seed = try? Sphinx.mnemonicToSeed(mnemonic: mnemonic) {
                if let keys = try? Sphinx.nodeKeys(net: "bitcoin", seed: seed) {
                    return SymmetricEncryptionManager.sharedInstance.encryptString(text: value, key: keys.secret)
                }
            }
        }
        return nil
    }
    
    func decrypt(value: String) -> String? {
        if let mnemonic = UserData.sharedInstance.getMnemonic() {
            if let seed = try? Sphinx.mnemonicToSeed(mnemonic: mnemonic) {
                if let keys = try? Sphinx.nodeKeys(net: "bitcoin", seed: seed) {
                    return SymmetricEncryptionManager.sharedInstance.decryptString(text: value, key: keys.secret)
                }
            }
        }
        return nil
    }
}

struct ItemsResponse: Codable {
    var items: [SettingItem]
    
    func getItemIndex(key: String, identifier: String) -> Int? {
        return items.firstIndex(where: { $0.key == key && $0.identifier == identifier })
    }
    
    func toOriginalFormatJSON(prettyPrinted: Bool = false) -> String? {
        var itemsArray: [[String: Any]] = []
        
        for item in items {
            var itemDict: [String: Any] = [
                "key": item.key,
                "identifier": item.identifier,
                "date": String(format: "%.0f", item.date.timeIntervalSince1970)
            ]
            
            // Convert value based on type
            switch item.value {
            case .string(let value):
                itemDict["value"] = value
                
            case .int(let value):
                itemDict["value"] = String(value)
                
            case .bool(let value):
                itemDict["value"] = value ? "true" : "false"
                
            case .timezone(let timezone):
                itemDict["value"] = [
                    "timezoneEnabled": timezone.timezoneEnabled ? "true" : "false",
                    "timezoneIdentifier": timezone.timezoneIdentifier
                ]
                
            case .feedStatus(let feedStatus):
                itemDict["value"] = [
                    "chat_pubkey": feedStatus.chatPubkey,
                    "feed_url": feedStatus.feedUrl,
                    "subscribed": feedStatus.subscribed ? "true" : "false",
                    "sats_per_minute": String(feedStatus.satsPerMinute),
                    "player_speed": String(feedStatus.playerSpeed),
                    "item_id": feedStatus.itemId,
                    "feed_id": feedStatus.feedId
                ]
                
            case .feedItemStatus(let itemStatus):
                itemDict["value"] = [
                    "duration": String(itemStatus.duration),
                    "current_time": String(itemStatus.currentTime)
                ]
            }
            
            itemsArray.append(itemDict)
        }
        
        let jsonObject: [String: Any] = ["items": itemsArray]
        
        do {
            let jsonData = try JSONSerialization.data(
                withJSONObject: jsonObject,
                options: prettyPrinted ? [.prettyPrinted, .sortedKeys] : []
            )
            return String(data: jsonData, encoding: .utf8)
        } catch {
            print("❌ Serialization error: \(error)")
            return nil
        }
    }
}

// MARK: - Setting Item

struct SettingItem: Codable {
    var key: String
    var identifier: String
    var dateString: String
    var value: SettingValue
    
    // Date as actual Date object
    var date: Date {
        if let timestamp = TimeInterval(dateString) {
            return Date(timeIntervalSince1970: timestamp)
        }
        return Date() // Fallback to current date
    }
    
    // CodingKeys to map JSON to properties
    enum CodingKeys: String, CodingKey {
        case key
        case identifier
        case dateString = "date"
        case value
    }
}

// MARK: - Setting Value (Handles String, Bool, Int, and Object)

enum SettingValue: Codable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case timezone(TimezoneSetting)
    case feedStatus(FeedStatus)
    case feedItemStatus(FeedItemStatus)
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        // Try FeedStatus first
        if let feedStatus = try? container.decode(FeedStatus.self) {
            self = .feedStatus(feedStatus)
            return
        }
        
        // Try FeedItemStatus
        if let feedItemStatus = try? container.decode(FeedItemStatus.self) {
            self = .feedItemStatus(feedItemStatus)
            return
        }
        
        // Try timezone object
        if let timezone = try? container.decode(TimezoneSetting.self) {
            self = .timezone(timezone)
            return
        }
        
        // Try string
        if let string = try? container.decode(String.self) {
            // Check if it's a boolean string
            if string.lowercased() == "true" {
                self = .bool(true)
                return
            } else if string.lowercased() == "false" {
                self = .bool(false)
                return
            }
            
            // Check if it's an integer string
            if let intValue = Int(string) {
                self = .int(intValue)
                return
            }
            
            // Check if it's a double string
            if let doubleValue = Double(string), !string.contains(".") {
                self = .int(Int(doubleValue))
                return
            }
            
            // Otherwise it's just a string
            self = .string(string)
            return
        }
        
        // Try direct int
        if let int = try? container.decode(Int.self) {
            self = .int(int)
            return
        }
        
        // Try direct bool
        if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
            return
        }
        
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Cannot decode value"
        )
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .timezone(let setting):
            try container.encode(setting)
        case .feedStatus(let status):
            try container.encode(status)
        case .feedItemStatus(let status):
            try container.encode(status)
        }
    }
    
    // Helper computed properties
    var asString: String? {
        switch self {
        case .string(let value): return value
        case .int(let value): return String(value)
        case .bool(let value): return String(value)
        default: return nil
        }
    }
    
    var asInt: Int? {
        switch self {
        case .int(let value): return value
        case .string(let value): return Int(value)
        case .bool(let value): return value ? 1 : 0
        default: return nil
        }
    }
    
    var asBool: Bool? {
        switch self {
        case .bool(let value): return value
        case .string(let value): return Bool(value)
        case .int(let value): return value != 0
        default: return nil
        }
    }
    
    var asTimezone: TimezoneSetting? {
        if case .timezone(let setting) = self {
            return setting
        }
        return nil
    }
    
    var asFeedStatus: FeedStatus? {
        if case .feedStatus(let status) = self {
            return status
        }
        return nil
    }
    
    var asFeedItemStatus: FeedItemStatus? {
        if case .feedItemStatus(let status) = self {
            return status
        }
        return nil
    }
    
    static func from(string: String, forKey key: DataSyncManager.SettingKey) -> SettingValue? {
        switch key {
        case .tipAmount:
            // tip_amount is always an Int
            guard let intValue = Int(string) else {
                print("❌ Failed to parse '\(string)' as Int for \(key.rawValue)")
                return nil
            }
            return .int(intValue)
            
        case .privatePhoto:
            // private_photo is always a Bool
            guard let boolValue = parseBool(from: string) else {
                print("❌ Failed to parse '\(string)' as Bool for \(key.rawValue)")
                return nil
            }
            return .bool(boolValue)
            
        case .timezone:
            // timezone is always a TimezoneSetting object
            guard let timezone = parseTimezone(from: string) else {
                print("❌ Failed to parse '\(string)' as TimezoneSetting for \(key.rawValue)")
                return nil
            }
            return .timezone(timezone)
            
        case .feedStatus:
            // feed_status is always a FeedStatus object
            guard let feedStatus = parseFeedStatus(from: string) else {
                print("❌ Failed to parse '\(string)' as FeedStatus for \(key.rawValue)")
                return nil
            }
            return .feedStatus(feedStatus)
            
        case .feedItemStatus:
            // feed_item_status is always a FeedItemStatus object
            guard let feedItemStatus = parseFeedItemStatus(from: string) else {
                print("❌ Failed to parse '\(string)' as FeedItemStatus for \(key.rawValue)")
                return nil
            }
            return .feedItemStatus(feedItemStatus)
        }
    }
    
    // MARK: - Private Parsing Helpers
    
    private static func parseBool(from string: String) -> Bool? {
        switch string.lowercased() {
        case "true", "1", "yes":
            return true
        case "false", "0", "no":
            return false
        default:
            return nil
        }
    }
    
    private static func parseTimezone(from string: String) -> TimezoneSetting? {
        guard let data = string.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let enabled = json["timezoneEnabled"] as? String,
              let identifier = json["timezoneIdentifier"] as? String else {
            return nil
        }
        
        return TimezoneSetting(
            timezoneEnabledString: enabled,
            timezoneIdentifier: identifier
        )
    }
    
    private static func parseFeedStatus(from string: String) -> FeedStatus? {
        guard let data = string.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let chatPubkey = json["chat_pubkey"] as? String,
              let feedUrl = json["feed_url"] as? String,
              let feedId = json["feed_id"] as? String,
              let subscribed = json["subscribed"] as? String,
              let satsPerMinute = json["sats_per_minute"] as? String,
              let playerSpeed = json["player_speed"] as? String,
              let itemId = json["item_id"] as? String else {
            return nil
        }
        
        return FeedStatus(
            chatPubkey: chatPubkey,
            feedUrl: feedUrl,
            feedId: feedId,
            subscribed: subscribed.lowercased() == "true",
            satsPerMinute: Int(satsPerMinute) ?? 0,
            playerSpeed: Double(playerSpeed) ?? 1.0,
            itemId: itemId
        )
    }
    
    private static func parseFeedItemStatus(from string: String) -> FeedItemStatus? {
        guard let data = string.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let duration = json["duration"] as? String,
              let currentTime = json["current_time"] as? String else {
            return nil
        }
        
        return FeedItemStatus(
            duration: Int(duration) ?? 0,
            currentTime: Int(currentTime) ?? 0
        )
    }
}

// MARK: - Timezone Setting

struct TimezoneSetting: Codable {
    private let timezoneEnabledString: String
    let timezoneIdentifier: String
    
    // Boolean property
    var timezoneEnabled: Bool {
        return timezoneEnabledString.lowercased() == "true"
    }
    
    enum CodingKeys: String, CodingKey {
        case timezoneEnabledString = "timezoneEnabled"
        case timezoneIdentifier
    }
    
    init(timezoneEnabledString: String, timezoneIdentifier: String) {
        self.timezoneEnabledString = timezoneEnabledString
        self.timezoneIdentifier = timezoneIdentifier
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timezoneEnabledString = try container.decode(String.self, forKey: .timezoneEnabledString)
        timezoneIdentifier = try container.decode(String.self, forKey: .timezoneIdentifier)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        // Encode values as strings
        try container.encode(timezoneEnabledString, forKey: .timezoneEnabledString)
        try container.encode(timezoneIdentifier, forKey: .timezoneIdentifier)
    }
    
    func toJSONString() -> String? {
        let encoder = JSONEncoder()
        
        do {
            let jsonData = try encoder.encode(self)
            return String(data: jsonData, encoding: .utf8)
        } catch {
            print("❌ Error encoding TimezoneSetting: \(error)")
            return nil
        }
    }
}

// MARK: - Feed Status

struct FeedStatus: Codable {
    let chatPubkey: String
    let feedUrl: String
    let feedId: String
    let subscribed: Bool
    let satsPerMinute: Int
    let playerSpeed: Double
    let itemId: String
    
    enum CodingKeys: String, CodingKey {
        case chatPubkey = "chat_pubkey"
        case feedUrl = "feed_url"
        case feedId = "feed_id"
        case subscribed = "subscribed"
        case satsPerMinute = "sats_per_minute"
        case playerSpeed = "player_speed"
        case itemId = "item_id"
    }
    
    init(
        chatPubkey: String,
        feedUrl: String,
        feedId: String,
        subscribed: Bool,
        satsPerMinute: Int,
        playerSpeed: Double,
        itemId: String
    ) {
        self.chatPubkey = chatPubkey
        self.feedUrl = feedUrl
        self.feedId = feedId
        self.subscribed = subscribed
        self.satsPerMinute = satsPerMinute
        self.playerSpeed = playerSpeed
        self.itemId = itemId
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Parse chat_pubkey
        chatPubkey = try container.decode(String.self, forKey: .chatPubkey)
        
        // Parse feed_url
        feedUrl = try container.decode(String.self, forKey: .feedUrl)
        
        // Parse feed_url
        feedId = try container.decode(String.self, forKey: .feedId)
        
        // Parse subscribed
        let subscribedString = try container.decode(String.self, forKey: .subscribed)
        subscribed = subscribedString.lowercased() == "true"
        
        // Parse sats_per_minute
        let satsString = try container.decode(String.self, forKey: .satsPerMinute)
        satsPerMinute = Int(satsString) ?? 0
        
        // Parse player_speed
        let speedString = try container.decode(String.self, forKey: .playerSpeed)
        playerSpeed = Double(speedString) ?? 1.0
        
        // Parse item_id
        let itemIdString = try container.decode(String.self, forKey: .itemId)
        itemId = itemIdString
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        // Encode all values as strings
        try container.encode(chatPubkey, forKey: .chatPubkey)
        try container.encode(feedUrl, forKey: .feedUrl)
        try container.encode(feedId, forKey: .feedId)
        try container.encode(subscribed ? "true" : "false", forKey: .subscribed)
        try container.encode(String(satsPerMinute), forKey: .satsPerMinute)
        try container.encode(String(playerSpeed), forKey: .playerSpeed)
        try container.encode(itemId, forKey: .itemId)
    }
    
    func toJSONString() -> String? {
        let encoder = JSONEncoder()
        
        do {
            let jsonData = try encoder.encode(self)
            return String(data: jsonData, encoding: .utf8)
        } catch {
            print("❌ Error encoding FeedStatus: \(error)")
            return nil
        }
    }
}

// MARK: - Feed Item Status

struct FeedItemStatus: Codable {
    let duration: Int
    let currentTime: Int
    
    enum CodingKeys: String, CodingKey {
        case duration
        case currentTime = "current_time"
    }
    
    init(duration: Int, currentTime: Int) {
        self.duration = duration
        self.currentTime = currentTime
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Parse duration
        let durationString = try container.decode(String.self, forKey: .duration)
        duration = Int(durationString) ?? 0
        
        // Parse current_time
        let currentTimeString = try container.decode(String.self, forKey: .currentTime)
        currentTime = Int(currentTimeString) ?? 0
    }
    
    // Computed property for progress percentage
    var progressPercentage: Double {
        guard duration > 0 else { return 0 }
        return (Double(currentTime) / Double(duration)) * 100
    }
    
    // Computed property for remaining time
    var remainingTime: Int {
        return max(0, duration - currentTime)
    }
    
    // Is completed?
    var isCompleted: Bool {
        return currentTime >= duration
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        // Encode all values as strings
        try container.encode(String(duration), forKey: .duration)
        try container.encode(String(currentTime), forKey: .currentTime)
    }
    
    func toJSONString() -> String? {
        let encoder = JSONEncoder()
        
        do {
            let jsonData = try encoder.encode(self)
            return String(data: jsonData, encoding: .utf8)
        } catch {
            print("❌ Error encoding FeedItemStatus: \(error)")
            return nil
        }
    }
}
