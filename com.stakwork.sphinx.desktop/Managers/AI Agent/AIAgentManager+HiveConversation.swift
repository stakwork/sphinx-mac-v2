//
//  AIAgentManager+HiveConversation.swift
//  Sphinx
//
//  Per-org "start a new Jamie conversation" decision logic.
//
//  Jamie (Hive) conversations are stored per org in `hiveConversationIdByOrg`.
//  Historically that id was never cleared, so every `query_hive_graph` call for
//  an org kept growing the same server-side thread forever, mixing unrelated
//  topics together. This file adds:
//    - a model-driven reset (`new_conversation: true` on the tool), and
//    - an idle backstop (30 minutes of inactivity for that org),
//  both of which are blocked while a proposal in that org is still awaiting
//  approval/rejection, so approve/reject never lose their conversation context.
//
//  All mutating/decision helpers here run under `AIAgentManager.hiveCacheSync`
//  (a plain `DispatchQueue.sync`, NOT re-entrant). Anything suffixed `Locked`
//  assumes the caller already holds that lock and must never call
//  `hiveCacheSync` (or any function that does) itself — doing so deadlocks.
//

import Foundation

extension AIAgentManager {

    /// How long an org's Jamie conversation can sit idle before the next query
    /// starts a fresh one automatically (see `conversationIdForQuery`).
    static let hiveConversationIdleTimeout: TimeInterval = 30 * 60

    // MARK: - Proposal guard

    /// Pure, lock-free read of an org's canvas history. Duplicates the body of
    /// `canvasHistory(orgId:)` instead of calling it, because that function takes
    /// `hiveCacheSync` itself — calling it from inside a locked context would
    /// recursively acquire the (non-reentrant) lock and deadlock.
    private static func canvasHistoryLocked(orgId: String) -> [CanvasChatMessage] {
        guard let data: Data = UserDefaults.Keys.hiveCanvasChatHistoryByOrg.get(),
              let dict = try? JSONDecoder().decode([String: [CanvasChatMessage]].self, from: data)
        else { return [] }
        return dict[orgId] ?? []
    }

    /// True if `orgId` has a proposal that hasn't been approved or rejected yet.
    /// Assumes the caller already holds `hiveCacheSync`'s lock and never takes it
    /// itself. A proposal counts as unactioned when either:
    ///   (a) the single pending-proposal slot (`hivePendingProposal`) belongs to
    ///       this org, or
    ///   (b) this org's own canvas history has a message whose `toolCalls`
    ///       include a propose_* tool and whose `approvalResult` is still nil.
    /// (b) exists because the pending slot holds only one org's proposal at a
    /// time — if org B proposes something after org A, B's proposal replaces
    /// A's in the slot while A's card is still showing (and approvable) in the
    /// UI from A's own canvas history. Without (b), a reset for org A would not
    /// see A's still-pending card.
    ///
    /// Known limit: a proposal card that the user never approves or rejects
    /// pins that org's conversation — both the `new_conversation` flag and the
    /// idle backstop are blocked — until it is actioned. This mirrors the
    /// existing behaviour in `fetchAndCacheOrgSlugs`, which already keeps an
    /// org's conversation id alive while a proposal for that org is pending.
    static func hasUnactionedProposalLocked(orgId: String) -> Bool {
        if let data: Data = UserDefaults.Keys.hivePendingProposal.get(),
           let proposal = try? JSONDecoder().decode(PendingProposal.self, from: data),
           proposal.orgId == orgId {
            return true
        }

        let proposalNames: Set<String> = ["propose_feature", "propose_initiative", "propose_milestone"]
        let history = canvasHistoryLocked(orgId: orgId)
        return history.contains(where: { msg in
            msg.approvalResult == nil &&
            (msg.toolCalls?.contains(where: { proposalNames.contains($0.toolName) }) == true)
        })
    }

    /// Thin wrapper around `hasUnactionedProposalLocked` that takes the lock.
    /// Use this from any call site that does not already hold `hiveCacheSync`.
    static func hasUnactionedProposal(orgId: String) -> Bool {
        hiveCacheSync { hasUnactionedProposalLocked(orgId: orgId) }
    }

    // MARK: - Decision

    /// The outcome of `conversationIdForQuery`, surfaced for logging and for the
    /// short annotation appended to the tool's returned text.
    struct HiveConversationDecision {
        let requestedNew: Bool
        let idleExpired: Bool
        let blockedByProposal: Bool
        let outcome: Outcome

        enum Outcome: String {
            case continued
            case reset
        }
    }

