//
//  FeedListenDashboardViewController.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 06/05/2025.
//  Copyright © 2025 Tomas Timinskas. All rights reserved.
//

import Cocoa

class FeedListenDashboardViewController: NSViewController {
    
    @IBOutlet weak var feedCollectionView: NSCollectionView!
    
    static func instantiate() -> FeedListenDashboardViewController {
        let viewController = StoryboardScene.Dashboard.feedListenDashboardViewController.instantiate()
        return viewController
    }

    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
}
