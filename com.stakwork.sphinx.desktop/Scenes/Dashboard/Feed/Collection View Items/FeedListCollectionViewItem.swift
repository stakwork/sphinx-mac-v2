//
//  FeedListCollectionViewItem.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 05/05/2025.
//  Copyright © 2025 Tomas Timinskas. All rights reserved.
//

import Cocoa
import SDWebImage

class FeedListCollectionViewItem: NSCollectionViewItem {

    @IBOutlet weak var feedImageView: AspectFillNSImageView!
    @IBOutlet weak var feedNameLabel: NSTextField!
    @IBOutlet weak var hostNameLabel: NSTextField!
    @IBOutlet weak var contentTypeImage: NSImageView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
    }
    
    func setupViews() {
        ///General setup
        feedImageView.wantsLayer = true
        feedImageView.gravity = .resizeAspectFill
        feedImageView.radius = 5
        feedImageView.image = NSImage(named: "podcastPlaceholder")
        
        feedNameLabel.stringValue = ""
        hostNameLabel.stringValue = ""
        
        contentTypeImage.isHidden = true
    }
    
    func render(
        with item: FeedListViewController.DataSourceItem
    ) {
        feedNameLabel.stringValue = item.title
        hostNameLabel.stringValue = item.authorName ?? item.feedDescription ?? ""
        
        if let imageURLString = item.imageUrl, let imageURL = URL(string: imageURLString) {
            
            let transformer = SDImageResizingTransformer(
                size: CGSize(width: feedImageView.bounds.size.width * 2, height: feedImageView.bounds.size.height * 2),
                scaleMode: .aspectFill
            )
            
            feedImageView.sd_setImage(
                with: imageURL,
                placeholderImage: NSImage(named: "podcastPlaceholder"),
                options: [.lowPriority],
                context: [.imageTransformer: transformer],
                progress: nil,
                completed: { [weak self] (image, error,_,_) in
                    if (error == nil) {
                        self?.feedImageView.image = image
                    }
                }
            )
        }
    }
    
}

extension FeedListCollectionViewItem {
    static let reuseID = "FeedListCollectionViewItem"
    static let nib: NSNib? = {
        NSNib(nibNamed: "FeedListCollectionViewItem", bundle: nil)
    }()
}

