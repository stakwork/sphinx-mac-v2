//
//  GroupsManager.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 05/06/2020.
//  Copyright © 2020 Sphinx. All rights reserved.
//

import Foundation
import SwiftyJSON

class GroupsManager {

    class var sharedInstance : GroupsManager {
        struct Static {
            static let instance = GroupsManager()
        }
        return Static.instance
    }
    
    var contactIds : [Int] = []
    var name : String? = nil
    private var chatLastReadLookup : [Int:(Int, CGFloat)] = [:]
    
    func resetData() {
        contactIds = [Int]()
        name = nil
    }
    
    func setName(name: String) {
        self.name = name
    }
    
    func setContactIds(contactIds: [Int]) {
        self.contactIds = contactIds
    }
    
    //chat scroll retention
    func setChatLastRead(chatID: Int, tablePosition: (Int, CGFloat)){
        chatLastReadLookup[chatID] = tablePosition
    }
    
    func getChatLastRead(chatID: Int?) -> (TransactionMessage?, CGFloat)? {
        if let chatID = chatID, let result = chatLastReadLookup[chatID]{
            return (TransactionMessage.getMessageWith(id: result.0), result.1)
        }
        return nil
    }
    
    func getGroupParams() -> (Bool, [String: AnyObject]) {
        var parameters = [String : AnyObject]()
        
        if let name = name {
            parameters["name"] = name as AnyObject
        } else {
            return (false, [:])
        }
        
        if contactIds.count > 0 {
            parameters["contact_ids"] = contactIds as AnyObject
        } else {
            return (false, [:])
        }
        
        return (true, parameters)
    }
    
    func getSelectedContacts(contacts: [UserContact]) -> [UserContact] {
        return contacts.filter { contactIds.contains($0.id) }
    }
    
    func getAddMembersParams() -> (Bool, [String: AnyObject]) {
        var parameters = [String : AnyObject]()
        
        if contactIds.count > 0 {
            parameters["contact_ids"] = contactIds as AnyObject
        } else {
            return (false, [:])
        }
        
        return (true, parameters)
    }
    
    func deleteGroup(chat: Chat?, completion: @escaping (Bool) -> ()) {
        guard let chat = chat else {
            completion(false)
            return
        }
        
//        API.sharedInstance.deleteGroup(id: chat.id, callback: { success in
//            if success {
//                CoreDataManager.sharedManager.deleteChatObjectsFor(chat)
//                completion(true)
//            } else {
//                completion(false)
//            }
//        })
    }
    
    var newGroupInfo = TribeInfo()
    
    func resetNewGroupInfo() {
        newGroupInfo = TribeInfo()
        newGroupInfo.tags = getGroupTags()
    }
    
    func setInfo(
        name: String? = nil,
        description: String? = nil,
        img: String? = nil,
        tags: [Tag]? = nil,
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
        newGroupInfo.name = name ?? newGroupInfo.name
        newGroupInfo.description = description ?? newGroupInfo.description
        newGroupInfo.img = img ?? newGroupInfo.img
        newGroupInfo.tags = tags ?? newGroupInfo.tags
        newGroupInfo.priceToJoin = priceToJoin ?? newGroupInfo.priceToJoin
        newGroupInfo.pricePerMessage = pricePerMessage ?? newGroupInfo.pricePerMessage
        newGroupInfo.amountToStake = amountToStake ?? newGroupInfo.amountToStake
        newGroupInfo.timeToStake = timeToStake ?? newGroupInfo.timeToStake
        newGroupInfo.appUrl = appUrl ?? newGroupInfo.appUrl
        newGroupInfo.secondBrainUrl = secondBrainUrl ?? newGroupInfo.secondBrainUrl
        newGroupInfo.feedUrl = feedUrl ?? newGroupInfo.feedUrl
        newGroupInfo.feedContentType = feedType ?? newGroupInfo.feedContentType
        newGroupInfo.unlisted = !listInTribes
        newGroupInfo.privateTribe = privateTribe
    }
    
    func isGroupInfoValid() -> Bool {
        return !(newGroupInfo.name ?? "").isEmpty && !(newGroupInfo.description ?? "").isEmpty
    }
    
