//
//  DraggingDestinationView.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 03/06/2020.
//  Copyright © 2020 Sphinx. All rights reserved.
//

import Cocoa

protocol DraggingViewDelegate: AnyObject {
    func imageDragged(image: NSImage)
}

@objc protocol ChatDraggingViewDelegate: AnyObject {
    @objc func attachmentAdded(url: URL?, data: Data, image: NSImage?)
    @objc optional func imageDismissed()
}

class DraggingDestinationView: NSView, LoadableNib {
    
    weak var delegate: DraggingViewDelegate?
    weak var chatDelegate: ChatDraggingViewDelegate?
    
    @IBOutlet var contentView: NSView!
    @IBOutlet weak var draggingContainer: NSView!
    @IBOutlet weak var dragLabel: NSTextField!
    
    @IBOutlet weak var topMargin: NSLayoutConstraint!
    @IBOutlet weak var leftMargin: NSLayoutConstraint!
    @IBOutlet weak var bottomMargin: NSLayoutConstraint!
    @IBOutlet weak var rightMargin: NSLayoutConstraint!
    
    var imagePreview: MediaFullScreenView? = nil
    
    var image : NSImage? = nil
    var mediaData : Data? = nil
    var fileName : String? = nil
    var borderColor = NSColor.Sphinx.LightDivider
    var giphyObject : GiphyObject? = nil
    
    var mediaType : AttachmentsManager.AttachmentType? = nil
    
    var acceptableTypes: [NSPasteboard.PasteboardType] { return [ NSPasteboard.PasteboardType.URL, NSPasteboard.PasteboardType.fileContents] }
    var filteringOptions = [NSPasteboard.ReadingOptionKey.urlReadingContentsConformToTypes: []]
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        loadViewFromNib()
        
