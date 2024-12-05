//
//  AttachmentPreviewCollectionViewItem.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 05/12/2024.
//  Copyright © 2024 Tomas Timinskas. All rights reserved.
//

import Cocoa

protocol AttachmentPreviewItemDelegate: AnyObject {
    func closeButtonClicked(item: NSCollectionViewItem)
    func playVideoButtonClicked(item: NSCollectionViewItem)
}

class AttachmentPreviewCollectionViewItem: NSCollectionViewItem {
    
    @IBOutlet weak var attachmentImageView: AspectFillNSImageView!
    @IBOutlet weak var gifView: NSView!
    @IBOutlet weak var videoButtonView: NSBox!
    @IBOutlet weak var playVideoButton: CustomButton!
    @IBOutlet weak var fileButton: CustomButton!
    @IBOutlet weak var fileInfoView: NSView!
    @IBOutlet weak var fileNameLabel: NSTextField!
    @IBOutlet weak var fileDescriptionLabel: NSTextField!
    @IBOutlet weak var closeButtonView: NSBox!
    @IBOutlet weak var closeButton: CustomButton!
    
    weak var delegate: AttachmentPreviewItemDelegate?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.wantsLayer = true
        
        playVideoButton.cursor = .pointingHand
        closeButton.cursor = .pointingHand
        
        attachmentImageView.wantsLayer = true
        attachmentImageView.layer?.backgroundColor = NSColor.white.cgColor
    }
    
    func resetAllViews() {
        attachmentImageView.isHidden = true
        videoButtonView.isHidden = true
        fileButton.isHidden = true
        fileInfoView.isHidden = true
        gifView.isHidden = true
        
        fileButton.title = "attachment"
    }
    
    func render(
        with item: AttachmentPreview,
        index: Int? = nil,
        itemDelegate: AttachmentPreviewItemDelegate? = nil
    ) {
        self.delegate = itemDelegate
        
        resetAllViews()
        
        switch (item.type) {
        case .imageAttachment:
            if item.isAnimated {
                if let animation = item.data?.createGIFAnimation() {
                    gifView.isHidden = false
                    gifView.wantsLayer = true
                    gifView.layer?.cornerRadius = 10
                    gifView.layer?.contents = nil
                    gifView.layer?.contentsGravity = .resizeAspect
                    gifView.layer?.add(animation, forKey: "contents")
                }
            } else {
                attachmentImageView.isHidden = false
                attachmentImageView.gravity = .resizeAspectFill
                attachmentImageView.image = item.image
            }
        case .videoAttachment:
            if let videoData = item.data, let videoUrl = item.url {
                MediaLoader.getThumbnailImageFromVideoData(
                    data: videoData,
                    videoUrl: videoUrl.absoluteString,
                    completion: { image in
                        self.attachmentImageView.isHidden = false
                        self.attachmentImageView.gravity = .resizeAspectFill
                        self.attachmentImageView.image = image
                    }
                )
            }
            videoButtonView.isHidden = false
        case .pdfAttachment:
            if let image = item.data?.getPDFImage(ofPage: 0) {
                attachmentImageView.isHidden = false
                attachmentImageView.gravity = .resizeAspectFill
                attachmentImageView.image = item.image
            } else {
                fileButton.isHidden = false
                fileButton.title = "picture_as_pdf"
            }
            fileInfoView.isHidden = false
            fileNameLabel.stringValue = item.name ?? "File"
            fileDescriptionLabel.stringValue = (item.pagesCount == 1) ? "\(item.pagesCount ?? 0) page" : "\(item.pagesCount ?? 0) pages"
        case .fileAttachment:
            fileButton.isHidden = false
            fileInfoView.isHidden = false
            fileNameLabel.stringValue = item.name ?? "File"
            fileDescriptionLabel.stringValue = item.fileSize ?? "0 KB"
        default:
            break
        }
    }
    
    @IBAction func playVideoButtonClicked(_ sender: Any) {
        delegate?.playVideoButtonClicked(item: self)
    }
    
    @IBAction func closeButtonClicked(_ sender: Any) {
        delegate?.closeButtonClicked(item: self)
    }
}
