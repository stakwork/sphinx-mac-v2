//
//  FeedListenCollectionViewItem.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 06/05/2025.
//  Copyright © 2025 Tomas Timinskas. All rights reserved.
//

import Cocoa

class FeedListenCollectionViewItem: NSCollectionViewItem {

    @IBOutlet weak var itemImageView: AspectFillNSImageView!
    @IBOutlet weak var itemTitle: NSTextField!
    @IBOutlet weak var itemDescription: NSTextField!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
    }
    
}
