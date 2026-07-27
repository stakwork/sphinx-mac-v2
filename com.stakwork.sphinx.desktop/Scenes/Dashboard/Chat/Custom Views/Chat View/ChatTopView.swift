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

    private struct ActiveCall {
        let roomName: String
        let messageDate: Date
        var callLink: String
        let banner: ActiveCallBannerView
    }

    /// All currently active calls sorted descending by messageDate (newest first).
    private var activeCalls: [ActiveCall] = []
    private var bannerViews: [String: ActiveCallBannerView] = [:]

    /// Creates or reuses the banner row for `roomName`, configures it, and keeps
    /// the top-3-by-date active calls visible in newest-first order.
    func showCallBanner(
        roomName: String,
        participants: [BubbleMessageLayoutState.CallParticipantInfo],
        callLink: String,
        messageDate: Date,
        isAlreadyInCall: Bool,
        delegate: ActiveCallBannerDelegate
    ) {
        // Get or create the banner view
        let banner: ActiveCallBannerView
        if let existing = bannerViews[roomName] {
            banner = existing
        } else {
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

        // Upsert into activeCalls and re-sort descending by date (newest first)
        if let idx = activeCalls.firstIndex(where: { $0.roomName == roomName }) {
            activeCalls[idx] = ActiveCall(roomName: roomName, messageDate: messageDate, callLink: callLink, banner: banner)
        } else {
            activeCalls.append(ActiveCall(roomName: roomName, messageDate: messageDate, callLink: callLink, banner: banner))
        }
        activeCalls.sort { $0.messageDate > $1.messageDate }

        // Trim to top 3; hide any overflow entries
        if activeCalls.count > 3 {
            for overflow in activeCalls[3...] {
                overflow.banner.isHidden = true
            }
            activeCalls = Array(activeCalls.prefix(3))
        }

        rebuildBannerStack()
    }

    /// Removes `roomName` from the active set and reorders the stack.
    func hideCallBanner(roomName: String) {
        activeCalls.removeAll { $0.roomName == roomName }
        rebuildBannerStack()
    }

    /// Hides every banner row, collapses the stack, and resets all state.
    func hideAllCallBanners() {
        activeCalls.removeAll()
        liveCallBannerStack.isHidden = true
        for view in liveCallBannerStack.arrangedSubviews {
            liveCallBannerStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        bannerViews.removeAll()
    }

    /// Reorders the stack's arranged subviews to match `activeCalls` (newest first = top).
    private func rebuildBannerStack() {
        for (idx, call) in activeCalls.enumerated() {
            liveCallBannerStack.removeArrangedSubview(call.banner)
            liveCallBannerStack.insertArrangedSubview(call.banner, at: idx)
            call.banner.isHidden = false
        }
        // Hide any banner views that are no longer in activeCalls
        let activeRoomNames = Set(activeCalls.map { $0.roomName })
        for (roomName, banner) in bannerViews where !activeRoomNames.contains(roomName) {
            banner.isHidden = true
        }
        liveCallBannerStack.isHidden = activeCalls.isEmpty
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
