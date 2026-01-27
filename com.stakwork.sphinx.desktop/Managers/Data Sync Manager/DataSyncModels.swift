//
//  DataSyncModels.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 18/12/2025.
//  Copyright © 2025 Tomas Timinskas. All rights reserved.
//

import Foundation

// MARK: - DataSyncSettingKey Enum

enum DataSyncSettingKey: String, CaseIterable {
    case tipAmount = "tip_amount"
    case privatePhoto = "private_photo"
    case timezone = "timezone"
    case feedStatus = "feed_status"
    case feedItemStatus = "feed_item_status"
}

// MARK: - Items Response

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
            #if DEBUG
            print("DataSync: Serialization error: \(error)")
            #endif
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

    static func from(string: String, forKey key: DataSyncSettingKey) -> SettingValue? {
        switch key {
        case .tipAmount:
            // tip_amount is always an Int
            guard let intValue = Int(string) else {
                #if DEBUG
                print("DataSync: Failed to parse '\(string)' as Int for \(key.rawValue)")
                #endif
                return nil
            }
            return .int(intValue)

        case .privatePhoto:
            // private_photo is always a Bool
            guard let boolValue = parseBool(from: string) else {
                #if DEBUG
                print("DataSync: Failed to parse '\(string)' as Bool for \(key.rawValue)")
                #endif
                return nil
            }
            return .bool(boolValue)

        case .timezone:
            // timezone is always a TimezoneSetting object
            guard let timezone = parseTimezone(from: string) else {
                #if DEBUG
                print("DataSync: Failed to parse '\(string)' as TimezoneSetting for \(key.rawValue)")
                #endif
                return nil
            }
            return .timezone(timezone)

        case .feedStatus:
            // feed_status is always a FeedStatus object
            guard let feedStatus = parseFeedStatus(from: string) else {
                #if DEBUG
                print("DataSync: Failed to parse '\(string)' as FeedStatus for \(key.rawValue)")
                #endif
                return nil
            }
            return .feedStatus(feedStatus)

        case .feedItemStatus:
            // feed_item_status is always a FeedItemStatus object
            guard let feedItemStatus = parseFeedItemStatus(from: string) else {
                #if DEBUG
                print("DataSync: Failed to parse '\(string)' as FeedItemStatus for \(key.rawValue)")
                #endif
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
            #if DEBUG
            print("DataSync: Error encoding TimezoneSetting: \(error)")
            #endif
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

        // Parse feed_id
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
            #if DEBUG
            print("DataSync: Error encoding FeedStatus: \(error)")
            #endif
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
            #if DEBUG
            print("DataSync: Error encoding FeedItemStatus: \(error)")
            #endif
            return nil
        }
    }
}
