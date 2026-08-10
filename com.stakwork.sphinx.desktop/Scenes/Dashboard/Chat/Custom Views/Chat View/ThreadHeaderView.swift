//
//  ThreadHeaderView.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 28/09/2023.
//  Copyright © 2023 Tomas Timinskas. All rights reserved.
//

import Cocoa

@objc protocol ThreadHeaderViewDelegate {
    @objc optional func shouldLoadImageDataFor(messageId: Int, and rowIndex: Int)
    @objc optional func shouldLoadPdfDataFor(messageId: Int, and rowIndex: Int)
    @objc optional func shouldLoadFileDataFor(messageId: Int, and rowIndex: Int)
    @objc optional func shouldLoadVideoDataFor(messageId: Int, and rowIndex: Int)
    @objc optional func shouldLoadGiphyDataFor(messageId: Int, and rowIndex: Int)
    @objc optional func shouldLoadAudioDataFor(messageId: Int, and rowIndex: Int)
    
    func didTapMediaButtonFor(messageId: Int, and rowIndex: Int)
    func didTapFileDownloadButtonFor(messageId: Int, and rowIndex: Int)
    func didTapPlayPauseButtonFor(messageId: Int, and rowIndex: Int)
    
    func shouldCloseThread()
    
    func shouldShowOptionsFor(messageId: Int, from button: NSButton)
}

class ThreadHeaderView: NSView, @preconcurrency LoadableNib {
    
    // 240 pt ≈ 12 lines of Roboto-Regular 16 pt — matches iOS isLabelTruncated() cap exactly.
    static let kMaxCollapsedTextHeight: CGFloat = 240.0
    
    private var isExpanded: Bool = false
    private var showMoreButton: NSButton?
    private var showMoreButtonContainer: NSView?
    private var needsCollapseEvaluation: Bool = false
    
    weak var delegate : ThreadHeaderViewDelegate? = nil
    
    var messageId: Int?
    
    @IBOutlet var contentView: NSView!
    
    @IBOutlet weak var chatAvatarView: ChatSmallAvatarView!
    @IBOutlet weak var userNameLabel: NSTextField!
    @IBOutlet weak var dateLabel: NSTextField!
    
    @IBOutlet weak var audioFileContainer: NSView!
    @IBOutlet weak var fileInfoView: FileInfoView!
    @IBOutlet weak var audioMessageView: AudioMessageView!
    
    @IBOutlet weak var mediaTextContainer: NSStackView!
    @IBOutlet weak var messageMediaContainer: NSView!
    @IBOutlet weak var messageMediaView: MediaMessageView!
    @IBOutlet weak var messageBoostView: NewMessageBoostView!
    @IBOutlet weak var messageBoostViewContainer: NSView!
    
    @IBOutlet weak var textContainer: NSView!
    @IBOutlet weak var messageLabel: MessageTextField!
    
    @IBOutlet weak var newMessageLabelScrollView: DisabledScrollView!
    @IBOutlet var newMessageLabel: NSTextView!
    @IBOutlet weak var closeButton: CustomButton!
    @IBOutlet weak var optionsButton: CustomButton!
    
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
        closeButton.cursor = .pointingHand
        optionsButton.cursor = .pointingHand
        
        addShadow(
            location: VerticalLocation.bottom,
            color: NSColor.black,
            opacity: 0.3,
            radius: 5.0
        )
        
        messageLabel.setSelectionColor(color: NSColor.getTextSelectionColor())
        messageLabel.allowsEditingTextAttributes = true
        
        fileInfoView.wantsLayer = true
        fileInfoView.layer?.backgroundColor = NSColor.Sphinx.Body.cgColor
        fileInfoView.layer?.cornerRadius = 9
        
