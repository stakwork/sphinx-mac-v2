//
//  CommonWelcomeViewController.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 19/02/2021.
//  Copyright © 2021 Tomas Timinskas. All rights reserved.
//

import Cocoa

class CommonWelcomeViewController: NSViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    func presentDashboard() {
        let mainScreen = NSScreen.main
        let frame = WindowsManager.sharedInstance.getCenteredFrameFor(
            size: CGSize(
                width: (mainScreen?.frame.width ?? 1375) * 0.9,
                height: (mainScreen?.frame.height ?? 1062) * 0.9
            )
        )
        view.alphaValue = 0.0
        view.window?.styleMask = [.titled, .resizable, .miniaturizable]
        view.window?.titlebarAppearsTransparent = false
        view.window?.titleVisibility = .visible
        view.window?.setFrame(frame, display: true, animate: true)
        view.window?.replaceContentBy(vc: DashboardViewController.instantiate())
    }
}
