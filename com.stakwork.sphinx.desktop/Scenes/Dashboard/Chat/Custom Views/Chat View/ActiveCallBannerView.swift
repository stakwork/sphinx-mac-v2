//
//  ActiveCallBannerView.swift
//  Sphinx
//
//  Persistent live-call strip shown below the tribe chat header.
//

import Cocoa
import QuartzCore

@MainActor
protocol ActiveCallBannerDelegate: AnyObject {
    func didTapJoin(callLink: String)
    func didTapOpen()
}

class ActiveCallBannerView: NSView {
    
    static let kHeight: CGFloat = 64
    
    // MARK: - State
    
    private weak var delegate: ActiveCallBannerDelegate?
    private var currentCallLink: String = ""
    private var isAlreadyInCall: Bool = false
    
    // MARK: - Subviews
    
    private let pulseCircleView: NSView = {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.wantsLayer = true
        v.layer?.cornerRadius = 5
        v.layer?.backgroundColor = NSColor.systemRed.cgColor
        return v
    }()
    
    private let liveLabel: NSTextField = {
        let label = NSTextField(labelWithString: "Live Call")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .labelColor
        label.isEditable = false
        label.isSelectable = false
        label.isBordered = false
        label.drawsBackground = false
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
    }()
    
    private let participantsScrollView: NSScrollView = {
        let sv = NSScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.hasHorizontalScroller = false
        sv.hasVerticalScroller = false
        sv.scrollerStyle = .overlay
        sv.drawsBackground = false
        sv.automaticallyAdjustsContentInsets = false
        sv.contentView.contentInsets = NSEdgeInsetsZero
        return sv
    }()
    
    private let participantsStackView: NSStackView = {
        let sv = NSStackView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.orientation = .horizontal
        sv.spacing = 4
        sv.alignment = .centerY
        return sv
    }()
    
    // Styled to match app's AUDIO/VIDEO call buttons: blue background, white text, corner radius 8
    private let joinButtonBG: NSView = {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.wantsLayer = true
        v.layer?.cornerRadius = 8
        v.layer?.backgroundColor = NSColor.Sphinx.PrimaryBlue.cgColor
        return v
    }()
    
    private let joinButtonLabel: NSTextField = {
        let label = NSTextField(labelWithString: "Join")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont(name: "Montserrat-Regular", size: 12) ?? NSFont.systemFont(ofSize: 12)
        label.textColor = .white
        label.isEditable = false
        label.isSelectable = false
        label.isBordered = false
        label.drawsBackground = false
        label.alignment = .center
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
    }()
    
    // Transparent button layered over joinButtonBG to receive clicks
    private lazy var joinClickTarget: NSButton = {
        let btn = NSButton()
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.isBordered = false
        btn.title = ""
        btn.alphaValue = 0.01 // nearly invisible but hittable
        btn.target = self
        btn.action = #selector(joinButtonTapped)
        return btn
    }()
    
    private let separatorLine: NSView = {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.separatorColor.cgColor
        return v
    }()
    
