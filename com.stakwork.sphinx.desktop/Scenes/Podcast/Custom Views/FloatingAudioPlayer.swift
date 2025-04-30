//
//  FloatingAudioPlayer.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 30/04/2025.
//  Copyright © 2025 Tomas Timinskas. All rights reserved.
//

import Cocoa

class FloatingAudioPlayer: NSView, LoadableNib {
    
    @IBOutlet var contentView: NSView!
    
    @IBOutlet weak var draggingBackgroundBox: NSBox!
    @IBOutlet weak var playerBackgroundBox: NSBox!
    @IBOutlet weak var fullScreenButton: CustomButton!
    @IBOutlet weak var episodeImageView: AspectFillNSImageView!
    @IBOutlet weak var podcastTitleLabel: NSTextField!
    @IBOutlet weak var episodeTitleLabel: NSTextField!
    @IBOutlet weak var durationBox: NSBox!
    @IBOutlet weak var currentTimeBox: NSBox!
    @IBOutlet weak var chaptersContainer: NSView!
    @IBOutlet weak var mouseDraggableView: MouseDraggableView!
    @IBOutlet weak var backward15Button: CustomButton!
    @IBOutlet weak var forward30Button: CustomButton!
    @IBOutlet weak var playButton: CustomButton!
    @IBOutlet weak var closeButtonCircle: NSBox!
    @IBOutlet weak var closeButton: CustomButton!
    
    @IBOutlet weak var currentTimeWidthConstraint: NSLayoutConstraint!
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        loadViewFromNib()
        setupView()
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        loadViewFromNib()
        setupView()
    }
    
    func setupView() {
        fullScreenButton.cursor = .pointingHand
        backward15Button.cursor = .pointingHand
        forward30Button.cursor = .pointingHand
        playButton.cursor = .pointingHand
        closeButton.cursor = .pointingHand
        
        episodeImageView.rounded = true
        episodeImageView.radius = 10
        episodeImageView.gravity = .resizeAspectFill
        
        draggingBackgroundBox.alphaValue = 0.1
        
        fullScreenButton.contentTintColor = NSColor.Sphinx.Text
        fullScreenButton.alphaValue = 0.5
        
        durationBox.alphaValue = 0.1
        currentTimeBox.alphaValue = 0.75
    }
    
}
