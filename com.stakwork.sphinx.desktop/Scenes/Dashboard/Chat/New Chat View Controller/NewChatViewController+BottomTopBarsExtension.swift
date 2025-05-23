//
//  NewChatViewController+BottomTopBarsExtension.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 14/07/2023.
//  Copyright © 2023 Tomas Timinskas. All rights reserved.
//

import Foundation
import Cocoa

extension NewChatViewController {
    func setMessageFieldActive() {
        guard let _ = chat else {
            return
        }
        chatBottomView.setMessageFieldActive()
    }
}

extension NewChatViewController : ChatHeaderViewDelegate {
    func didClickOptionsButton() {
        guard let chat = chat else {
            return
        }
        MessageOptionsHelper.sharedInstance.showMenuForChatHeader(
            in: self.view,
            from: self.chatTopView.getOptionsButtonView(),
            with: self,
            and: chat
        )
    }
    
    func didClickThreadsButton() {
        if let chatId = chat?.id {
            let threadsListVC = ThreadsListViewController.instantiate(
                chatId: chatId,
                delegate: self
            )
          
            WindowsManager.sharedInstance.showVCOnRightPanelWindow(
                with: "threads-list".localized,
                identifier: "threads-list",
                contentVC: threadsListVC,
                shouldReplace: false,
                panelFixedWidth: true
            )
        }
    }
    
    func didClickWebAppButton() {
        WindowsManager.sharedInstance.showWebAppWindow(
            chat: chat,
            view: view
        )
    }
    
    func didClickSecondBrainAppButton() {
        WindowsManager.sharedInstance.showWebAppWindow(
            chat: chat,
            view: view,
            isAppURL: false
        )
    }
    
    func didClickMuteButton() {
        guard let chat = chat else {
            return
        }

        if chat.isPublicGroup() {
            childViewControllerContainer.showNotificaionLevelViewOn(
                parentVC: self,
                with: chat,
                delegate: self
            )
        } else {
            newChatViewModel.toggleVolume(
                completion: { chat in
                    if let chat = chat, chat.isMuted(){
                        self.messageBubbleHelper.showGenericMessageView(
                            text: "chat.muted.message".localized,
                            delay: 2.5
                        )
                    }
                }
            )
        }
    }
    
    func didClickCallButton() {
        childViewControllerContainer.showCallOptionsMenuOn(
            parentVC: self,
            with: self.chat,
            delegate: self
        )
    }
    
    func didClickHeaderButton() {
        if let contact = contact {
            
            let contactVC = ContactDetailsViewController.instantiate(
                contactId: contact.id,
                delegate: self
            )
            
            WindowsManager.sharedInstance.showVCOnRightPanelWindow(
                with: "contact.info".localized,
                identifier: "contact-window",
                contentVC: contactVC
            )
            
        } else if let chat = chat {
            
            let chatDetailsVC = GroupDetailsViewController.instantiate(
                chat: chat,
                delegate: self
            )
            
            WindowsManager.sharedInstance.showVCOnRightPanelWindow(
                with: "tribe.info".localized,
                identifier: "chat-window",
                contentVC: chatDetailsVC
            )
        }
    }
    
    func didClickSearchButton() {
        toggleSearchMode(active: true)
    }
    
    func didClickRefreshButton() {
        if let contact = self.contact {
            SphinxOnionManager.sharedInstance.retryAddingContact(contact: contact)
        }
    }
}

extension NewChatViewController : GroupDetailsDelegate {
    func shouldExitTribeOrGroup(
        completion: @escaping () -> ()
    ) {
        exitAndDeleteGroup(completion: completion)
    }
    
