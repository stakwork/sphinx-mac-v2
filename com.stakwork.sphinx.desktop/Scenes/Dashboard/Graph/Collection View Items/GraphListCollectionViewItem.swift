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
    
    @IBOutlet weak var typeLabel: NSTextField!
    @IBOutlet weak var separator: NSTextField!
    @IBOutlet weak var textLabel: NSTextField!
    @IBOutlet weak var dateLabel: NSTextField!
    @IBOutlet weak var iconImageView: NSImageView!
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
        
        if item.status == ContentItem.ContentItemStatus.error.rawValue, item.errorMessage != nil {
            textLabel.stringValue = item.errorMessage ?? ""
            textLabel.textColor = NSColor.Sphinx.PrimaryRed
            textLabel.isHidden = false
            separator.isHidden = false
        } else if item.type == ContentItem.ContentType.text.rawValue, item.status == ContentItem.ContentItemStatus.onQueue.rawValue {
            textLabel.stringValue = item.value
            textLabel.textColor = NSColor.Sphinx.SecondaryText
            textLabel.isHidden = false
            separator.isHidden = false
        } else {
            textLabel.isHidden = true
            separator.isHidden = true
        }
        
        
        dateLabel.stringValue = item.date.getStringDate(format: "EEE dd MMM, hh:mm a")
        
        let status = ContentItem.ContentItemStatus(fromRawValue: Int(item.status))
        
        statusLabel.stringValue = item.statusString
        statusLabel.textColor = status.color

        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            .applying(.init(hierarchicalColor: status.color))

        if let image = NSImage(systemSymbolName: status.sfSymbol, accessibilityDescription: nil) {
            iconImageView.image = image.withSymbolConfiguration(config)
        }
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
