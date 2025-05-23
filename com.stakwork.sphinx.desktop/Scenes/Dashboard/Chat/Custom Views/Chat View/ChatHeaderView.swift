//
//  ChatHeaderView.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 07/07/2023.
//  Copyright © 2023 Tomas Timinskas. All rights reserved.
//

import Cocoa
import SDWebImage

protocol ChatHeaderViewDelegate : AnyObject {
    func didClickThreadsButton()
    func didClickWebAppButton()
    func didClickMuteButton()
    func didClickCallButton()
    func didClickHeaderButton()
    func didClickSearchButton()
    func didClickSecondBrainAppButton()
    func didClickRefreshButton()
    func didClickOptionsButton()
}

class ChatHeaderView: NSView, LoadableNib {
    
    weak var delegate: ChatHeaderViewDelegate?
    
    @IBOutlet var contentView: NSView!
    
    @IBOutlet weak var imageContainer: NSView!
    @IBOutlet weak var profileImageView: AspectFillNSImageView!
    @IBOutlet weak var initialsContainer: NSBox!
    @IBOutlet weak var initialsLabel: NSTextField!
    @IBOutlet weak var nameLabel: NSTextField!
    @IBOutlet weak var contributionsContainer: NSStackView!
    @IBOutlet weak var contributedSatsLabel: NSTextField!
    @IBOutlet weak var contributionSign: NSTextField!
    @IBOutlet weak var tribePriceLabel: NSTextField!
    @IBOutlet weak var remoteTimezoneIdentifier: NSTextField!
    @IBOutlet weak var lockSign: NSTextField!
    @IBOutlet weak var boltSign: NSTextField!
    @IBOutlet weak var scheduleIcon: NSTextField!
    @IBOutlet weak var volumeButton: CustomButton!
    @IBOutlet weak var webAppButton: CustomButton!
    @IBOutlet weak var secondBrainButton: CustomButton!
    @IBOutlet weak var callButton: CustomButton!
    @IBOutlet weak var headerButton: CustomButton!
    @IBOutlet weak var threadsButton: CustomButton!
    @IBOutlet weak var searchButton: CustomButton!
    @IBOutlet weak var refreshButton: CustomButton!
    @IBOutlet weak var optionsButton: CustomButton!
    @IBOutlet weak var dashedLineView: NSView!
    @IBOutlet weak var imageWidthConstraint: NSLayoutConstraint!
    
    let kMinimumChatHeaderForButtons: CGFloat = 700
    
