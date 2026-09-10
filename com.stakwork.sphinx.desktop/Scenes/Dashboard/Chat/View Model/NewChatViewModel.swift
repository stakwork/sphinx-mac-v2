//
//  NewChatViewModel.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 19/09/2023.
//  Copyright © 2023 Tomas Timinskas. All rights reserved.
//

import Foundation

@MainActor class NewChatViewModel {
    
    var chat: Chat?
    var contact: UserContact?
    var chatDataSource: NewChatTableDataSource? = nil
    
//    var chatLeaderboard : [ChatLeaderboardEntry] = [ChatLeaderboardEntry]()
//    var availableBadges : [Badge] = [Badge]()
    
    var podcastComment: PodcastComment? = nil
    var replyingTo: TransactionMessage? = nil
    var threadUUID: String? = nil
    
    var audioRecorderHelper = AudioRecorderHelper.shared

    // MARK: - Dictation (owned by NewChatViewModel+DictationExtension)

    enum DictationPhase {
        case idle
        case connecting
        case dictating
        case stopping
    }

    var dictationPhase: DictationPhase = .idle
    var dictationGeneration: Int = 0
    var dictationClient: StrutDictationClient?
    var dictationDisplay = ComposerDictationDisplay()
    var dictationConnectingTask: Task<Void, Never>?
    var holdsDictationOccupancy = false
    /// Occupancy-minted session id. Never read from composer text or callers.
    var dictationSessionId: String?
    /// Survives idle until send success, leave, voice-note, or the next start.
    var pendingCorrection: (session: String, prefix: String, committed: String)?

    var onDictationTextChanged: ((String) -> Void)?
    var onDictationActiveChanged: ((Bool) -> Void)?
    var onDictationFailed: ((String) -> Void)?
    var dictationPrefixProvider: (() -> String)?
    
    init(
        chat: Chat?,
        contact: UserContact?,
        threadUUID: String? = nil
    ) {
        self.chat = chat
        self.contact = contact
        self.threadUUID = threadUUID
    }
    
    func setDataSource(_ dataSource: NewChatTableDataSource?) {
        self.chatDataSource = dataSource
    }
    
    ///Volume
    func toggleVolume(
        completion: @escaping (Chat?) -> ()
    ) {
        guard let chat = chat else {
            return
        }
        
        let currentMode = chat.isMuted()
        
        SphinxOnionManager.sharedInstance.toggleChatSound(
            chatId: chat.id,
            muted: !currentMode,
            completion: { chat in
                completion(chat)
            }
        )
    }
    
    ///Leaderboard and badges
//    func loadBadgesAndLeaderboard() {
//        getChatLeaderboards()
//        getChatBadges()
//    }
    
//    func getChatLeaderboards() {
//        if let uuid = chat?.tribeInfo?.uuid {
//            API.sharedInstance.getTribeLeaderboard(
//                tribeUUID: uuid,
//                callback: { results in
//                    if let chatLeaderboardEntries = Mapper<ChatLeaderboardEntry>().mapArray(JSONObject: Array(results)) {
//                        self.chatLeaderboard = chatLeaderboardEntries
//                    }
//                },
//                errorCallback: {}
//            )
//        }
//    }
//
//    func getChatBadges(){
//        if let chat = chat, let tribeInfo = chat.tribeInfo {
//            API.sharedInstance.getAssetsByID(
//                assetIDs: tribeInfo.badgeIds,
//                callback: { results in
//                    self.availableBadges = results
//                },
//                errorCallback: {}
//            )
//        }
//    }
//
//    func getLeaderboardEntryFor(message: TransactionMessage) -> ChatLeaderboardEntry? {
//        return chatLeaderboard.filter({ $0.alias == message.senderAlias }).first
//    }
    
    ///Mentions
    func getMentionsFrom(mentionText: String) -> [(String, String)] {
        var possibleMentions: [(String, String)] = []
        
        if mentionText.count > 0 {
            for alias in self.chat?.aliasesAndPics ?? [] {
                if (mentionText.count > alias.0.count) {
                    continue
                }
                let substring = alias.0.substring(range: NSRange(location: 0, length: mentionText.count))
                if (substring.lowercased() == mentionText && mentionText.isNotEmpty) {
                    possibleMentions.append(alias)
                }
            }
        }
        
        return possibleMentions
    }
    
    @MainActor func wasTimezoneNotSentRecently() -> Bool {
        return chatDataSource?.timezoneNotSentRecently ?? true
    }
    
    ///Reply view
    func resetReply() {
        podcastComment = nil
        replyingTo = nil
    }
}
