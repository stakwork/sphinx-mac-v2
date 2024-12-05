//
//  ChatMessageFieldView+AttachmentsPreviewExtension.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 05/12/2024.
//  Copyright © 2024 Tomas Timinskas. All rights reserved.
//

import Foundation

extension ChatMessageFieldView : AttachmentPreviewDataSourceDelegate {
    func shouldRemoveItemAt(index: Int) {
        attachments.remove(at: index)
        
        attachmentsPreviewDataSource?.updateAttachments(
            attachments: self.attachments
        )
        
        if attachments.isEmpty {
            toggleAttachmentAdded(false)
            attachmentsPreviewContainer.isHidden = true
        } else {
            attachmentsPreviewContainer.isHidden = false
        }
        
        let _ = updateBottomBarHeight(animated: true)
    }
    
    func attachmentAdded(url: URL, data: Data?, image: NSImage?) {
        if attachments.count >= 10 {
            return
        }
        
        toggleAttachmentAdded(true)
        
        let attachment = AttachmentPreview(url: url, data: data, image: image)
        attachments.append(attachment)
        
        attachmentsPreviewDataSource?.updateAttachments(
            attachments: self.attachments
        )

        attachmentsPreviewContainer.isHidden = false
        
        let _ = updateBottomBarHeight(animated: true)
    }
}
