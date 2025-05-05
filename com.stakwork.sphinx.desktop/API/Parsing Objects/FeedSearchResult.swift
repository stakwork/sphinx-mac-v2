//
//  FeedSearchResult.swift
//  sphinx
//
//  Created by Tomas Timinskas on 05/05/2025.
//  Copyright © 2025 Tomas Timinskas. All rights reserved.
//

import Foundation
import CoreData
import SwiftyJSON

public class FeedSearchResult: NSObject {
    
    public var feedId: String
    public var title: String
    public var feedDescription: String?
    public var imageUrl: String?
    public var feedURLPath: String
    public var feedType: FeedType
    
    init(
        _ feedId: String,
        _ title: String,
        _ feedDescription: String?,
        _ imageUrl: String?,
        _ feedURLPath: String,
        _ feedType: FeedType) {
        
        self.feedId = feedId
        self.title = title
        self.feedDescription = feedDescription
        self.imageUrl = imageUrl
        self.feedURLPath = feedURLPath
        self.feedType = feedType
    }
    
    func printAll() {
        print("Feed ID: \(feedId)")
        print("Title: \(title)")
        print("Description: \(feedDescription ?? "No Description")")
        print("Image URL: \(imageUrl ?? "No Image URL")")
        print("Feed URL Path: \(feedURLPath)")
        print("Feed Type: \(feedType)")
    }
    
    public static func convertFrom(
        contentFeed: ContentFeed
    ) -> FeedSearchResult {
        
        let feed = FeedSearchResult(
            contentFeed.feedID,
            contentFeed.title ?? "",
            contentFeed.feedDescription,
            contentFeed.imageToShow,
            contentFeed.feedURL?.absoluteString ?? "",
            contentFeed.feedKind
        )
        
        return feed
    }
    
    public static func convertFrom(
        searchResult: JSON,
        type: FeedType
    ) -> FeedSearchResult {
        
        let feedId = searchResult[ContentFeed.CodingKeys.feedID.rawValue].stringValue
        let title = searchResult[ContentFeed.CodingKeys.title.rawValue].stringValue
        let feedDescription = searchResult[ContentFeed.CodingKeys.feedDescription.rawValue].stringValue
        let imageUrl = searchResult[ContentFeed.CodingKeys.imageURL.rawValue].stringValue
        let feedURLPath = searchResult[ContentFeed.CodingKeys.feedURL.rawValue].stringValue
        
        let feed = FeedSearchResult(
            feedId.fixedFeedId(feedUrl: feedURLPath),
            title,
            feedDescription,
            imageUrl,
            feedURLPath,
            type
        )
        
        return feed
    }
}
