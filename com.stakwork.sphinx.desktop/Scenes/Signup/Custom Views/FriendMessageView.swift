//
//  FriendMessageView.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 10/02/2021.
//  Copyright © 2021 Tomas Timinskas. All rights reserved.
//

import Cocoa
import SwiftyJSON

class FriendMessageView: NSView, LoadableNib {
    
    weak var delegate: WelcomeEmptyViewDelegate?
    
    @IBOutlet var contentView: NSView!
    @IBOutlet weak var titleLabel: NSTextField!
    @IBOutlet weak var friendName: NSTextField!
    @IBOutlet weak var friendMessage: NSTextField!
    @IBOutlet weak var continueButtonView: SignupButtonView!
    @IBOutlet weak var loadingWheel: NSProgressIndicator!
    @IBOutlet weak var initialsCircle: NSBox!
    @IBOutlet weak var initialsLabel: NSTextField!
    
    var loading = false {
        didSet {
            LoadingWheelHelper.toggleLoadingWheel(loading: loading, loadingWheel: loadingWheel, color: NSColor.white, controls: [continueButtonView.getButton()])
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        loadViewFromNib()
    }
    
    init(
        frame frameRect: NSRect,
        delegate: WelcomeEmptyViewDelegate
    ) {
        super.init(frame: frameRect)
        
        self.delegate = delegate
        
        loadViewFromNib()
        configureView()
    }
    
    func configureView() {
        continueButtonView.configureWith(
            title: "get.started".localized,
            icon: "",
            tag: -1,
            delegate: self
        )
        
        if let alias = SphinxOnionManager.sharedInstance.stashedInviterAlias {
            friendName.stringValue = alias
            initialsLabel.stringValue = alias.getInitialsFromName()
        }
    }
}

extension FriendMessageView : SignupButtonViewDelegate {
    func didClickButton(tag: Int) {
        loading = true
        continueToPinView()
    }
    
    func continueToPinView() {
        UserData.sharedInstance.signupStep = SignupHelper.SignupStep.InviterContactCreated.rawValue
        delegate?.shouldContinueTo?(mode: -1)
    }
    
    func didFailCreatingContact() {
        loading = false
        NewMessageBubbleHelper().showGenericMessageView(text: "generic.error.message".localized)
    }
}
