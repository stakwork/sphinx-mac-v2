// WebAppLogStore.swift
// Sphinx

import Foundation

@MainActor
class WebAppLogStore {

    enum LogLevel {
        case log, warn, error, info
    }

    enum LogSource {
        case jsConsole, navigation, bridgeInbound, bridgeOutbound, network
    }

    struct WebAppLogEntry {
        let id = UUID()
        let timestamp: Date
        let level: LogLevel
        let source: LogSource
        let message: String
    }

    private(set) var entries: [WebAppLogEntry] = []
    var onNewEntry: ((WebAppLogEntry) -> Void)?

    func append(_ entry: WebAppLogEntry) {
        entries.append(entry)
        onNewEntry?(entry)
    }

    func clear() {
        entries.removeAll()
    }
}
