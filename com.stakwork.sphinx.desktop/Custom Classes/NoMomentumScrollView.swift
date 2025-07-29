//
//  NoMomentumScrollView.swift
//  sphinx
//
//  Created by Tomas Timinskas on 29/07/2025.
//  Copyright © 2025 Tomas Timinskas. All rights reserved.
//
@objc protocol ScrollLoadMoreDelegate: AnyObject {
    func shouldLoadMore() -> Bool
    func loadMoreRequested()
    
    @objc optional func scrollDidBegin()
    @objc optional func scrollDidEnd()
    @objc optional func scrollDidChange(offset: CGFloat)
    
    // New momentum-specific methods
    @objc optional func momentumDidBegin()
    @objc optional func momentumDidEnd()
}

class MomentumAwareScrollView: NSScrollView {
    
    // MARK: - Properties
    weak var loadMoreDelegate: ScrollLoadMoreDelegate?
    
    private var isUserScrolling = false
    private var isMomentumScrolling = false
    private var loadMoreThreshold: CGFloat = 1000.0
    
    // MARK: - Public Methods
    
    func setLoadMoreThreshold(_ threshold: CGFloat) {
        loadMoreThreshold = threshold
    }
    
    // MARK: - Scroll Wheel Override
    
    override func scrollWheel(with event: NSEvent) {
        // Track user gesture phase
        handleUserGesturePhase(event.phase)
        
        // Track momentum phase
        handleMomentumPhase(event.momentumPhase)
        
        // Process the scroll normally
        super.scrollWheel(with: event)
        
        // Check for load more during scroll (optional)
        loadMoreDelegate?.scrollDidChange?(offset: documentYOffset)
    }
    
    // MARK: - Private Methods
    
    private func handleUserGesturePhase(_ phase: NSEvent.Phase) {
        switch phase {
        case .began:
            isUserScrolling = true
            loadMoreDelegate?.scrollDidBegin?()
            
        case .ended, .cancelled:
            isUserScrolling = false
            loadMoreDelegate?.scrollDidEnd?()
            
        default:
            break
        }
    }
    
    private func handleMomentumPhase(_ momentumPhase: NSEvent.Phase) {
        switch momentumPhase {
        case .began:
            isMomentumScrolling = true
            loadMoreDelegate?.momentumDidBegin?()
            
        case .ended, .cancelled:
            isMomentumScrolling = false
            loadMoreDelegate?.momentumDidEnd?()
            
            // This is the key moment - momentum has naturally ended
            // Check for load more after a brief delay to ensure everything has settled
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.checkForLoadMoreAfterMomentumEnd()
            }
            
        default:
            break
        }
    }
    
    private func checkForLoadMoreAfterMomentumEnd() {
        guard let delegate = loadMoreDelegate else { return }
        
        let currentOffset = documentYOffset
        
        // Only trigger load more if:
        // 1. User is not actively scrolling
        // 2. Momentum has ended
        // 3. We're within the threshold
        // 4. Load more is allowed
        if !isUserScrolling &&
           !isMomentumScrolling &&
           currentOffset <= loadMoreThreshold &&
           delegate.shouldLoadMore() {
            delegate.loadMoreRequested()
        }
    }
    
    func scrollToPosition(_ position: CGFloat, animated: Bool = false) {
        let contentHeight = documentView?.frame.height ?? 0
        let scrollViewHeight = contentSize.height
        let maxY = max(0, contentHeight - scrollViewHeight)
        let constrainedY = max(0, min(maxY, position))
        
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                contentView.animator().setBoundsOrigin(NSPoint(x: 0, y: constrainedY))
            }
        } else {
            contentView.setBoundsOrigin(NSPoint(x: 0, y: constrainedY))
        }
    }
}
