//
//  AttachmentsPreviewDataSource.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 05/12/2024.
//  Copyright © 2024 Tomas Timinskas. All rights reserved.
//

import Cocoa

protocol AttachmentPreviewDataSourceDelegate: AnyObject {
    
}

class AttachmentsPreviewDataSource : NSObject {
    var attachments : [AttachmentPreview] = [AttachmentPreview]()
    
    var attachmentsCollectionView : NSCollectionView!
    var scrollView: NSScrollView!
    
    weak var delegate: AttachmentPreviewDataSourceDelegate!
    
    let kCellWidth : CGFloat = 152.0
    let kCellHeight : CGFloat = 140.0
    
    init(
        collectionView: NSCollectionView,
        scrollView: NSScrollView,
        delegate: AttachmentPreviewDataSourceDelegate
    ){
        super.init()
        
        self.attachmentsCollectionView = collectionView
        self.delegate = delegate
        self.scrollView = scrollView
//        self.collectionView.backgroundColors = [NSColor.Sphinx.HeaderBG]
        
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.horizontalScrollElasticity = .automatic
        scrollView.verticalScrollElasticity = .none
        
        attachmentsCollectionView.delegate = self
        attachmentsCollectionView.dataSource = self
        attachmentsCollectionView.registerItem(AttachmentPreviewCollectionViewItem.self)
       
        configureCollectionView()
        updateAttachments(attachments: [])
    }
    
    func updateAttachments(attachments: [AttachmentPreview]) {
        if attachments.isEmpty == true {
            self.attachments = []
            self.scrollView.isHidden = true
            return
        }
        
        self.scrollView.isHidden = false
        self.attachments = attachments
        
        attachmentsCollectionView.reloadData()
        
        if attachments.isEmpty {
            return
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01, execute: {
            self.attachmentsCollectionView.animator().scrollToItems(
                at: [IndexPath(item: self.attachments.count - 1, section: 0)],
                scrollPosition: .bottom
            )
        })
    }
    
    func isTableVisible() -> Bool {
        return attachments.count > 0 && !self.scrollView.isHidden
    }
    
    func configureCollectionView() {
        let flowLayout = NSCollectionViewFlowLayout()
        flowLayout.sectionInset = NSEdgeInsets(top: 0.0, left: 0.0, bottom: 0.0, right: 0.0)
        flowLayout.minimumInteritemSpacing = 0.0
        flowLayout.minimumLineSpacing = 0.0
        flowLayout.scrollDirection = .horizontal
        flowLayout.itemSize = NSSize(width: kCellWidth, height: kCellHeight)
        attachmentsCollectionView.collectionViewLayout = flowLayout
    }
}

extension AttachmentsPreviewDataSource : NSCollectionViewDelegate, NSCollectionViewDataSource{
    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        return 1
    }
    
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        return attachments.count
    }
    
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        
        let item = collectionView.makeItem(
            withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "AttachmentPreviewCollectionViewItem"),
            for: indexPath
        )
        
        guard let attachmentItem = item as? AttachmentPreviewCollectionViewItem else {return item}
        
        return attachmentItem
    }
    
    func collectionView(_ collectionView: NSCollectionView, willDisplay item: NSCollectionViewItem, forRepresentedObjectAt indexPath: IndexPath) {
        if let collectionViewItem = item as? AttachmentPreviewCollectionViewItem {
//            attachmentItem.configureWith(
//                mentionOrMacro: suggestions[indexPath.item],
//                delegate: delegate
//            )
        }
    }
}
