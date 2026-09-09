//
//  StrutModelInstaller.swift
//  com.stakwork.sphinx.desktop
//
//  One-time speech-model install against a captured StrutReadyConnection.
//  Caller supplies a ready connection; this type never probes health and
//  never uses the 3-second ephemeral session.
//

import Foundation

// MARK: - Scheme allowlist (shared with the dictation client)

enum StrutRedirectPolicy {
    static func isSameHost(_ original: URL?, _ next: URL?) -> Bool {
        guard let originalHost = original?.host?.lowercased(),
              let nextHost = next?.host?.lowercased(),
              !originalHost.isEmpty,
              !nextHost.isEmpty else {
            return false
        }
        return originalHost == nextHost
    }
}

enum StrutURLSchemePolicy {

    static func isLoopbackHost(_ host: String?) -> Bool {
        guard let host else { return false }
        let lowered = host.lowercased()
        return lowered == "127.0.0.1"
            || lowered == "localhost"
            || lowered == "::1"
            || lowered == "[::1]"
    }

    /// `http`/`ws` only for loopback; every other host requires `https`/`wss`.
    static func validate(_ url: URL) -> StrutModelInstallError? {
        let scheme = (url.scheme ?? "").lowercased()
        let host = url.host ?? ""
        switch scheme {
        case "https", "wss":
            return nil
        case "http", "ws":
            if isLoopbackHost(url.host) { return nil }
            return .disallowedScheme(scheme: scheme, host: host)
        default:
            return .disallowedScheme(scheme: scheme, host: host)
        }
    }
}

// MARK: - Errors

enum StrutModelInstallError: Error, Equatable, Sendable {
    case disallowedScheme(scheme: String, host: String)
    case httpStatus(Int)
    case sttUnavailable
    case invalidModelId(String)
    case missingDefaultModels
    case downloadFailed(String)
    case invalidResponse
    case redirectRefused
    case stalled
    case transport
}

// MARK: - DTOs (locked contract)

struct StrutAudioModelsResponse: Decodable, Sendable {
    let available: Bool
    let models: [StrutAudioModelEntry]
}

struct StrutAudioModelEntry: Decodable, Sendable {
    let id: String
    let role: String
    let isDefault: Bool
    let installed: Bool

    enum CodingKeys: String, CodingKey {
        case id, role, installed
        case isDefault = "default"
    }
}

typealias StrutModelProgressHandler = @Sendable (
    _ phase: String?,
    _ received: Int?,
    _ total: Int?
) -> Void

// MARK: - Installer

/// `@unchecked Sendable` because URLSession delegate callbacks arrive on a
/// session queue and mutable per-task state is serialized by `NSLock` — the
/// same pattern as `GraphChatSSEManager` / `StrutConnection`.
final class StrutModelInstaller: NSObject, @unchecked Sendable {

    private static let resourceTimeout: TimeInterval = 15 * 60
    private static let requestTimeout: TimeInterval = 60

    private let ready: StrutReadyConnection
    private let session: URLSession
    private let lock = NSLock()
    private var tasks: [Int: TaskBox] = [:]

