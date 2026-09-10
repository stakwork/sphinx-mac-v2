//
//  StrutHotwordList.swift
//  com.stakwork.sphinx.desktop
//
//  Pure helpers for dictation hotwords. Takes [String] / plain snapshots
//  only — never touches Core Data or NSManagedObject.
//

import Foundation

enum StrutHotwordList {

    static let alwaysIncluded = ["Sphinx", "Stakwork"]

    /// Case-insensitive de-dupe, drop empty/whitespace entries, always
    /// append "Sphinx" and "Stakwork" (once, case-insensitively).
    static func build(from names: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        func append(_ raw: String) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { return }
            seen.insert(key)
            result.append(trimmed)
        }

        for name in names {
            append(name)
        }
        for word in alwaysIncluded {
            append(word)
        }
        return result
    }

    /// Plain-value snapshot of the UserContact fields the filter cares about.
    /// Built on the MainActor from view-context objects; never hops an
    /// `NSManagedObject` across a Task boundary.
    struct Contact: Equatable, Sendable {
        let nickname: String?
        let isConfirmed: Bool
        let isOwner: Bool
        let isAgent: Bool
        let fromGroup: Bool
        let pin: String?
    }

    /// Confirmed, non-owner, non-agent, non-tribe-row contacts with a
    /// non-empty nickname. Pin-hidden rows (`pin != nil`) are excluded —
    /// `GroupsPinManager.isStandardPIN` is no longer live in this target
    /// and the rest of the app treats the standard-PIN case (skip `pin != nil`).
    static func nicknames(from contacts: [Contact]) -> [String] {
        contacts.compactMap { contact in
            guard contact.isConfirmed else { return nil }
            guard !contact.isOwner else { return nil }
            guard !contact.isAgent else { return nil }
            guard !contact.fromGroup else { return nil }
            guard contact.pin == nil else { return nil }
            let name = (contact.nickname ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            return name
        }
    }
}
