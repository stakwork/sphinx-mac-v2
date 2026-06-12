//
//  ChatTopView.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 07/07/2023.
//  Copyright © 2023 Tomas Timinskas. All rights reserved.
//

import Cocoa

class ChatTopView: NSView, LoadableNib {
    
    weak var searchDelegate: ChatSearchTextFieldViewDelegate?

    @IBOutlet var contentView: NSView!

    @IBOutlet weak var chatHeaderView: ChatHeaderView!
    @IBOutlet weak var pinMessageBarView: PinMessageBarView!
    @IBOutlet weak var chatSearchView: ChatSearchTextFieldView!
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        loadViewFromNib()
        setup()
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        loadViewFromNib()
        setup()
    }
    
    // MARK: - Active call banner stack
    // A self-sizing vertical stack of banner rows (one per active call room).
    // Owned here, installed into the VC's view hierarchy by
    // NewChatViewController+LiveCallBanner (below chatTopView, not inside it).
    private(set) var liveCallBannerStack: NSStackView = {
        let sv = NSStackView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.orientation = .vertical
        sv.spacing = 0
        sv.alignment = .leading
        sv.distribution = .fill
        sv.isHidden = true
        return sv
    }()

    private var bannerViews: [String: ActiveCallBannerView] = [:]

    /// Creates or reuses the banner row for `roomName`, configures it, and makes it visible.
    func showCallBanner(
        roomName: String,
        participants: [BubbleMessageLayoutState.CallParticipantInfo],
        callLink: String,
        isAlreadyInCall: Bool,
        delegate: ActiveCallBannerDelegate
    ) {
        let banner: ActiveCallBannerView
        if let existing = bannerViews[roomName] {
            banner = existing
        } else {
            // Cap at 3 visible rows
            let visibleCount = bannerViews.values.filter { !$0.isHidden }.count
            guard visibleCount < 3 else { return }
            banner = ActiveCallBannerView()
            bannerViews[roomName] = banner
            liveCallBannerStack.addArrangedSubview(banner)
            NSLayoutConstraint.activate([
                banner.leadingAnchor.constraint(equalTo: liveCallBannerStack.leadingAnchor),
                banner.trailingAnchor.constraint(equalTo: liveCallBannerStack.trailingAnchor),
            ])
        }

        banner.configureWith(
            participants: participants,
            callLink: callLink,
            isAlreadyInCall: isAlreadyInCall,
            delegate: delegate
        )

        liveCallBannerStack.isHidden = false

        if banner.isHidden {
            banner.alphaValue = 0
            banner.isHidden = false
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                banner.animator().alphaValue = 1
            }
        }
    }

    /// Fully removes the banner row for `roomName` from the stack and view hierarchy.
    func removeCallBanner(roomName: String) {
        guard let banner = bannerViews[roomName] else { return }
        liveCallBannerStack.removeArrangedSubview(banner)
        banner.removeFromSuperview()
        bannerViews.removeValue(forKey: roomName)
        if bannerViews.isEmpty { liveCallBannerStack.isHidden = true }
    }

    /// Hides the row for `roomName`; collapses the stack if all rows are hidden.
    func hideCallBanner(roomName: String) {
        bannerViews[roomName]?.isHidden = true
        if bannerViews.values.allSatisfy({ $0.isHidden }) {
            liveCallBannerStack.isHidden = true
        }
    }

    /// Hides every banner row and collapses the stack.
    func hideAllCallBanners() {
        bannerViews.values.forEach { $0.isHidden = true }
        liveCallBannerStack.isHidden = true
        // Remove all arranged subviews so the next chat starts clean
        for view in liveCallBannerStack.arrangedSubviews {
            liveCallBannerStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        bannerViews.removeAll()
    }
    
    // MARK: - Setup

    func setup() {
        if NSAppearance.current.name == .darkAqua {
            self.removeShadow()
        } else {
            self.addShadow(
                location: VerticalLocation.bottom,
                color: NSColor.black,
                opacity: 0.1,
                radius: 5.0
            )
        }
    }
    
    func updateViewOnTribeFetch() {
        setChatInfoOnHeader()
        updateSatsEarnedOnHeader()
        toggleWebAppIcon()
        toggleSecondBrainAppIcon()
    }
    
    func setChatInfoOnHeader() {
        chatHeaderView.setChatInfo()
    }
    
    func setVolumeState() {
        chatHeaderView.setVolumeState()
    }
    
    func updateSatsEarnedOnHeader() {
        chatHeaderView.configureContributions()
    }
    
    func toggleWebAppIcon() {
        chatHeaderView.toggleWebAppIcon()
    }
    
    func toggleSecondBrainAppIcon() {
        chatHeaderView.toggleSecondBrainAppIcon()
    }
    
    func checkRoute() {
        chatHeaderView.checkRoute()
    }
    
    func getOptionsButtonView() -> NSView {
        return chatHeaderView.getOptionsButtonView()
    }
    
    func toggleButtonsWith(width: CGFloat) {
        chatHeaderView.toggleButtonsWith(width: width)
    }

    func showWebAppActions(_ show: Bool) {
        chatHeaderView.showWebAppActions(show)
    }
    
    func configureHeaderWith(
        chat: Chat?,
        contact: UserContact?,
        andDelegate delegate: ChatHeaderViewDelegate,
        searchDelegate: ChatSearchTextFieldViewDelegate? = nil,
        viewWidth: CGFloat
    ) {
        chatHeaderView.configureWith(
            chat: chat,
            contact: contact,
            delegate: delegate,
            viewWidth: viewWidth
        )
        
        self.searchDelegate = searchDelegate
        
        chatSearchView.setDelegate(self)
    }
    
    func configureScheduleIcon(
        lastMessage: TransactionMessage,
        ownerId: Int
    ) {
        chatHeaderView.configureScheduleIcon(
            lastMessage: lastMessage,
            ownerId: ownerId
        )
    }
    
    func configurePinnedMessageViewWith(
        chatId: Int,
        andDelegate delegate: PinnedMessageViewDelegate,
        completion: (() ->())? = nil
    ) {
        pinMessageBarView.configureWith(
            chatId: chatId,
            and: delegate,
            completion: completion
        )
    }
    
    func configureSearchMode(
        active: Bool
    ) {
        chatHeaderView.isHidden = active
        chatSearchView.isHidden = !active
        
        if active {
            chatSearchView.makeFieldActive()
        }
    }
}

extension ChatTopView : ChatSearchTextFieldViewDelegate {
    func shouldSearchFor(term: String) {
        searchDelegate?.shouldSearchFor(term: term)
    }
    
    func didTapSearchCancelButton() {
        configureSearchMode(active: false)
        
        searchDelegate?.didTapSearchCancelButton()
    }
}
