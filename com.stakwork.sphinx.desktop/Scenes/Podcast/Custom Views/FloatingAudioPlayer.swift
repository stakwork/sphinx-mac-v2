//
//  FloatingAudioPlayer.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 30/04/2025.
//  Copyright © 2025 Tomas Timinskas. All rights reserved.
//

import Cocoa
import AVFoundation

class FloatingAudioPlayer: NSView, LoadableNib {
    
    @IBOutlet var contentView: NSView!
    
    @IBOutlet weak var draggingBackgroundBox: NSBox!
    @IBOutlet weak var playerBackgroundBox: NSBox!
    @IBOutlet weak var fullScreenButton: CustomButton!
    @IBOutlet weak var episodeImageView: AspectFillNSImageView!
    @IBOutlet weak var podcastTitleLabel: NSTextField!
    @IBOutlet weak var episodeTitleLabel: NSTextField!
    @IBOutlet weak var durationBox: NSBox!
    @IBOutlet weak var currentTimeBox: NSBox!
    @IBOutlet weak var chaptersContainer: NSView!
    @IBOutlet weak var mouseDraggableView: MouseDraggableView!
    @IBOutlet weak var backward15Button: CustomButton!
    @IBOutlet weak var forward30Button: CustomButton!
    @IBOutlet weak var playButton: CustomButton!
    @IBOutlet weak var closeButtonCircle: NSBox!
    @IBOutlet weak var closeButton: CustomButton!
    
    @IBOutlet weak var currentTimeWidthConstraint: NSLayoutConstraint!
    
    let podcastPlayerController = PodcastPlayerController.sharedInstance
    var podcast: PodcastFeed! = nil
    
    var dragging = false
//    var skippingAdvert = false
    
    var audioLoading = false {
        didSet {
//            LoadingWheelHelper.toggleLoadingWheel(loading: audioLoading, loadingWheel: audioLoadingWheel, color: NSColor.Sphinx.Text, controls: [])
        }
    }
    
    let kDurationLineWidth: CGFloat = 270
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        loadViewFromNib()
        setupView()
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        loadViewFromNib()
        setupView()
    }
    
    func setupView() {
        fullScreenButton.cursor = .pointingHand
        backward15Button.cursor = .pointingHand
        forward30Button.cursor = .pointingHand
        playButton.cursor = .pointingHand
        closeButton.cursor = .pointingHand
        
        episodeImageView.rounded = true
        episodeImageView.radius = 10
        episodeImageView.gravity = .resizeAspectFill
        
        draggingBackgroundBox.alphaValue = 0.1
        
        fullScreenButton.contentTintColor = NSColor.Sphinx.Text
        fullScreenButton.alphaValue = 0.5
        
        durationBox.alphaValue = 0.1
        currentTimeBox.alphaValue = 0.75
    }
    
}

extension FloatingAudioPlayer : PlayerDelegate {
    func loadAndSetPodcastFrom(_ podcastData: PodcastData) {
        if podcastData.podcastId == podcast?.feedID {
            return
        }
        if let feed = ContentFeed.getFeedById(feedId: podcastData.podcastId) {
            let podcast = PodcastFeed.convertFrom(contentFeed: feed)
            self.podcast = podcast
        }
    }
    
    func loadingState(_ podcastData: PodcastData) {
        loadAndSetPodcastFrom(podcastData)
        configureControls(playing: true)
        showInfo()
        audioLoading = true
    }
    
    func playingState(_ podcastData: PodcastData) {
        if dragging {
            return
        }
        loadAndSetPodcastFrom(podcastData)
        configureControls(playing: true)
        
        setProgress(
            duration: podcastData.duration ?? 0,
            currentTime: podcastData.currentTime ?? 0
        )
        
        audioLoading = false
    }
    
    func pausedState(_ podcastData: PodcastData) {
        loadAndSetPodcastFrom(podcastData)
        configureControls(playing: false)
        
        setProgress(
            duration: podcastData.duration ?? 0,
            currentTime: podcastData.currentTime ?? 0
        )
        
        audioLoading = false
    }
    
    func endedState(_ podcastData: PodcastData) {
        loadAndSetPodcastFrom(podcastData)
        configureControls(playing: false)
        
        setProgress(
            duration: podcastData.duration ?? 0,
            currentTime: podcastData.currentTime ?? 0
        )
    }
    
    func errorState(_ podcastData: PodcastData) {
        loadAndSetPodcastFrom(podcastData)
        audioLoading = false
        configureControls(playing: false)
    }
    
    func showInfo() {
        if let imageURL = podcast.getImageURL() {
            loadImage(imageURL: imageURL)
        }

        episodeTitleLabel.stringValue = podcast.getCurrentEpisode()?.title ?? ""
        
        loadTime()
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
        
        episodeImageView.gravity = .resizeAspect
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
    
    func configureControls(
        playing: Bool? = nil
    ) {
        let isPlaying = playing ?? podcastPlayerController.isPlaying(podcastId: podcast.feedID)
        playButton.title = isPlaying ? "pause" : "play_arrow"
        
        mouseDraggableView.delegate = self
    }
    
    func setProgress(
        duration: Int,
        currentTime: Int
    ) {
//        if skipAdvertIfNeeded(duration: duration, currentTime: currentTime) {
//            return
//        }
        
        let progress = (Double(currentTime) * 100 / Double(duration))/100
        let durationLineWidth = kDurationLineWidth
        var progressWidth = durationLineWidth * CGFloat(progress)

        if !progressWidth.isFinite || progressWidth < 0 {
            progressWidth = 0
        }

        currentTimeWidthConstraint.constant = progressWidth
        currentTimeBox.layoutSubtreeIfNeeded()
        
//        addChaptersDots(duration: duration)
    }
}

extension FloatingAudioPlayer : MouseDraggableViewDelegate {
    func mouseDownOn(x: CGFloat) {
        dragging = true
//        livePodcastDataSource?.resetData()
        
        mouseDraggedOn(x: x)
    }
    
    func mouseUpOn(x: CGFloat) {
        dragging = false
        
        guard let episode = podcast.getCurrentEpisode(), let duration = episode.duration else {
            return
        }
        
        let progress = ((currentTimeWidthConstraint.constant * 100) / kDurationLineWidth) / 100
        let currentTime = Int(Double(duration) * progress)
        
        guard let podcastData = podcast.getPodcastData(
            currentTime: currentTime
        ) else {
            return
        }
        
        podcastPlayerController.submitAction(
            UserAction.Seek(podcastData)
        )
        
//        delegate?.shouldSyncPodcast()
    }
    
    func mouseDraggedOn(x: CGFloat) {
        let totalProgressWidth = kDurationLineWidth
        let translation = (x < 0) ? 0 : ((x > totalProgressWidth) ? totalProgressWidth : x)
        
        if !translation.isFinite || translation < 0 {
            return
        }

        currentTimeWidthConstraint.constant = translation
        currentTimeBox.layoutSubtreeIfNeeded()
        
        guard let episode = podcast.getCurrentEpisode(), let duration = episode.duration else {
            return
        }
        
        let progress = ((currentTimeWidthConstraint.constant * 100) / kDurationLineWidth) / 100
        let currentTime = Int(Double(duration) * progress)
        setProgress(duration: duration, currentTime: currentTime)
    }
}