    /// Decides whether `orgId`'s next Jamie query should continue the existing
    /// conversation or start a new one, and applies that decision (clearing only
    /// this org's stored id on reset). Runs entirely inside one `hiveCacheSync`
    /// acquisition and calls only `...Locked` helpers internally.
    ///
    /// - `idleExpired` is true when more than `hiveConversationIdleTimeout` has
    ///   passed since `hiveLastQueryAtByOrg[orgId]`. It is ALSO true when there is
    ///   no timestamp recorded but a conversation id is already stored for this
    ///   org — this retires the long-lived threads that existing users already
    ///   have, on their first query after upgrading, instead of carrying them
    ///   forward indefinitely. When there is neither a timestamp nor a stored id,
    ///   there is nothing to reset, so `idleExpired` is false (a no-op).
    /// - If (`requestNew` || `idleExpired`) and not `blockedByProposal`, this
    ///   removes only `orgId`'s entry from the conversation-id dictionary and
    ///   returns `nil` with outcome `.reset`. Otherwise it returns the stored id
    ///   (which may itself be nil if none was ever set) with outcome `.continued`.
    static func conversationIdForQuery(
        orgId: String,
        requestNew: Bool,
        now: Date
    ) -> (id: String?, decision: HiveConversationDecision) {
        hiveCacheSync {
            let lastQueryAt: Double? = {
                guard let data: Data = UserDefaults.Keys.hiveLastQueryAtByOrg.get(),
                      let dict = try? JSONDecoder().decode([String: Double].self, from: data)
                else { return nil }
                return dict[orgId]
            }()

            let storedId: String? = {
                guard let data: Data = UserDefaults.Keys.hiveConversationIdByOrg.get(),
                      let dict = try? JSONDecoder().decode([String: String].self, from: data)
                else { return nil }
                return dict[orgId]
            }()

            let idleExpired: Bool
            if let lastQueryAt = lastQueryAt {
                idleExpired = now.timeIntervalSince1970 - lastQueryAt > hiveConversationIdleTimeout
            } else {
                idleExpired = storedId != nil
            }

            let blockedByProposal = hasUnactionedProposalLocked(orgId: orgId)
            let shouldReset = (requestNew || idleExpired) && !blockedByProposal

            if shouldReset {
                if let data: Data = UserDefaults.Keys.hiveConversationIdByOrg.get(),
                   var dict = try? JSONDecoder().decode([String: String].self, from: data) {
                    dict.removeValue(forKey: orgId)
                    if let encoded = try? JSONEncoder().encode(dict) {
                        UserDefaults.Keys.hiveConversationIdByOrg.set(encoded)
                    }
                }
                let decision = HiveConversationDecision(
                    requestedNew: requestNew, idleExpired: idleExpired,
                    blockedByProposal: blockedByProposal, outcome: .reset
                )
                return (nil, decision)
            } else {
                let decision = HiveConversationDecision(
                    requestedNew: requestNew, idleExpired: idleExpired,
                    blockedByProposal: blockedByProposal, outcome: .continued
                )
                return (storedId, decision)
            }
        }
    }

    // MARK: - Compare-and-set write

    /// Writes `newId` for `orgId` only if the currently stored value equals
    /// `startedWith` (the id the stream was opened with) or already equals
    /// `newId` (idempotent retry of the same write). Otherwise the write is
    /// skipped and logged.
    ///
    /// This stops two races:
    ///   - a continuing stream that started with the OLD id finishing after a
    ///     parallel reset has already cleared/replaced that org's id — it must
    ///     not stomp the fresher value;
    ///   - a late response arriving after a reset bringing back a cleared id.
    /// When two parallel streams both start with `startedWith == nil` (e.g. two
    /// near-simultaneous resets), the first write wins and the second Hive
    /// thread is simply abandoned client-side — acceptable, since both are
    /// freshly started conversations and only one needs to be remembered.
    @discardableResult
    static func storeConversationId(orgId: String, newId: String, startedWith: String?) -> Bool {
        hiveCacheSync {
            var dict: [String: String] = [:]
            if let data: Data = UserDefaults.Keys.hiveConversationIdByOrg.get(),
               let existing = try? JSONDecoder().decode([String: String].self, from: data) {
                dict = existing
            }

            let current = dict[orgId]
            guard current == startedWith || current == newId else {
                print("AIAgent [HiveConversation] staleConversationIdIgnored org=\(orgId)")
                return false
            }

            dict[orgId] = newId
            if let encoded = try? JSONEncoder().encode(dict) {
                UserDefaults.Keys.hiveConversationIdByOrg.set(encoded)
            }
            return true
        }
    }

    // MARK: - Activity timestamp

    /// Records that `orgId` had a successful Hive turn at `date`, used by the
    /// idle backstop in `conversationIdForQuery`. Call this ONLY after a turn
    /// that actually reached Hive and completed without `onError` (a
    /// conversation id was returned, or a non-empty result came back) —
    /// token/slug resolution failures and errored streams must not count as
    /// activity, since nothing reached Hive for that org.
    static func recordHiveQuery(orgId: String, at date: Date) {
        hiveCacheSync {
            var dict: [String: Double] = [:]
            if let data: Data = UserDefaults.Keys.hiveLastQueryAtByOrg.get(),
               let existing = try? JSONDecoder().decode([String: Double].self, from: data) {
                dict = existing
            }
            dict[orgId] = date.timeIntervalSince1970
            if let encoded = try? JSONEncoder().encode(dict) {
                UserDefaults.Keys.hiveLastQueryAtByOrg.set(encoded)
            }
        }
    }
}
