//
//  JoinVideoCallView.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 02/06/2020.
//  Copyright © 2020 Sphinx. All rights reserved.
//

import Cocoa

@MainActor
protocol JoinCallViewDelegate: AnyObject {
    func didTapCopyLink()
    func didTapAudioButton()
    func didTapVideoButton()
}

class JoinVideoCallView: NSView, @preconcurrency LoadableNib {
    
    weak var delegate: JoinCallViewDelegate?
    
    @IBOutlet var contentView: NSView!
    @IBOutlet weak var videoButtonContainer: NSBox!
    @IBOutlet weak var audioButtonContainer: NSBox!
    @IBOutlet weak var audioButton: CustomButton!
    @IBOutlet weak var videoButton: CustomButton!
    @IBOutlet weak var copyButton: CustomButton!
    @IBOutlet weak var participantsScrollView: NSScrollView!
    
    static let kViewHeight: CGFloat = 206
    static let kViewAudioOnlyHeight: CGFloat = 158
    static let kParticipantsRowHeight: CGFloat = 60
    
    private let participantsCountLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 11)
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.isEditable = false
        label.isSelectable = false
        label.isBordered = false
        label.drawsBackground = false
        label.textColor = .Sphinx.Text
        label.alignment = .center
        return label
    }()
    
    private let participantsStackView: NSStackView = {
        let stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.spacing = 2
        return stackView
    }()
    
    public enum CallButton: Int {
        case Audio
        case Video
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        loadViewFromNib()
        
        audioButtonContainer.wantsLayer = true
        audioButtonContainer.layer?.cornerRadius = 8

        videoButtonContainer.wantsLayer = true
        videoButtonContainer.layer?.cornerRadius = 8
        
        audioButton.cursor = .pointingHand
        videoButton.cursor = .pointingHand
        copyButton.cursor = .pointingHand
        
        participantsScrollView.documentView = participantsStackView

        NSLayoutConstraint.activate([
            participantsStackView.leadingAnchor.constraint(equalTo: participantsScrollView.contentView.leadingAnchor),
            participantsStackView.topAnchor.constraint(equalTo: participantsScrollView.contentView.topAnchor),
            participantsStackView.bottomAnchor.constraint(equalTo: participantsScrollView.contentView.bottomAnchor),
        ])
        
        participantsScrollView.contentView.contentInsets = NSEdgeInsetsZero
        participantsScrollView.automaticallyAdjustsContentInsets = false
        participantsScrollView.scrollerStyle = .overlay
        participantsScrollView.hasHorizontalScroller = false
    }
    
    func configureWith(
        callLink: BubbleMessageLayoutState.CallLink,
        and delegate: JoinCallViewDelegate
    ) {
        self.delegate = delegate
        
        videoButtonContainer.isHidden = callLink.callMode == .Audio
    }
    
    func configure(delegate: JoinCallViewDelegate, link: String) {
        self.delegate = delegate
        
        configureWith(link: link)
    }
    
    func configureWith(link: String) {
        let mode = VideoCallHelper.getCallMode(link: link)
        
        audioButtonContainer.isHidden = false
        videoButtonContainer.isHidden = false
        
        switch (mode) {
        case .Audio:
            videoButtonContainer.isHidden = true
            break
        default:
            break
        }
    }
    
    func configureWith(participantsData: MessageTableCellState.ParticipantsData?) {
        let stackView = participantsStackView
        
        // Remove all existing arranged subviews
        for view in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        
        guard let participants = participantsData?.participants, !participants.isEmpty else {
            participantsScrollView.isHidden = true
            return
        }
        
        if !participants.isEmpty {
            for participant in participants {
                let boxView = ParticipantBoxView()
                boxView.configure(with: participant)
                stackView.addArrangedSubview(boxView)
            }       
        }
        participantsScrollView.isHidden = false
    }
    
    @IBAction func callButtonTouched(_ sender: Any) {
        guard let sender = sender as? NSButton else {
            return
        }

        switch(sender.tag) {
        case CallButton.Audio.rawValue:
            delegate?.didTapAudioButton()
            break
        case CallButton.Video.rawValue:
            delegate?.didTapVideoButton()
            break
        default:
            break
        }
    }
    
    @IBAction func copyLinkButtonTouched(_ sender: Any) {
        delegate?.didTapCopyLink()
    }
    
}