    static func makeLongTimeoutConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return configuration
    }

    init(
        ready: StrutReadyConnection,
        sessionConfiguration: URLSessionConfiguration = StrutModelInstaller.makeLongTimeoutConfiguration()
    ) {
        self.ready = ready
        let delegate = StrutModelSessionDelegate()
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

    func install(
        progress: StrutModelProgressHandler? = nil,
        completion: @escaping @Sendable (Result<Void, StrutModelInstallError>) -> Void
    ) {
        Task {
            let result = await self.install(progress: progress)
            completion(result)
        }
    }

    func install(
        progress: StrutModelProgressHandler? = nil
    ) async -> Result<Void, StrutModelInstallError> {
        if let schemeError = StrutURLSchemePolicy.validate(ready.baseURL) {
            return .failure(schemeError)
        }

        let host = ready.baseURL.host ?? ""
        AppLogger.shared.log(
            level: .info,
            message: "[StrutModels] Install started host=\(host) path=/audio/models"
        )

        let modelsURL = ready.baseURL
            .appendingPathComponent("audio")
            .appendingPathComponent("models")

        do {
            let list = try await fetchModels(url: modelsURL)
            if list.available == false {
                AppLogger.shared.log(
                    level: .error,
                    message: "[StrutModels] available: false host=\(host) path=/audio/models"
                )
                return .failure(.sttUnavailable)
            }

            let defaults = list.models.filter { $0.isDefault }
            guard
                let primary = defaults.first(where: { $0.role == "model" }),
                let partial = defaults.first(where: { $0.role == "partialModel" })
            else {
                return .failure(.missingDefaultModels)
            }

            for entry in [primary, partial] {
                try validateModelId(entry.id)
                if entry.installed {
                    AppLogger.shared.log(
                        level: .info,
                        message: "[StrutModels] already installed role=\(entry.role) host=\(host) path=/audio/models"
                    )
                    continue
                }
                try await downloadModel(id: entry.id, progress: progress)
            }

            return .success(())
        } catch let error as StrutModelInstallError {
            logInstallError(error, host: host)
            return .failure(error)
        } catch {
            AppLogger.shared.log(
                level: .error,
                message: "[StrutModels] error host=\(host) path=/audio/models"
            )
            return .failure(.transport)
        }
    }

    // MARK: - Network

    private func fetchModels(url: URL) async throws -> StrutAudioModelsResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(ready.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await performDataTask(request, sse: false)
        let status = response.statusCode
        AppLogger.shared.log(
            level: status == 401 || !(200...299).contains(status) ? .error : .info,
            message: "[StrutModels] GET /audio/models host=\(url.host ?? "") path=\(url.path) status=\(status)"
        )
        guard (200...299).contains(status) else {
            throw StrutModelInstallError.httpStatus(status)
        }
        guard let decoded = try? JSONDecoder().decode(StrutAudioModelsResponse.self, from: data) else {
            throw StrutModelInstallError.invalidResponse
        }
        return decoded
    }

    private func downloadModel(
        id: String,
        progress: StrutModelProgressHandler?
    ) async throws {
        let url = ready.baseURL
            .appendingPathComponent("audio")
            .appendingPathComponent("models")
            .appendingPathComponent(id)
            .appendingPathComponent("download")

        AppLogger.shared.log(
            level: .info,
            message: "[StrutModels] download start host=\(url.host ?? "") path=\(url.path)"
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(ready.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (_, response) = try await performDataTask(request, sse: true, progress: progress)
        let status = response.statusCode
        guard (200...299).contains(status) else {
            AppLogger.shared.log(
                level: .error,
                message: "[StrutModels] download HTTP status=\(status) host=\(url.host ?? "") path=\(url.path)"
            )
            throw StrutModelInstallError.httpStatus(status)
        }
        AppLogger.shared.log(
            level: .info,
            message: "[StrutModels] done host=\(url.host ?? "") path=\(url.path)"
        )
    }

    private func performDataTask(
        _ request: URLRequest,
        sse: Bool,
        progress: StrutModelProgressHandler? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request)
            let box = TaskBox(
                sse: sse,
                progress: progress,
                continuation: continuation
            )
            lock.lock()
            tasks[task.taskIdentifier] = box
            lock.unlock()
            task.resume()
        }
    }

    // MARK: - Validation

    static func isValidModelId(_ id: String) -> Bool {
        if id.isEmpty { return false }
        if id.contains("/") || id.contains("\\") { return false }
        if id.contains("..") { return false }
        if id.contains("?") || id.contains("#") { return false }
        if id.contains("://") { return false }
        return true
    }

    private func validateModelId(_ id: String) throws {
        guard Self.isValidModelId(id) else {
            throw StrutModelInstallError.invalidModelId(id)
        }
    }

    private func logInstallError(_ error: StrutModelInstallError, host: String) {
        let detail: String
        switch error {
        case .httpStatus(let status):
            detail = "HTTP status \(status)"
        case .sttUnavailable:
            detail = "available: false"
        case .invalidModelId:
            detail = "invalid model id"
        case .downloadFailed(let message):
            detail = "download error \(message)"
        case .redirectRefused:
            detail = "redirect refused"
        case .stalled:
            detail = "stalled"
        default:
            detail = "error"
        }
        AppLogger.shared.log(
            level: .error,
            message: "[StrutModels] \(detail) host=\(host) path=/audio/models"
        )
    }

    // MARK: - Delegate plumbing

    fileprivate func handleResponse(
        task: URLSessionTask,
        response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        lock.lock()
        let box = tasks[task.taskIdentifier]
        lock.unlock()
        guard let box else {
            completionHandler(.cancel)
            return
        }
        guard let http = response as? HTTPURLResponse else {
            box.resumeOnce(.failure(StrutModelInstallError.invalidResponse))
            completionHandler(.cancel)
            return
        }
        box.response = http
        if !(200...299).contains(http.statusCode) {
            // Abort before consuming any SSE (or other) body — especially 401.
            box.resumeOnce(.failure(StrutModelInstallError.httpStatus(http.statusCode)))
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    fileprivate func handleData(task: URLSessionTask, data: Data) {
        lock.lock()
        guard let box = tasks[task.taskIdentifier], !box.isFinished else {
            lock.unlock()
            return
        }
        if !box.sse {
            box.body.append(data)
            lock.unlock()
            return
        }
        box.appendSSE(data)
        let events = box.drainSSE()
        lock.unlock()
        for (event, payload) in events {
            handleSSEEvent(event, payload: payload, box: box)
        }
    }

    fileprivate func handleRedirect(
        task: URLSessionTask,
        response: HTTPURLResponse,
        newRequest: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        let original = task.originalRequest?.url
        let next = newRequest.url
        if !StrutRedirectPolicy.isSameHost(original, next) {
            lock.lock()
            let box = tasks[task.taskIdentifier]
            lock.unlock()
            box?.resumeOnce(.failure(.redirectRefused))
            AppLogger.shared.log(
                level: .error,
                message: "[StrutModels] redirect refused host=\(original?.host ?? "") path=\(original?.path ?? "") status=\(response.statusCode)"
            )
            completionHandler(nil)
            return
        }
        var sanitized = newRequest
        sanitized.setValue(nil, forHTTPHeaderField: "Authorization")
        completionHandler(sanitized)
    }

    fileprivate func handleComplete(task: URLSessionTask, error: Error?) {
        lock.lock()
        let box = tasks.removeValue(forKey: task.taskIdentifier)
        lock.unlock()
        guard let box else { return }
        if let error {
            if (error as NSError).code == NSURLErrorCancelled {
                box.resumeOnce(.failure(.transport))
                return
            }
            box.resumeOnce(.failure(.transport))
            return
        }
        if box.sse {
            let leftover = box.flushSSE()
            for (event, payload) in leftover {
                handleSSEEvent(event, payload: payload, box: box)
            }
            // Stream ended without a `done` event — stall, do not reconnect.
            box.resumeOnce(.failure(.stalled))
            return
        }
        guard let response = box.response else {
            box.resumeOnce(.failure(.invalidResponse))
            return
        }
        box.resumeOnce(.success((box.body, response)))
    }

    private func handleSSEEvent(_ event: String, payload: String, box: TaskBox) {
        switch event {
        case "progress":
            let parsed = Self.parseProgress(payload)
            box.progress?(parsed.phase, parsed.received, parsed.total)
        case "done":
            if let response = box.response {
                box.resumeOnce(.success((Data(), response)))
            } else {
                box.resumeOnce(.failure(.invalidResponse))
            }
        case "error":
            let message = Self.parseErrorMessage(payload)
            box.resumeOnce(.failure(.downloadFailed(message)))
        default:
            break
        }
    }

    private static func parseProgress(
        _ payload: String
    ) -> (phase: String?, received: Int?, total: Int?) {
        guard
            let data = payload.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return (nil, nil, nil)
        }
        let phase = object["phase"] as? String
        let received = (object["received"] as? NSNumber)?.intValue
        let total = (object["total"] as? NSNumber)?.intValue
        return (phase, received, total)
    }

    private static func parseErrorMessage(_ payload: String) -> String {
        guard
            let data = payload.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return payload
        }
        return (object["error"] as? String)
            ?? (object["message"] as? String)
            ?? payload
    }
}

