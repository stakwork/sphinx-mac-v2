//
//  FeedSectionHeaderView.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 07/05/2025.
//  Copyright © 2025 Tomas Timinskas. All rights reserved.
//

import Cocoa

class FeedSectionHeaderView: NSView, NSCollectionViewElement, LoadableNib {
    
    @IBOutlet var contentView: NSView!
    @IBOutlet weak var headerLabel: NSTextField!
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        loadViewFromNib()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        loadViewFromNib()
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        
        headerLabel.stringValue = ""
    }
    
    func renderWith(title: String) {
        headerLabel.stringValue = title
    }
}