    struct TribeInfo {
        var name : String? = nil
        var description : String? = nil
        var img : String? = nil
        var groupKey : String? = nil
        var ownerPubkey : String? = nil
        var ownerAlias : String? = nil
        var pin : String? = nil
        var host : String! = nil
        var uuid : String! = nil
        var tags : [Tag] = []
        var pricePerMessage : Int? = nil
        var amountToStake : Int? = nil
        var timeToStake : Int? = nil
        var unlisted : Bool = false
        var privateTribe : Bool = false
        var deleted : Bool = false
        var appUrl : String? = nil
        var feedUrl : String? = nil
        var secondBrainUrl : String? = nil
        var feedContentType : FeedContentType? = nil
        var ownerRouteHint : String? = nil
        var bots : [Bot] = []
        var priceToJoin : Int? = nil
        
        var nonZeroPriceToJoin: Int {
            if let priceToJoin = priceToJoin, priceToJoin > 0 {
                return priceToJoin
            }
            return 1000
        }
    }
    
    struct Tag {
        var image : String
        var description : String
        var selected : Bool = false
        
        init(image: String, description: String) {
            self.image = image
            self.description = description
        }
    }
    
    struct Bot {
        var prefix: String = ""
        var price: Int = 0
        var commands: [BotCommand] = []
        
        init(json: JSON) {
            self.prefix = json["prefix"].string ?? ""
            self.price = json["price"].int ?? 0
            
            var commandObjects: [BotCommand] = []
            
            for cmd in json["commands"].array ?? [] {
                let commandObject = BotCommand(json: cmd)
                commandObjects.append(commandObject)
            }
            
            self.commands = commandObjects
        }
    }

    struct BotCommand {
        var command: String? = nil
        var price: Int? = nil
        var minPrice: Int? = nil
        var maxPrice: Int? = nil
        var priceIndex: Int? = nil
        var adminOnly: Bool? = nil
        
        init(json: JSON) {
            self.command = json["command"].string
            self.price = json["price"].int
            self.minPrice = json["min_price"].int
            self.maxPrice = json["max_price"].int
            self.priceIndex = json["price_index"].int
            self.adminOnly = json["admin_only"].bool
        }
    }

    
    func getGroupTags() -> [Tag] {
        let bitcoingTag = Tag(image: "bitcoinTagIcon", description: "Bitcoin")
        let lightningTag = Tag(image: "lightningTagIcon", description: "Lightning")
        let sphinxTag = Tag(image: "sphinxTagIcon", description: "Sphinx")
        let cryptoTag = Tag(image: "cryptoTagIcon", description: "Crypto")
        let techTag = Tag(image: "techTagIcon", description: "Tech")
        let altcoinsTag = Tag(image: "altcoinsTagIcon", description: "Altcoins")
        let musicTag = Tag(image: "musicTagIcon", description: "Music")
        let podcastTag = Tag(image: "podcastTagIcon", description: "Podcast")
        
        return [bitcoingTag, lightningTag, sphinxTag, cryptoTag, techTag, altcoinsTag, musicTag, podcastTag]
    }
    
    func getGroupInfo(query: String) -> TribeInfo? {
        var tribeInfo = TribeInfo()
        
        let components = query.components(separatedBy: "&")
        if components.count > 0 {
            for component in components {
                let elements = component.components(separatedBy: "=")
                if elements.count > 1 {
                    let key = elements[0]
                    let value = elements[1]
                    
                    switch(key) {
                    case "uuid":
                        tribeInfo.uuid = value
                        break
                    case "host":
                        tribeInfo.host = value
                        break
                    case "pubkey":
                        tribeInfo.ownerPubkey = value
                        tribeInfo.uuid = value
                        break
                    default:
                        break
                    }
                }
            }
        }
        
        if let _ = tribeInfo.uuid, let _ = tribeInfo.host {
            ///v1
            return tribeInfo
        } else if let _ = tribeInfo.ownerPubkey, let _ = tribeInfo.host {
            ///v2
            return tribeInfo
        }
        return nil
    }
    