    // MARK: - Init
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }
    
    // MARK: - Setup
    
    private func setupViews() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.Sphinx.ReceivedMsgBG.cgColor
        
        participantsScrollView.documentView = participantsStackView
        
        joinButtonBG.addSubview(joinButtonLabel)
        joinButtonBG.addSubview(joinClickTarget)
        
        addSubview(separatorLine)
        addSubview(pulseCircleView)
        addSubview(liveLabel)
        addSubview(participantsScrollView)
        addSubview(joinButtonBG)
        
        NSLayoutConstraint.activate([
            // Bottom separator
            separatorLine.leadingAnchor.constraint(equalTo: leadingAnchor),
            separatorLine.trailingAnchor.constraint(equalTo: trailingAnchor),
            separatorLine.bottomAnchor.constraint(equalTo: bottomAnchor),
            separatorLine.heightAnchor.constraint(equalToConstant: 1),
            
            // Pulsing dot – left side
            pulseCircleView.widthAnchor.constraint(equalToConstant: 10),
            pulseCircleView.heightAnchor.constraint(equalToConstant: 10),
            pulseCircleView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            pulseCircleView.centerYAnchor.constraint(equalTo: centerYAnchor),
            
            // "Live Call" label
            liveLabel.leadingAnchor.constraint(equalTo: pulseCircleView.trailingAnchor, constant: 6),
            liveLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            
            // Blue button background – right side, 70 × 32
            joinButtonBG.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            joinButtonBG.centerYAnchor.constraint(equalTo: centerYAnchor),
            joinButtonBG.widthAnchor.constraint(equalToConstant: 70),
            joinButtonBG.heightAnchor.constraint(equalToConstant: 32),
            
            // Label centred inside blue bg
            joinButtonLabel.centerXAnchor.constraint(equalTo: joinButtonBG.centerXAnchor),
            joinButtonLabel.centerYAnchor.constraint(equalTo: joinButtonBG.centerYAnchor),
            
            // Click target fills blue bg
            joinClickTarget.leadingAnchor.constraint(equalTo: joinButtonBG.leadingAnchor),
            joinClickTarget.trailingAnchor.constraint(equalTo: joinButtonBG.trailingAnchor),
            joinClickTarget.topAnchor.constraint(equalTo: joinButtonBG.topAnchor),
            joinClickTarget.bottomAnchor.constraint(equalTo: joinButtonBG.bottomAnchor),
            
            // Participants scroll – fills space between label and button
            participantsScrollView.leadingAnchor.constraint(equalTo: liveLabel.trailingAnchor, constant: 10),
            participantsScrollView.trailingAnchor.constraint(equalTo: joinButtonBG.leadingAnchor, constant: -10),
            participantsScrollView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            participantsScrollView.bottomAnchor.constraint(equalTo: separatorLine.topAnchor, constant: -8),
            
            // Stack view inside scroll view
            participantsStackView.leadingAnchor.constraint(equalTo: participantsScrollView.contentView.leadingAnchor),
            participantsStackView.topAnchor.constraint(equalTo: participantsScrollView.contentView.topAnchor),
            participantsStackView.bottomAnchor.constraint(equalTo: participantsScrollView.contentView.bottomAnchor),
        ])
        
        startPulseAnimation()
    }
    
    override func layout() {
        super.layout()
        // Re-apply layer colors after first layout pass (needed for named colors)
        joinButtonBG.layer?.backgroundColor = NSColor.Sphinx.PrimaryBlue.cgColor
        layer?.backgroundColor = NSColor.Sphinx.ReceivedMsgBG.cgColor
    }
    
    // MARK: - Pulse animation
    
    private func startPulseAnimation() {
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.4
        pulse.toValue = 1.0
        pulse.duration = 0.8
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        pulseCircleView.layer?.add(pulse, forKey: "pulse")
    }
    
    // MARK: - Public configure
    
    func configureWith(
        participants: [BubbleMessageLayoutState.CallParticipantInfo],
        callLink: String,
        isAlreadyInCall: Bool,
        delegate: ActiveCallBannerDelegate
    ) {
        self.currentCallLink = callLink
        self.isAlreadyInCall = isAlreadyInCall
        self.delegate = delegate
        
        joinButtonLabel.stringValue = isAlreadyInCall ? "Open" : "Join"
        
        for view in participantsStackView.arrangedSubviews {
            participantsStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        
        for participant in participants {
            let boxView = ParticipantBoxView()
            boxView.configure(with: participant)
            participantsStackView.addArrangedSubview(boxView)
        }
        
        participantsScrollView.isHidden = participants.isEmpty
    }
    
    // MARK: - Actions
    
    @objc private func joinButtonTapped() {
        if isAlreadyInCall {
            delegate?.didTapOpen()
        } else {
            delegate?.didTapJoin(callLink: currentCallLink)
        }
    }
    
    // MARK: - Appearance
    
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = NSColor.Sphinx.ReceivedMsgBG.cgColor
        separatorLine.layer?.backgroundColor = NSColor.separatorColor.cgColor
        joinButtonBG.layer?.backgroundColor = NSColor.Sphinx.PrimaryBlue.cgColor
    }
}
