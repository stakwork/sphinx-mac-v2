// Transport.swift
// SphinxErrorReporter
//
// Async URLSession POST to POST /api/webhook/errors.
// Auth: Authorization: Bearer <key>, x-api-key fallback header.
// Never throws to caller — errors flow to ReportStore for retry.

import Foundation

/// Internal transport layer. Wraps URLSession; injectable for tests.
final class Transport: @unchecked Sendable {

    // MARK: - Properties

    private let session: URLSession
    private let config: Config

    init(config: Config, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    // MARK: - Send

    /// POST a single ErrorReport. Returns true on 2xx, false otherwise.
    /// Never throws; failure is silent (caller decides retry).
    @discardableResult
    func send(_ report: ErrorReport, completion: ((Bool) -> Void)? = nil) -> Bool {
        guard let request = buildRequest(for: report) else {
            SDKLogger.log("Transport: failed to build request", config: config)
            completion?(false)
            return false
        }

        // Fire-and-forget on background queue
        let task = session.dataTask(with: request) { [weak self] _, response, error in
            guard let self = self else { return }
            if let error = error {
                SDKLogger.log("Transport: send failed — \(error.localizedDescription)", config: self.config)
                completion?(false)
                return
            }
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let success = (200..<300).contains(statusCode)
            SDKLogger.log("Transport: send status \(statusCode)", config: self.config)
            completion?(success)
        }
        task.resume()
        return true
    }

    // MARK: - Request builder

    private func buildRequest(for report: ErrorReport) -> URLRequest? {
        let url = config.hiveBaseURL.appendingPathComponent("webhook/errors")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Primary auth header
        request.setValue("Bearer \(config.ingestKey)", forHTTPHeaderField: "Authorization")
        // Fallback header (server checks both)
        request.setValue(config.ingestKey, forHTTPHeaderField: "x-api-key")

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        do {
            request.httpBody = try encoder.encode(report)
        } catch {
            SDKLogger.log("Transport: JSON encode error — \(error)", config: config)
            return nil
        }
        return request
    }
}
