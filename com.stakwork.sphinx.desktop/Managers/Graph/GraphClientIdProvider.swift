//
//  GraphClientIdProvider.swift
//  sphinx
//
import Foundation

protocol GraphClientIdProviding: Sendable {
    func clientId() throws -> String
}

/// Uses `UserData.accountUUID` (UserDefaults-backed, generated on first read, so never
/// nil). See docs/graph-journal-core.md for the findings behind this choice.
struct AccountUUIDClientIdProvider: GraphClientIdProviding {

    func clientId() throws -> String {
        let id = UserData.sharedInstance.accountUUID
        guard !id.isEmpty else {
            throw GraphJournalError.emptyClientId
        }
        return id
    }
}
