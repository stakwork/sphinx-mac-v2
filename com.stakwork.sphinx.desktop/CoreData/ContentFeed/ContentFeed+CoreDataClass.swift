// ContentFeed+CoreDataClass.swift
//
// Created by CypherPoet.
// ✌️
//

import Foundation
import CoreData
import SwiftyJSON

@objc(ContentFeed)
public class ContentFeed: NSManagedObject {
    
    public static func createObjectFrom(
        json: JSON,
        searchResultDescription: String? = nil,
        searchResultImageUrl: String? = nil,
        context: NSManagedObjectContext? = nil
    ) -> ContentFeed? {
        
        guard let fId = json[CodingKeys.feedID.rawValue].string else {
            return nil
        }
        
        let feedType = FeedType(rawValue: json[CodingKeys.feedKindValue.rawValue].int16Value)?.rawValue ?? 0
        let feedUrl = json[CodingKeys.feedURL.rawValue].stringValue
        let feedId = fId.fixedFeedId(feedUrl: feedUrl)
        
        if feedType != FeedType.Podcast.rawValue {
            return nil
        }
        
        var contentFeed: ContentFeed
        
        let itemsData = ContentFeed.deleteFeedWith(feedId: feedId)
        
        guard let items = json[CodingKeys.items.rawValue].array, items.count > 0 else {
            return nil
        }
        
        if let managedObjectContext = context {
            contentFeed = ContentFeed(context: managedObjectContext)
        } else {
            contentFeed = ContentFeed(entity: ContentFeed.entity(), insertInto: nil)
        }
        
        contentFeed.feedURL = URL(string: feedUrl)
        contentFeed.feedID = feedId
        contentFeed.title = json[CodingKeys.title.rawValue].stringValue
        contentFeed.feedKindValue = feedType
        contentFeed.ownerURL = URL(string: json[CodingKeys.ownerURL.rawValue].stringValue)
        contentFeed.generator = json[CodingKeys.generator.rawValue].stringValue
        contentFeed.authorName = json[CodingKeys.authorName.rawValue].stringValue
        contentFeed.linkURL = URL(string: json[CodingKeys.linkURL.rawValue].stringValue)
        contentFeed.datePublished = Date(timeIntervalSince1970: json[CodingKeys.datePublished.rawValue].doubleValue)
        contentFeed.dateUpdated = Date(timeIntervalSince1970: json[CodingKeys.dateUpdated.rawValue].doubleValue)
        contentFeed.language = json[CodingKeys.language.rawValue].string
        
        //Using search result image and description
        if let imageUrlPath = json[CodingKeys.imageURL.rawValue].string, !imageUrlPath.isEmpty {
            contentFeed.imageURL = URL(string: imageUrlPath)
        } else if let searchResultImageUrl = searchResultImageUrl, !searchResultImageUrl.isEmpty {
            contentFeed.imageURL = URL(string: searchResultImageUrl)
        }
        
        if let feedDescription = json[CodingKeys.feedDescription.rawValue].string, !feedDescription.isEmpty {
            contentFeed.feedDescription = feedDescription
        } else if let searchResultDescription = searchResultDescription {
            contentFeed.feedDescription = searchResultDescription
        }
        
        if let items = json[CodingKeys.items.rawValue].array {
            for item in items {
                let i = ContentFeedItem.createObjectFrom(
                    json: item,
                    context: context,
                    itemsData: itemsData
                )
                i?.contentFeed = contentFeed
            }
        }
        
        if let value = json[CodingKeys.value.rawValue].dictionary {
               
            if let model = value[CodingKeys.Value.paymentModel.rawValue]?.dictionary {
                contentFeed.paymentModel = ContentFeedPaymentModel.createObjectFrom(json: JSON(model), context: context)
            }
            
            if let destinations = value[CodingKeys.Value.paymentDestinations.rawValue]?.array {
                for destination in destinations {
                    let d = ContentFeedPaymentDestination.createObjectFrom(json: destination, context: context)
                    d?.feed = contentFeed
                }
            }
        }
        
        contentFeed.managedObjectContext?.saveContext()
        
        return contentFeed
    }
    
