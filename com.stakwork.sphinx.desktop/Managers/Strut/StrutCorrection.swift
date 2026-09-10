//
//  StrutCorrection.swift
//  com.stakwork.sphinx.desktop
//
//  Pure helpers for the optional dictation learning-loop correction POST.
//  No networking, no UI — callers decide when to snapshot, discard, or send.
//

import Foundation

enum StrutCorrection {

    /// Occupancy-minted `UUID().uuidString` only. Rejects path/query
    /// characters the same way `StrutLearningClient.isValidSessionId` does.
    static func isValidSession(_ session: String) -> Bool {
        StrutLearningClient.isValidSessionId(session)
    }

    /// Leave and voice-note stops must never produce a correction POST.
    static func shouldDiscardPending(reason: String) -> Bool {
        reason == "leave" || reason == "voice note"
    }

    /// Snapshot after `stopAndWait` (send / user-toggle). Leave and voice-note
    /// drop any pending record. Empty finals on send/toggle keep `existing`
    /// so a leftover user-toggle snapshot is not wiped by a connecting cancel.
    static func pendingRecordAfterStop(
        reason: String,
        session: String?,
        prefix: String,
        committed: String,
        existing: (session: String, prefix: String, committed: String)? = nil
    ) -> (session: String, prefix: String, committed: String)? {
        if shouldDiscardPending(reason: reason) { return nil }
        return makePendingSnapshot(
            session: session,
            prefix: prefix,
            committed: committed
        ) ?? existing
    }

    /// Snapshot only when the session is a real UUID and at least one
    /// non-whitespace final was committed.
    static func makePendingSnapshot(
        session: String?,
        prefix: String,
        committed: String
    ) -> (session: String, prefix: String, committed: String)? {
        guard let session, isValidSession(session) else { return nil }
        let trimmed = committed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return (session: session, prefix: prefix, committed: committed)
    }

    /// On a successful send, returns the span to POST (or `nil` for send-as-is
    /// / isolation failure). Callers must clear their stored pending record
    /// after this returns so a retry cannot double-POST; a failed send must
    /// not call this, so the same record remains for the retry.
    static func consumeOnSuccessfulSend(
        pending: (session: String, prefix: String, committed: String)?,
        sent: String
    ) -> String? {
        guard let pending else { return nil }
        return shouldPostCorrection(
            session: pending.session,
            prefix: pending.prefix,
            committed: pending.committed,
            sent: sent
        )
    }

    /// Returns the dictated span to POST, or `nil` when this send is not a
    /// correction (invalid session, empty finals, send-as-is, or the
    /// pre-dictation prefix was edited so isolation fails).
    static func shouldPostCorrection(
        session: String,
        prefix: String,
        committed: String,
        sent: String
    ) -> String? {
        guard isValidSession(session) else { return nil }

        let trimmedCommitted = committed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCommitted.isEmpty else { return nil }

        let span: String
        if prefix.isEmpty {
            span = sent.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if sent.hasPrefix(prefix) {
            span = String(sent.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            // User edited the pre-dictation prefix — never POST it as audio.
            return nil
        }

        if span == trimmedCommitted {
            return nil
        }
        return span
    }
}
