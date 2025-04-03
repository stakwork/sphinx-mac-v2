//
//  EpisodeChapterView.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 03/04/2025.
//  Copyright © 2025 Tomas Timinskas. All rights reserved.
//

import Cocoa

protocol ChapterViewDelegate : NSObject {
    func shouldPlayChapterWith(index: Int)
}

class EpisodeChapterView: NSView, LoadableNib {
    
    weak var delegate: ChapterViewDelegate?
    
    @IBOutlet var contentView: NSView!
    @IBOutlet weak var episodeTitleLabel: NSTextField!
    @IBOutlet weak var isAdLabel: NSTextField!
    @IBOutlet weak var timestampLabel: NSTextField!
    @IBOutlet weak var chapterButton: CustomButton!
    
    var index: Int! = nil
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        loadViewFromNib()
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        loadViewFromNib()
    }
    
    func configureWith(
        chapter: Chapter,
        delegate: ChapterViewDelegate?,
        index: Int,
        episodeRow: Bool
    ) {
        self.delegate = delegate
        self.index = index
        
        chapterButton.cursor = .pointingHand
        isAdLabel.isHidden = !chapter.isAd
        
        episodeTitleLabel.stringValue = chapter.name
        timestampLabel.stringValue = chapter.timestamp
    }
    
    @IBAction func chapterButtonClicked(_ sender: Any) {
        delegate?.shouldPlayChapterWith(index: index)
    }
    
}
