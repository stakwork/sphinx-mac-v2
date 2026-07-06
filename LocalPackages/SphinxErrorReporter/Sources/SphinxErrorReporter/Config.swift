// Config.swift
// SphinxErrorReporter
//
// Configuration for the SphinxErrorReporter SDK.
// All values are injected at startup — zero host-app coupling.

import Foundation

/// Configuration object for SphinxErrorReporter.
/// Pass an instance to `SphinxErrorReporter.start(_:)` at app launch.
public struct Config: Sendable {
    /// Base URL for the Hive ingest endpoint (e.g. "https://hive.sphinx.chat/api")
    public let hiveBaseURL: URL
    /// Ingest API key (format: "hive_...")
    public let ingestKey: String
    /// Default repository slug for error reports (e.g. "stakwork/sphinx-mac-v2")
    public let mainRepo: String
    /// Optional environment tag (e.g. "production", "staging")
    public let environment: String?
    /// Optional release version string
    public let release: String?
    /// Optional git commit SHA for source-link resolution
    public let commitSha: String?
    /// Enable verbose lifecycle logging (off by default)
    public let debug: Bool

    public init(
        hiveBaseURL: URL,
        ingestKey: String,
        mainRepo: String,
        environment: String? = nil,
        release: String? = nil,
        commitSha: String? = nil,
        debug: Bool = false
    ) {
        self.hiveBaseURL = hiveBaseURL
        self.ingestKey = ingestKey
        self.mainRepo = mainRepo
        self.environment = environment
        self.release = release
        self.commitSha = commitSha
        self.debug = debug
    }
}