    func getNewGroupParams() -> [String: AnyObject] {
        var parameters = [String : AnyObject]()
        
        parameters["owner_alias"] = (UserContact.getOwner()?.nickname ?? "anon") as AnyObject
        parameters["name"] = (newGroupInfo.name ?? "") as AnyObject
        
        parameters["price_per_message"] = ((newGroupInfo.pricePerMessage ?? 0) * 1000) as AnyObject
        parameters["price_to_join"] = ((newGroupInfo.priceToJoin ?? 0) * 1000) as AnyObject
        parameters["escrow_amount"] = ((newGroupInfo.amountToStake ?? 0) * 1000) as AnyObject
        
        parameters["pin"] = (newGroupInfo.pin ?? nil) as AnyObject
        
        let escrowMillis = (newGroupInfo.timeToStake ?? 0).millisFromHours
        parameters["escrow_millis"] = escrowMillis as AnyObject
        
        if let img = newGroupInfo.img {
            parameters["img"] = img as AnyObject
        }
        
        if let description = newGroupInfo.description {
            parameters["description"] = description as AnyObject
        }
        
        let selectedTags = newGroupInfo.tags.filter { $0.selected }
        let tagsParams:[String] = selectedTags.map {  $0.description }
        
        parameters["tags"] = tagsParams as AnyObject
        parameters["is_tribe"] = true as AnyObject
        parameters["unlisted"] = newGroupInfo.unlisted as AnyObject
        parameters["private"] = newGroupInfo.privateTribe as AnyObject
        parameters["app_url"] = newGroupInfo.appUrl as AnyObject
        parameters["feed_url"] = newGroupInfo.feedUrl as AnyObject
        parameters["second_brain_url"] = newGroupInfo.secondBrainUrl as AnyObject
        
        if let feedContentType = newGroupInfo.feedContentType {
            parameters["feed_type"] = feedContentType.id as AnyObject
        }
        
        return parameters
    }
    
    func getParamsFrom(tribe: TribeInfo) -> [String: AnyObject] {
        var parameters = [String : AnyObject]()
        
        if let uuid = tribe.uuid, !uuid.isEmpty {
            parameters["uuid"] = uuid as AnyObject
        }
        
        if let img = tribe.img, !img.isEmpty {
            parameters["img"] = img as AnyObject
        }
        
        if let host = tribe.host, !host.isEmpty {
            parameters["host"] = host as AnyObject
        }
        
        if let groupKey = tribe.groupKey, !groupKey.isEmpty {
            parameters["group_key"] = groupKey as AnyObject
        }
        
        if let name = tribe.name, !name.isEmpty {
            parameters["name"] = name as AnyObject
        }
        
        if let ownerPubkey = tribe.ownerPubkey, !ownerPubkey.isEmpty {
            parameters["owner_pubkey"] = ownerPubkey as AnyObject
        }
        
        if let ownerAlias = tribe.ownerAlias, !ownerAlias.isEmpty {
            parameters["owner_alias"] = ownerAlias as AnyObject
        }
        
        if let ownerRouteHint = tribe.ownerRouteHint, !ownerRouteHint.isEmpty {
            parameters["owner_route_hint"] = ownerRouteHint as AnyObject
        }
        
        parameters["amount"] = (tribe.priceToJoin ?? 0) as AnyObject
        parameters["private"] = tribe.privateTribe as AnyObject
        
        return parameters
    }
    
