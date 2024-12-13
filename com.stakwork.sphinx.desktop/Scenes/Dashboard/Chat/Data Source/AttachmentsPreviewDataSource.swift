//
//  AttachmentsPreviewDataSource.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 05/12/2024.
//  Copyright © 2024 Tomas Timinskas. All rights reserved.
//

import Cocoa

protocol AttachmentPreviewDataSourceDelegate: AnyObject {
    func shouldRemoveItemAt(index: Int?)
    func didClickAddAttachment()
}

class AttachmentsPreviewDataSource : NSObject {
    var attachments : [AttachmentPreview] = [AttachmentPreview]()
    
    var attachmentsCollectionView : NSCollectionView!
    var scrollView: NSScrollView!
    
    weak var delegate: AttachmentPreviewDataSourceDelegate!
    
    let kCellWidth : CGFloat = 152.0
    let kCellHeight : CGFloat = 155.0
    let kAddCellWidth : CGFloat = 72.0
    
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
        attachmentsCollectionView.registerItem(AddAttachmentCollectionViewItem.self)
       
        configureCollectionView()
        updateAttachments(attachments: [])
    }
    
    func updateAttachments(attachments: [AttachmentPreview]) {
        if attachments.isEmpty {
            self.attachments = []
            self.scrollView.isHidden = true
            return
        }
        
        self.scrollView.isHidden = false
        self.attachments = attachments
        
        attachmentsCollectionView.collectionViewLayout?.invalidateLayout()
        attachmentsCollectionView.reloadData()
        
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
        attachmentsCollectionView.collectionViewLayout = flowLayout
    }
}

extension AttachmentsPreviewDataSource : NSCollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> NSSize {
        var itemSize = NSSize(width: kCellWidth, height: kCellHeight)
        
        if indexPath.item == attachments.count {
            itemSize = NSSize(width: kAddCellWidth, height: kCellHeight)
        }
        
        return itemSize
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
        return attachments.count + 1
    }
    
    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        
        if indexPath.item == attachments.count {
            let item = collectionView.makeItem(
                withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "AddAttachmentCollectionViewItem"),
                for: indexPath
            )
            
            guard let addAttachmentItem = item as? AddAttachmentCollectionViewItem else {return item}
            
            return addAttachmentItem
        }
        
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
        } else if let collectionViewItem = item as? AddAttachmentCollectionViewItem {
            collectionViewItem.configureWith(delegate: self)
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

extension AttachmentsPreviewDataSource: AddAttachmentDelegate {
    func didClickAddAttachment() {
        delegate?.didClickAddAttachment()
    }
}
