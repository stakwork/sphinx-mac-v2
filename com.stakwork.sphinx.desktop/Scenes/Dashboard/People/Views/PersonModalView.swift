//
//  PersonModalView.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 05/01/2022.
//  Copyright © 2022 Tomas Timinskas. All rights reserved.
//

import Cocoa
import SwiftyJSON

class PersonModalView: CommonModalView, LoadableNib {
    
    @IBOutlet var contentView: NSView!
    @IBOutlet weak var imageView: AspectFillNSImageView!
    @IBOutlet weak var nicknameLabel: NSTextField!
    @IBOutlet weak var priceLabel: NSTextField!
    
    @IBOutlet weak var loadingWheel: NSProgressIndicator!
    @IBOutlet weak var loadingWheelContainer: NSBox!

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        imageView.wantsLayer = true
        imageView.rounded = true
        imageView.gravity = .resizeAspectFill
        imageView.layer?.cornerRadius = imageView.frame.height / 2
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        loadViewFromNib()
    }
    
    var loading = false {
        didSet {
            loadingWheelContainer.isHidden = !loading
            
            LoadingWheelHelper.toggleLoadingWheel(
                loading: loading,
                loadingWheel: loadingWheel,
                color: NSColor.white,
                controls: []
            )
        }
    }
    
    override func modalWillShowWith(query: String, delegate: ModalViewDelegate) {
        super.modalWillShowWith(query: query, delegate: delegate)
        
        loading = true
        
        processQuery()
        let existingUser = getPersonInfo()
        
        if existingUser {
            self.delegate?.shouldDismissModals()
            return
        }
    }
    
    func getPersonInfo() -> Bool {
        if let host = authInfo?.host, let pubkey = authInfo?.pubkey {
            if let _ = UserContact.getContactWith(pubkey: pubkey) {
                showMessage(message: "already.connected".localized, color: NSColor.Sphinx.PrimaryRed)
                return true
            }
            API.sharedInstance.getPersonInfo(host: host, pubkey: pubkey, callback: { success, person in
                if let person = person {
                    self.showPersonInfo(person: person)
                } else {
                    self.delegate?.shouldDismissModals()
                }
            })
        }
        return false
    }
    
    func showPersonInfo(person: JSON) {
        authInfo?.jsonBody = person
        
        if !(authInfo?.jsonBody["owner_route_hint"].string ?? "").isRouteHint {
            showMessage(message: "invalid.public-key".localized, color: NSColor.Sphinx.PrimaryRed)
            self.delegate?.shouldDismissModals()
            return
        }
        
        if let imageUrl = person["img"].string, let nsUrl = URL(string: imageUrl), imageUrl != "" {
            MediaLoader.asyncLoadImage(imageView: imageView, nsUrl: nsUrl, placeHolderImage: NSImage(named: "profileAvatar"))
        } else {
            imageView.image = NSImage(named: "profileAvatar")
        }
        
        nicknameLabel.stringValue = person["owner_alias"].string ?? "Unknown"
        priceLabel.stringValue = "\("price.to.meet".localized)\((person["price_to_meet"].int ?? 0)) sat"
        
        loading = false
    }
    
    override func modalDidShow() {
        super.modalDidShow()
    }
    
    override func didTapConfirmButton() {
        super.didTapConfirmButton()
        
        if let pubkey = authInfo?.pubkey {
            let nickname = authInfo?.jsonBody["owner_alias"].string ?? "Unknown"
            let pubkey = authInfo?.jsonBody["owner_pubkey"].string ?? ""
            let routeHint = authInfo?.jsonBody["owner_route_hint"].string ?? ""
            
            UserContactsHelper.createV2Contact(
                nickname: nickname,
                pubKey: pubkey,
                routeHint: routeHint,
                callback: { (success, _) in
                    self.loading = false
                
                    if success {
                        self.delegate?.shouldDismissModals()
                    } else {
                        self.showErrorMessage()
                    }
                }
            )
        }
    }
    
    func showErrorMessage() {
        showMessage(message: "generic.error.message".localized, color: NSColor.Sphinx.BadgeRed)
    }
    
    func showMessage(message: String, color: NSColor) {
        buttonLoading = false
        messageBubbleHelper.showGenericMessageView(text: message, delay: 3, textColor: NSColor.white, backColor: color, backAlpha: 1.0)
    }
    
}
