//
//  ChaptersManager.swift
//  sphinx
//
//  Created by Tomas Timinskas on 03/04/2025.
//  Copyright © 2025 Tomas Timinskas. All rights reserved.
//
import Foundation
import Cocoa

class ChaptersManager : NSObject {
    
    class var sharedInstance : ChaptersManager {
        struct Static {
            static let instance = ChaptersManager()
        }
        return Static.instance
    }
    
    var processingEpisodes: [String: Date] = [:]
    
    func isDateWithinLastHour(date: Date) -> Bool {
        let currentDate = Date()  // Get the current date and time
        let oneHourAgo = currentDate.addingTimeInterval(-3600)  // Subtract one hour (3600 seconds)
        
        // Check if the given date is after the time one hour ago
        return date >= oneHourAgo && date <= currentDate
    }
    
    func processChaptersData(
        episodeId: String
    ) {
        processChaptersData(episodeId: episodeId, completion: { (success, chaptersData) in
            if success && chaptersData.count > 0 {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .refreshFeedDataAndUI, object: nil)
                }
            }
        })
    }
    
    func processChaptersData(
        episodeId: String,
        completion: @escaping (Bool, [Chapter]) -> ()
    ) {
        if let processingDate = processingEpisodes[episodeId], isDateWithinLastHour(date: processingDate) {
            completion(false, [])
            return
        }
        
        guard let contentFeedItem = ContentFeedItem.getItemWith(itemID: episodeId) else {
            completion(false, [])
            return
        }
        guard let feed = contentFeedItem.contentFeed else {
            completion(false, [])
            return
        }
        
        let podcast = PodcastFeed.convertFrom(contentFeed: feed)
        let episode = PodcastEpisode.convertFrom(contentFeedItem: contentFeedItem, feed: podcast)
        
        if (episode.chapters?.count ?? 0) > 0 {
            completion(false, [])
            return
        }
        
        self.processingEpisodes[episodeId] = Date()
        
        if let refereceId = episode.referenceId {
            ///ReferenceID stored in Episode. It was processed before. Try to fetch chapters data
            self.getAndStoreChaptersData(
                referenceId: refereceId,
                episode: episode,
                completion: completion
            )
        } else {
            ///ReferenceID not stored in Episode. Start process with checking if node exists
            checkIfNodeExists(episode: episode) { (nodeExists, refId) in
                if let refId = refId {
                    contentFeedItem.referenceId = refId
                    contentFeedItem.managedObjectContext?.saveContext()
                    
                    if nodeExists {
                        ///Node exists, save referenceId and try to fetch chapters data
                        self.getAndStoreChaptersData(
                            referenceId: refId,
                            episode: episode,
                            completion: completion
                        )
                    } else {
                        ///Node doesn't exist, but it was created. Run GraphMinset workflow to extract chapters
                        completion(true, [])
                    }
                } else {
                    self.processingEpisodes[episodeId] = nil
                    completion(false, [])
                }
            }
        }
    }
    
    func getAndStoreChaptersData(
        referenceId: String,
        episode: PodcastEpisode,
        completion: @escaping (Bool, [Chapter]) -> ()
    ) {
        guard let contentFeedItem = ContentFeedItem.getItemWith(itemID: episode.itemID) else {
            self.processingEpisodes[episode.itemID] = nil
            completion(false, [])
            return
        }
        
        self.getChaptersData(referenceId: referenceId, completion: { (success, jsonString) in
            if success, let jsonString = jsonString {
                let chapters = PodcastEpisode.getChaptersFrom(json: jsonString)
                if chapters.count > 0 {
                    ///Chapters data available. Store in episode and return them
                    contentFeedItem.chaptersData = jsonString
                    episode.chapters = chapters
                    contentFeedItem.managedObjectContext?.saveContext()
                    
                    self.processingEpisodes[episode.itemID] = nil
                    completion(true, episode.chapters ?? [])
                    return
                }
            }
            ///Chapters data unavailable. Check episode status
            self.checkEpisodeStatus(referenceId: referenceId, completion: { (success, nodeStatusResponse) in
                if success, let nodeStatusResponse = nodeStatusResponse {
                    if nodeStatusResponse.processing {
                        if let _ = nodeStatusResponse.projectId {
                            ///Node workflow already running. Just wait
                            completion(true, [])
                        } else {
                            ///Node created but workflow not running. Run GraphMinset workflow to extract chapters
                            self.runGraphMindset(
                                referenceId: referenceId,
                                episode: episode,
                                completion: { success in
                                    completion(true, [])
                                }
                            )
                        }
                    } else if nodeStatusResponse.completed {
                        ///Node created and workflow run. Try to fetch chapters data again
                        self.getChaptersData(referenceId: referenceId, completion: { (success, jsonString) in
                            if success, let jsonString = jsonString {
                                contentFeedItem.chaptersData = jsonString
                                let chapters = PodcastEpisode.getChaptersFrom(json: jsonString)
                                episode.chapters = chapters
                                completion(true, episode.chapters ?? [])
                            }
                        })
                    } else {
                        self.processingEpisodes[episode.itemID] = nil
                        completion(false, [])
                    }
                }
            })
        })
    }
    
    func checkIfNodeExists(
        episode: PodcastEpisode,
        completion: @escaping (Bool, String?) -> ()
    ) {
        if
            let mediaUrl = episode.urlPath,
            let date = episode.datePublished,
            let episodeTitle = episode.title
        {
            API.sharedInstance.checkEpisodeNodeExists(
                mediaUrl: mediaUrl,
                publishDate: Int(date.timeIntervalSince1970),
                title: episodeTitle,
                thumbnailUrl: episode.imageURLPath,
                showTitle: episode.showTitle ?? "Show Title",
                callback: { checkNodeResponse in
                    let refId = checkNodeResponse.refId
                    
                    if checkNodeResponse.success {
                        //Episode was created. Call graphmindset run
                        completion(false, refId)
                    } else {
                        //Episode already exists. Try getting chapters
                        completion(true, refId)
                    }
                },
                errorCallback: { _ in
                    completion(false, nil)
                }
            )
        } else {
            completion(false, nil)
        }
        
    }
    
    func getChaptersData(
        referenceId: String,
        completion: @escaping (Bool, String?) -> ()
    ) {
        API.sharedInstance.getEpisodeNodeChapters(
            refId: referenceId,
            callback: { chaptersJsonString in
                completion(true, chaptersJsonString)
            },
            errorCallback: { error in
                completion(false, nil)
            }
        )
    }
    
    func runGraphMindset(
        referenceId: String,
        episode: PodcastEpisode,
        completion: @escaping (Bool) -> ()
    ) {
        if
            let mediaUrl = episode.urlPath,
            let date = episode.datePublished,
            let episodeTitle = episode.title
        {
            API.sharedInstance.ceateGrandMindsetRun(
                mediaUrl: mediaUrl,
                refId: referenceId,
                publishDate: Int(date.timeIntervalSince1970),
                title: episodeTitle,
                thumbnailUrl: episode.imageURLPath,
                showTitle: episode.showTitle ?? "Show Title",
                callback: { createRunResponse in
                    if let _ = createRunResponse.projectId, createRunResponse.success {
                        completion(true)
                    } else {
                        completion(false)
                    }
                },
                errorCallback: { error in
                    completion(false)
                }
            )
        }
    }
    
    func checkEpisodeStatus(
        referenceId: String,
        completion: @escaping (Bool, API.NodeStatusResponse?) -> ()
    ) {
        API.sharedInstance.checkEpisodeNodeStatus(
            refId: referenceId,
            callback: { nodeStatusResponse in
                completion(true, nodeStatusResponse)
            },
            errorCallback: { _ in
                completion(false, nil)
            }
        )
    }
    
    func checkProjectStatus(
        projectId: String,
        completion: @escaping (Bool) -> ()
    ) {
        API.sharedInstance.checkProjectStatus(
            projectId: projectId,
            callback: { success in
                completion(success)
            },
            errorCallback: { error in
                completion(false)
            }
        )
    }
}
