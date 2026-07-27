// SDKLogger.swift
// SphinxErrorReporter
//
// Opt-in debug logger (Config.debug = true to enable).
// Logs only lifecycle boundaries — never payload/key contents.

import Foundation

enum SDKLogger {
    static func log(_ message: String, config: Config?) {
        guard config?.debug == true else { return }
        print("[SphinxErrorReporter] \(message)")
    }
}
