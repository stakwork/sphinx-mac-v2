//
//  PodcastEpisodesDataSource.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 14/10/2020.
//  Copyright © 2020 Sphinx. All rights reserved.
//

import Foundation
import Cocoa

protocol PodcastEpisodesDSDelegate : AnyObject {
    func shouldShareClip(comment: PodcastComment)
    func shouldSendBoost(message: String, amount: Int, animation: Bool) -> TransactionMessage?
    func shouldCopyShareLink(link: String)
}

class PodcastEpisodesDataSource : NSObject {
    
    weak var delegate: PodcastEpisodesDSDelegate?
    
    public static let kPlayerRowHeight: CGFloat = 670
    
    let kRowHeight: CGFloat = 200
    let kChapterHeight: CGFloat = 40
    let kHeaderHeight: CGFloat = 60
    
    var collectionView: NSCollectionView! = nil
    
    var chat: Chat? = nil
    var podcast: PodcastFeed! = nil
    var episodesExpanded: [Int: Bool] = [:]
    
    let podcastPlayerController = PodcastPlayerController.sharedInstance
    let feedsManager = FeedsManager.sharedInstance
    
    init(
        collectionView: NSCollectionView,
        chat: Chat?,
        podcastFeed: PodcastFeed,
        delegate: PodcastEpisodesDSDelegate
    ) {
        super.init()
        
        self.chat = chat
        self.podcast = podcastFeed
        self.collectionView = collectionView
        self.delegate = delegate
        
        let flowLayout = NSCollectionViewFlowLayout()
        flowLayout.sectionInset = NSEdgeInsets(top: 0.0, left: 0.0, bottom: 0.0, right: 0.0)
        flowLayout.minimumInteritemSpacing = 0.0
        flowLayout.minimumLineSpacing = 0.0
        flowLayout.sectionHeadersPinToVisibleBounds = true
        self.collectionView.collectionViewLayout = flowLayout
        
        self.collectionView.delegate = self
        self.collectionView.dataSource = self
        self.collectionView.reloadData()
    }
}


extension PodcastEpisodesDataSource : NSCollectionViewDataSource {
    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        return 2
    }
  
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        if section == 0 {
            return 1
        }
        return podcast.episodesArray.count
    }
  
    func collectionView(_ itemForRepresentedObjectAtcollectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        if indexPath.section == 0 {
            let item = collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "PodcastPlayerCollectionViewItem"), for: indexPath)
            return item
        }
        let item = collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "PodcastEpisodeCollectionViewItem"), for: indexPath)
        
        return item
    }
    
    func collectionView(_ collectionView: NSCollectionView, willDisplay item: NSCollectionViewItem, forRepresentedObjectAt indexPath: IndexPath) {
        if let collectionViewItem = item as? PodcastEpisodeCollectionViewItem {
            
            let episode = podcast.episodesArray[indexPath.item]
            let isLastRow = indexPath.item == podcast.episodesArray.count - 1
            let isPlaying = podcastPlayerController.isPlaying(episodeId: episode.itemID)
            
            collectionViewItem.configureWith(
                podcast: podcast,
                and: episode,
                isLastRow: isLastRow,
                playing: isPlaying,
                expanded: episodesExpanded[indexPath.item] ?? false
            )
            collectionViewItem.delegate = self
            
        } else if let collectionViewItem = item as? PodcastPlayerCollectionViewItem {
            
            collectionViewItem.configureWith(chat: chat, podcast: podcast, delegate: self)
        }
    }
}

extension PodcastEpisodesDataSource : NSCollectionViewDelegate, NSCollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> NSSize {
        if indexPath.section == 0 {
            return NSSize(width: self.collectionView.frame.width, height: PodcastEpisodesDataSource.kPlayerRowHeight)
        }
        
        let episodes = podcast.episodesArray
        let episode = episodes[indexPath.item]
        
        if episodesExpanded[indexPath.item] ?? false {
            let height = kRowHeight + (CGFloat((episode.chapters?.count ?? 0)) * kChapterHeight)
            return NSSize(width: self.collectionView.frame.width, height: height)
        }
        
