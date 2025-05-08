//
//  PodcastPlayerCollectionViewItem+UI.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 06/02/2023.
//  Copyright © 2023 Tomas Timinskas. All rights reserved.
//

import Foundation
import AVKit

extension PodcastPlayerCollectionViewItem {
    func setupView() {
        audioLoading = podcastPlayerController.isPlaying(podcastId: podcast.feedID)
        
        podcastSatsView.configureWith(chat: chat)
        showInfo()
        configureControls()
        configureSubscribeButton()
    }
    
    func configureSubscribeButton() {
        subscribeButtonContainer.isHidden = (chat != nil)
        subscribeButton.title = podcast.subscribed == true ? "UNSUBSCRIBE" : "SUBSCRIBE"
    }
    
    func addMessagesFor(ts: Int) {
//        if !podcastPlayerController.isPlaying {
//            return
//        }
//        
//        if let liveM = liveMessages[ts] {
//            livePodcastDataSource?.insert(messages: liveM)
//        }
    }
    
    func showInfo() {
        if let imageURL = podcast.getImageURL() {
            loadImage(imageURL: imageURL)
        }

        episodeLabel.stringValue = podcast.getCurrentEpisode()?.title ?? ""
        
        loadTime()
        loadMessages()
    }
    
    func loadMessages() {
//        liveMessages = [:]
//
//        guard let episodeId = podcast.getCurrentEpisode()?.itemID else {
//            return
//        }
//        let messages = TransactionMessage.getLiveMessagesFor(chat: chat, episodeId: episodeId)
//
//        for m in messages {
//            addToLiveMessages(message: m)
//        }
//
//        if livePodcastDataSource == nil {
//            livePodcastDataSource = PodcastLiveDataSource(collectionView: liveCollectionView, scrollView: liveScrollView, chat: chat)
//        }
//        livePodcastDataSource?.resetData()
    }
    
    func addToLiveMessages(message: TransactionMessage) {
//        if let ts = message.getTimeStamp() {
//            var existingM = liveMessages[ts] ?? Array<TransactionMessage>()
//            existingM.append(message)
//            liveMessages[ts] = existingM
//        }
    }
    
    func loadTime() {
        let episode = podcast.getCurrentEpisode()
        
        if let duration = episode?.duration {
            setProgress(
                duration: duration,
                currentTime: episode?.currentTime ?? 0
            )
        } else if let url = episode?.getAudioUrl() {
            audioLoading = true
            
            setProgress(
                duration: 0,
                currentTime: 0
            )
            
            let asset = AVAsset(url: url)
            asset.loadValuesAsynchronously(forKeys: ["duration"], completionHandler: {
                let duration = Int(Double(asset.duration.value) / Double(asset.duration.timescale))
                episode?.duration = duration
                
                DispatchQueue.main.async {
                    self.setProgress(
                        duration: duration,
                        currentTime: episode?.currentTime ?? 0
                    )
                    self.audioLoading = false
                }
            })
        }
    }
    
    func loadImage(imageURL: URL?) {
        guard let url = imageURL else {
            episodeImageView.image = NSImage(named: "podcastPlaceholder")!
            return
        }
        
        episodeImageView.sd_setImage(
            with: url,
            placeholderImage: NSImage(named: "podcastPlaceholder"),
            options: [.highPriority],
            progress: nil
        )
    }
    
    func setProgress(
        duration: Int,
        currentTime: Int
    ) {
        if skipAdvertIfNeeded(duration: duration, currentTime: currentTime) {
            return
        }
        
        let currentTimeString = currentTime.getPodcastTimeString()
        
        currentTimeLabel.stringValue = currentTimeString
        durationLabel.stringValue = duration.getPodcastTimeString()
        
        let progress = (Double(currentTime) * 100 / Double(duration))/100
        let durationLineWidth = self.view.frame.width - kDurationLineMargins
        var progressWidth = durationLineWidth * CGFloat(progress)

        if !progressWidth.isFinite || progressWidth < 0 {
            progressWidth = 0
        }

        progressLineWidth.constant = progressWidth
        progressLine.layoutSubtreeIfNeeded()
        
        addChaptersDots(duration: duration)
    }
    
