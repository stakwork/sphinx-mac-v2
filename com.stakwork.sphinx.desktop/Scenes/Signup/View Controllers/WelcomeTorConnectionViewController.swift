//
//  WelcomeTorConnectionViewController.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 11/02/2021.
//  Copyright © 2021 Tomas Timinskas. All rights reserved.
//

import Cocoa

class WelcomeErrorHandlerViewController : CommonWelcomeViewController {
    
    @IBOutlet weak var loadingWheel: NSProgressIndicator!
    @IBOutlet weak var loadingLabel: NSTextField!
    
    let messageBubbleHelper = NewMessageBubbleHelper()
    
    var loading = false {
        didSet {
            LoadingWheelHelper.toggleLoadingWheel(loading: loading, loadingWheel: loadingWheel, color: NSColor.white, controls: [])
            loadingLabel.isHidden = !loading
        }
    }
    
    func errorRestoring(message: String) {
        loadingLabel.textColor = NSColor.Sphinx.BadgeRed
        loadingLabel.stringValue = message
        loading = true
    }
}
