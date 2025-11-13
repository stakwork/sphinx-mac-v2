//
//  FeedListHeaderView.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 05/05/2025.
//  Copyright © 2025 Tomas Timinskas. All rights reserved.
//

import Cocoa

protocol FeedListHeaderViewDelegate: AnyObject {
    func didClickRefreshButton()
}

class FeedListHeaderView: NSView, NSCollectionViewElement, LoadableNib {
    
    weak var delegate: FeedListHeaderViewDelegate?
    
    @IBOutlet var contentView: NSView!
    @IBOutlet weak var backgroundColorBox: NSBox!
    @IBOutlet weak var headerLabel: NSTextField!
    @IBOutlet weak var refreshButton: CustomButton!
    
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
    
    func configureView() {
        refreshButton.cursor = .pointingHand
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        
        headerLabel.stringValue = ""
    }
    
    func renderWith(title: String) {
        headerLabel.stringValue = title
    }
    
    func renderWith(
        title: String,
        backgroundColor: NSColor,
        showRefreshButton: Bool,
        delegate: FeedListHeaderViewDelegate?
    ) {
        backgroundColorBox.fillColor = backgroundColor
        
        headerLabel.stringValue = title
        
        refreshButton.isHidden = !showRefreshButton
    }
    
    @IBAction func refreshButtonClicked(_ sender: Any) {
        delegate?.didClickRefreshButton()
    }
}