// MARK: - URLSession delegate (separate object to avoid session ↔ installer cycle)

private final class StrutModelSessionDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    weak var owner: StrutModelInstaller?

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        owner?.handleResponse(
            task: dataTask,
            response: response,
            completionHandler: completionHandler
        )
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        owner?.handleData(task: dataTask, data: data)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        owner?.handleRedirect(
            task: task,
            response: response,
            newRequest: request,
            completionHandler: completionHandler
        )
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        owner?.handleComplete(task: task, error: error)
    }
}

// MARK: - Per-task state

private final class TaskBox {
    let sse: Bool
    let progress: StrutModelProgressHandler?
    var body = Data()
    var sseBuffer = ""
    var response: HTTPURLResponse?
    private let resumeLock = NSLock()
    private var finished = false
    private var continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>?

    var isFinished: Bool {
        resumeLock.lock()
        defer { resumeLock.unlock() }
        return finished
    }

    init(
        sse: Bool,
        progress: StrutModelProgressHandler?,
        continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>
    ) {
        self.sse = sse
        self.progress = progress
        self.continuation = continuation
    }

    func resumeOnce(_ result: Result<(Data, HTTPURLResponse), Error>) {
        resumeLock.lock()
        defer { resumeLock.unlock() }
        guard !finished else { return }
        finished = true
        continuation?.resume(with: result)
        continuation = nil
    }

    func appendSSE(_ data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        sseBuffer += chunk
    }

    func drainSSE() -> [(String, String)] {
        let blocks = sseBuffer.components(separatedBy: "\n\n")
        sseBuffer = blocks.last ?? ""
        return blocks.dropLast().map { Self.parseBlock($0) }
    }

    func flushSSE() -> [(String, String)] {
        var events = drainSSE()
        let remaining = sseBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !remaining.isEmpty {
            events.append(Self.parseBlock(sseBuffer))
            sseBuffer = ""
        }
        return events
    }

    private static func parseBlock(_ block: String) -> (event: String, data: String) {
        var event = "message"
        var dataLines: [String] = []
        let normalized = block.replacingOccurrences(of: "\r\n", with: "\n")
        for line in normalized.components(separatedBy: "\n") {
            if line.hasPrefix("event:") {
                event = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                dataLines.append(
                    line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                )
            }
        }
        return (event, dataLines.joined(separator: "\n"))
    }
}