    func exitAndDeleteGroup(completion: @escaping () -> ()) {
//        if !NetworkMonitor.shared.isNetworkConnected() {
//            AlertHelper.showAlert(
//                title: "generic.error.title".localized,
//                message: SphinxOnionManagerError.SOMNetworkError.localizedDescription
//            )
//            return
//        }
        
        guard let chat = self.chat else {
            return
        }
        
        let isPublicGroup = chat.isPublicGroup()
        let isMyPublicGroup = chat.isMyPublicGroup()
        let deleteLabel = (isPublicGroup ? "delete.tribe" : "delete.group").localized
        let confirmDeleteLabel = (isMyPublicGroup ? "confirm.delete.tribe" : (isPublicGroup ? "confirm.exit.delete.tribe" : "confirm.exit.delete.group")).localized
        
        AlertHelper.showTwoOptionsAlert(title: deleteLabel, message: confirmDeleteLabel, confirm: {
            let som = SphinxOnionManager.sharedInstance
            var success = false
            
            if isMyPublicGroup {
                success = som.deleteTribe(tribeChat: chat)
            } else {
                success = som.exitTribe(
                    tribeChat: chat,
                    errorCallback: { error in
                        AlertHelper.showAlert(
                            title: "generic.error.title".localized,
                            message: error.localizedDescription
                        )
                    }
                )
            }
            
            if !success {
                return
            }
            
            let _ = som.deleteContactOrChatMsgsFor(chat: chat)
            
            DelayPerformedHelper.performAfterDelay(seconds: 0.5) {
                CoreDataManager.sharedManager.deleteChatObjectsFor(chat)
                completion()
                self.delegate?.shouldResetTribeView()
            }
        })
    }
}

extension NewChatViewController : ChatBottomViewDelegate {
    
    func getAttachmentObjects(
        text: String,
        price: Int
    ) -> [AttachmentObject] {
        if chatBottomView.isSendingMedia() {
            let attachmentObjects = chatBottomView.getAttachmentObjects(text: text, price: price)
            return attachmentObjects
        } else {
            if let data = text.data(using: .utf8) {
                let (key, encryptedData) = SymmetricEncryptionManager.sharedInstance.encryptData(data: data)
                
                if let encryptedData = encryptedData {
                    let attachmentObject = AttachmentObject(
                        data: encryptedData,
                        mediaKey: key,
                        type: .Text,
                        text: nil,
                        paidMessage: text,
                        price: price,
                        contactPubkey: chat?.getContact()?.publicKey
                    )
                    return [attachmentObject]
                }
            }
        }
        return []
    }
    
    func shouldSendMessage(
        text: String,
        price: Int,
        completion: @escaping (Bool) -> ()
    ) {
        chatBottomView.resetReplyView()
        ChatTrackingHandler.shared.deleteReplyableMessage(with: chat?.id)
        
        if let text = giphyText(text: text), let data = draggingView.getMediaData() {
            
            draggingView.setup()
            
            newChatViewModel.shouldSendGiphyMessage(
                text: text,
                type: TransactionMessage.TransactionMessageType.message.rawValue,
                data: data,
                completion: { (success, _) in
                    completion(success)
                }
            )
        } else if shouldUploadMedia() {
            
            let attachmentObjects = getAttachmentObjects(
                text: text,
                price: price
            )
            
            if !attachmentObjects.isEmpty {
                chatBottomView.resetAttachments()
                
                newChatViewModel.insertProvisionalAttachmentMessagesAndUpload(
                    attachmentObjects: attachmentObjects,
                    chat: chat
                )
            } else {
                messageBubbleHelper.showGenericMessageView(
                    text: "generic.error.message".localized, in: view
                )
            }
        } else {
            newChatViewModel.shouldSendMessage(
                text: text,
                type: TransactionMessage.TransactionMessageType.message.rawValue,
                provisionalMessage: nil,
                completion: { (success, _) in
                    completion(success)
                }
            )
        }
    }
    
    func shouldMainChatOngoingMessage() {
        chatVCDelegate?.shouldResetOngoingMessage()
    }
    
    func giphyText(
        text: String
    ) -> String? {
        let (sendingGiphy, giphyObject) = draggingView.isSendingGiphy()
        
        if let giphyObject = giphyObject, sendingGiphy {
            
            return GiphyHelper.getMessageStringFrom(
                media: giphyObject,
                text: text
            )
        }
        
        return nil
    }
    
    func shouldUploadMedia() -> Bool {
        return chatBottomView.isPaidTextMessage() ||
                chatBottomView.isSendingMedia()
    }
    
    func didClickAttachmentsButton() {
        guard let chat = chat else {
            return
        }
        
        if chat.isPublicGroup() {
            chatBottomView.didClickAddAttachment()
        } else {
            childViewControllerContainer.showPmtOptionsMenuOn(
                parentVC: self,
                with: chat,
                delegate: self
            )
        }
    }
    
