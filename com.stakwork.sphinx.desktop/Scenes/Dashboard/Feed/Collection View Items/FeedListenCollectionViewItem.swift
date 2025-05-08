//
//  FeedListenCollectionViewItem.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 06/05/2025.
//  Copyright © 2025 Tomas Timinskas. All rights reserved.
//

import Cocoa
import SDWebImage

class FeedListenCollectionViewItem: NSCollectionViewItem {

    @IBOutlet weak var itemImageView: AspectFillNSImageView!
    @IBOutlet weak var itemTitle: NSTextField!
    @IBOutlet weak var itemDescription: NSTextField!
    @IBOutlet weak var releasedDateLabel: NSTextField!
    @IBOutlet weak var durationContainer: NSStackView!
    @IBOutlet weak var durationLabel: NSTextField!
    @IBOutlet weak var durationBox: NSBox!
    @IBOutlet weak var currentTimeBox: NSBox!
    @IBOutlet weak var currentTimeWidthConstraint: NSLayoutConstraint!
    
    let kProgressViewContainerWidth: CGFloat = 40.0
    
    enum Section: Int {
        case recentlyReleasePods
        case recentlyPlayedPods
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        itemImageView.rounded = true
        itemImageView.radius = 5
        
        itemDescription.maximumNumberOfLines = 3
        durationBox.alphaValue = 0.2
    }
    
    func configure(
        withItem item: PodcastEpisode,
        section: Int
    ) {
        itemTitle.stringValue = item.title ?? ""
        itemDescription.stringValue = item.formattedDescription
        itemImageView.image = NSImage(named: "podcastPlaceholder")
        
        if let publishDate = item.datePublished?.publishDateString, section == Section.recentlyReleasePods.rawValue {
            releasedDateLabel.stringValue = publishDate
            releasedDateLabel.isHidden = false
        } else {
            releasedDateLabel.isHidden = true
        }
        
        if section == Section.recentlyReleasePods.rawValue {
            configureTimeView(withItem: item)
        } else {
            durationContainer.isHidden = true
        }
        
        if let imageURLString = item.imageURLPath, let imageURL = URL(string: imageURLString) {
            
            let transformer = SDImageResizingTransformer(
                size: CGSize(width: itemImageView.bounds.size.width * 2, height: itemImageView.bounds.size.height * 2),
                scaleMode: .aspectFill
            )
            itemImageView.sd_setImage(
                with: imageURL,
                placeholderImage: NSImage(named: "podcastPlaceholder"),
                options: [.lowPriority],
                context: [.imageTransformer: transformer],
                progress: nil,
                completed: { [weak self] (image, error,_,_) in
                    if (error == nil) {
                        self?.itemImageView.image = image
                    } else {
                        self?.itemImageView.image = NSImage(named: "podcastPlaceholder")
                    }
                }
            )
        }
    }
    
    private func configureTimeView(withItem item: PodcastEpisode) {
        if let duration = item.duration, duration > 0 {
            
            let currentTime = item.currentTime ?? 0
            
            durationBox.isHidden = currentTime == 0
            currentTimeBox.isHidden = currentTime == 0
            
            currentTimeWidthConstraint.constant = CGFloat(currentTime) / CGFloat(duration) * kProgressViewContainerWidth
            currentTimeBox.layoutSubtreeIfNeeded()
            
            setTimeLabel(duration: duration, currentTime: currentTime)
            
            durationContainer.isHidden = false
        } else {
            durationContainer.isHidden = true
        }
    }
    
    private func setTimeLabel(
        duration: Int,
        currentTime: Int
    ) {
        let timeString = (duration - currentTime).getEpisodeTimeString(
            isOnProgress: currentTime > 0
        )
        
        durationLabel.stringValue = timeString
    }
    
}
