//
//  ChatMessageFieldView+AttachmentsPreviewExtension.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 05/12/2024.
//  Copyright © 2024 Tomas Timinskas. All rights reserved.
//

import Cocoa

extension ChatMessageFieldView : AttachmentPreviewDataSourceDelegate {
    func shouldRemoveItemAt(index: Int?) {
        let index = index ?? attachments.count - 1
        
        if index > attachments.count - 1 {
            return
        }
        
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
        
        ChatTrackingHandler.shared.saveOngoingAttachments(attachments, chatId: chat?.id, threadUUID: threadUUID)
        
        let _ = updateBottomBarHeight(animated: true)
    }
    
    func attachmentAdded(url: URL?, data: Data, image: NSImage?) {
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
        
        ChatTrackingHandler.shared.saveOngoingAttachments(attachments, chatId: chat?.id, threadUUID: threadUUID)
        
        let _ = updateBottomBarHeight(animated: true)
    }
    
    func resetAttachments() {
        attachments = []
        toggleAttachmentsAdded()
        attachmentsPreviewDataSource?.updateAttachments(attachments: [])
        attachmentsPreviewContainer.isHidden = true
        ChatTrackingHandler.shared.deleteOngoingAttachments(with: chat?.id, threadUUID: threadUUID)
        let _ = updateBottomBarHeight(animated: true)
    }
    
    func setOngoingAttachments() {
        guard let saved = ChatTrackingHandler.shared.getOngoingAttachmentsFor(
            chatId: chat?.id, threadUUID: threadUUID
        ), !saved.isEmpty else { return }
        
        attachments = saved
        toggleAttachmentsAdded()
        attachmentsPreviewDataSource?.updateAttachments(attachments: attachments)
        attachmentsPreviewContainer.isHidden = false
        let _ = updateBottomBarHeight(animated: false)
    }
    
    func didClickAddAttachment() {
        let openPanel = NSOpenPanel()

        openPanel.title = "Choose a File"
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = true

        openPanel.begin { response in
            if response == .OK {
                for url in openPanel.urls {
                    if !url.absoluteString.starts(with: "file://") {
                        continue
                    }
                    
                    if let data = self.getDataFrom(url: url) {
                        self.attachmentAdded(url: url, data: data, image: nil)
                    }
                }
            }
        }
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
