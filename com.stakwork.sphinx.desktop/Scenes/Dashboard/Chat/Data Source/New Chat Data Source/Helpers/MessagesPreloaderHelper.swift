//
//  MessagesPreloaderHelper.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 18/07/2023.
//  Copyright © 2023 Tomas Timinskas. All rights reserved.
//

import Foundation

class MessagesPreloaderHelper {

    class var sharedInstance : MessagesPreloaderHelper {
        struct Static {
            static let instance = MessagesPreloaderHelper()
        }
        return Static.instance
    }

    struct ScrollState {
        var firstRowId: Int
        var difference: CGFloat
        var isAtBottom: Bool

        init(
            firstRowId: Int,
            difference: CGFloat,
            isAtBottom: Bool
        ) {
            self.firstRowId = firstRowId
            self.difference = difference
            self.isAtBottom = isAtBottom
        }
    }

    struct PreloadedMessagesState {
        var messageCellStates: [MessageTableCellState]
        var resultsControllerCount: Int

        init(
            messageCellStates: [MessageTableCellState],
            resultsControllerCount: Int
        ) {
            self.messageCellStates = messageCellStates
            self.resultsControllerCount = resultsControllerCount
        }
    }

    private let maxPreloadedChats = 5
    private var preloadedChatOrder: [Int] = []

    func releaseMemory() {
        tribesData = [:]
        linksData = [:]
    }

    var chatMessages: [Int: PreloadedMessagesState] = [:]
    var chatScrollState: [Int: ScrollState] = [:]

    var tribesData: [String: MessageTableCellState.TribeData] = [:]
    var linksData: [String: MessageTableCellState.LinkData] = [:]

    func add(
        messageStateArray: [MessageTableCellState],
        resultsControllerCount: Int,
        for chatId: Int
    ) {
        guard !messageStateArray.isEmpty else {
            return
        }

        self.chatMessages[chatId] = PreloadedMessagesState(
            messageCellStates: messageStateArray,
            resultsControllerCount: resultsControllerCount
        )

        markChatAsRecentlyPreloaded(chatId)
        trimPreloadedChatsIfNeeded()
    }

    func getPreloadedMessagesState(for chatId: Int) -> PreloadedMessagesState? {
        if let preloadedMessagesState = chatMessages[chatId], preloadedMessagesState.messageCellStates.count > 0 {
            return preloadedMessagesState
        }
        return nil
    }

    func save(
        firstRowId: Int,
        difference: CGFloat,
        isAtBottom: Bool,
        for chatId: Int
    ) {
        self.chatScrollState[chatId] = ScrollState(
            firstRowId: firstRowId,
            difference: difference,
            isAtBottom: isAtBottom
        )
    }

    func reset(
        for chatId: Int
    ) {
        self.chatScrollState.removeValue(forKey: chatId)
        self.chatMessages.removeValue(forKey: chatId)
        self.preloadedChatOrder.removeAll(where: { $0 == chatId })
    }

    func getScrollState(
        for chatId: Int,
        pinnedMessageId: Int? = nil
    ) -> ScrollState? {
        if let pinnedMessageId = pinnedMessageId {
            return ScrollState(
                firstRowId: pinnedMessageId,
                difference: 0,
                isAtBottom: false
            )
        }
        if let scrollState = chatScrollState[chatId] {
            return scrollState
        }
        return nil
    }

    private func markChatAsRecentlyPreloaded(_ chatId: Int) {
        preloadedChatOrder.removeAll(where: { $0 == chatId })
        preloadedChatOrder.append(chatId)
    }

    private func trimPreloadedChatsIfNeeded() {
        while preloadedChatOrder.count > maxPreloadedChats {
            let oldestChatId = preloadedChatOrder.removeFirst()
            chatMessages.removeValue(forKey: oldestChatId)
            chatScrollState.removeValue(forKey: oldestChatId)
        }
    }
}
