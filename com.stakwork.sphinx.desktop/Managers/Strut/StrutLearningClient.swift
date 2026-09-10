//
//  StrutLearningClient.swift
//  com.stakwork.sphinx.desktop
//
//  Fire-and-forget POST/PUT helper for the optional Strut learning loop.
//  Failures are logged and swallowed; callers must never await this before
//  opening the mic or sending a message.
//

import Foundation

/// `@unchecked Sendable` because URLSession delegate callbacks arrive on a
/// session queue and `URLSession` itself is not Sendable under complete
/// checking — same pattern as `StrutModelInstaller` / `StrutConnection`.
final class StrutLearningClient: NSObject, @unchecked Sendable {

    private static let requestTimeout: TimeInterval = 8
    private static let resourceTimeout: TimeInterval = 8

    private let session: URLSession

    /// Process-wide client so fire-and-forget `Task { await shared.postCorrection(...) }`
    /// does not deallocate the session mid-request. Tests construct their own
    /// instance with a stub `URLSessionConfiguration`.
    nonisolated(unsafe) static let shared = StrutLearningClient()

    static func makeShortTimeoutConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return configuration
    }

    init(
        sessionConfiguration: URLSessionConfiguration = StrutLearningClient.makeShortTimeoutConfiguration()
    ) {
        let delegate = StrutLearningSessionDelegate()
        self.session = URLSession(
            configuration: sessionConfiguration,
            delegate: delegate,
            delegateQueue: nil
        )
        super.init()
        delegate.owner = self
    }

    deinit {
        session.invalidateAndCancel()
    }

    // MARK: - Entry points (never throw)

    func postCorrection(
        sessionId: String,
        text: String,
        ready: StrutReadyConnection
    ) async {
        if let schemeError = StrutURLSchemePolicy.validate(ready.baseURL) {
            logDisallowedScheme(schemeError, ready: ready)
            return
        }
        guard Self.isValidSessionId(sessionId) else {
            AppLogger.shared.log(
                level: .error,
                message: "[StrutLearning] invalid session id host=\(ready.baseURL.host ?? "") path=/audio/sessions"
            )
            return
        }

        let url = ready.baseURL
            .appendingPathComponent("audio")
            .appendingPathComponent("sessions")
            .appendingPathComponent(sessionId)
            .appendingPathComponent("corrections")

        await sendJSON(
            method: "POST",
            url: url,
            body: ["text": text],
            authorization: ready.authorizationHeaderValue,
            logContext: "session=\(sessionId)"
        )
    }

    func putHotwords(
        name: String,
        words: [String],
        ready: StrutReadyConnection
    ) async {
        if let schemeError = StrutURLSchemePolicy.validate(ready.baseURL) {
            logDisallowedScheme(schemeError, ready: ready)
            return
        }
        guard Self.isValidHotwordName(name) else {
            AppLogger.shared.log(
                level: .error,
                message: "[StrutLearning] invalid hotword name host=\(ready.baseURL.host ?? "") path=/audio/hotwords"
            )
            return
        }

        let url = ready.baseURL
            .appendingPathComponent("audio")
            .appendingPathComponent("hotwords")
            .appendingPathComponent(name)

        await sendJSON(
            method: "PUT",
            url: url,
            body: ["words": words],
            authorization: ready.authorizationHeaderValue,
            logContext: "words.count=\(words.count)"
        )
    }

    // MARK: - Validation

    /// Occupancy-minted `UUID().uuidString` only. Reject path/query characters
    /// the same way `StrutModelInstaller.isValidModelId` does, then require
    /// `UUID(uuidString:)`.
    static func isValidSessionId(_ id: String) -> Bool {
        if id.isEmpty { return false }
        if id.contains("/") || id.contains("\\") { return false }
        if id.contains("..") { return false }
        if id.contains("?") || id.contains("#") { return false }
        if id.contains("://") { return false }
        return UUID(uuidString: id) != nil
    }

    static func isValidHotwordName(_ name: String) -> Bool {
        if name.isEmpty { return false }
        if name.contains("/") || name.contains("\\") { return false }
        if name.contains("..") { return false }
        if name.contains("?") || name.contains("#") { return false }
        if name.contains("://") { return false }
        return true
    }

    // MARK: - Request

    private func sendJSON(
        method: String,
        url: URL,
        body: [String: Any],
        authorization: String,
        logContext: String
    ) async {
        let host = url.host ?? ""
        let path = url.path

        guard let json = try? JSONSerialization.data(
            withJSONObject: body,
            options: []
        ) else {
            AppLogger.shared.log(
                level: .error,
                message: "[StrutLearning] JSON encode failed host=\(host) path=\(path) \(logContext)"
            )
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = json
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (_, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let ok = (200...299).contains(status)
            AppLogger.shared.log(
                level: ok ? .info : .error,
                message: "[StrutLearning] \(method) host=\(host) path=\(path) status=\(status) \(logContext)"
            )
        } catch {
            AppLogger.shared.log(
                level: .error,
                message: "[StrutLearning] \(method) failed host=\(host) path=\(path) \(logContext)"
            )
        }
    }

    private func logDisallowedScheme(
        _ error: StrutModelInstallError,
        ready: StrutReadyConnection
    ) {
        let scheme: String
        let host: String
        if case .disallowedScheme(let s, let h) = error {
            scheme = s
            host = h
        } else {
            scheme = ready.baseURL.scheme ?? ""
            host = ready.baseURL.host ?? ""
        }
        AppLogger.shared.log(
            level: .error,
            message: "[StrutLearning] disallowed scheme \(scheme) host=\(host) path=\(ready.baseURL.path)"
        )
    }

    // MARK: - Delegate plumbing

    fileprivate func handleRedirect(
        task: URLSessionTask,
        response: HTTPURLResponse,
        newRequest: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        let original = task.originalRequest?.url
        if let sanitized = StrutRedirectPolicy.followRequestStrippingAuthorization(
            originalURL: original,
            newRequest: newRequest
        ) {
            completionHandler(sanitized)
            return
        }
        AppLogger.shared.log(
            level: .error,
            message: "[StrutLearning] redirect refused host=\(original?.host ?? "") path=\(original?.path ?? "") status=\(response.statusCode)"
        )
        completionHandler(nil)
    }
}

// MARK: - URLSession delegate (separate object to avoid session ↔ client cycle)

private final class StrutLearningSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    weak var owner: StrutLearningClient?

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let owner else {
            completionHandler(nil)
            return
        }
        owner.handleRedirect(
            task: task,
            response: response,
            newRequest: request,
            completionHandler: completionHandler
        )
    }
}
