//
//  PodcastEpisodesHeaderView.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 04/11/2020.
//  Copyright © 2020 Sphinx. All rights reserved.
//

import Cocoa

protocol PodcastEpisodesHeaderViewDelegate : AnyObject {
    func skipAdsButtonClicked() -> Bool
}

class PodcastEpisodesHeaderView: NSView {
    
    weak var delegate: PodcastEpisodesHeaderViewDelegate?
    
    @IBOutlet weak var episodesLabel: NSTextField!
    @IBOutlet weak var episodesCountLabel: NSTextField!
    @IBOutlet weak var skipAdsContainer: NSBox!
    @IBOutlet weak var skipAdsLabel: NSTextField!
    @IBOutlet weak var skipAdsButton: CustomButton!
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    func configureWith(
        count: Int,
        skipAdsEnabled: Bool,
        delegate: PodcastEpisodesHeaderViewDelegate?
    ) {
        self.delegate = delegate
       
        skipAdsButton.cursor = .pointingHand
        episodesLabel.stringValue = "episodes".localized.uppercased()
        episodesCountLabel.stringValue = "\(count)"
        
        configureSkipAdsButton(enable: skipAdsEnabled)
    }
    
    @IBAction func skipAdsButtonClicked(_ sender: Any) {
        if let newValue = delegate?.skipAdsButtonClicked() {
            configureSkipAdsButton(enable: newValue)
        }
    }
    
    func configureSkipAdsButton(enable: Bool) {
        skipAdsContainer.fillColor = enable ? NSColor.Sphinx.PrimaryGreen : NSColor(hex: "#B0B7BC")
        skipAdsLabel.textColor = enable ? NSColor.white : NSColor(hex: "#6B7A8D")
        skipAdsLabel.stringValue = enable ? "SKIP ADS ENABLED" : "SKIP ADS DISABLED"
    }
}
