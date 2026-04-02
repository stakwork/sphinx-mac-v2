//
//  NewChatHeaderView.swift
//  Sphinx
//
//  Created by Oko-osi Korede on 23/04/2024.
//  Copyright © 2024 Tomas Timinskas. All rights reserved.
//

import Cocoa

@MainActor
protocol NewChatHeaderViewDelegate: AnyObject {
    func refreshTapped()
    func menuTapped(_ frame: CGRect)
    func profileButtonClicked()
    func qrButtonTapped()
    func aiAgentButtonTapped()
}

class NewChatHeaderView: NSView, LoadableNib {
    
    weak var delegate: NewChatHeaderViewDelegate?
    
    @IBOutlet var contentView: NSView!
    @IBOutlet weak var nameLabel: NSTextField!
    @IBOutlet weak var profileImageView: AspectFillNSImageView!
    
    @IBOutlet weak var balanceLabel: NSTextField!
    @IBOutlet weak var balanceUnitLabel: NSTextField!
    
    @IBOutlet weak var healthCheckView: HealthCheckView!
    
    @IBOutlet weak var reloadButton: CustomButton!
    @IBOutlet weak var menuButton: CustomButton!
    @IBOutlet weak var balanceButton: CustomButton!
    @IBOutlet weak var qrCodeButton: CustomButton!
    /// AI agent button — wired from XIB, hidden until a provider is configured
    @IBOutlet weak var aiAgentButton: CustomButton!
    
    @IBOutlet weak var loadingWheel: NSProgressIndicator!
    @IBOutlet weak var loadingWheelContainer: NSView!
    
    var walletBalanceService = WalletBalanceService()
    
    var ownerResultsController: NSFetchedResultsController<UserContact>!
    var profile: UserContact? = nil
    
    var hideBalance: Bool = false
    
    var loading = false {
        didSet {
            loadingWheelContainer.isHidden = !loading
            LoadingWheelHelper.toggleLoadingWheel(loading: loading, loadingWheel: loadingWheel, color: NSColor.Sphinx.Text, controls: [])
        }
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        
        loadViewFromNib()
        setup()
        setupViews()
        loading = true
        healthCheckView.delegate = self
        configureProfile()
        listenForNotifications()
    }
    
    private func setup() {
        configureOwnerFetchResultsController()
    }
    
    func configureOwnerFetchResultsController() {
        if let _ = ownerResultsController {
            return
        }
        
        let ownerFetchRequest = UserContact.FetchRequests.owner()

        ownerResultsController = NSFetchedResultsController(
            fetchRequest: ownerFetchRequest,
            managedObjectContext: CoreDataManager.sharedManager.persistentContainer.viewContext,
            sectionNameKeyPath: nil,
            cacheName: nil
        )
        
        ownerResultsController.delegate = self
        
        do {
            try ownerResultsController.performFetch()
        } catch {}
    }
    
    func configureProfile() {
        walletBalanceService.updateBalance(labels: [balanceLabel])
        balanceUnitLabel.stringValue = "sats"
        
        setupViews()
        
        if let profile = profile {
            if let imageUrl = profile.avatarUrl?.trim(), imageUrl != "" {
                MediaLoader.loadAvatarImage(url: imageUrl, objectId: profile.id, completion: { (image, id) in
                    guard let image = image else {
                        return
                    }
                    self.profileImageView.bordered = false
                    self.profileImageView.image = image
                })
            } else {
                profileImageView.image = NSImage(named: "profileAvatar")
            }
            
            let nickname = profile.nickname ?? ""
            nameLabel.stringValue = nickname.getNameStyleString(lineBreak: false)
        }
    }
    
    func setupViews() {
        reloadButton.cursor = .pointingHand
        menuButton.cursor = .pointingHand
        balanceButton.cursor = .pointingHand
        qrCodeButton.cursor = .pointingHand

        profileImageView.wantsLayer = true
        profileImageView.rounded = true
        profileImageView.layer?.cornerRadius = profileImageView.frame.height / 2

        configureAIAgentButton()
    }

