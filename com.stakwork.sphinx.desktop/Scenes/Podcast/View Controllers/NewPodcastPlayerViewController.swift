//
//  NewPodcastPlayerViewController.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 04/11/2020.
//  Copyright © 2020 Sphinx. All rights reserved.
//

import Cocoa

class NewPodcastPlayerViewController: NSViewController {
    
    weak var delegate: PodcastPlayerViewDelegate? = nil
    
    @IBOutlet weak var playerCollectionView: NSCollectionView!
    
    var newEpisodeView: NewEpisodeAlertView? = nil
    
    var chat: Chat? = nil
    var podcast: PodcastFeed! = nil
    var collectionViewDS: PodcastEpisodesDataSource! = nil
    var deepLinkData : DeeplinkData? = nil

    override func viewDidLoad() {
        super.viewDidLoad()
        
        showEpisodesTable()
    }
    
    override func viewDidLayout() {
        super.viewDidLayout()
        
        playerCollectionView.collectionViewLayout?.invalidateLayout()
        
        NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: playerCollectionView.enclosingScrollView?.contentView,
            queue: OperationQueue.main
        ) { [weak self] (n: Notification) in
            self?.newEpisodeView?.hideView()
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: nil)
    }
    
    static func instantiate(
        chat: Chat?,
        podcast: PodcastFeed,
        delegate: PodcastPlayerViewDelegate?,
        deepLinkData: DeeplinkData? = nil
    ) -> NewPodcastPlayerViewController {
        let viewController = StoryboardScene.Podcast.newPodcastPlayerViewController.instantiate()
        viewController.chat = chat
        viewController.podcast = podcast
        viewController.delegate = delegate
        viewController.deepLinkData = deepLinkData
        
        return viewController
    }
    
    func showEpisodesTable() {
        collectionViewDS = PodcastEpisodesDataSource(
            collectionView: playerCollectionView,
            chat: chat,
            podcastFeed: podcast,
            delegate: self
        )
        
        newEpisodeView = NewEpisodeAlertView.checkForNewEpisode(
            podcast: podcast,
            view: self.view
        )
        
        if let data = deepLinkData,
           let deeplinkedItem = podcast.episodes?.first(where: {$0.itemID == data.itemID}) {
            
            if let playerView = collectionViewDS.collectionView.item(
                at: IndexPath(item: 0, section: 0)
            ) as? PodcastPlayerCollectionViewItem {
                playerView.selectEpisode(
                    episode: deeplinkedItem,
                    atTime: data.timestamp
                )
            }
        }
    }
}

extension NewPodcastPlayerViewController : PodcastEpisodesDSDelegate {    
    func shouldShareClip(comment: PodcastComment) {
        delegate?.shouldShareClip(comment: comment)
    }
    
    func shouldSendBoost(message: String, amount: Int, animation: Bool) -> TransactionMessage? {
        return delegate?.shouldSendBoost(message: message, amount: amount, animation: animation)
    }
    
    func shouldCopyShareLink(link: String) {
        ClipboardHelper.copyToClipboard(text: link)
    }
}