        return NSSize(width: self.collectionView.frame.width, height: kRowHeight)
    }
    
    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> NSSize {
        if section == 0 {
            return NSSize.zero
        }
        return NSSize(width: self.collectionView.frame.width, height: kHeaderHeight)
    }
    
    func collectionView(_ collectionView: NSCollectionView, viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind, at indexPath: IndexPath) -> NSView {
        let view = collectionView.makeSupplementaryView(
            ofKind: NSCollectionView.elementKindSectionHeader,
            withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "PodcastEpisodesHeaderView"),
            for: indexPath
        ) as! PodcastEpisodesHeaderView
        
        view.configureWith(count: podcast.episodesArray.count, delegate: self)
        view.addShadow(location: VerticalLocation.bottom, color: NSColor.black, opacity: 0.2, radius: 3.0)
        
        return view
    }
    
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        if let indexPath = indexPaths.first {
            if indexPath.section == 0 { return }
            playEpisode(atIndexPath: indexPath)
        }
    }
    
    
    func playEpisode(atIndexPath:IndexPath){
        if let playerView = collectionView.item(at: IndexPath(item: 0, section: 0)) as? PodcastPlayerCollectionViewItem {
            playerView.didTapEpisodeAt(index: atIndexPath.item)
        }
    }
}

extension PodcastEpisodesDataSource : PodcastPlayerViewDelegate {
    func shouldReloadEpisodesTable() {
        if let feed = ContentFeed.getFeedById(feedId: podcast.feedID) {
            self.podcast = PodcastFeed.convertFrom(contentFeed: feed)
        }
        self.collectionView.reloadSections(IndexSet(integer: 1))
    }
    
    func shouldShareClip(comment: PodcastComment) {
        delegate?.shouldShareClip(comment: comment)
    }
    
    func shouldSendBoost(message: String, amount: Int, animation: Bool) -> TransactionMessage? {
        return delegate?.shouldSendBoost(message: message, amount: amount, animation: animation)
    }
    
    func shouldSyncPodcast() {
        feedsManager.saveContentFeedStatus(for: podcast.feedID)
    }
}

extension PodcastEpisodesDataSource : PodcastEpisodesHeaderViewDelegate {
    func skipAdsButtonClicked() -> Bool {
        let newValue = !podcast.skipAds
        podcast.skipAds = newValue
        return newValue
    }
}


extension PodcastEpisodesDataSource:PodcastEpisodeCollectionViewItemDelegate{
    func episodeShareTapped(episode: PodcastEpisode) {
            AlertHelper.showTwoOptionsAlert(
                title: "Share from beginning or current time?",
                message: "",
                confirm: {
                    if let link = episode.constructShareLink(){
                        self.delegate?.shouldCopyShareLink(link: link)
                    }
                },
                cancel: {
                    if let link = episode.constructShareLink(useTimestamp: true){
                        self.delegate?.shouldCopyShareLink(link: link)
                    }
                },
                confirmLabel: "Share from Beginning",
                cancelLabel: "Share from Current Time"
            )
            
    }
    
    func episodeChaptersTapped(episode: PodcastEpisode, with index: Int) {
        let podcastPlayerController = PodcastPlayerController.sharedInstance
        
        if let chapter = episode.chapters?[index] {
            var newTime = chapter.timestamp.toSeconds()
            newTime = max(newTime, 0)
            newTime = min(newTime, podcast.duration)
            
            guard let podcastData = podcast.getPodcastData(
                episodeId: episode.itemID,
                currentTime: newTime
            ) else {
                return
            }
            
            if podcastPlayerController.isPlaying(episodeId: episode.itemID) {
                podcastPlayerController.submitAction(
                    UserAction.Seek(podcastData)
                )
            } else {
                podcastPlayerController.submitAction(
                    UserAction.Play(podcastData)
                )
            }
        }
    }
    
    func chaptersButtonTappedFor(episode: PodcastEpisode, on cell: NSCollectionViewItem) {
        if let indexPath = collectionView.indexPath(for: cell) {
            var indexRowsToUpdate: [IndexPath] = [indexPath]
            
            for (index, _) in episodesExpanded.enumerated() {
                if index != indexPath.item {
                    if (episodesExpanded[index] ?? false) {
                        indexRowsToUpdate.append(IndexPath(item: index, section: 0))
                    }
                    episodesExpanded[index] = false
                }
            }
            
            episodesExpanded[indexPath.item] = !(episodesExpanded[indexPath.item] ?? false)
            
            collectionView.animator().performBatchUpdates {
                self.collectionView.reloadItems(at: Set(indexRowsToUpdate))
            } completionHandler: { _ in
                self.collectionView.collectionViewLayout?.invalidateLayout()
            }
        }
    }
    
    func episodePlayTapped(episode: PodcastEpisode) {
        guard let podcastData = podcast.getPodcastData(
            episodeId: episode.itemID
        ) else {
            return
        }
        
        if podcastPlayerController.isPlaying(episodeId: episode.itemID) {
            podcastPlayerController.submitAction(
                UserAction.Pause(podcastData)
            )
        } else {
            podcastPlayerController.submitAction(
                UserAction.Play(podcastData)
            )
        }
    }
}
