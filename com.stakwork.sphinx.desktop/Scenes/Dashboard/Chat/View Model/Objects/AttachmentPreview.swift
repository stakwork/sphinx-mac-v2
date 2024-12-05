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
    var URL: String
    var name: String?
    var pagesCount: String?
    var fileSize: Int?
    
    init(
        type: TransactionMessage.TransactionMessageType,
        URL: String,
        name: String? = nil,
        pagesCount: String? = nil,
        fileSize: Int? = nil
    ) {
        self.type = type
        self.URL = URL
        self.name = name
        self.pagesCount = pagesCount
        self.fileSize = fileSize
    }
}