    func didClickGiphyButton() {
        let isAtBottom = isChatAtBottom()
        
        chatBottomView.loadGiphySearchWith(delegate: self)
        
        if isAtBottom {
            shouldScrollToBottom()
        }
    }
    
    func didClickMicButton() {
        newChatViewModel.shouldStartRecordingWith(delegate: self)
    }
    
    func didClickConfirmRecordingButton() {
        newChatViewModel.didClickConfirmRecordingButton()
    }
    
    func didClickCancelRecordingButton() {
        newChatViewModel.didClickCancelRecordingButton()
    }
    
    func didSelectSendPaymentMacro() {
        childViewControllerContainer.showPaymentModeWith(
            parentVC: self,
            with: chat,
            delegate: self,
            mode: .Send
        )
    }
    
    func didSelectReceivePaymentMacro() {
        childViewControllerContainer.showPaymentModeWith(
            parentVC: self,
            with: chat,
            delegate: self,
            mode: .Request
        )
    }
    
    func hideModals() -> Bool {
        if !childViewControllerContainer.isHidden {
            childViewControllerContainer.hideView()
            return true
        }
        return false
    }
    
    func shouldUpdateMentionSuggestionsWith(
        _ object: [MentionOrMacroItem],
        text: String,
        cursorPosition: Int
    ) {
        DispatchQueue.main.async {
            if (!object.isEmpty) {
                let leadingPos = self.getCurrentPosition(
                    cursorPoint: cursorPosition - text.count,
                    isMention: object.first?.type == .mention
                )
                self.mentionScrollViewLeadingConstraints.constant = leadingPos.0
                self.mentionScrollViewBottomConstraints.constant = leadingPos.1
                self.setupCollectionView()
            }
            self.chatMentionAutocompleteDataSource?.setViewWidth(viewWidth: 170)
            self.chatMentionAutocompleteDataSource?.updateMentionSuggestions(suggestions: object)
        }
    }
    
    func getCurrentPosition(
        cursorPoint: Int,
        isMention: Bool
    ) -> (CGFloat, CGFloat) {
        // Get the layout manager and text container
        guard let layoutManager = chatBottomView.messageFieldView.messageTextView.layoutManager,
              let textContainer = chatBottomView.messageFieldView.messageTextView.textContainer else { return (0, 0) }

                // Get the glyph range for the cursor position
                let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: cursorPoint, length: 0), actualCharacterRange: nil)

                // Get the bounding rectangle for the glyph
                let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

                // Convert the glyph rect to the text view's coordinate system
                let textRectInView = chatBottomView.messageFieldView.messageTextView.convert(glyphRect, to: chatBottomView.messageFieldView.messageTextView)
        
        let attachmentsViewHeight: CGFloat = chatBottomView.messageFieldView.isAttachmentAdded ? 180 : 0

        return (
            CGFloat((isMention ? 38 : 52) + textRectInView.origin.x + textRectInView.width),
            CGFloat(22 + textRectInView.origin.y + attachmentsViewHeight)
        )
    }
    
    func shouldGetSelectedMention() -> String? {
        if let selectedValue = chatMentionAutocompleteDataSource?.getSelectedValue() {
            chatMentionAutocompleteDataSource?.updateMentionSuggestions(suggestions: [])
            return selectedValue
        }
        return nil
    }
    
    func shouldGetSelectedMacroAction() -> (() -> ())? {
        if let selectedAction = chatMentionAutocompleteDataSource?.getSelectedAction() {
            chatMentionAutocompleteDataSource?.updateMentionSuggestions(suggestions: [])
            return selectedAction
        }
        return nil
    }
    
    func didTapEscape() {
        shouldCloseThread()
    }
    
    func didTapUpArrow() -> Bool {
        chatMentionAutocompleteDataSource?.moveSelectionUp()
        return chatMentionAutocompleteDataSource?.isTableVisible() ?? false
    }
    
    func didTapDownArrow() -> Bool {
        chatMentionAutocompleteDataSource?.moveSelectionDown()
        return chatMentionAutocompleteDataSource?.isTableVisible() ?? false
    }
    
    func isChatAtBottom() -> Bool {
        return chatCollectionView.isAtBottom()
    }
    
    func shouldScrollToBottom() {
        chatCollectionView.scrollToBottom(animated: false)
    }
    
    func isMessageLengthValid(
        text: String
    ) -> Bool {
        let messageLengthValid = SphinxOnionManager.sharedInstance.isMessageLengthValid(
            text: text,
            sendingAttachment: chatBottomView.isSendingMedia(),
            threadUUID: self.newChatViewModel.replyingTo?.uuid,
            replyUUID: self.threadUUID ?? self.newChatViewModel.replyingTo?.replyUUID,
            metaDataString: chat?.getMetaDataJsonStringValue()
        )
        
        if !messageLengthValid {
            self.newMessageBubbleHelper.showGenericMessageView(
                text: "message.limit.reached".localized,
                delay: 5,
                textColor: NSColor.white,
                backColor: NSColor.Sphinx.BadgeRed,
                backAlpha: 1.0
            )
        }
        
        return messageLengthValid
    }
}