    func addChaptersDots(
        duration: Int
    ) {
        guard let episode = podcast.getCurrentEpisode() else {
            return
        }
        
        if chapterInfoEpisodeId != episode.itemID {
            for view in chaptersContainer.subviews {
                view.removeFromSuperview()
            }
        }
        
        chapterInfoEpisodeId = episode.itemID
        
        if chaptersContainer.subviews.count == (episode.chapters ?? []).count {
            return
        }
        
        let chapters = episode.chapters ?? []
        
        for chapter in chapters {
            let chapterTime = chapter.timestamp.toSeconds()
            let progress = (Double(chapterTime) * 100 / Double(duration))/100
            let durationLineWidth = self.view.frame.width - kDurationLineMargins
            let progressWidth = durationLineWidth * CGFloat(progress)
            
            let dotSize: CGFloat = 10
            let dotHalfSize: CGFloat = 5
            let containerHeight: CGFloat = 40
            let chapterDot = NSView(frame: CGRect(x: progressWidth - dotHalfSize, y: (containerHeight / 2) - dotHalfSize, width: dotSize, height: dotSize))
            chapterDot.wantsLayer = true
            chapterDot.layer?.backgroundColor = (chapter.isAd ? NSColor.Sphinx.SecondaryText : NSColor.Sphinx.Text).cgColor
            chapterDot.layer?.cornerRadius = dotHalfSize
            chaptersContainer.addSubview(chapterDot)
        }
    }
    
    func configureControls(
        playing: Bool? = nil
    ) {
        let isPlaying = playing ?? podcastPlayerController.isPlaying(podcastId: podcast.feedID)
        playPauseButton.title = isPlaying ? "pause" : "play_arrow"

        let selectedValue = podcast.playerSpeed.speedDescription + "x"
        
        speedButton.removeAllItems()
        speedButton.addItems(withTitles: speedValues)

        let selectedIndex = speedValues.firstIndex(of: selectedValue)
        speedButton.selectItem(at: selectedIndex ?? 2)
        
        mouseDraggableView.delegate = self
        
        let hasDestinations = podcast.destinationsArray.count > 0
        boostButtonView.alphaValue = hasDestinations ? 1.0 : 0.3
        boostButtonView.toggleEnabled(enabled: hasDestinations)
    }
    
    func skipAdvertIfNeeded(
        duration: Int,
        currentTime: Int
    ) -> Bool {
        if !podcast.skipAds {
            return false
        }
        
        guard let episode = podcast.getCurrentEpisode() else {
            return false
        }
        
        if skippingAdvert {
            return true
        }
        
        let adTimestamps: [(Int, Int)] = episode.getAdTimestamps()
        let addTimestampStarts = adTimestamps.map({ $0.0 })
        
        if addTimestampStarts.contains(currentTime + 2) {
            advertLabel.stringValue = "Ad detected"
            advertContainer.isHidden = false
        } else if addTimestampStarts.contains(currentTime) {
            if let currentAddTimestamps = adTimestamps.first(where: { $0.0 == currentTime }) {
                skippingAdvert = true
                advertLabel.stringValue = "Skipping Ad"
                advertContainer.isHidden = false

                let newTime = currentAddTimestamps.1
                
                let progress = (Double(newTime) * 100 / Double(duration))/100
                let durationLineWidth = self.view.frame.width - kDurationLineMargins
                var progressWidth = durationLineWidth * CGFloat(progress)
                
                if !progressWidth.isFinite || progressWidth < 0 {
                    progressWidth = 0
                }
                
                progressLineWidth.constant = progressWidth
                
                togglePlayState()
                
                AnimationHelper.animateViewWith(duration: 1.0, animationsBlock: {
                    self.progressLine.layoutSubtreeIfNeeded()
                }, completion: {
                    guard let podcastData = self.podcast.getPodcastData(
                        currentTime: newTime
                    ) else {
                        return
                    }
                    
                    self.setProgress(
                        duration: podcastData.duration ?? 0,
                        currentTime: newTime
                    )
                    
                    self.podcastPlayerController.submitAction(
                        UserAction.Seek(podcastData)
                    )
                    
                    self.togglePlayState()
                    self.skippingAdvert = false
                    self.hideAdvertLabel()
                })
                return true
            } else {
                advertContainer.isHidden = true
                return false
            }
        }
        return false
    }
    
    func hideAdvertLabel() {
        DelayPerformedHelper.performAfterDelay(seconds: 1.0, completion: {
            self.advertContainer.isHidden = true
        })
    }
}
