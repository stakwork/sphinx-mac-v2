//
//  AIAgentThreadingRules.swift
//  sphinx
//
//  Pure, Core-Data-free rules that make the Sphinx Agent thread- and
//  reply-aware. `AIAgentManager` maps `TransactionMessage` / `Chat` into the
//  plain value types below at the call site, so all the threading logic can
//  be unit tested without a managed object context.
//
//  These rules mirror the composer's own behaviour
//  (`NewChatViewModel+SendMessageExtension.shouldSendMessage`) and the
//  Threads list's own grouping/threshold
//  (`ThreadsListDataSource.processThreadMessages` /
//  `getThreadMessagesFrom`), so the agent never invents a different notion
//  of "thread" than what the user already sees in the app.
//

import Foundation

// MARK: - Value types

/// A Core-Data-free snapshot of the fields of a `TransactionMessage` needed
/// to make threading/reply decisions.
struct AgentMessageRef: Sendable, Equatable {
    let uuid: String?
    let threadUUID: String?
    let replyUUID: String?
    let chatId: Int?
    let isDeleted: Bool

    init(
        uuid: String?,
        threadUUID: String?,
        replyUUID: String?,
        chatId: Int?,
        isDeleted: Bool = false
    ) {
        self.uuid = uuid
        self.threadUUID = threadUUID
        self.replyUUID = replyUUID
        self.chatId = chatId
        self.isDeleted = isDeleted
    }
}

/// A Core-Data-free snapshot of the fields needed to group messages into
/// threads for `read_threads` (and for marking `THREAD ROOT` / `IN THREAD`
/// when reading a chat).
struct AgentThreadRow: Sendable, Equatable {
    let uuid: String?
    let threadUUID: String?
    let date: Date

    init(uuid: String?, threadUUID: String?, date: Date) {
        self.uuid = uuid
        self.threadUUID = threadUUID
        self.date = date
    }
}

/// Outcome of a validation rule: either the action is allowed, or it is
/// refused with a human-readable reason suitable for a `Send failed: …`
/// style message.
enum ValidationResult: Sendable, Equatable {
    case ok
    case refused(String)

    var isOK: Bool {
        if case .ok = self { return true }
        return false
    }

    /// The refusal reason, or nil if `.ok`.
    var reason: String? {
        if case .refused(let reason) = self { return reason }
        return nil
    }
}

// MARK: - Threading rules

enum AIAgentThreadingRules {

    // MARK: Wire values

    /// Works out the wire `threadUUID` / `replyUUID` pair using the same
    /// rules as the chat composer (`NewChatViewModel+SendMessageExtension`,
    /// `shouldSendMessage`), so the agent never has to invent its own
    /// formula:
    ///
    /// - Case A (no thread, no reply): `(nil, nil)`.
    /// - Case E (thread only, no reply): `(threadUUID, nil)`.
    /// - Cases B/D (reply to `R`, with or without an explicit thread):
    ///   `(threadUUID ?? R.threadUUID ?? R.replyUUID ?? R.uuid, R.uuid)`.
    ///
    /// NOTE: In a 1:1 chat a plain reply (case B) still produces a non-nil
    /// wire thread value. This is intentional — it exactly matches what the
    /// composer sends when the user swipes-to-reply in a 1:1 chat. Threads
    /// as a *listed* concept only exist in tribes (see `threadRootUUIDs`),
    /// but the wire value itself is still computed the same way everywhere.
    static func wireValues(
        threadUUID: String?,
        replyTo: AgentMessageRef?
    ) -> (thread: String?, reply: String?) {
        guard let replyTo = replyTo else {
            // Case A / Case E — no reply target, so the explicit thread (if
            // any) passes straight through.
            return (threadUUID, nil)
        }

        // Case B / Case D
        let resolvedThread = threadUUID ?? replyTo.threadUUID ?? replyTo.replyUUID ?? replyTo.uuid
        return (resolvedThread, replyTo.uuid)
    }

    // MARK: Validation

    /// Validates a message looked up as a reply target.
    static func validateReplyTarget(_ ref: AgentMessageRef?, chatId: Int) -> ValidationResult {
        guard let ref = ref else {
            return .refused("message not found")
        }
        guard let uuid = ref.uuid, !uuid.isEmpty else {
            return .refused("message is not yet confirmed and has no uuid to reply to")
        }
        if ref.isDeleted {
            return .refused("message has been deleted")
        }
        if ref.chatId != chatId {
            return .refused("message belongs to a different chat")
        }
        return .ok
    }

