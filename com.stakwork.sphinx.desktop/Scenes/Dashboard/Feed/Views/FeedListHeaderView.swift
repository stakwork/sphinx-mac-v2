//
//  FeedListHeaderView.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 05/05/2025.
//  Copyright © 2025 Tomas Timinskas. All rights reserved.
//

import Cocoa

protocol FeedListHeaderViewDelegate: AnyObject {
    func didClickRefreshButton(completion: @escaping () -> ())
}

class FeedListHeaderView: NSView, NSCollectionViewElement, LoadableNib {
    
    weak var delegate: FeedListHeaderViewDelegate?
    
    @IBOutlet var contentView: NSView!
    @IBOutlet weak var backgroundColorBox: NSBox!
    @IBOutlet weak var headerLabel: NSTextField!
    @IBOutlet weak var refreshButton: CustomButton!
    @IBOutlet weak var loadingWheel: NSProgressIndicator!
    
    var loading = false {
        didSet {
            LoadingWheelHelper.toggleLoadingWheel(
                loading: loading,
                loadingWheel: loadingWheel,
                color: NSColor.white,
                controls: [refreshButton]
            )
            refreshButton.isHidden = loading
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        loadViewFromNib()
        configureView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        loadViewFromNib()
        configureView()
    }
    
    func configureView() {
        refreshButton.cursor = .pointingHand
        
        backgroundColorBox.fillColor = NSColor.Sphinx.Body
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        
        headerLabel.stringValue = ""
    }
    
    func renderWith(
        title: String
    ) {
        headerLabel.stringValue = title
    }
    
    func renderWith(
        title: String,
        showRefreshButton: Bool,
        delegate: FeedListHeaderViewDelegate?
    ) {
        self.delegate = delegate
        
        headerLabel.stringValue = title
        
        refreshButton.isHidden = !showRefreshButton
    }
    
    @IBAction func refreshButtonClicked(_ sender: Any) {
        loading = true
        
        delegate?.didClickRefreshButton() {
            DispatchQueue.main.async {
                self.loading = false
            }
        }
    }
}