    func update(tribeInfo: inout TribeInfo, from json: JSON) {
        tribeInfo.host = json["host"].string ?? tribeInfo.host
        tribeInfo.uuid = json["uuid"].string ?? tribeInfo.uuid
        tribeInfo.name = json["name"].string ?? tribeInfo.name
        tribeInfo.description = json["description"].string ?? tribeInfo.description
        tribeInfo.img = json["img"].string ?? tribeInfo.img
        tribeInfo.pin = json["pin"].string ?? tribeInfo.pin
        tribeInfo.groupKey = json["group_key"].string ?? tribeInfo.groupKey
        tribeInfo.ownerPubkey = json["owner_pubkey"].string ?? tribeInfo.ownerPubkey
        tribeInfo.ownerAlias = json["owner_alias"].string ?? tribeInfo.ownerAlias
        tribeInfo.priceToJoin = json["price_to_join"].int ?? tribeInfo.priceToJoin
        tribeInfo.pricePerMessage = json["price_per_message"].int ?? tribeInfo.pricePerMessage
        tribeInfo.amountToStake = json["escrow_amount"].int ?? tribeInfo.amountToStake
        tribeInfo.timeToStake = (json["escrow_millis"].int?.hoursFromMillis ?? tribeInfo.timeToStake)
        tribeInfo.unlisted = json["unlisted"].boolValue
        tribeInfo.privateTribe = json["private"].boolValue
        tribeInfo.deleted = json["deleted"].boolValue
        tribeInfo.appUrl = json["app_url"].string ?? tribeInfo.appUrl
        tribeInfo.secondBrainUrl = json["second_brain_url"].string ?? tribeInfo.secondBrainUrl
        tribeInfo.feedUrl = json["feed_url"].string ?? tribeInfo.feedUrl
        tribeInfo.feedContentType = json["feed_type"].int?.toFeedContentType ?? tribeInfo.feedContentType
        tribeInfo.ownerRouteHint = json["owner_route_hint"].string ?? json["route_hint"].string ?? tribeInfo.ownerRouteHint
        
        var tags = getGroupTags()
        if let jsonTags = json["tags"].arrayObject as? [String] {
            for x in 0..<tags.count {
                var tag = tags[x]
                
                if jsonTags.contains(tag.description) {
                    tag.selected = true
                    tags[x] = tag
                }
            }
        }
        tribeInfo.tags = tags
        
        var botObjects : [Bot] = []
        if let data = json["bots"].stringValue.data(using: .utf8) {
            if let jsonObject = try? JSON(data: data) {
                if let bots = jsonObject.array {
                    for bot in bots {
                        let botObject = Bot(json: bot)
                        botObjects.append(botObject)
                    }
                }
            }
        }
        tribeInfo.bots = botObjects
    }
    
    func getTribesInfoFrom(json: JSON) -> TribeInfo {
        var tribeInfo = TribeInfo()
        update(tribeInfo: &tribeInfo, from: json)
        return tribeInfo
    }
    
    func calculateBotPrice(chat: Chat?, text: String) -> (Int, String?) {
        guard let tribeInfo = chat?.tribeInfo, text.starts(with: "/") else {
            return (0, nil)
        }
        
        var price = 0
        var failureMessage: String? = nil
    
        for b in tribeInfo.bots {
            if !text.starts(with: b.prefix) { continue }
            if b.price > 0 {
                price = b.price
            }
            
            if b.commands.count > 0 {
                let arr = text.components(separatedBy: " ")
                if arr.count < 2 { continue }
                
                for cmd in b.commands {
                    let theCommand = arr[1]
                    if cmd.command != "*" && theCommand != cmd.command { continue }
                    
                    if let cmdPrice = cmd.price, cmdPrice > 0 {
                        price = cmdPrice
                    } else if let cmdPriceIndex = cmd.priceIndex, cmdPriceIndex > 0 {
                        if arr.count - 1 < cmdPriceIndex { continue }
                        
                        if let amount = Int(arr[cmdPriceIndex]) {
                            if let cmdMinPrice = cmd.minPrice, cmdMinPrice > 0 && amount < cmdMinPrice {
                                failureMessage = "amount.too.low".localized
                                break
                            }
                            if let cmdMaxPrice = cmd.maxPrice, cmdMaxPrice > 0 && amount > cmdMaxPrice {
                                failureMessage = "amount.too.high".localized
                                break
                            }
                            price = amount
                        }
                    }
                }
            }
        } 
        return (price, failureMessage)
    }
    
    ///Sphinx v2
    func getChatJSON(
        tribeInfo: TribeInfo
    ) -> JSON? {
        let chatDict : [String: Any] = [
            "id": SphinxOnionManager.sharedInstance.generateCryptographicallySecureRandomInt(upperBound: Int(1e5)) as Any,
            "owner_pubkey": tribeInfo.ownerPubkey as Any,
            "name" : tribeInfo.name ?? "Unknown Name",
            "private": tribeInfo.privateTribe,
            "photo_url": tribeInfo.img ?? "",
            "unlisted": tribeInfo.unlisted,
            "price_per_message": tribeInfo.pricePerMessage ?? 0,
            "escrow_amount": max(tribeInfo.amountToStake ?? 3, 3)
        ]
        let chatJSON = JSON(chatDict)
        return chatJSON
    }
    
