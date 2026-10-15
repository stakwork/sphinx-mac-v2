//
//  NSCollectionView.swift
//  com.stakwork.sphinx.desktop
//
//  Created by Tomas Timinskas on 18/05/2020.
//  Copyright © 2020 Sphinx. All rights reserved.
//

import Cocoa

extension NSCollectionView {
    
    func registerItem(_ type: NSCollectionViewItem.Type) {
        register(type, forItemWithIdentifier: NSUserInterfaceItemIdentifier(String(describing: type)))
        register(NSNib(nibNamed: String(describing: type), bundle: Bundle.main), forItemWithIdentifier: NSUserInterfaceItemIdentifier(String(describing: type)))
    }

    func scrollToBottom(animated: Bool = true) {
        let sections = self.numberOfSections
        guard sections > 0 else {
            return
        }
        let targetIndex = self.numberOfItems(inSection: sections - 1)
        scrollToIndex(targetIndex: targetIndex, animated: animated)
    }
    
    func scrollToOffset(yPosition: CGFloat) {
        let y = (enclosingScrollView?.contentView.bounds.origin.y ?? 0)
        
        if (yPosition == y) {
            return
        }
        
        if let scrollView = self.enclosingScrollView {
            scrollView.documentYOffset = yPosition
        }
    }
    
    /// Returns true only if `indexPath` points at a section and item that
    /// currently exist in this collection view, according to its data source
    /// counts at the time this is called.
    func isValidIndexPath(_ indexPath: IndexPath) -> Bool {
        let sections = self.numberOfSections
        guard indexPath.section >= 0, indexPath.section < sections else {
            return false
        }
        
        let items = self.numberOfItems(inSection: indexPath.section)
        guard indexPath.item >= 0, indexPath.item < items else {
            return false
        }
        
        return true
    }
    
    /// Scrolls to `indexPath` only if it is currently valid (in bounds) and
    /// the layout is able to produce attributes for it. Skips silently
    /// otherwise, which avoids the SIGABRT that AppKit throws when
    /// `scrollToItems` is given a stale or out-of-range target.
    func safeScrollToItem(
        _ indexPath: IndexPath,
        position: NSCollectionView.ScrollPosition,
        animated: Bool,
        duration: TimeInterval = 0.2
    ) {
        guard window != nil, !isHiddenOrHasHiddenAncestor else {
            return
        }
        
        guard isValidIndexPath(indexPath) else {
            return
        }
        
        layoutSubtreeIfNeeded()
        
        guard collectionViewLayout?.layoutAttributesForItem(at: indexPath) != nil else {
            return
        }
        
        if animated {
            let ctx = NSAnimationContext.current
            ctx.duration = duration
            ctx.allowsImplicitAnimation = true
        }
        
        self.animator().scrollToItems(at: [indexPath], scrollPosition: position)
    }
    
    /// Scrolls to the item at `targetIndex`, treated as a **1-based** index
    /// into the last section (i.e. scrolls to item `targetIndex - 1`). This
    /// matches `scrollToBottom`, which passes `numberOfItems` as the target,
    /// and `PaymentTemplatesDataSource`, which passes `item + 1`.
    ///
    /// Callers that already hold a 0-based index (search match index, reply
    /// row index) should keep calling this unchanged; row 0 is clamped to
    /// item 0 instead of producing an invalid `-1` index.
    func scrollToIndex(
        targetIndex: Int,
        animated: Bool,
        position: NSCollectionView.ScrollPosition = .bottom
    ){
        DispatchQueue.main.async {
            let sections = self.numberOfSections
            guard sections > 0 else {
                return
            }
            
            let section = sections - 1
            let item = max(targetIndex - 1, 0)
            
            self.safeScrollToItem(
                IndexPath(item: item, section: section),
                position: position,
                animated: animated
            )
        }
    }
    
    func isAtBottom() -> Bool {
        let y = (enclosingScrollView?.contentView.bounds.origin.y ?? 0)
        let contentHeight = (bounds.height - (enclosingScrollView?.frame.size.height ?? 0)) + (enclosingScrollView?.contentInsets.bottom ?? 0)
        let difference = contentHeight - y
        
        return difference == 0
    }
    
    func getOffsetY() -> CGFloat {
        let y = (enclosingScrollView?.contentView.bounds.origin.y ?? 0)
        return y
    }
    
    func getDistanceToBottom() -> CGFloat {
        let y = (enclosingScrollView?.contentView.bounds.origin.y ?? 0)
        let contentHeight = (bounds.height - (enclosingScrollView?.frame.size.height ?? 0)) + (enclosingScrollView?.contentInsets.bottom ?? 0)
        let difference = contentHeight - y
        
        return difference
    }
    
    func shouldScrollToBottom() -> Bool {
        let y = (enclosingScrollView?.contentView.bounds.origin.y ?? 0)
        let contentHeight = (bounds.height - (enclosingScrollView?.frame.size.height ?? 0)) + (enclosingScrollView?.contentInsets.bottom ?? 0)
        let difference = contentHeight - y
        
        if difference <= 50 {
            return true
        }
        return false
    }
    
    func isClosedToBottom(yPosition: CGFloat) -> Bool {
        let contentHeight = (bounds.height - (enclosingScrollView?.frame.size.height ?? 0)) + (enclosingScrollView?.contentInsets.bottom ?? 0)
        let difference = contentHeight - yPosition
        
        if difference <= 10 {
            return true
        }
        return false
    }
}
