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
