//
//  GraphListCollectionViewItem.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 30/10/2025.
//  Copyright © 2025 Tomas Timinskas. All rights reserved.
//

import Cocoa

class GraphListCollectionViewItem: NSCollectionViewItem {
    
    @IBOutlet weak var typeImageView: AspectFillNSImageView!
    @IBOutlet weak var typeLabel: NSTextField!
    @IBOutlet weak var dateLabel: NSTextField!
    @IBOutlet weak var statusLabel: NSTextField!

    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    func render(
        with item: GraphListViewController.DataSourceItem
    ) {
        typeLabel.stringValue = item.typeDescription
        dateLabel.stringValue = item.date.getStringDate(format: "EEE dd, hh:mm a")
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
    
}

extension GraphListCollectionViewItem {
    static let reuseID = "GraphListCollectionViewItem"
    static let nib: NSNib? = {
        NSNib(nibNamed: "GraphListCollectionViewItem", bundle: nil)
    }()
}
