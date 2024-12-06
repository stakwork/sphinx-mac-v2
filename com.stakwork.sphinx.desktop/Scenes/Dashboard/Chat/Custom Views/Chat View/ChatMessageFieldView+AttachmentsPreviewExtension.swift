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
        
        toggleAttachmentsAdded()
        
        if attachments.isEmpty {
            attachmentsPreviewContainer.isHidden = true
        } else {
            attachmentsPreviewContainer.isHidden = false
        }
        
        let _ = updateBottomBarHeight(animated: true)
    }
    
    func attachmentAdded(url: URL, data: Data, image: NSImage?) {
        if attachments.count >= 10 {
            return
        }
        
        let attachment = AttachmentPreview(url: url, data: data, image: image)
        attachments.append(attachment)
        
        toggleAttachmentsAdded()
        
        attachmentsPreviewDataSource?.updateAttachments(
            attachments: self.attachments
        )

        attachmentsPreviewContainer.isHidden = false
        
        let _ = updateBottomBarHeight(animated: true)
    }
    
    func resetAttachments() {
        attachments = []
        toggleAttachmentsAdded()
        attachmentsPreviewDataSource?.updateAttachments(attachments: [])
        attachmentsPreviewContainer.isHidden = true
        let _ = updateBottomBarHeight(animated: true)
    }
}
