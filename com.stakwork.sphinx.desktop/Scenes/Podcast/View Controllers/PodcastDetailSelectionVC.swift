//
//  PodcastDetailSelectionVC.swift
//  Sphinx
//
//  Created by James Carucci on 3/31/23.
//  Copyright © 2023 Tomas Timinskas. All rights reserved.
//

import Foundation
import Cocoa

protocol PodcastDetailSelectionVCDelegate: NSObject {
    func shareButtonTapped(_ sender: Any)
    func shouldReloadList()
}

class PodcastDetailSelectionVC : NSViewController{
    
    @IBOutlet weak var podcastDetailImageView: NSImageView!
    @IBOutlet weak var podcastTitleLabel: NSTextField!
    @IBOutlet weak var episodeTitleLabel: NSTextField!
    @IBOutlet weak var mediaTypeImageView : NSImageView!
    @IBOutlet weak var dotView : NSView!
    @IBOutlet weak var mediaTypeDescriptionLabel : NSTextField!
    @IBOutlet weak var publishedDateLabel : NSTextField!
    @IBOutlet weak var dotView2 : NSView!
    @IBOutlet weak var timeRemainingLabel : NSTextField!
    @IBOutlet weak var collectionView: NSCollectionView!
    @IBOutlet weak var chaptersContainer: NSView!
    @IBOutlet weak var chaptersTitle: NSTextField!
    @IBOutlet weak var chaptersCollectionView: NSCollectionView!
    @IBOutlet weak var divider: NSBox!
    
    weak var delegate : PodcastDetailSelectionVCDelegate!
    
    var podcast: PodcastFeed? = nil
    var episode: PodcastEpisode!
    
    lazy var podcastDetailSelectionVM: PodcastDetailSelectionVM = {
        return PodcastDetailSelectionVM(
            collectionView: collectionView,
            episode: episode,
            delegate: delegate
        )
    }()
    
    lazy var episodeChapterDS: EpisodeChaptersDataSource = {
        return EpisodeChaptersDataSource(
            collectionView: chaptersCollectionView,
            episode: episode
        )
    }()
    
    override func viewDidLoad() {
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.Sphinx.SecondaryText.withAlphaComponent(0.5).cgColor
        chaptersContainer.isHidden = (episode.chapters?.count ?? 0) == 0
        
        adjustUI(episode: episode, podcast: podcast)
        
        podcastDetailSelectionVM.setupCollectionView()
        episodeChapterDS.setupCollectionView()
    }
    
    static func instantiate(
        podcast: PodcastFeed?,
        and episode: PodcastEpisode,
        delegate: PodcastDetailSelectionVCDelegate
    ) -> PodcastDetailSelectionVC {
        let viewController = StoryboardScene.Podcast.podcastDetailSelectionViewController.instantiate()
        viewController.episode = episode
        viewController.podcast = podcast
        viewController.delegate = delegate
        
        return viewController
    }
    
    func adjustUI(
        episode: PodcastEpisode,
        podcast: PodcastFeed?
    ){
        episodeTitleLabel.maximumNumberOfLines = 3
        episodeTitleLabel.cell?.wraps = true
        mediaTypeImageView.wantsLayer = true
        mediaTypeImageView.layer?.cornerRadius = 3.0
        dotView.wantsLayer = true
        dotView.layer?.backgroundColor = NSColor.Sphinx.Text.cgColor
        dotView.makeCircular()
        dotView2.wantsLayer = true
        dotView2.layer?.backgroundColor = NSColor.Sphinx.Text.cgColor
        dotView2.makeCircular()
        podcastDetailImageView.wantsLayer = true
        podcastDetailImageView.layer?.cornerRadius = 8.0
        
        podcastTitleLabel.stringValue = podcast?.title ?? "No Title"
        episodeTitleLabel.stringValue = episode.title ?? "No Description"
        publishedDateLabel.stringValue = episode.dateString ?? "Unknown Date"
        
        let duration = episode.duration ?? 0
        let currentTime = episode.currentTime ?? 0
        let timeString = (duration - currentTime).getEpisodeTimeString(
            isOnProgress: currentTime > 0
        )
        
        timeRemainingLabel.stringValue = timeString
        
        let imageUrl = episode.imageURLPath ?? podcast?.imageURLPath
        
        if let episodeURLPath = imageUrl, let url = URL(string: episodeURLPath) {
            podcastDetailImageView.sd_setImage(
                with: url,
                placeholderImage: NSImage(named: "podcastPlaceholder"),
                options: [.highPriority],
                progress: nil
            )
        }
    }
}
