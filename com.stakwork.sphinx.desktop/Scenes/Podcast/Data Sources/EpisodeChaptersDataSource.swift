//
//  EpisodeChaptersDataSource.swift
//  sphinx
//
//  Created by Tomas Timinskas on 04/04/2025.
//  Copyright © 2025 Tomas Timinskas. All rights reserved.
//
import Foundation
import Cocoa


class EpisodeChaptersDataSource : NSObject{
    
    weak var collectionView : NSCollectionView?
    
    var episode: PodcastEpisode!
    
    let kCellHeight = 40.0

    init(
        collectionView: NSCollectionView,
        episode: PodcastEpisode
    ) {
        self.episode = episode
        self.collectionView = collectionView
    }
    
    func setupCollectionView(){
        collectionView?.delegate = self
        collectionView?.dataSource = self
    }
}


extension EpisodeChaptersDataSource : NSCollectionViewDataSource,NSCollectionViewDelegate, NSCollectionViewDelegateFlowLayout{
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        return episode.chapters?.count ?? 0
    }
    
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        return collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "EpisodeChapterItemView"), for: indexPath) as! EpisodeChapterItemView
    }
    
    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> NSSize {
        return CGSize(width: collectionView.frame.width, height: kCellHeight)
    }
    
    func collectionView(_ collectionView: NSCollectionView, willDisplay item: NSCollectionViewItem, forRepresentedObjectAt indexPath: IndexPath) {
        if let item = item as? EpisodeChapterItemView {
            if let chapter = episode.chapters?[indexPath.item] {
                item.configureWith(chapter: chapter, delegate: self, index: indexPath.item)
            }
        }
    }
}

extension EpisodeChaptersDataSource : ChapterViewDelegate {
    func shouldPlayChapterWith(index: Int) {
        
    }
}
