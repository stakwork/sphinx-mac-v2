//
//  EpisodeChapterItemView.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 04/04/2025.
//  Copyright © 2025 Tomas Timinskas. All rights reserved.
//

import Cocoa

class EpisodeChapterItemView: NSCollectionViewItem {

    @IBOutlet weak var episodeChapterView: EpisodeChapterView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    func configureWith(
        chapter: Chapter,
        delegate: ChapterViewDelegate?,
        index: Int
    ) {
        episodeChapterView.configureWith(chapter: chapter, delegate: delegate, index: index)
    }
    
}
