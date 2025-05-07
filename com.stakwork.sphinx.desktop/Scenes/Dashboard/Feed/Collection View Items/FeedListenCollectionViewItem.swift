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
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    func configure(withItem item: PodcastEpisode) {
        itemTitle.stringValue = item.title ?? ""
        itemDescription.stringValue = item.formattedDescription
        itemImageView.image = NSImage(named: "podcastPlaceholder")
        
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
    
}
