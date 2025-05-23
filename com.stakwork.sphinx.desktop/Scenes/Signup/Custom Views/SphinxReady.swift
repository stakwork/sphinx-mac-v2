//
//  SphinxReady.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 11/02/2021.
//  Copyright © 2021 Tomas Timinskas. All rights reserved.
//

import Cocoa

class SphinxReady: NSView, LoadableNib {
    
    weak var delegate: WelcomeEmptyViewDelegate?

    @IBOutlet var contentView: NSView!
    @IBOutlet weak var centerLabel: NSTextField!
    @IBOutlet weak var topLabel: NSTextField!
    @IBOutlet weak var continueButton: SignupButtonView!
    @IBOutlet weak var loadingWheel: NSProgressIndicator!
    
    var loading = false {
        didSet {
            LoadingWheelHelper.toggleLoadingWheel(loading: loading, loadingWheel: loadingWheel, color: NSColor.white, controls: [continueButton.getButton()])
        }
    }
    
    let walletBalanceService = WalletBalanceService()
    
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
        loadViewFromNib()
        
        self.delegate = delegate
        
        configureView()
    }
    
    func configureView() {
        continueButton.configureWith(title: "finish".localized.capitalized, icon: "", tag: -1, delegate: self)
        setAttributedTitles(local: 0, remote: 0)
        
        loadBalances()
    }
    
    func loadBalances() {
        loading = true
        
        if let storedBalance = walletBalanceService.balance {
            loading = false
            
            setAttributedTitles(local: Int(storedBalance), remote: 0)
        }
    }
    
    func setAttributedTitles(local: Int, remote: Int) {
        let formattedLocal = local.formattedWithSeparator
        let formattedRemote = remote.formattedWithSeparator
        
        let normalFont = NSFont(name: "Roboto-Light", size: 17.0)!
        let boldFont = NSFont(name: "Roboto-Bold", size: 17.0)!
        
        let completeMessage = String(format: "ready.sphinx.text".localized, formattedLocal, formattedRemote)
        let firstSatsMsg = String(format: "x.sats,".localized, formattedLocal)
        let secondSatsMsg = String(format: "x.sats.".localized, formattedRemote)
        
        centerLabel.attributedStringValue = String.getAttributedText(
            string: completeMessage,
            boldStrings: [firstSatsMsg, secondSatsMsg],
            font: normalFont,
            boldFont: boldFont
        )
    }
}

extension SphinxReady : SignupButtonViewDelegate {
    func didClickButton(tag: Int) {
        loading = true
        
        DelayPerformedHelper.performAfterDelay(seconds: 0.5, completion: {
            self.goToApp()
        })
    }
    
    func goToApp() {
        SignupHelper.resetSignupData()
        UserData.sharedInstance.signupStep = SignupHelper.SignupStep.SphinxReady.rawValue
        
        DelayPerformedHelper.performAfterDelay(seconds: 1.0, completion: {
            self.delegate?.shouldContinueTo?(mode: -1)
        })
    }
}