        newMessageLabel.textContainerInset = NSSize(width: 0, height: 0)
        newMessageLabel.textContainer?.lineFragmentPadding = 0
        newMessageLabel.delegate = self
        newMessageLabel.linkTextAttributes = [
            .foregroundColor: NSColor.Sphinx.PrimaryBlue,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        
        let btn = NSButton(title: "Show more", target: self, action: #selector(showMoreButtonTapped))
        btn.isBordered = false
        btn.font = NSFont(name: "Roboto-Light", size: 13.0) ?? NSFont.systemFont(ofSize: 13.0, weight: .light)
        btn.contentTintColor = NSColor.Sphinx.PrimaryBlue
        btn.alignment = .right
        btn.translatesAutoresizingMaskIntoConstraints = false
        showMoreButton = btn

        // Wrap in a container so the button sits in the bottom-right corner with margins,
        // regardless of the leading-aligned parent NSStackView (YlO-at-1xE).
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.isHidden = true
        container.addSubview(btn)
        NSLayoutConstraint.activate([
            btn.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            btn.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            btn.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
        ])
        showMoreButtonContainer = container
        
        // Deactivate the storyboard placeholder height constraint (priority 750, constant 65 pt)
        // to prevent Auto Layout warnings once the header is driven by content height.
        if let placeholderHeight = constraints.first(where: {
            $0.firstAttribute == .height &&
            $0.priority == NSLayoutConstraint.Priority(750) &&
            $0.secondItem == nil
        }) {
            placeholderHeight.isActive = false
        }
    }
    
    func hideAllViews() {
        audioFileContainer.isHidden = true
        audioMessageView.isHidden = true
        fileInfoView.isHidden = true
        mediaTextContainer.isHidden = true
        messageMediaContainer.isHidden = true
        messageMediaView.isHidden = true
        textContainer.isHidden = true
        messageBoostViewContainer.isHidden = true
    }
    
    func configureWith(
        messageCellState: MessageTableCellState,
        mediaData: MessageTableCellState.MediaData?,
        delegate: ThreadHeaderViewDelegate
    ){
        hideAllViews()
        
        var mutableMessageCellState = messageCellState
        
        self.delegate = delegate
        self.messageId = mutableMessageCellState.messageId
        
        configureWith(threadOriginalMessage: mutableMessageCellState.threadOriginalMessageHeader)
        configureWith(messageMedia: mutableMessageCellState.messageMedia, mediaData: mediaData)
        configureWith(genericFile: mutableMessageCellState.genericFile, mediaData: mediaData)
        configureWith(audio: mutableMessageCellState.audio, mediaData: mediaData)
        
        if let bubble = mutableMessageCellState.bubble {
            configureWith(boosts: mutableMessageCellState.boosts, and: bubble)
        }
    }
    
    func configureWith(
        threadOriginalMessage: NoBubbleMessageLayoutState.ThreadOriginalMessage?
    ) {
        guard let threadOriginalMessage = threadOriginalMessage else {
            return
        }
        
        dateLabel.stringValue = threadOriginalMessage.timestamp
        userNameLabel.stringValue = threadOriginalMessage.senderAlias
        
        chatAvatarView.configureForUserWith(
            color: threadOriginalMessage.senderColor,
            alias: threadOriginalMessage.senderAlias,
            picture: threadOriginalMessage.senderPic,
            radius: 18.0
        )
        
        // Full reset — clears any prior message's collapse/expand UI state unconditionally.
        isExpanded = false
        messageLabel.maximumHeight = 0
        messageLabel.invalidateIntrinsicContentSize()
        newMessageLabelScrollView.disabled = true
        showMoreButtonContainer?.isHidden = true
        needsCollapseEvaluation = false
        
        guard threadOriginalMessage.text.isNotEmpty else {
            return
        }
        
        mediaTextContainer.isHidden = false
        textContainer.isHidden = false
        messageLabel.isHidden = true
        newMessageLabel.isEditable = false
        
        if threadOriginalMessage.hasNoMarkdown {
            messageLabel.attributedStringValue = NSMutableAttributedString(string: "")
            newMessageLabel.string = threadOriginalMessage.text
            newMessageLabel.font = NSFont.getThreadHeaderFont()
            messageLabel.stringValue = threadOriginalMessage.text
            messageLabel.font = NSFont.getThreadHeaderFont()
        } else {
            let messageC = threadOriginalMessage.text

            let attributedString = NSMutableAttributedString(
                attributedString: ChatHelper.markdownRenderer.render(messageC)
            )
            ChatHelper.applySphinxLinkTransforms(to: attributedString)

            messageLabel.attributedStringValue = attributedString
            messageLabel.isEnabled = true
            newMessageLabel.string = attributedString.string
            newMessageLabel.textStorage?.setAttributedString(attributedString)
        }
        
        // Schedule collapse evaluation on the next layout pass (after Auto Layout resolves
        // the actual frame width, including any media-column deduction).
        needsCollapseEvaluation = true
        needsLayout = true
    }
    
    func configureWith(
        messageMedia: BubbleMessageLayoutState.MessageMedia?,
        mediaData: MessageTableCellState.MediaData?
    ) {
        newMessageLabelScrollView.disabled = false
        
        if let messageMedia = messageMedia {
            if messageMedia.isImageLink {
                if let mediaData = mediaData {
                    if mediaData.failed {
                        return
                    }
                    messageMediaView.configureWith(
                        messageMedia: messageMedia,
                        mediaData: mediaData,
                        bubble: BubbleMessageLayoutState.Bubble(direction: .Incoming, grouping: .Isolated),
                        and: self
                    )
                    newMessageLabelScrollView.disabled = false
                    messageMediaView.isHidden = false
                    mediaTextContainer.isHidden = false
                    messageMediaContainer.isHidden = false
                    
                }
//                else if let messageId = messageId, mediaData == nil {
//                    let delayTime = DispatchTime.now() + Double(Int64(0.1 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
//                    DispatchQueue.global().asyncAfter(deadline: delayTime) {
//                        self.delegate?.shouldLoadImageDataFor?(
//                            messageId: messageId,
//                            and: NewChatTableDataSource.kThreadHeaderRowIndex
//                        )
//                    }
//                }
            } else {
                messageMediaView.configureWith(
                    messageMedia: messageMedia,
                    mediaData: mediaData,
                    bubble: BubbleMessageLayoutState.Bubble(direction: .Incoming, grouping: .Isolated),
                    and: self
                )
                
                newMessageLabelScrollView.disabled = false
                messageMediaView.isHidden = false
                mediaTextContainer.isHidden = false
                messageMediaContainer.isHidden = false

                if let messageId = messageId, mediaData == nil {
                    let delayTime = DispatchTime.now() + Double(Int64(0.1 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
                    DispatchQueue.global().asyncAfter(deadline: delayTime) {
                        Task { @MainActor in
                            if messageMedia.isImage {
                                self.delegate?.shouldLoadImageDataFor?(
                                    messageId: messageId,
                                    and: NewChatTableDataSource.kThreadHeaderRowIndex
                                )
                            } else if messageMedia.isPdf {
                                self.delegate?.shouldLoadPdfDataFor?(
                                    messageId: messageId,
                                    and: NewChatTableDataSource.kThreadHeaderRowIndex
                                )
                            } else if messageMedia.isVideo {
                                self.delegate?.shouldLoadVideoDataFor?(
                                    messageId: messageId,
                                    and: NewChatTableDataSource.kThreadHeaderRowIndex
                                )
                            } else if messageMedia.isGiphy {
                                self.delegate?.shouldLoadGiphyDataFor?(
                                    messageId: messageId,
                                    and: NewChatTableDataSource.kThreadHeaderRowIndex
                                )
                            }
                        }
                    }
                }
            }
        }
    }
    
    func configureWith(
        genericFile: BubbleMessageLayoutState.GenericFile?,
        mediaData: MessageTableCellState.MediaData?
    ) {
        if let _ = genericFile {
            fileInfoView.configureWith(
                mediaData: mediaData,
                and: self
            )
            
            audioFileContainer.isHidden = false
            fileInfoView.isHidden = false
            
            if let messageId = messageId, mediaData == nil {
                let delayTime = DispatchTime.now() + Double(Int64(0.1 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
                DispatchQueue.global().asyncAfter(deadline: delayTime) {
                    Task { @MainActor in
                        self.delegate?.shouldLoadFileDataFor?(
                            messageId: messageId,
                            and: NewChatTableDataSource.kThreadHeaderRowIndex
                        )
                    }
                }
            }
        }
    }
    
    func configureWith(
        audio: BubbleMessageLayoutState.Audio?,
        mediaData: MessageTableCellState.MediaData?
    ) {
        if let audio = audio {
            audioMessageView.configureWith(
                audio: audio,
                mediaData: mediaData,
                bubble: BubbleMessageLayoutState.Bubble(direction: .Incoming, grouping: .Isolated),
                and: self
            )
            
            audioFileContainer.isHidden = false
            audioMessageView.isHidden = false
            
            if let messageId = messageId, mediaData == nil {
                let delayTime = DispatchTime.now() + Double(Int64(0.1 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
                DispatchQueue.global().asyncAfter(deadline: delayTime) {
                    Task { @MainActor in
                        self.delegate?.shouldLoadAudioDataFor?(
                            messageId: messageId,
                            and: NewChatTableDataSource.kThreadHeaderRowIndex
                        )
                    }
                }
            }
        }
    }
    
    func configureWith(
        boosts: BubbleMessageLayoutState.Boosts?,
        and bubble: BubbleMessageLayoutState.Bubble
    ) {
        if let boosts = boosts {
            messageBoostView.configureWith(boosts: boosts, and: bubble, isThreadHeader: true)
            messageBoostViewContainer.isHidden = false
        }
    }
    
    override func layout() {
        super.layout()
        guard needsCollapseEvaluation else { return }
        needsCollapseEvaluation = false
        evaluateCollapseNeeded()
    }
    
    @MainActor
    private func evaluateCollapseNeeded() {
        // newMessageLabel.textContainer is the NSTextContainer of the NSTextView —
        // distinct from the `textContainer` IBOutlet (NSView).
        guard let lm = newMessageLabel.layoutManager,
              let tc = newMessageLabel.textContainer else { return }
        lm.ensureLayout(for: tc)       // defensive: ensures glyphs are laid out even if display hasn't run
        let fullHeight = lm.usedRect(for: tc).height
        // Compare against (kMaxCollapsedTextHeight − 16): the messageLabel cap, not the textContainer cap,
        // because textContainer.height = messageLabel.height + 16 (XIB pin cX0-DG-YiD).
        let needsCollapse = fullHeight > Self.kMaxCollapsedTextHeight - 16
        updateCollapseState(needsCollapse: needsCollapse)
        superview?.needsLayout = true  // let the parent NSStackView redistribute freed space asynchronously
    }
    
    @MainActor
    private func updateCollapseState(needsCollapse: Bool) {
        let shouldCap = needsCollapse && !isExpanded
        
        // Drive textContainer height via the XIB bottom-pin (cX0-DG-YiD, priority 1000):
        //   textContainer.height = messageLabel.height + 16
        // Setting maximumHeight = 224 (= 240 − 16) caps textContainer at 240 pt.
        // Setting 0 removes the cap entirely.
        messageLabel.maximumHeight = shouldCap ? Self.kMaxCollapsedTextHeight - 16 : 0
        messageLabel.invalidateIntrinsicContentSize()
        
        // Prevent the NSTextView from being scrolled past the clip boundary.
        newMessageLabelScrollView.disabled = shouldCap
        
        // Insert the container after textContainer in its parent NSStackView (once only).
        if let container = showMoreButtonContainer, container.superview == nil,
           let stack = textContainer.superview as? NSStackView {
            if let idx = stack.arrangedSubviews.firstIndex(of: textContainer) {
                stack.insertArrangedSubview(container, at: idx + 1)
            } else {
                stack.addArrangedSubview(container)
            }
            // Pin container trailing to the stack's trailing edge so the button
            // reaches the right margin regardless of the leading-aligned stack.
            NSLayoutConstraint.activate([
                container.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
                container.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            ])
        }
        
        showMoreButtonContainer?.isHidden = !needsCollapse
        showMoreButton?.title = isExpanded ? "Show less" : "Show more"
    }
    
    @objc private func showMoreButtonTapped() {
        isExpanded.toggle()
        updateCollapseState(needsCollapse: true)  // button is only visible when message is long
        superview?.layoutSubtreeIfNeeded()        // synchronous: gives immediate visual feedback on tap
    }
    
    @IBAction func optionsButtonClicked(_ sender: Any) {
        if let button = sender as? NSButton, let messageId = messageId {
            delegate?.shouldShowOptionsFor(messageId: messageId, from: button)
        }
    }
    
    @IBAction func closeButtonClicked(_ sender: Any) {
        delegate?.shouldCloseThread()
    }
}

extension ThreadHeaderView : @preconcurrency MediaMessageViewDelegate {
    func didTapMediaButton() {
        if let messageId = messageId {
            delegate?.didTapMediaButtonFor(messageId: messageId, and: NewChatTableDataSource.kThreadHeaderRowIndex)
        }
    }
}

extension ThreadHeaderView : @preconcurrency FileInfoViewDelegate {
    func didTouchDownloadButton() {
        if let messageId = messageId {
            delegate?.didTapFileDownloadButtonFor(messageId: messageId, and: NewChatTableDataSource.kThreadHeaderRowIndex)
        }
    }
}

extension ThreadHeaderView : @preconcurrency AudioMessageViewDelegate {
    func didTapPlayPauseButton() {
        if let messageId = messageId {
            delegate?.didTapPlayPauseButtonFor(messageId: messageId, and: NewChatTableDataSource.kThreadHeaderRowIndex)
        }
    }
}

extension ThreadHeaderView : @preconcurrency NSTextViewDelegate {
    func textView(
        _ textView: NSTextView,
        clickedOnLink link: Any,
        at charIndex: Int
    ) -> Bool {
        DispatchQueue.main.async {
            self.window?.makeFirstResponder(nil)
        }

        var resolvedURL: URL?
        if let url = link as? URL { resolvedURL = url }
        else if let str = link as? String { resolvedURL = URL(string: str) }
        guard let url = resolvedURL else { return false }

        if url.scheme == "sphinx.chat" {
            if url.getLinkAction() == "webapp" {
                NotificationCenter.default.post(
                    name: .onWebAppLinkTapped,
                    object: nil,
                    userInfo: ["link": url.absoluteString]
                )
            } else {
                DeepLinksHandlerHelper.handleLinkQueryFrom(url: url)
            }
            return true
        }

        NSWorkspace.shared.open(url)
        return true
    }
}