    func getV2Pubkey(qrString: String) -> String? {
        if let url = URL(string: "\(API.kHUBServerUrl)?\(qrString)"),
            let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
            let queryItems = components.queryItems,
            let pubkey = queryItems.first(where: { $0.name == "pubkey" })?.value
        {
            return cleanPubKey(pubkey)
        }
        return nil
    }
    
    func getV2Host(qrString: String) -> String? {
        if let url = URL(string: "\(API.kHUBServerUrl)?\(qrString)"),
            let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
            let queryItems = components.queryItems,
            let host = queryItems.first(where: { $0.name == "host" })?.value
        {
            return cleanPubKey(host)
        }
        return nil
    }
    
    func cleanPubKey(_ key: String) -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("\")") {
            return String(trimmed.dropLast(2))
        } else {
            return trimmed
        }
    }
    
    func fetchTribeInfo(
        host: String,
        uuid: String,
        useSSL: Bool = false,
        completion: @escaping CreateGroupCallback,
        errorCallback: @escaping EmptyCallback
    ){
        API.sharedInstance.getTribeInfo(
            host: host,
            uuid: uuid,
            callback: { groupInfo in
                completion(groupInfo)
            }, errorCallback: {
                errorCallback()
            }
        )
    }
    
    func finalizeTribeJoin(
        tribeInfo: TribeInfo
    ){
        if let chatJSON = getChatJSON(tribeInfo: tribeInfo),
           let routeHint = tribeInfo.ownerRouteHint
        {
            guard let pubkey = tribeInfo.ownerPubkey else {
                return
            }
            
            let isPrivate = tribeInfo.privateTribe
            let priceToJoin = tribeInfo.nonZeroPriceToJoin
            
            if SphinxOnionManager.sharedInstance.joinTribe(
                tribePubkey: pubkey,
                routeHint: routeHint,
                joinAmountMsats: priceToJoin,
                alias: UserContact.getOwner()?.nickname,
                isPrivate: isPrivate,
                errorCallback: { error in
                    AlertHelper.showAlert(
                        title: "generic.error.title".localized,
                        message: error.localizedDescription
                    )
                }
            ) {
                if let chat = Chat.insertChat(chat: chatJSON) {
                    chat.status = (isPrivate) ? Chat.ChatStatus.pending.rawValue : Chat.ChatStatus.approved.rawValue
                    chat.type = Chat.ChatType.publicGroup.rawValue
                    chat.managedObjectContext?.saveContext()
                }
            }
        }
    }
    
    func lookupAndRestoreTribe(
        pubkey: String,
        host: String,
        completion: @escaping (Chat?) -> ()
    ){
        let tribeInfo = GroupsManager.TribeInfo(ownerPubkey: pubkey, host: host, uuid: pubkey)
        
        GroupsManager.sharedInstance.fetchTribeInfo(
            host: tribeInfo.host,
            uuid: tribeInfo.uuid,
            useSSL: false,
            completion: { groupInfo in
                if groupInfo["deleted"].boolValue == true {
                    completion(nil)
                    return
                }
                
                let chatDict : [String: Any] = [
                    "id": SphinxOnionManager.sharedInstance.generateCryptographicallySecureRandomInt(upperBound: Int(1e5)) as Any,
                    "owner_pubkey": groupInfo["pubkey"],
                    "name" : groupInfo["name"],
                    "private": groupInfo["private"],
                    "photo_url": groupInfo["img"],
                    "unlisted": groupInfo["unlisted"],
                    "price_per_message": groupInfo["price_per_message"],
                    "escrow_amount": max(groupInfo["escrow_amount"].int ?? 3, 3)
                ]
                let chatJSON = JSON(chatDict)
                let resultantChat = Chat.insertChat(chat: chatJSON)
                resultantChat?.status = (chatDict["private"] as? Bool ?? false) ? Chat.ChatStatus.pending.rawValue : Chat.ChatStatus.approved.rawValue
                resultantChat?.type = (chatDict["private"] as? Bool ?? false) ? Chat.ChatType.privateGroup.rawValue : Chat.ChatType.publicGroup.rawValue
                resultantChat?.managedObjectContext?.saveContext()
                completion(resultantChat)
            },
            errorCallback: {
                completion(nil)
        })
    }
}

extension Int {
    var toFeedContentType: FeedContentType? {
        return FeedContentType.allCases.filter { $0.id == self }.first
    }
}