    func updateLastConsumed(){
        dateLastConsumed = Date()
        managedObjectContext?.saveContext()
    }
    
    public static func fetchChatFeedContentInBackground(
        feedUrl: String,
        chatId: Int,
        completion: @escaping (String?) -> ()
    ) {
        fetchContentFeed(
            at: feedUrl,
            chat: nil,
            persistingIn: CoreDataManager.sharedManager.persistentContainer.viewContext
        ) { result in
            
            if case .success(let contentFeed) = result {
                let feedId = contentFeed.feedID
                
                DispatchQueue.main.async {
                    completion(feedId)
                }
                return
            }
            
            completion(nil)
        }
    }
    
    public static func fetchContentFeed(
        at feedURLPath: String,
        chat: Chat?,
        searchResultDescription: String? = nil,
        searchResultImageUrl: String? = nil,
        persistingIn managedObjectContext: NSManagedObjectContext,
        then completionHandler: ((Result<ContentFeed, Error>) -> Void)? = nil
    ) {
        let tribesServerURL = "\(API.tribesV1Url)/feed?url=\(feedURLPath)&fulltext=true"
        
        API.sharedInstance.getContentFeed(
            url: tribesServerURL,
            callback: { feedJSON in
                
                if let contentFeed = ContentFeed.createObjectFrom(
                    json: feedJSON,
                    searchResultDescription: searchResultDescription,
                    searchResultImageUrl: searchResultImageUrl,
                    context: managedObjectContext
                ) {
                    contentFeed.chat = chat
                    
                    completionHandler?(.success(contentFeed))
                } else {
                    completionHandler?(.failure((API.RequestError.failedToFetchContentFeed)))
                }
            },
            errorCallback: {
                completionHandler?(.failure((API.RequestError.failedToFetchContentFeed)))
            }
        )
    }
    
    var imageToShow: String? {
        return imageURL?.absoluteString ?? chat?.photoUrl ?? itemsArray.first?.imageURL?.absoluteString
    }
    
    public static func fetchFeedItems(
        feedUrl: String,
        feedId: String,
        context: NSManagedObjectContext,
        completion: @escaping (Result<ContentFeed, Error>) -> ()
    ) {
        let backgroundContentFeed: ContentFeed? = ContentFeed.getFeedById(feedId: feedId, managedContext: context)
        
        fetchContentFeedItems(
            at: feedUrl,
            contentFeed: backgroundContentFeed,
            persistingIn: context
        ) { result in
            
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }
    
    public static func fetchContentFeedItems(
        at feedURLPath: String,
        contentFeed: ContentFeed?,
        persistingIn managedObjectContext: NSManagedObjectContext,
        then completionHandler: ((Result<ContentFeed, Error>) -> Void)? = nil
    ) {
        let tribesServerURL = "\(API.tribesV1Url)/feed?url=\(feedURLPath)&fulltext=true"
        
        API.sharedInstance.getContentFeed(
            url: tribesServerURL,
            callback: { feedJSON in
                if let contentFeed = contentFeed {
                    let itemsData = contentFeed.getItemsData()
                    
                    if let items = feedJSON[ContentFeed.CodingKeys.items.rawValue].array {
                        for item in items {
                            let i = ContentFeedItem.createObjectFrom(
                                json: item,
                                context: managedObjectContext,
                                itemsData: itemsData
                            )
                            i?.contentFeed = contentFeed
                        }
                    }
                    completionHandler?(.success(contentFeed))
                } else {
                    completionHandler?(.failure((API.RequestError.failedToFetchContentFeed)))
                }
            },
            errorCallback: {
                completionHandler?(.failure((API.RequestError.failedToFetchContentFeed)))
            }
        )
    }
}

extension String {
    func fixedFeedId(feedUrl: String) -> String {
        if feedUrl.isYouTubeRSSFeed {
            if let range = feedUrl.range(of: "?playlist_id=") {
                return "yt:playlist:\(feedUrl[range.upperBound...])"
            }
            if let range = feedUrl.range(of: "?channel_id=") {
                return "yt:channel:\(feedUrl[range.upperBound...])"
            }
        }
        return self
    }
}
