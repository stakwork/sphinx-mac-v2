//
//  ImportSeedView.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 27/03/2024.
//  Copyright © 2024 Tomas Timinskas. All rights reserved.
//

import Cocoa

@MainActor protocol ImportSeedViewDelegate : NSObject{
    func showImportSeedView(network: String, host: String, relay: String)//TODO: review this before shipping prod. May not need this anymore
    func showImportSeedView()
    func didTapCancelImportSeed()
    func didTapConfirm()
    func didTapScanQR()
}

class ImportSeedView: NSView, LoadableNib {
    
    @IBOutlet var contentView: NSView!
    @IBOutlet weak var textView: NSTextView!
    @IBOutlet weak var loadingView: NSBox!
    @IBOutlet weak var loadingWheel: NSProgressIndicator!
    
    weak var delegate : ImportSeedViewDelegate? = nil
    
    var originalFrame: CGRect = .zero
    var isKeyboardShown = false
    var network:String = ""
    var host:String = ""
    var relay:String = ""
    
    var loading: Bool = false {
        didSet {
            loadingView.isHidden = !loading
            
            LoadingWheelHelper.toggleLoadingWheel(loading: loading, loadingWheel: loadingWheel, color: NSColor.Sphinx.Text, controls: [])
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        loadViewFromNib()
        setup()
    }
    
    private var scanButtonAdded = false
    
    private func setup() {
        textView.delegate = self
        addScanQRButtonIfNeeded()
    }
    
    // MARK: - Scan QR Button (programmatic)
    // textView hierarchy from xib:
    // textView → NSClipView → NSScrollView → NSView(borderBox content) → NSBox(ZyC-U2-vAS) → customView(9Qb-gg-3TI textContainer) → NSView(v4g-gY-YnE cardContent)
    private func addScanQRButtonIfNeeded() {
        guard !scanButtonAdded else { return }
        
        // 5 levels up from textView = textContainer (customView 9Qb-gg-3TI)
        // 6 levels up from textView = cardContentView (v4g-gY-YnE)
        guard
            let textContainer = textView.superview?.superview?.superview?.superview?.superview,
            let cardContentView = textContainer.superview
        else { return }
        
        scanButtonAdded = true
        
        let primaryBlue = NSColor(red: 0.380, green: 0.541, blue: 1.0, alpha: 1.0)
        
        // Outer container
        let buttonContainer = NSView()
        buttonContainer.translatesAutoresizingMaskIntoConstraints = false
        cardContentView.addSubview(buttonContainer)
        
        // Blue rounded background box
        let backgroundBox = NSBox()
        backgroundBox.boxType = .custom
        backgroundBox.borderType = .lineBorder
        backgroundBox.cornerRadius = 17
        backgroundBox.titlePosition = .noTitle
        backgroundBox.fillColor = primaryBlue
        backgroundBox.borderColor = .clear
        backgroundBox.translatesAutoresizingMaskIntoConstraints = false
        buttonContainer.addSubview(backgroundBox)
        
        // Label
        let label = NSTextField(labelWithString: "Scan QR Code")
        label.font = NSFont(name: "Roboto-Regular", size: 13) ?? NSFont.systemFont(ofSize: 13)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        backgroundBox.addSubview(label)
        
        // Transparent hit-target button on top
        let button = CustomButton()
        button.isBordered = false
        button.title = ""
        button.bezelStyle = .shadowlessSquare
        button.isTransparent = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.target = self
        button.action = #selector(scanQRTapped(_:))
        button.cursor = .pointingHand
        buttonContainer.addSubview(button)
        
        // Remove the XIB constraint that pins textContainer.top to the label below it,
        // so we can insert our button between them.
        for constraint in cardContentView.constraints {
            if (constraint.firstItem as? NSView) == textContainer,
               constraint.firstAttribute == .top {
                cardContentView.removeConstraint(constraint)
                break
            }
        }
        
        NSLayoutConstraint.activate([
            // Button container sits just above the textContainer
            buttonContainer.leadingAnchor.constraint(equalTo: cardContentView.leadingAnchor, constant: 16),
            buttonContainer.trailingAnchor.constraint(equalTo: cardContentView.trailingAnchor, constant: -16),
            buttonContainer.bottomAnchor.constraint(equalTo: textContainer.topAnchor, constant: -8),
            buttonContainer.heightAnchor.constraint(equalToConstant: 34),
            
            // Background box fills container
            backgroundBox.leadingAnchor.constraint(equalTo: buttonContainer.leadingAnchor),
            backgroundBox.trailingAnchor.constraint(equalTo: buttonContainer.trailingAnchor),
            backgroundBox.topAnchor.constraint(equalTo: buttonContainer.topAnchor),
            backgroundBox.bottomAnchor.constraint(equalTo: buttonContainer.bottomAnchor),
            
            // Label centered
            label.centerXAnchor.constraint(equalTo: backgroundBox.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: backgroundBox.centerYAnchor),
            
            // Transparent button covers container
            button.leadingAnchor.constraint(equalTo: buttonContainer.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: buttonContainer.trailingAnchor),
            button.topAnchor.constraint(equalTo: buttonContainer.topAnchor),
            button.bottomAnchor.constraint(equalTo: buttonContainer.bottomAnchor),
        ])
        
        // Expand the card box height by 42pt (34 button + 8 spacing) to avoid clipping.
        // The height constraint is a self-constraint on the NSBox that wraps cardContentView.
        if let cardBox = cardContentView.superview {
            for constraint in cardBox.constraints {
                if constraint.firstItem as? NSObject === cardBox,
                   constraint.firstAttribute == .height,
                   constraint.secondItem == nil {
                    constraint.constant += 42
                    break
                }
            }
        }
    }
    
    func showWith(
        delegate: ImportSeedViewDelegate?,
        network: String,
        host: String,
        relay: String
    ) {
        self.delegate = delegate
        self.network = network
        self.host = host
        self.relay = relay
        
        textView.becomeFirstResponder()
    }
    
    func showWith(
        delegate: ImportSeedViewDelegate?
    ) {
        self.delegate = delegate
        
        textView.becomeFirstResponder()
    }
    
    func getMnemonicWords() -> String {
        return textView.string
    }
    
    @IBAction func scanQRTapped(_ sender: Any) {
        delegate?.didTapScanQR()
    }
    
    func populateWith(scannedString: String) {
        textView.string = scannedString
    }
    
    @IBAction func cancelTapped(_ sender: Any) {
        textView.resignFirstResponder()
        textView.string = ""
        
        self.loading = false
        
        delegate?.didTapCancelImportSeed()
    }
    
    @IBAction func confirmTapped(_ sender: Any) {
        let words = textView.string.split(separator: " ").map { String($0).trim().lowercased() }
        let (error, additionalString) = SphinxOnionManager.sharedInstance.validateSeed(words: words)
        
        if let error = error {
            AlertHelper.showAlert(
                title: "profile.seed-validation-error-title".localized,
                message: error.localizedDescription + (additionalString ?? "")
            )
            return
        }
        
        textView.resignFirstResponder()
        loading = true
        
        delegate?.didTapConfirm()
    }
}

extension ImportSeedView: NSTextViewDelegate {
    func textView(
        _ textView: NSTextView,
        shouldChangeTextIn affectedCharRange: NSRange,
        replacementString: String?
    ) -> Bool {
        if let replacementString = replacementString, replacementString == "\n" {
            textView.resignFirstResponder()
            return false
        }
        return true
    }
}
