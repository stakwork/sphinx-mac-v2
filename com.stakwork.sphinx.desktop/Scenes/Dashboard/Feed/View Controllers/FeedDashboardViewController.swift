//
//  FeedDashboardViewController.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 06/05/2025.
//  Copyright © 2025 Tomas Timinskas. All rights reserved.
//

import Cocoa

class FeedDashboardViewController: NSViewController {    
    
    @IBOutlet weak var childContainerView: NSView!
    
    var addedVC: NSViewController? = nil
    
    static func instantiate() -> FeedDashboardViewController {
        let viewController = StoryboardScene.Dashboard.feedDashboardViewController.instantiate()
        return viewController
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
    }
    
    override func viewDidLayout() {
        super.viewDidLayout()
        addChildViewController()
    }
    
    func resizeSubviews(frame: NSRect) {
        view.frame = frame
        
        guard let currentVC = addedVC else {
            return
        }
        currentVC.view.frame = childContainerView.bounds
    }
    
    func addChildViewController() {
        if let _ = addedVC {
            return
        }
        let feedListenVC = FeedListenDashboardViewController.instantiate(
            onPodcastEpisodeCellSelected: handlePodcastEpisodeCellSelection(_:)
        )
        addChildVC(child: feedListenVC, container: childContainerView)
        addedVC = feedListenVC
    }
    
    private func handlePodcastEpisodeCellSelection(_ feedItemId: String) {
        guard let contentFeedItem = ContentFeedItem.getItemWith(itemID: feedItemId) else {
            return
        }
        
        if let contentFeed = contentFeedItem.contentFeed {
            let podcast = PodcastFeed.convertFrom(contentFeed: contentFeed)
            
            pausePlayingIfNeeded(podcast: podcast, itemId: feedItemId)
            
            podcast.currentEpisodeId = contentFeedItem.itemID
            
            let podcastPlayerVC = NewPodcastPlayerViewController.instantiate(
                chat: podcast.chat,
                podcast: podcast,
                delegate: nil
            )
            
            WindowsManager.sharedInstance.showVCOnRightPanelWindow(
                with: "Podcast",
                identifier: "podcast-window-\(contentFeed.feedID)",
                contentVC: podcastPlayerVC,
                shouldReplace: false,
                panelFixedWidth: true
            )
        }
    }
    
    private func pausePlayingIfNeeded(
        podcast: PodcastFeed,
        itemId: String
    ) {
        let podcastPlayerController = PodcastPlayerController.sharedInstance
        
        if podcastPlayerController.isPlaying(podcastId: podcast.feedID) {
            if let episode = podcast.getCurrentEpisode(), let url = episode.getAudioUrl(), episode.itemID != itemId {
                podcastPlayerController.submitAction(
                    UserAction.Pause(
                        PodcastData(
                            podcast.chat?.id,
                            podcast.feedID,
                            episode.itemID,
                            url,
                            episode.currentTime,
                            episode.duration,
                            podcast.playerSpeed
                        )
                    )
                )
            }
        }
    }
}
