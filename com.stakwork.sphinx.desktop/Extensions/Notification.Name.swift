//
//  Notification.Name.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 02/06/2020.
//  Copyright © 2020 Sphinx. All rights reserved.
//

import Foundation

extension Notification.Name {
    static let onBalanceDidChange = Notification.Name("onBalanceDidChange")
    static let shouldUpdateDashboard = Notification.Name("shouldUpdateDashboard")
    static let shouldResetChat = Notification.Name("shouldResetChat")
    static let shouldReloadViews = Notification.Name("shouldReloadViews")
    static let shouldReloadChatLists = Notification.Name("shouldReloadChatLists")
    static let shouldReloadTribeData = Notification.Name("shouldReloadTribeData")
    static let onPubKeyClick = Notification.Name("onPubKeyClick")
    static let onJoinTribeClick = Notification.Name("onJoinTribeClick")
    static let chatNotificationClicked = Notification.Name("chatNotificationClicked")
    static let onConnectionStatusChanged = Notification.Name.init("onConnectionStatusChanged")
    static let screenIsLocked = Notification.Name.init("com.apple.screenIsLocked")
    static let onInterfaceThemeChanged = Notification.Name("AppleInterfaceThemeChangedNotification")
    
    static let onAuthDeepLink = Notification.Name("onAuthDeepLink")
    static let onPersonDeepLink = Notification.Name("onPersonDeepLink")
    static let onSaveProfileDeepLink = Notification.Name("onSaveProfileDeepLink")
    static let onStakworkAuthDeepLink = Notification.Name("onStakworkAuthDeepLink")
    static let onRedeemSatsDeepLink = Notification.Name("onRedeemSatsDeepLink")
    static let onInvoiceDeepLink = Notification.Name("onInvoiceDeepLink")
    static let onShareContentDeeplink = Notification.Name("onShareContentDeeplink")
    static let onShareContactDeeplink = Notification.Name("onShareContactDeeplink")
    
    static let onContactsAndChatsChanged = Notification.Name("onContactsAndChatsChanged")
    static let onFilePaste = Notification.Name("onImagePaste")
    static let webViewImageClicked = Notification.Name("webViewImageClicked")
    
    static let onMQTTConnectionStatusChanged = Notification.Name("onMQTTConnectionStatusChanged")
    static let newOnionMessageWasReceived = Notification.Name("newOnionMessageWasReceived")
    static let invoiceIPaidSettled = Notification.Name("invoiceIPaidSettled")
    static let sentInvoiceSettled = Notification.Name("sentInvoiceSettled")
    
    static let shouldCloseRightPanel = Notification.Name("shouldCloseRightPanel")
    
    static let connectedToInternet = Notification.Name("connectedToInternet")
    static let disconnectedFromInternet = Notification.Name("disconnectedFromInternet")
    static let onKeysendStatusReceived = Notification.Name("onKeysendStatusReceived")
    
    static let refreshFeedDataAndUI = Notification.Name(rawValue: "refreshFeedDataAndUI")
    static let onPodcastPlayerClosed = Notification.Name(rawValue: "onPodcastPlayerClosed")
    static let refreshFeedUI = Notification.Name(rawValue: "refreshFeedUI")
    static let onGraphLabelChanged = Notification.Name(rawValue: "onGraphLabelChanged")
}