    // MARK: - AI Agent button

    private func configureAIAgentButton() {
        // Set the SF symbol image (XIB has no image set; we assign it here)
        if let img = NSImage(systemSymbolName: "brain.head.profile", accessibilityDescription: "AI Agent") {
            aiAgentButton?.image = img
        } else if let img = NSImage(systemSymbolName: "cpu", accessibilityDescription: "AI Agent") {
            aiAgentButton?.image = img
        }
        aiAgentButton?.cursor = .pointingHand
        aiAgentButton?.toolTip = "Open Sphinx AI"

        updateAIAgentButtonVisibility()
    }

    /// Show the AI agent button only when a provider + API key are configured
    func updateAIAgentButtonVisibility() {
        // The container customView in the stack has hidden="YES" by default;
        // we toggle its superview (the container) — aiAgentButton.superview is the 32×32 wrapper
        let isConfigured = AIAgentManager.sharedInstance.isConfigured
        aiAgentButton?.superview?.isHidden = !isConfigured
    }

    @IBAction func aiAgentButtonTapped(_ sender: Any) {
        delegate?.aiAgentButtonTapped()
    }

    // MARK: - IBActions

    @IBAction func refreshButtonTapped(_ sender: NSButton) {
        loading = true
        delegate?.refreshTapped()
        updateBalance()
    }
    
    @IBAction func menuButtonTapped(_ sender: NSButton) {
        delegate?.menuTapped(menuButton.frame)
    }
    
    @IBAction func toggleHideBalance(_ sender: NSButton) {
        hideBalance = !hideBalance
        hideBalance ? hideAmount() : updateBalance()
    }
    
    @IBAction func qrcodeButtonTapped(_ sender: NSButton) {
        delegate?.qrButtonTapped()
    }
    
    @IBAction func profileButtonClicked(_ sender: Any) {
        delegate?.profileButtonClicked()
    }
    
    func hideAmount() {
        var hiddenAmount = ""
        "\(walletBalanceService.balance ?? 0)".forEach { _ in hiddenAmount += "*" }
        balanceLabel.stringValue = hiddenAmount
    }
    
    func listenForNotifications() {
        healthCheckView.listenForEvents()
        
        NotificationCenter.default.addObserver(
            forName: .onBalanceDidChange,
            object: nil,
            queue: OperationQueue.main
        ) { [weak self] (n: Notification) in
            Task { @MainActor [weak self] in
                DispatchQueue.main.async {
                    self?.updateBalance()
                }
            }
        }

        // Re-check AI button visibility whenever the agent is reconfigured
        NotificationCenter.default.addObserver(
            forName: .aiAgentReconfigured,
            object: nil,
            queue: OperationQueue.main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateAIAgentButtonVisibility()
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: .onBalanceDidChange, object: nil)
        NotificationCenter.default.removeObserver(self, name: .aiAgentReconfigured, object: nil)
    }
    
    func updateBalance() {
        balanceUnitLabel.stringValue = "sats"
        walletBalanceService.updateBalance(labels: [balanceLabel])
    }
}

extension NewChatHeaderView : HealthCheckDelegate {
    func shouldShowBubbleWith(_ message: String) {
        NewMessageBubbleHelper().showGenericMessageView(text:message, in: self.contentView, position: .Top, delay: 3)
    }
}

extension NewChatHeaderView : @preconcurrency NSFetchedResultsControllerDelegate {
    func controller(
        _ controller: NSFetchedResultsController<NSFetchRequestResult>,
        didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference
    ) {
        if
            let resultController = controller as? NSFetchedResultsController<NSManagedObject>,
            let firstSection = resultController.sections?.first {
            
            if resultController == ownerResultsController {
                profile = firstSection.objects?.first as? UserContact
                configureProfile()
            }
        }
    }
}
