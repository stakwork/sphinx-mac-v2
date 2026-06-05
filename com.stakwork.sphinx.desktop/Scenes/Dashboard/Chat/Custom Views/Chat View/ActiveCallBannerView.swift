//
//  ActiveCallBannerView.swift
//  Sphinx
//
//  Created for live call banner in tribe chat header.
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
    
    private lazy var joinButton: NSButton = {
        let btn = NSButton(title: "Join", target: self, action: #selector(joinButtonTapped))
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.bezelStyle = .rounded
        btn.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        btn.setContentHuggingPriority(.required, for: .horizontal)
        btn.setContentCompressionResistancePriority(.required, for: .horizontal)
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
        
        // Scroll view document view
        participantsScrollView.documentView = participantsStackView
        
        addSubview(pulseCircleView)
        addSubview(liveLabel)
        addSubview(participantsScrollView)
        addSubview(joinButton)
        addSubview(separatorLine)
        
        NSLayoutConstraint.activate([
            // Separator at bottom
            separatorLine.leadingAnchor.constraint(equalTo: leadingAnchor),
            separatorLine.trailingAnchor.constraint(equalTo: trailingAnchor),
            separatorLine.bottomAnchor.constraint(equalTo: bottomAnchor),
            separatorLine.heightAnchor.constraint(equalToConstant: 1),
            
            // Pulsing red circle – left side
            pulseCircleView.widthAnchor.constraint(equalToConstant: 10),
            pulseCircleView.heightAnchor.constraint(equalToConstant: 10),
            pulseCircleView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            pulseCircleView.centerYAnchor.constraint(equalTo: centerYAnchor),
            
            // "Live Call" label right of circle
            liveLabel.leadingAnchor.constraint(equalTo: pulseCircleView.trailingAnchor, constant: 6),
            liveLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            
            // Join / Open button – right side
            joinButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            joinButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            
            // Participants scroll view fills the middle
            participantsScrollView.leadingAnchor.constraint(equalTo: liveLabel.trailingAnchor, constant: 10),
            participantsScrollView.trailingAnchor.constraint(equalTo: joinButton.leadingAnchor, constant: -10),
            participantsScrollView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            participantsScrollView.bottomAnchor.constraint(equalTo: separatorLine.topAnchor, constant: -8),
            
            // Stack view inside scroll view
            participantsStackView.leadingAnchor.constraint(equalTo: participantsScrollView.contentView.leadingAnchor),
            participantsStackView.topAnchor.constraint(equalTo: participantsScrollView.contentView.topAnchor),
            participantsStackView.bottomAnchor.constraint(equalTo: participantsScrollView.contentView.bottomAnchor),
        ])
        
        startPulseAnimation()
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
        
        joinButton.title = isAlreadyInCall ? "Open" : "Join"
        
        // Rebuild participant boxes
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
    
    // MARK: - Appearance update
    
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = NSColor.Sphinx.ReceivedMsgBG.cgColor
        separatorLine.layer?.backgroundColor = NSColor.separatorColor.cgColor
    }
}