        let optionsArray = [String]()
        configureFilteringOptions(types: optionsArray)
    }
    
    func configureFilteringOptions(types: [String]) {
        filteringOptions = [NSPasteboard.ReadingOptionKey.urlReadingContentsConformToTypes: types]
    }
    
    func configureForProfilePicture() {
        configureFilteringOptions(types: NSImage.imageTypes)
        dragLabel.stringValue = "drag.image".localized
        dragLabel.font = NSFont(name: "Roboto-Medium", size: 8)!
    }
    
    func configureForTribeImage() {
        configureFilteringOptions(types: NSImage.imageTypes)
        dragLabel.stringValue = "drag.image".localized
        dragLabel.font = NSFont(name: "Roboto-Medium", size: 8)!
        
        topMargin.constant = 0
        bottomMargin.constant = 0
        rightMargin.constant = 0
        leftMargin.constant = 0
        
        self.layoutSubtreeIfNeeded()
    }
    
    func configureForSignup() {
        borderColor = NSColor.clear
        configureFilteringOptions(types: NSImage.imageTypes)
        dragLabel.stringValue = ""
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        if isReceivingDrag {
            resetView()
            configureDraggingStyle()
        }
    }
    
    var isReceivingDrag = false {
        didSet {
            needsDisplay = true
        }
    }
    
    func setup(
        delegate: ChatDraggingViewDelegate? = nil
    ) {
        reset()
        resetView()
        
        registerForDraggedTypes(acceptableTypes)
        
        if let delegate = delegate {
            self.chatDelegate = delegate
        }
    }
    
    func reset() {
        image = nil
        mediaData = nil
        mediaType = nil
        giphyObject = nil
    }
    
    func addImagePreviewView() {
        imagePreview = MediaFullScreenView()
        
        if let imagePreview = imagePreview {
            contentView.addSubview(imagePreview)
            
            imagePreview.delegate = self
            imagePreview.constraintTo(view: contentView)
        }
    }
    
    func resetView() {
        layer?.backgroundColor = NSColor.clear.cgColor
        draggingContainer.isHidden = true
        
        if let imagePreview = imagePreview {
            imagePreview.removeFromSuperview()
            self.imagePreview = nil
        }
        
        reset()
        
        chatDelegate?.imageDismissed?()
    }
    
    func isSendingGiphy() -> (Bool, GiphyObject?) {
        return (giphyObject != nil, giphyObject)
    }
    
    func getData(price: Int, text: String) -> AttachmentObject? {
        if let data = mediaData, let type = mediaType {
            let (key, encryptedData) = SymmetricEncryptionManager.sharedInstance.encryptData(data: data)
            if let encryptedData = encryptedData {
                let attachmentObject = AttachmentObject(data: encryptedData, fileName: fileName, mediaKey: key, type: type, text: text, image: image, price: price)
                return attachmentObject
            }
        }
        return nil
    }
    
    func getMediaData() -> Data? {
        return mediaData
    }
    
    func configureDraggingStyle() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.Sphinx.Body.withAlphaComponent(0.95).cgColor
        
        draggingContainer.wantsLayer = true
        draggingContainer.addDashedBorder(color: borderColor, size: draggingContainer.bounds.size, lineWidth: 5)
        draggingContainer.layer?.cornerRadius = 10
        draggingContainer.isHidden = false
    }
    
    func showGiphyPreview(data: Data, object: GiphyObject) {
        resetView()
        setData(data, image: image, giphyObject: object)
        mediaType = .Gif
        
        addImagePreviewView()
        imagePreview?.showGifWith(data: data, size: self.frame.size)
        imagePreview?.isHidden = false
        MediaLoader.storeMediaDataInCache(data: data, url: GiphyHelper.getSearchURL(url: object.url))
        
        let smallUrl = GiphyHelper.get200WidthURL(url: object.url)
        GiphyHelper.getGiphyDataFrom(url: smallUrl, messageId: 0, cache: false, completion: { (data, messageId) in
            if let data = data {
                MediaLoader.storeMediaDataInCache(data: data, url: smallUrl)
                self.imagePreview?.showGifWith(data: data, size: self.frame.size)
            }
        })
        
        GiphyHelper.getGiphyDataFrom(url: object.url, messageId: 0, cache: false, completion: { (data, messageId) in
            if let data = data {
                MediaLoader.storeMediaDataInCache(data: data, url: object.url)
                self.imagePreview?.showGifWith(data: data, size: self.frame.size)
            }
        })
    }
    
    func setData(_ data: Data, image: NSImage?, giphyObject: GiphyObject? = nil) {
        self.image = image
        self.mediaData = data
        self.giphyObject = giphyObject
    }
    
    func shouldAllowDrag(_ draggingInfo: NSDraggingInfo) -> Bool {
        var shouldAccept = false
        let pasteBoard = draggingInfo.draggingPasteboard

        let filteringOptionsCount = filteringOptions[NSPasteboard.ReadingOptionKey.urlReadingContentsConformToTypes]?.count ?? 0
        let options = filteringOptionsCount > 0 ? filteringOptions : nil
        
        if pasteBoard.canReadObject(forClasses: [NSURL.self], options: options) {
            shouldAccept = true
        }
        return shouldAccept
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        reset()
        
        let allow = shouldAllowDrag(sender)
        isReceivingDrag = allow
        return allow ? .copy : NSDragOperation()
    }
    
    override func draggingExited(_ sender: NSDraggingInfo?) {
        isReceivingDrag = false
        resetView()
    }
    
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let allow = shouldAllowDrag(sender)
        return allow
    }
    
    override func performDragOperation(_ draggingInfo: NSDraggingInfo) -> Bool {
        isReceivingDrag = false
        let pasteBoard = draggingInfo.draggingPasteboard
        
        let urlResult = processURLs(pasteBoard: pasteBoard)
        if(urlResult == true){
            return true
        }
        
        resetView()
        return false
    }
    
    func performPasteOperation(pasteBoard: NSPasteboard) -> Bool {
        isReceivingDrag = false
        
        let urlResult = processURLs(pasteBoard: pasteBoard)
        if (urlResult == true) {
            return true
        }
        
        return false
    }
    
    func processURLs(pasteBoard: NSPasteboard) -> Bool{
        let filteringOptionsCount = filteringOptions[NSPasteboard.ReadingOptionKey.urlReadingContentsConformToTypes]?.count ?? 0
        let options = filteringOptionsCount > 0 ? filteringOptions : nil
        
        if let urls = pasteBoard.readObjects(forClasses: [NSURL.self], options: options) as? [URL], urls.count > 0 {
            
            if let delegate = delegate, urls.count == 1 {
                let url = urls[0]
                
                if let image = NSImage(contentsOf: url) {
                    resetView()
                    delegate.imageDragged(image: image)
                    return true
                }
            }
            
            if let delegate = delegate, let _ = self.mediaData, let image = self.image {
                delegate.imageDragged(image: image)
            }
            
            for url in urls {
                if !url.absoluteString.starts(with: "file://") {
                    continue
                }
                
                if let data = getDataFrom(url: url) {
                    chatDelegate?.attachmentAdded(url: url, data: data, image: image)
                }
                resetView()
            }
            return true
        } else if let images = pasteBoard.readObjects(forClasses: [NSImage.self], options: options) as? [NSImage], images.count > 0 {
            if let delegate = delegate, images.count == 1 {
                resetView()
                delegate.imageDragged(image: images[0])
                return true
            }
            
            for image in images {
                if let data = image.tiffRepresentation {
                    chatDelegate?.attachmentAdded(url: nil, data: data, image: image)
                }
                resetView()
            }
        }
        return false
    }
    
    func getDataFrom(url: URL) -> Data? {
        do {
            let data = try Data(contentsOf: url)
            return data
        } catch {
            return nil
        }
    }
}

extension DraggingDestinationView : MediaFullScreenDelegate {
    func willDismissView() {
        resetView()
    }
}
