//
//  AttachmentsPreviewDataSource.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 05/12/2024.
//  Copyright © 2024 Tomas Timinskas. All rights reserved.
//

import Cocoa

protocol AttachmentPreviewDataSourceDelegate: AnyObject {
    func shouldRemoveItemAt(index: Int)
}

class AttachmentsPreviewDataSource : NSObject {
    var attachments : [AttachmentPreview] = [AttachmentPreview]()
    
    var attachmentsCollectionView : NSCollectionView!
    var scrollView: NSScrollView!
    
    weak var delegate: AttachmentPreviewDataSourceDelegate!
    
    let kCellWidth : CGFloat = 152.0
    let kCellHeight : CGFloat = 155.0
    
    init(
        collectionView: NSCollectionView,
        scrollView: NSScrollView,
        delegate: AttachmentPreviewDataSourceDelegate
    ){
        super.init()
        
        self.attachmentsCollectionView = collectionView
        self.delegate = delegate
        self.scrollView = scrollView
        
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
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: {
            let ctx = NSAnimationContext.current
            ctx.duration = 0.15
            ctx.allowsImplicitAnimation = true
            
            self.attachmentsCollectionView.animator().scrollToItems(
                at: [IndexPath(item: self.attachments.count - 1, section: 0)],
                scrollPosition: .right
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
    
    func collectionView(
        _ collectionView: NSCollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        return attachments.count
    }
    
    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        
        let item = collectionView.makeItem(
            withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "AttachmentPreviewCollectionViewItem"),
            for: indexPath
        )
        
        guard let attachmentItem = item as? AttachmentPreviewCollectionViewItem else {return item}
        
        return attachmentItem
    }
    
    func collectionView(
        _ collectionView: NSCollectionView,
        willDisplay item: NSCollectionViewItem,
        forRepresentedObjectAt indexPath: IndexPath
    ) {
        if let collectionViewItem = item as? AttachmentPreviewCollectionViewItem {
            let item = attachments[indexPath.item]
            collectionViewItem.render(
                with: item,
                index: indexPath.item,
                itemDelegate: self
            )
        }
    }
}

extension AttachmentsPreviewDataSource : AttachmentPreviewItemDelegate {
    func closeButtonClicked(item: NSCollectionViewItem) {
        if let indexPath = attachmentsCollectionView.indexPath(for: item) {
            let index = indexPath.item
            
            attachments.remove(at: index)
            attachmentsCollectionView.reloadData()
            
            delegate?.shouldRemoveItemAt(index: index)
        }
    }
    
    func playVideoButtonClicked(item: NSCollectionViewItem) {
//        if let indexPath = attachmentsCollectionView.indexPath(for: item) {
//            
//        }
    }
}