extension NewChatViewController : GiphySearchViewDelegate {
    func didSelectGiphy(object: GiphyObject, data: Data) {
        draggingView.showGiphyPreview(data: data, object: object)
        chatBottomView.toggleAttachmentsAdded(forceShowSend: draggingView.isSendingGiphy().0)
    }
}

extension NewChatViewController : AudioHelperDelegate {
    func didStartRecording(_ success: Bool) {
        if success {
            chatBottomView.toggleRecordingViews(show: true)
        }
    }
    
    func didFinishRecording(_ success: Bool) {
        if success {
            newChatViewModel.didFinishRecording()
        }
        chatBottomView.toggleRecordingViews(show: false)
    }
    
    func audioTooShort() {
        messageBubbleHelper.showGenericMessageView(text: "audio.too.short".localized, in: self.view)
    }
    
    func recordingProgress(minutes: String, seconds: String) {
        chatBottomView.recordingProgress(minutes: minutes, seconds: seconds)
    }
    
    func permissionDenied() {
        chatBottomView.toggleRecordButton(enable: false)
    }
}

extension NewChatViewController : ActionsDelegate {
    func didCreateMessage() {}
    
    func didFailInvoiceOrPayment() {
        messageBubbleHelper.showGenericMessageView(text: "generic.error.message".localized, in: view)
    }
    
    func shouldCreateCall(mode: VideoCallHelper.CallMode) {
        let link = VideoCallHelper.createCallMessage(
            mode: mode,
            secondBrainUrl: chat?.getSecondBrainUrl(),
            appUrl: chat?.getAppUrl()
        )
        newChatViewModel.sendCallMessage(link: link)
    }
    
    func shouldSendPaymentFor(
        paymentObject: PaymentViewModel.PaymentObject,
        callback: ((Bool) -> ())?
    ) {
        newChatViewModel.shouldSendPaymentFor(
            paymentObject: paymentObject,
            callback: callback
        )
    }
    
    func shouldShowAttachmentsPopup() {
        chatBottomView.didClickAddAttachment()
    }
    
    func shouldReloadMuteState() {}
    
    func didDismissView() {
        setMessageFieldActive()
    }
}

extension NewChatViewController : NewMessagesIndicatorViewDelegate {
    func didTouchButton() {
        chatCollectionView.scrollToBottom()
    }
}

extension NewChatViewController : NewChatViewControllerDelegate {
    func shouldResetOngoingMessage() {
        chatBottomView.clearMessage()
    }
}

extension NewChatViewController : ThreadsListViewControllerDelegate {
    func didSelectThreadWith(uuid: String) {
        showThread(threadID: uuid)
    }
}

extension NewChatViewController : ChatDraggingViewDelegate {
    func attachmentAdded(url: URL?, data: Data, image: NSImage?) {
        chatBottomView.attachmentAdded(url: url, data: data, image: image)
    }
    
    func imageDismissed() {
        chatBottomView.toggleAttachmentsAdded(forceShowSend: draggingView.isSendingGiphy().0)
    }
}

extension NewChatViewController : ContactDetailsViewDelegate {
    func didDeleteContact() {
        delegate?.shouldResetContactView()
    }
    
    func didTapOnAvatarImage(url: String) {
        delegate?.shouldShowFullMediaFor(url: url)
    }
}
