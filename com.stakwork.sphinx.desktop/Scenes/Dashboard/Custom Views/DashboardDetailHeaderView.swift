//
//  DashboardDetailHeaderView.swift
//  Sphinx
//
//  Created by Oko-osi Korede on 18/04/2024.
//  Copyright © 2024 Tomas Timinskas. All rights reserved.
//

import Cocoa

protocol DetailHeaderViewDelegate: AnyObject {
    func backButtonTapped()
    func closeButtonTapped()
    func openInNSTapped()
}
class DashboardDetailHeaderView: NSView, LoadableNib {
    
    weak var delegate: DetailHeaderViewDelegate?
    
    @IBOutlet var contentView: NSView!
    @IBOutlet weak var closeButton: CustomButton!
    @IBOutlet weak var backButton: CustomButton!
    @IBOutlet weak var headerTitle: NSTextField!
    @IBOutlet weak var openNWContainer: NSBox!
    @IBOutlet weak var openNWButton: CustomButton!
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        loadViewFromNib()
        setup()
    }
    
    private func setup() {
        closeButton.cursor = .pointingHand
        backButton.cursor = .pointingHand
        openNWButton.cursor = .pointingHand
        
        hideBackButton(hide: true)
    }
    
    func setHeaderTitle(_ title: String) {
        headerTitle.stringValue = title
    }
    
    func setOpenNWButtonVisible(visible: Bool) {
        openNWContainer.isHidden = !visible
    }
    
    @IBAction func openNewWindowButtonTapped(_ sender: Any) {
        delegate?.openInNSTapped()
    }
    
    @IBAction func backButtonTapped(_ sender: NSButton) {
        delegate?.backButtonTapped()
    }
    
    @IBAction func closeButtonTapped(_ sender: NSButton) {
        delegate?.closeButtonTapped()
    }
    
    func hideBackButton(hide: Bool) {
        backButton.isHidden = hide
    }
    
}
