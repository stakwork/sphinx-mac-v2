//
//  AuthExternalView.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 05/01/2022.
//  Copyright © 2022 Tomas Timinskas. All rights reserved.
//

import Cocoa

class AuthExternalView: CommonModalView, LoadableNib {
    
    @IBOutlet var contentView: NSView!
    @IBOutlet weak var hostLabel: NSTextField!
    @IBOutlet weak var buttonLabel: NSTextField!
    @IBOutlet weak var authorizeLabel: NSTextField!
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        loadViewFromNib()
    }
    
    override func viewDidHide() {
        super.viewDidHide()
        print("viewDidHide")
    }
    
    override func modalWillShowWith(query: String, delegate: ModalViewDelegate) {
        super.modalWillShowWith(query: query, delegate: delegate)
        
        processQuery()
        
        hostLabel.stringValue = "\(authInfo?.host ?? "...")?"
        
        if (authInfo?.action == "redeem_sats") {
            buttonLabel.stringValue = "confirm".localized.uppercased()
            authorizeLabel.stringValue = String(format: "popup.redeem-sats".localized, authInfo?.amount ?? 0)
        } else {
            buttonLabel.stringValue = "authorize".localized.uppercased()
            authorizeLabel.stringValue = "popup.authorize-with".localized
        }
    }
    
    override func modalDidShow() {
        super.modalDidShow()
    }
    
    override func didTapConfirmButton() {
        super.didTapConfirmButton()
        
        let action = authInfo?.action ?? ""
        switch (action) {
        case "auth":
            verifyExternal()
            break
        case "challenge":
            authorizeStakwork()
            break
        case "redeem_sats":
            redeemSats()
            break
        default:
            buttonLoading = false
            break
        }
    }
    
    func authorizeStakwork() {
        let owner = UserContact.getOwner()
        
        authInfo?.pubkey = owner?.publicKey
        authInfo?.routeHint = owner?.routeHint
        
        guard let authInfo = authInfo, let challenge = authInfo.challenge else {
            showErrorAlert()
            return
        }
        
        guard let sig = SphinxOnionManager.sharedInstance.signChallenge(challenge: challenge) else {
            showErrorAlert()
           return
        }

        self.authInfo?.sig = sig
        self.takeUserToAuth()
    }
    
    func redeemSats() {
        guard let authInfo = authInfo, let host = authInfo.host, let token = authInfo.token, let pubkey = authInfo.pubkey else {
            showErrorAlert()
            return
        }
        let params: [String: AnyObject] = ["token": token as AnyObject, "pubkey": pubkey as AnyObject]
        API.sharedInstance.redeemSats(url: host, params: params, callback: {
            NotificationCenter.default.post(name: .onBalanceDidChange, object: nil)
            self.delegate?.shouldDismissModals()
        }, errorCallback: {
            self.showErrorAlert()
        })
    }
    
    func verifyExternal() {
        guard let query = self.query else {
            AlertHelper.showAlert(
                title: "Error",
                message: "Could not parse auth request"
            )
            authorizationDone(success: false, host: self.authInfo?.host ?? "")
            return
        }

        SphinxOnionManager.sharedInstance.processPeopleAuthChallenge(
            urlString: query,
            completion: { authParams in
                if let (host, challenge, token, params) = authParams {
                    self.authInfo?.host = host
                    self.authInfo?.challenge = challenge
                    self.authInfo?.token = token
                    self.authInfo?.verificationSignature = params["verification_signature"] as? String
                    
                    self.authorizationDone(success: true, host: host)
                } else {
                    AlertHelper.showAlert(
                        title: "Error",
                        message: "Could not parse auth request"
                    )
                    self.authorizationDone(success: false, host: self.authInfo?.host ?? "")
                }
            }
        )
    }
    
    func takeUserToAuth() {
        guard let authInfo = authInfo, let id = authInfo.id, let sig = authInfo.sig, let pubkey = authInfo.pubkey else {
            showErrorAlert()
            return
        }
        
        var urlString = "https://auth.sphinx.chat/oauth_verify?id=\(id)&sig=\(sig.urlSafe)&pubkey=\(pubkey)"
        
        if let routeHint = authInfo.routeHint, !routeHint.isEmpty {
            urlString = urlString + "&route_hint=\(routeHint)"
        }
        
        if let url = URL(string: urlString) {
            delegate?.shouldDismissModals()
            NSWorkspace.shared.open(url)
        }
    }
    
    func authorizationDone(success: Bool, host: String) {
        if success {
            messageBubbleHelper.showGenericMessageView(
                text: "authorization.login".localized,
                delay: 7,
                textColor: NSColor.white,
                backColor: NSColor.Sphinx.PrimaryGreen, 
                backAlpha: 1.0
            )
            
            delegate?.shouldDismissModals()
        } else {
            showErrorAlert()
        }
    }
    
    func showErrorAlert() {
        buttonLoading = false
        
        messageBubbleHelper.showGenericMessageView(text: "authorization.failed".localized, delay: 5, textColor: NSColor.white, backColor: NSColor.Sphinx.BadgeRed, backAlpha: 1.0)
        
        delegate?.shouldDismissModals()
    }
}
