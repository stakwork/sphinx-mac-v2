//
//  GraphListCollectionViewItem.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 30/10/2025.
//  Copyright © 2025 Tomas Timinskas. All rights reserved.
//

import Cocoa

protocol ContentItemCollectionViewDelegate : NSObject {
    func didRightClickOn(item: NSCollectionViewItem)
}

class GraphListCollectionViewItem: NSCollectionViewItem {
    
    weak var delegate: ContentItemCollectionViewDelegate?
    
    @IBOutlet weak var typeImageView: AspectFillNSImageView!
    @IBOutlet weak var typeLabel: NSTextField!
    @IBOutlet weak var dateLabel: NSTextField!
    @IBOutlet weak var statusLabel: NSTextField!

    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    func render(
        with item: GraphListViewController.DataSourceItem,
        and delegate: ContentItemCollectionViewDelegate?
    ) {
        self.delegate = delegate
        
        typeLabel.stringValue = item.typeDescription
        dateLabel.stringValue = item.date.getStringDate(format: "EEE dd MMM, hh:mm a")
        statusLabel.stringValue = item.statusString
        
//        if let type = ContentItem.ContentType(rawValue: item.type) {
//            switch(type) {
//            case .text:
//                typeImageView.image = NSImage(named: "text.bubble.fill")
//                break
//            case .externalURL:
//                typeImageView.image = NSImage(named: "text.bubble.fill")
//                break
//            case .fileURL:
//                break
//            }
//        }
    }
    
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            self.rightMouseDown(with: event)
        } else {
            super.mouseDown(with: event)
        }
    }

    
    override func rightMouseDown(with event: NSEvent) {
        delegate?.didRightClickOn(item: self)
    }
}

extension GraphListCollectionViewItem {
    static let reuseID = "GraphListCollectionViewItem"
    static let nib: NSNib? = {
        NSNib(nibNamed: "GraphListCollectionViewItem", bundle: nil)
    }()
}
