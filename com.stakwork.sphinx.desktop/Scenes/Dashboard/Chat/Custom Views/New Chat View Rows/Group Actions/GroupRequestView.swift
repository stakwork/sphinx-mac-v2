//
//  GroupRequestView.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 18/09/2023.
//  Copyright © 2023 Tomas Timinskas. All rights reserved.
//

import Cocoa

class GroupRequestView: NSView, LoadableNib {
    
    weak var delegate: GroupActionsViewDelegate?
    
    @IBOutlet var contentView: NSView!
    
    @IBOutlet weak var messageView: NSBox!
    @IBOutlet weak var messageLabel: NSTextField!
    @IBOutlet weak var cancelButtonContainer: NSBox!
    @IBOutlet weak var cancelButton: CustomButton!
    @IBOutlet weak var doneButtonContainer: NSBox!
    @IBOutlet weak var doneButton: CustomButton!
    
    static let kViewHeight: CGFloat = 90
    
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
        cancelButton.cursor = .pointingHand
        doneButton.cursor = .pointingHand
    }
    
    func configureWith(
        status: NoBubbleMessageLayoutState.GroupMemberRequest.MemberRequestStatus,
        isActiveMember: Bool,
        senderAlias: String,
        andDelegate delegate: GroupActionsViewDelegate?
    ) {
        self.delegate = delegate
        
        let rejected = status == NoBubbleMessageLayoutState.GroupMemberRequest.MemberRequestStatus.Rejected
        let approved = status == NoBubbleMessageLayoutState.GroupMemberRequest.MemberRequestStatus.Approved
        let pending = !rejected && !approved
        
        doneButton.isEnabled = !isActiveMember && pending
        cancelButton.isEnabled = !isActiveMember && pending

        doneButtonContainer.isHidden = rejected || approved
        cancelButtonContainer.isHidden = rejected || approved
        
        if approved {
            messageLabel.stringValue = String(format: "admin.request.approved".localized, senderAlias)
        } else if rejected {
            messageLabel.stringValue = String(format: "admin.request.rejected".localized, senderAlias)
        } else {
            messageLabel.stringValue = String(format: "member.request".localized, senderAlias)
        }
        
        messageView.fillColor = (rejected ? NSColor.Sphinx.MemberApprovalRejected : (approved ? NSColor.Sphinx.MemberApprovalAccepted : NSColor.Sphinx.ReceivedMsgBG))
        messageView.borderColor = (rejected || approved) ? NSColor.clear : NSColor.Sphinx.LightDivider
        messageLabel.textColor = (rejected || approved) ? NSColor.white : NSColor.Sphinx.Text
    }
    
    @IBAction func doneButtonClicked(_ sender: Any) {
        delegate?.didTapApproveRequestButton()
    }
    
    @IBAction func cancelButtonClicked(_ sender: Any) {
        delegate?.didTapRejectRequestButton()
    }
    
}