    /// Validates a message looked up as a thread root.
    ///
    /// Reply count is intentionally NOT checked here — posting into a root
    /// that currently has 0 or 1 replies is valid; the post itself creates
    /// or completes the thread.
    static func validateThreadRoot(
        _ ref: AgentMessageRef?,
        chatId: Int,
        isTribe: Bool
    ) -> ValidationResult {
        guard isTribe else {
            return .refused("threads are only available in tribes; this is a 1:1 chat")
        }
        guard let ref = ref else {
            return .refused("thread root message not found")
        }
        if ref.isDeleted {
            return .refused("thread root message has been deleted")
        }
        if ref.chatId != chatId {
            return .refused("thread root message belongs to a different chat")
        }
        if let threadUUID = ref.threadUUID, let uuid = ref.uuid, threadUUID != uuid {
            return .refused("message is itself part of a thread and cannot be used as a thread root")
        }
        return .ok
    }

    /// When both an explicit thread and a reply target are given, requires
    /// the reply target to actually belong to that thread (either as its
    /// root, or as one of its members) so the agent can't send into thread
    /// T a message that quotes a message from somewhere else.
    static func validateThreadReplyConsistency(
        threadUUID: String,
        replyTo: AgentMessageRef
    ) -> ValidationResult {
        if replyTo.uuid == threadUUID || replyTo.threadUUID == threadUUID {
            return .ok
        }
        return .refused("reply target is not part of the specified thread")
    }

    // MARK: Root marking / grouping

    /// Returns the set of root uuids that have 2 or more messages pointing
    /// at them — the same threshold as
    /// `ThreadsListDataSource.processThreadMessages` (`count > 1`), and the
    /// root itself is not counted. Returns an empty set when `!isTribe`,
    /// matching `TransactionMessage.getThreadMessagesFor`, which returns
    /// `[:]` for non-public-group chats (threads are tribe-only).
    static func threadRootUUIDs(
        replies: [AgentThreadRow],
        isTribe: Bool
    ) -> Set<String> {
        guard isTribe else { return [] }

        var counts: [String: Int] = [:]
        for row in replies {
            guard let threadUUID = row.threadUUID, !threadUUID.isEmpty else { continue }
            counts[threadUUID, default: 0] += 1
        }
        return Set(counts.filter { $0.value >= 2 }.map { $0.key })
    }

    /// Groups thread rows by `threadUUID`, keeps groups with 2 or more
    /// replies, and sorts by latest activity, newest first — mirroring
    /// `processThreadMessages` / `getThreadMessagesFrom` so the sort order
    /// and threshold can be tested independently of Core Data.
    static func groupThreads(
        rows: [AgentThreadRow]
    ) -> [(rootUUID: String, replyCount: Int, lastActivity: Date)] {
        var groups: [String: (count: Int, lastActivity: Date)] = [:]

        for row in rows {
            guard let threadUUID = row.threadUUID, !threadUUID.isEmpty else { continue }
            let existing = groups[threadUUID]
            let count = (existing?.count ?? 0) + 1
            let lastActivity = max(existing?.lastActivity ?? row.date, row.date)
            groups[threadUUID] = (count, lastActivity)
        }

        return groups
            .filter { $0.value.count >= 2 }
            .map { (rootUUID: $0.key, replyCount: $0.value.count, lastActivity: $0.value.lastActivity) }
            .sorted { $0.lastActivity > $1.lastActivity }
    }

    // MARK: Line formatting

    /// Builds one `read_recent_messages` / `read_unseen_messages` /
    /// `read_threads` output line:
    ///
    ///   `[sender] date (uuid=… thread=… reply=… [THREAD ROOT, n replies] [IN THREAD]): content`
    ///
    /// Sender rules:
    /// - the owner sent it → "Me"
    /// - a 1:1 chat → the caller-resolved contact display name (never the
    ///   raw `contact_name` the model typed)
    /// - a tribe → `senderAlias ?? "Unknown"` (never the tribe name)
    static func formatLine(
        isOwner: Bool,
        isTribe: Bool,
        senderAlias: String?,
        resolvedContactName: String?,
        date: Date,
        uuid: String?,
        threadUUID: String?,
        replyUUID: String?,
        isThreadRoot: Bool,
        threadReplyCount: Int,
        isInThread: Bool,
        content: String,
        dateFormatter: ISO8601DateFormatter = AIAgentThreadingRules.isoFormatter
    ) -> String {
        let sender: String
        if isOwner {
            sender = "Me"
        } else if isTribe {
            sender = senderAlias ?? "Unknown"
        } else {
            sender = resolvedContactName ?? "Unknown"
        }

        let dateStr = dateFormatter.string(from: date)

        var meta = "uuid=\(uuid ?? "pending")"
        if let threadUUID = threadUUID { meta += " thread=\(threadUUID)" }
        if let replyUUID = replyUUID { meta += " reply=\(replyUUID)" }
        if isThreadRoot {
            meta += " [THREAD ROOT, \(threadReplyCount) replies]"
        }
        if isInThread {
            meta += " [IN THREAD]"
        }

        return "[\(sender)] \(dateStr) (\(meta)): \(content)"
    }

    static let isoFormatter = ISO8601DateFormatter()
}