    var isDisable = false
    var viewWidth: CGFloat? = nil
    var chat: Chat? = nil
    var contact: UserContact? = nil

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        loadViewFromNib()
        setupView()
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        loadViewFromNib()
        setupView()
    }
    
    func setupView() {
        profileImageView.wantsLayer = true
        profileImageView.rounded = true
        profileImageView.layer?.cornerRadius = profileImageView.frame.height / 2
        profileImageView.gravity = .resizeAspectFill
        
        volumeButton.cursor = .pointingHand
        webAppButton.cursor = .pointingHand
        secondBrainButton.cursor = .pointingHand
        callButton.cursor = .pointingHand
        headerButton.cursor = .pointingHand
        threadsButton.cursor = .pointingHand
        searchButton.cursor = .pointingHand
        optionsButton.cursor = .pointingHand
    }
    
    func getOptionsButtonView() -> NSView {
        return optionsButton
    }
    
    func configureWith(
        chat: Chat?,
        contact: UserContact?,
        delegate: ChatHeaderViewDelegate,
        viewWidth: CGFloat
    ) {
        if chat == nil && contact == nil {
            setupDisabledMode()
            return
        }
       
        self.viewWidth = viewWidth
        self.isDisable = false
        self.chat = chat
        self.contact = contact
        self.delegate = delegate
        
        setChatInfo()
    }
    
    func configureScheduleIcon(
        lastMessage: TransactionMessage,
        ownerId: Int
    ) {
        scheduleIcon.isHidden = true
        
        if lastMessage.isOutgoing(ownerId: ownerId), !lastMessage.isConfirmedAsReceived() && !lastMessage.failed() {
            let thirtySecondsAgo = Date().addingTimeInterval(-30)
            if lastMessage.messageDate < thirtySecondsAgo {
                scheduleIcon.isHidden = false
            }
        }
    }
    
    func setupDisabledMode() {
        isDisable = true
        
        nameLabel.stringValue = "Open a conversation to start messaging"
        
        imageContainer.isHidden = true
        contributionsContainer.isHidden = true
        
        lockSign.isHidden = true
        boltSign.isHidden = true
        volumeButton.isHidden = true
        webAppButton.isHidden = true
        secondBrainButton.isHidden = true
        callButton.isHidden = true
        threadsButton.isHidden = true
        searchButton.isHidden = true
    }
    
    func setChatInfo() {
        configureHeaderBasicInfo()
        configureEncryptionSign()
        setVolumeState()
        configureImageOrInitials()
        configureContributionsAndPrices()
        configureTimezoneInfo()
    }
    
    func configureTimezoneInfo() {
        remoteTimezoneIdentifier.isHidden = true
        
        if let timezoneString = chat?.remoteTimezoneIdentifier {
            let timezone = TimeZone(abbreviation: timezoneString) ?? TimeZone(identifier: timezoneString)
            
            if let timezone = timezone {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "hh:mm a"
                dateFormatter.timeZone = timezone

                remoteTimezoneIdentifier.stringValue = "\(dateFormatter.string(from: Date())) \(timezone.abbreviation() ?? timezone.identifier)"
                remoteTimezoneIdentifier.isHidden = false
            }
        }
    }
    
    func configureHeaderBasicInfo() {
        nameLabel.stringValue = getHeaderName()
        
        toggleButtonsWith(width: viewWidth)
    }
    
    func configureEncryptionSign() {
        let isEncrypted = (contact?.status == UserContact.Status.Confirmed.rawValue) || (chat?.status == Chat.ChatStatus.approved.rawValue)
        lockSign.isHidden = !isEncrypted
        refreshButton.isHidden = true
        
        imageWidthConstraint.constant = isEncrypted ? 46 : 36
        profileImageView.superview?.layoutSubtreeIfNeeded()
        profileImageView.makeCircular()
        
        initialsContainer.cornerRadius = isEncrypted ? 23 : 18
        initialsContainer.layoutSubtreeIfNeeded()
        
        dashedLineView.isHidden = isEncrypted
        
        if !isEncrypted {
            dashedLineView.layer?.sublayers?.forEach { layer in
                layer.removeFromSuperlayer()
            }
            
            dashedLineView.addDottedCircularBorder(
                lineWidth: 1.0,
                dashPattern: [3,2],
                color: NSColor.Sphinx.PlaceholderText
            )
        }
    }
    
    func configureImageOrInitials() {
        if let _ = profileImageView.image {
            return
        }
        
        imageContainer.isHidden = false
        profileImageView.isHidden = true
        initialsContainer.isHidden = true
        
        profileImageView.sd_cancelCurrentImageLoad()
        
        showInitialsFor(
            contact: contact,
            and: chat
        )
        
        if let imageUrl = getImageUrl()?.trim(), let nsUrl = URL(string: imageUrl) {
            profileImageView.sd_setImage(
                with: nsUrl,
                placeholderImage: NSImage(named: "profileAvatar"),
                options: [.scaleDownLargeImages, .decodeFirstFrameOnly],
                progress: nil,
                completed: { (image, error, _, _) in
                    if (error == nil) {
                        self.initialsContainer.isHidden = true
                        self.profileImageView.isHidden = false
                        self.profileImageView.image = image
                    }
                }
            )
        }
    }
    
    func showInitialsFor(
        contact: UserContact?,
        and chat: Chat?
    ) {
        let name = getHeaderName()
        let color = getInitialsColor()
        
        initialsContainer.isHidden = false
        initialsContainer.fillColor = color
        
        initialsLabel.textColor = NSColor.white
        initialsLabel.stringValue = name.getInitialsFromName()
    }
    
    func getHeaderName() -> String {
        if let chat = chat, chat.isGroup() {
            return chat.getName()
        } else if let contact = contact {
            return contact.getName()
        } else {
            return "name.unknown".localized
        }
    }
    
    func getInitialsColor() -> NSColor {
        if let chat = chat, chat.isGroup() {
            return chat.getColor()
        } else if let contact = contact {
            return contact.getColor()
        } else {
            return NSColor.random()
        }
    }
    
    func getImageUrl() -> String? {
        if let chat = chat, let url = chat.getPhotoUrl(), !url.isEmpty {
            return url.removeDuplicatedProtocol()
        } else if let contact = contact, let url = contact.getPhotoUrl(), !url.isEmpty {
            return url.removeDuplicatedProtocol()
        }
        return nil
    }
    
    func configureContributionsAndPrices() {
        if let prices = chat?.getTribePrices(), chat?.shouldShowPrice() ?? false {
            tribePriceLabel.stringValue = String(
                format: "group.price.text".localized,
                "\(prices.0)",
                "\(prices.1)"
            )
            contributionsContainer.isHidden = false
            remoteTimezoneIdentifier.isHidden = true
        } else if let remoteTimezone = chat?.remoteTimezoneIdentifier, remoteTimezone.isNotEmpty {
            tribePriceLabel.isHidden = true
            remoteTimezoneIdentifier.isHidden = false
            contributionsContainer.isHidden = false
        } else {
            contributionsContainer.isHidden = true
        }
        
        contributionSign.isHidden = true
        contributedSatsLabel.isHidden = true
    }
    
    func configureContributions() {
//        if let contentFeed = chat?.contentFeed, !contentFeed.feedID.isEmpty {
//            let isMyTribe = (chat?.isMyPublicGroup() ?? false)
//            let label = isMyTribe ? "earned.sats".localized : "contributed.sats".localized
//            let sats = PodcastPaymentsHelper.getSatsEarnedFor(contentFeed.feedID)
//            
//            contributionSign.isHidden = false
//            contributedSatsLabel.isHidden = false
//        
//            contributedSatsLabel.stringValue = String(format: label, sats)
//        }
    }
    
    func setVolumeState() {
        volumeButton.image = NSImage(
            named: chat?.isMuted() ?? false ? "muteOnIcon" : "muteOffIcon"
        )
        toggleButtonsWith(width: viewWidth)
    }
    
    func toggleWebAppIcon() {
        toggleButtonsWith(width: viewWidth)
    }
    
    func toggleSecondBrainAppIcon() {
        toggleButtonsWith(width: viewWidth)
    }
    
    func checkRoute() {
        if self.chat == nil && self.contact == nil {
            return
        }
        
        let success = (contact?.status == UserContact.Status.Confirmed.rawValue) || (chat?.status == Chat.ChatStatus.approved.rawValue)
        
        boltSign.isHidden = !success
        boltSign.textColor = success ? HealthCheckView.kConnectedColor : HealthCheckView.kNotConnectedColor
    }
    
    func toggleButtonsWith(width: CGFloat?) {
        guard let width = width else {
            return
        }
        
        if isDisable {
            return
        }
        
        viewWidth = width
        
        if width < kMinimumChatHeaderForButtons {
            searchButton.isHidden = true
            threadsButton.isHidden = true
            webAppButton.isHidden = true
            secondBrainButton.isHidden = true
            volumeButton.isHidden = true
            callButton.isHidden = true
            optionsButton.isHidden = false
        } else {
            searchButton.isHidden = false
            threadsButton.isHidden = chat?.isPublicGroup() == false
            webAppButton.isHidden = chat?.hasWebApp() == false
            secondBrainButton.isHidden = chat?.hasSecondBrainApp() == false
            volumeButton.isHidden = false
            callButton.isHidden = false
            optionsButton.isHidden = true
        }
    }
    
    @IBAction func threadsButtonClicked(_ sender: Any) {
        delegate?.didClickThreadsButton()
    }
    
    @IBAction func webAppButtonClicked(_ sender: Any) {
        delegate?.didClickWebAppButton()
    }
    
    @IBAction func secondBrainAppButtonClicked(_ sender: Any) {
        delegate?.didClickSecondBrainAppButton()
    }
    
    @IBAction func muteButtonClicked(_ sender: Any) {
        delegate?.didClickMuteButton()
    }
    
    @IBAction func callButtonClicked(_ sender: Any) {
        delegate?.didClickCallButton()
    }
    
    @IBAction func headerButtonClicked(_ sender: Any) {
        delegate?.didClickHeaderButton()
    }
    
    @IBAction func searchButtonClicked(_ sender: Any) {
        delegate?.didClickSearchButton()
    }
    
    @IBAction func refreshButtonClicked(_ sender: Any) {
        refreshButton.isHidden = true
        
        delegate?.didClickRefreshButton()
    }
    
    @IBAction func optionsButtonClicked(_ sender: Any) {
        delegate?.didClickOptionsButton()
    }
}
