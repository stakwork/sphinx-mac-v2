// PodcastEpisode+CoreDataProperties.swift
//
// Created by CypherPoet.
// ✌️
//

import Foundation
import CoreData

public class PodcastEpisode: NSObject {
    
    public var itemID: String
    public var feedID: String?
    public var title: String?
    public var author: String?
    public var episodeDescription: String?
    public var datePublished: Date?
    public var dateUpdated: Date?
    public var urlPath: String?
    public var imageURLPath: String?
    public var linkURLPath: String?
    public var clipStartTime: Int?
    public var clipEndTime: Int?
    public var showTitle: String?
    public var feedUrlPath: String?
    public var people: [String] = []
    public var topics: [String] = []
    public var destination: PodcastDestination? = nil
    public var referenceId: String? = nil
    public var chapters: Array<Chapter>? = nil

    //For recommendations podcast
    public var type: String?
    
    init(_ itemID: String) {
        self.itemID = itemID
    }
    
    var duration: Int? {
        get {
            return UserDefaults.standard.value(forKey: "duration-\(feedAndItemId)") as? Int
        }
        set {
            if (newValue ?? 0 > 0) {
                UserDefaults.standard.set(newValue, forKey: "duration-\(feedAndItemId)")
            }
        }
    }
    
    var currentTime: Int? {
        get {
            return UserDefaults.standard.value(forKey: "current-time-\(feedAndItemId)") as? Int
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "current-time-\(feedAndItemId)")
        }
    }
    
    var feedAndItemId: String {
        get {
            if let feedID = feedID {
                return "\(feedID)-\(itemID)"
            }
            return "\(itemID)"
        }
    }
    
    var youtubeVideoId: String? {
        get {
            var videoId: String? = nil
        
            if let urlPath = self.linkURLPath {
                if let range = urlPath.range(of: "v=") {
                    videoId = String(urlPath[range.upperBound...])
                } else if let range = urlPath.range(of: "v/") {
                    videoId = String(urlPath[range.upperBound...])
                }
            }
            
            return videoId
        }
    }
}


extension PodcastEpisode {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<ContentFeedItem> {
        return NSFetchRequest<ContentFeedItem>(entityName: "ContentFeedItem")
    }
}

extension PodcastEpisode: Identifiable {}



// MARK: -  Public Methods
extension PodcastEpisode {
    
    public static func convertFrom(
        contentFeedItem: ContentFeedItem,
        feed: PodcastFeed? = nil
    ) -> PodcastEpisode {
        
        let podcastEpisode = PodcastEpisode(
            contentFeedItem.itemID
        )
        
        podcastEpisode.author = contentFeedItem.authorName
        podcastEpisode.datePublished = contentFeedItem.datePublished
        podcastEpisode.dateUpdated = contentFeedItem.dateUpdated
        podcastEpisode.episodeDescription = contentFeedItem.itemDescription
        podcastEpisode.urlPath = contentFeedItem.enclosureURL?.absoluteString
        podcastEpisode.linkURLPath = contentFeedItem.linkURL?.absoluteString
        
        if let itemImage = contentFeedItem.imageURL?.absoluteString {
            podcastEpisode.imageURLPath = itemImage
        } else if let feedImage = feed?.imageURLPath {
            podcastEpisode.imageURLPath = feedImage
        }
        
        podcastEpisode.title = contentFeedItem.title
        podcastEpisode.type = ActionsManager.PODCAST_TYPE
        podcastEpisode.feedID = feed?.feedID
        podcastEpisode.feedUrlPath = feed?.feedURLPath
        podcastEpisode.referenceId = contentFeedItem.referenceId
        
        if let chaptersData = contentFeedItem.chaptersData {
            let chapters = PodcastEpisode.getChaptersFrom(json: chaptersData)
            podcastEpisode.chapters = chapters
        }
        
        return podcastEpisode
    }
    
    public static func getChaptersFrom(json: String) -> [Chapter] {
        var chapters: [Chapter] = []
        
        if let jsonData = json.data(using: .utf8) {
            do {
                let graphData = try JSONDecoder().decode(GraphData.self, from: jsonData)
                
                for node in graphData.nodes {
                    let timestamp: TimeInterval = node.date_added_to_graph
                    let date = Date(timeIntervalSince1970: timestamp)
                    
                    if node.node_type == "Chapter" {
                        chapters.append(
                            Chapter(
                                dateAddedToGraph: date,
                                nodeType: node.node_type,
                                isAd: (node.properties.is_ad == "True") ? true : false,
                                name: node.properties.name ?? node.properties.episode_title ?? "Unknown",
                                sourceLink: node.properties.source_link ?? "Unknown",
                                timestamp: node.properties.timestamp ?? "Unknown",
                                referenceId: node.ref_id
                            )
                        )
                    }
                }
            } catch {
                print("Error decoding JSON: \(error)")
            }
        } else {
            print("Failed to convert string to Data.")
        }
        
        return chapters.sorted(by: { $0.timestamp.toSeconds() < $1.timestamp.toSeconds() })
    }
    
    var isMusicClip: Bool {
        return type == ActionsManager.PODCAST_TYPE || type == ActionsManager.TWITTER_TYPE
    }
    
    var isPodcast: Bool {
        return type == ActionsManager.PODCAST_TYPE
    }
    
    var isTwitterSpace: Bool {
        return type == ActionsManager.TWITTER_TYPE
    }
    
    var isYoutubeVideo: Bool {
        return type == ActionsManager.YOUTUBE_VIDEO_TYPE
    }

    var intType: Int {
        get {
            if isMusicClip {
                return Int(FeedType.Podcast.rawValue)
            }
            if isYoutubeVideo {
                return Int(FeedType.Video.rawValue)
            }
            return Int(FeedType.Podcast.rawValue)
        }
    }
    
    func constructShareLink(useTimestamp:Bool=false)->String?{
        var link : String? = nil
        if let feedID = self.feedID,
           let feedURL = self.feedUrlPath {
            link = "sphinx.chat://?action=share_content&feedURL=\(feedURL)&feedID=\(feedID)&itemID=\(itemID)"
        }
        
        if useTimestamp == true,
        let timestamp = currentTime,
        let _ = link{
            link! += "&atTime=\(timestamp)"
        }
        return link
    }
    
    func getAdTimestamps() -> [(Int, Int)] {
        guard let chapters = chapters else {
            return []
        }
        
        var timestamps: [(Int, Int)] = []
        
        for (index, chapter) in chapters.enumerated() {
            if chapter.isAd {
                let nextChapterStart = chapters[index + 1].timestamp.toSeconds()
                let adStart = chapter.timestamp.toSeconds()
                timestamps.append((adStart, nextChapterStart))
            }
        }
        
        return timestamps
    }
    
}
