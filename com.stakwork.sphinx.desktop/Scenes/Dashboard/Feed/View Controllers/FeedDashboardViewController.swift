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
    
    func addChildViewController() {
        let feedListenVC = FeedListenDashboardViewController.instantiate()
        addChildVC(child: feedListenVC, container: childContainerView)
    }
}
