//
//  LoadingMoreMessagesView.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 01/10/2025.
//  Copyright © 2025 Tomas Timinskas. All rights reserved.
//

import Cocoa

class LoadingMoreMessagesView: NSView, LoadableNib {
    
    @IBOutlet var contentView: NSView!
    @IBOutlet weak var loadingWheel: NSProgressIndicator!
    
    var loading = false {
        didSet {
            LoadingWheelHelper.toggleLoadingWheel(
                loading: loading,
                loadingWheel: loadingWheel,
                color: NSColor.Sphinx.SecondaryText,
                controls: []
            )
        }
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        loadViewFromNib()
        setup()
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        loadViewFromNib()
        setup()
    }
    
    func setup() {
        loading = true
    }
    
    func configure() {
        loading = true
    }
    
}
