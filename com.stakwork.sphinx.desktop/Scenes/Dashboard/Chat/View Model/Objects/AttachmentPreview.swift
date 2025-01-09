//
//  AttachmentPreview.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 05/12/2024.
//  Copyright © 2024 Tomas Timinskas. All rights reserved.
//

import Foundation
import AppKit

class AttachmentPreview: NSObject {
    
    var type: AttachmentsManager.AttachmentType
    var url: URL?
    var data: Data
    var image: NSImage?
    var name: String?
    var pagesCount: Int?
    var fileSize: String?

    init(
        url: URL?,
        data: Data,
        image: NSImage?
    ) {
        if let nnImage = NSImage(contentsOf: url ?? URL(fileURLWithPath: "")) ?? image {
            if url?.isPDF == true {
                self.type = .PDF
                self.url = url
                self.data = data
                self.image = nnImage
                self.name = (url?.absoluteString as? NSString)?.lastPathComponent.percentNotEscaped ?? "file.pdf"
                self.pagesCount = data.getPDFPagesCount() ?? 0
            } else if data.isAnimatedImage() {
                self.type = .Gif
                self.url = url
                self.data = data
                self.image = nnImage
            } else {
                self.type = .Photo
                self.url = url
                self.data = data
                self.image = nnImage
            }
        } else if url?.isVideo == true {
            self.type = .Video
            self.url = url
            self.data = data
            self.image = image
        } else {
            self.type = .GenericFile
            self.url = url
            self.data = data
            self.image = image
            self.name = (url?.absoluteString as? NSString)?.lastPathComponent.percentNotEscaped ?? "File"
            self.fileSize = data.formattedSize
        }
    }
}
