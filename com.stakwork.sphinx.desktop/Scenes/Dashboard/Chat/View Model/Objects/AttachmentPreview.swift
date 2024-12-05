//
//  AttachmentPreview.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 05/12/2024.
//  Copyright © 2024 Tomas Timinskas. All rights reserved.
//

import Foundation

class AttachmentPreview: NSObject {
    
    var type: TransactionMessage.TransactionMessageType
    var isAnimated: Bool = false
    var url: URL?
    var data: Data?
    var image: NSImage?
    var name: String?
    var pagesCount: Int?
    var fileSize: String?

    init(
        url: URL,
        data: Data?,
        image: NSImage?
    ) {
        if let image = NSImage(contentsOf: url) {
            if url.isPDF {
                self.type = .pdfAttachment
                self.url = url
                self.data = data
                self.image = image
                self.name = (url.absoluteString as NSString).lastPathComponent.percentNotEscaped ?? "file.pdf"
                self.pagesCount = data?.getPDFPagesCount() ?? 0
            } else if data?.isAnimatedImage() == true {
                self.type = .imageAttachment
                self.url = url
                self.data = data
                self.image = image
                self.isAnimated = true
            } else {
                self.type = .imageAttachment
                self.url = url
                self.data = data
                self.image = image
            }
        } else if url.isVideo {
            self.type = .videoAttachment
            self.url = url
            self.data = data
            self.image = image
        } else {
            self.type = .fileAttachment
            self.url = url
            self.data = data
            self.image = image
            self.name = (url.absoluteString as NSString).lastPathComponent.percentNotEscaped ?? "File"
            self.fileSize = data?.formattedSize
        }
    }
}
