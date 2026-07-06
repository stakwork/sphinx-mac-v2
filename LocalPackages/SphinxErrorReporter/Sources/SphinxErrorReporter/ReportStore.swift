// ReportStore.swift
// SphinxErrorReporter
//
// Disk-persistent queue for ErrorReports.
// Flushes on start() and on NWPathMonitor reconnect.
// Deletes a report only after confirmed 2xx.
// Fails silently. Capped retry (max 5 attempts per report).

import Foundation
import Network

/// Persistent disk queue + delivery engine.
final class ReportStore: @unchecked Sendable {

    // MARK: - Constants

    private static let maxRetries = 5
    private static let queueDirName = "SphinxErrorReporter"
    private static let retryKey = "retryCount"

    // MARK: - State

    private let queue = DispatchQueue(label: "com.sphinxerror.reportstore", qos: .utility)
    private var transport: Transport?
    private var monitor: NWPathMonitor?
    private var monitorQueue: DispatchQueue?
    private let storeDir: URL

    // MARK: - Init

    init() {
        // Resolve storage dir under Application Support
        let base: URL
        if let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            base = appSupport
        } else {
            base = FileManager.default.temporaryDirectory
        }
        storeDir = base.appendingPathComponent(ReportStore.queueDirName, isDirectory: true)
        try? FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
    }

    // MARK: - Configuration

    func configure(transport: Transport, config: Config) {
        self.transport = transport
        startNetworkMonitor(config: config)
    }

    // MARK: - Public API

    /// Enqueue a report for delivery. Persists to disk then tries to send.
    func enqueue(_ report: ErrorReport) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.persist(report)
            self.flushPending()
        }
    }

    /// Persist synchronously (used from crash handler — avoids dispatch_async).
    func persistSync(_ report: ErrorReport) {
        persist(report)
    }

    /// Flush all pending reports (called at startup and on reconnect).
    func flush() {
        queue.async { [weak self] in
            self?.flushPending()
        }
    }

    // MARK: - Persistence helpers

    private func persist(_ report: ErrorReport) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(report) else { return }
        let filename = "\(UUID().uuidString).json"
        let fileURL = storeDir.appendingPathComponent(filename)
        try? data.write(to: fileURL, options: .atomic)
    }

    private func flushPending() {
        guard let transport = transport else { return }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: storeDir,
            includingPropertiesForKeys: nil
        )) ?? []

        SDKLogger.log("ReportStore: flushing \(files.count) pending report(s)", config: nil)

        for fileURL in files where fileURL.pathExtension == "json" {
            deliverFile(fileURL, transport: transport)
        }
    }

    private func deliverFile(_ fileURL: URL, transport: Transport) {
        guard let data = try? Data(contentsOf: fileURL) else {
            // Unreadable file — remove it
            try? FileManager.default.removeItem(at: fileURL)
            return
        }

        // Check retry count via xattr-based metadata (encoded as a separate sidecar)
        let retryCount = getRetryCount(for: fileURL)
        if retryCount >= ReportStore.maxRetries {
            SDKLogger.log("ReportStore: dropping report after \(retryCount) retries", config: nil)
            try? FileManager.default.removeItem(at: fileURL)
            return
        }

        guard let report = try? JSONDecoder().decode(ErrorReport.self, from: data) else {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }

        transport.send(report) { [weak self] success in
            guard let self = self else { return }
            if success {
                SDKLogger.log("ReportStore: delivered — removing \(fileURL.lastPathComponent)", config: nil)
                try? FileManager.default.removeItem(at: fileURL)
            } else {
                self.incrementRetryCount(for: fileURL)
            }
        }
    }

    // MARK: - Retry count (stored in a sidecar .retries file)

    private func sidecarURL(for fileURL: URL) -> URL {
        fileURL.deletingPathExtension().appendingPathExtension("retries")
    }

    private func getRetryCount(for fileURL: URL) -> Int {
        let sc = sidecarURL(for: fileURL)
        guard let data = try? Data(contentsOf: sc),
              let count = Int(String(data: data, encoding: .utf8) ?? "") else {
            return 0
        }
        return count
    }

    private func incrementRetryCount(for fileURL: URL) {
        let sc = sidecarURL(for: fileURL)
        let current = getRetryCount(for: fileURL)
        let data = "\(current + 1)".data(using: .utf8)!
        try? data.write(to: sc, options: .atomic)
    }

    // MARK: - Network monitoring

    private func startNetworkMonitor(config: Config) {
        let monitor = NWPathMonitor()
        let monitorQ = DispatchQueue(label: "com.sphinxerror.netmonitor", qos: .utility)
        monitor.pathUpdateHandler = { [weak self] path in
            if path.status == .satisfied {
                SDKLogger.log("ReportStore: network reconnected — flushing", config: config)
                self?.flush()
            }
        }
        monitor.start(queue: monitorQ)
        self.monitor = monitor
        self.monitorQueue = monitorQ
    }
}
