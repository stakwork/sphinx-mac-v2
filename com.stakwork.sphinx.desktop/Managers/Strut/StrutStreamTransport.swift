//
//  StrutStreamTransport.swift
//  com.stakwork.sphinx.desktop
//
//  Thin URLSessionWebSocketTask wrapper for `/audio/stream`.
//  Binary PCM frames; Starscream stays on the call-participant JSON socket.
//  Never uses StrutConnection.makeEphemeralSession() (3s health timeout).
//

import Foundation

enum StrutStreamTransportError: Error, Equatable, Sendable {
    case disallowedScheme(scheme: String, host: String)
    case rejectedAuth(code: Int)
    case upgradeFailed(code: Int)
    case invalidURL
}

extension StrutStreamTransportError {
    var userMessage: String {
        switch self {
        case .disallowedScheme(let scheme, let host):
            return "disallowed scheme \(scheme) for host \(host)"
        case .rejectedAuth(let code):
            return "authentication rejected (\(code))"
        case .upgradeFailed(let code):
            return "stream upgrade failed (\(code))"
        case .invalidURL:
            return "invalid stream URL"
        }
    }

    var logCode: Int {
        switch self {
        case .rejectedAuth(let code), .upgradeFailed(let code):
            return code
        case .disallowedScheme, .invalidURL:
            return 0
        }
    }
}

enum StrutStreamURLBuilder {
    /// Swap `http`→`ws`, `https`→`wss`, then append `audio/stream`.
    /// Authorization must never be placed on the query or fragment.
    static func makeStreamURL(from baseURL: URL) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        switch (components.scheme ?? "").lowercased() {
        case "http":
            components.scheme = "ws"
        case "https":
            components.scheme = "wss"
        case "ws", "wss":
            break
        default:
            return nil
        }
        components.query = nil
        components.fragment = nil
        guard let url = components.url else { return nil }
        return url
            .appendingPathComponent("audio")
            .appendingPathComponent("stream")
    }
}

protocol StrutStreamTransport: AnyObject, Sendable {
    func setHandlers(
        onMessage: @escaping @Sendable (Int, StrutServerMessage) -> Void,
        onClose: @escaping @Sendable (_ generation: Int, _ closeCode: Int) -> Void,
        onFailure: @escaping @Sendable (Int, StrutStreamTransportError) -> Void
    )
    func open(
        ready: StrutReadyConnection,
        generation: Int
    ) async -> Result<Void, StrutStreamTransportError>
    func send(text: String)
    func send(data: Data)
    func close(code: Int) async
}

/// `@unchecked Sendable` because URLSession delegate callbacks arrive on a
/// session queue and mutable socket state is serialized by `NSLock` — the
/// same pattern as `GraphChatSSEManager` / `StrutConnection`.
final class URLSessionStrutStreamTransport: NSObject, StrutStreamTransport, @unchecked Sendable {

    private static let requestTimeout: TimeInterval = 60
    private static let resourceTimeout: TimeInterval = 60 * 60

    private let lock = NSLock()
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var generation: Int = 0
    private var logHost: String = ""
    private var opened = false
    private var closed = false
    private var openContinuation: CheckedContinuation<Result<Void, StrutStreamTransportError>, Never>?
    private var closeContinuation: CheckedContinuation<Void, Never>?

    private var onMessage: (@Sendable (Int, StrutServerMessage) -> Void)?
    private var onClose: (@Sendable (Int, Int) -> Void)?
    private var onFailure: (@Sendable (Int, StrutStreamTransportError) -> Void)?

    /// Retains transports through teardown so an in-flight write cannot race
    /// a released socket (mirrors `CallParticipantsSocketManager.disconnecting`).
    private static let disconnectingLock = NSLock()
    private static var disconnecting: [URLSessionStrutStreamTransport] = []

    static func makeLongLivedConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return configuration
    }

    init(sessionConfiguration: URLSessionConfiguration = URLSessionStrutStreamTransport.makeLongLivedConfiguration()) {
        let proxy = StrutWebSocketDelegateProxy()
        self.session = URLSession(
            configuration: sessionConfiguration,
            delegate: proxy,
            delegateQueue: nil
        )
        super.init()
        proxy.owner = self
    }

    deinit {
        session.invalidateAndCancel()
    }

    func setHandlers(
        onMessage: @escaping @Sendable (Int, StrutServerMessage) -> Void,
        onClose: @escaping @Sendable (Int, Int) -> Void,
        onFailure: @escaping @Sendable (Int, StrutStreamTransportError) -> Void
    ) {
        lock.lock()
        self.onMessage = onMessage
        self.onClose = onClose
        self.onFailure = onFailure
        lock.unlock()
    }

    func open(
        ready: StrutReadyConnection,
        generation: Int
    ) async -> Result<Void, StrutStreamTransportError> {
        if let schemeError = StrutURLSchemePolicy.validate(ready.baseURL) {
            return .failure(mapSchemeError(schemeError, url: ready.baseURL))
        }
        guard let streamURL = StrutStreamURLBuilder.makeStreamURL(from: ready.baseURL) else {
            return .failure(.invalidURL)
        }
        if let schemeError = StrutURLSchemePolicy.validate(streamURL) {
            return .failure(mapSchemeError(schemeError, url: streamURL))
        }

        var request = URLRequest(url: streamURL)
        request.setValue(ready.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let host = streamURL.host ?? ""

        return await withCheckedContinuation { continuation in
            lock.lock()
            self.generation = generation
            self.logHost = host
            self.opened = false
            self.closed = false
            self.openContinuation = continuation
            let socket = session.webSocketTask(with: request)
            self.task = socket
            lock.unlock()
            socket.resume()
        }
    }

    func send(text: String) {
        lock.lock()
        let socket = task
        let isOpen = opened && !closed
        lock.unlock()
        guard isOpen, let socket else { return }
        socket.send(.string(text)) { _ in }
    }

    func send(data: Data) {
        lock.lock()
        let socket = task
        let isOpen = opened && !closed
        lock.unlock()
        guard isOpen, let socket else { return }
        socket.send(.data(data)) { _ in }
    }

    func close(code: Int) async {
        retainForDisconnect()
        lock.lock()
        if closed || task == nil {
            closed = true
            lock.unlock()
            releaseDisconnect()
            return
        }
        let socket = task
        let closeCode = URLSessionWebSocketTask.CloseCode(rawValue: code) ?? .invalid
        lock.unlock()
        socket?.cancel(with: closeCode, reason: nil)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if closed {
                lock.unlock()
                continuation.resume()
                return
            }
            closeContinuation = continuation
            lock.unlock()
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.resumeCloseWait()
            }
        }
        releaseDisconnect()
    }

    // MARK: - Delegate plumbing

    fileprivate func handleOpen() {
        lock.lock()
        opened = true
        let gen = generation
        let continuation = openContinuation
        openContinuation = nil
        let socket = task
        lock.unlock()
        continuation?.resume(returning: .success(()))
        if let socket {
            receiveLoop(socket: socket, generation: gen)
        }
    }

    fileprivate func handlePeerClose(code: Int) {
        lock.lock()
        let alreadyClosed = closed
        closed = true
        let gen = generation
        let host = logHost
        let openWait = openContinuation
        openContinuation = nil
        lock.unlock()

        AppLogger.shared.log(
            level: .info,
            message: "[StrutDictation] socket close code=\(code) host=\(host) path=/audio/stream"
        )

        if let openWait {
            openWait.resume(returning: .failure(.upgradeFailed(code: code)))
        }
        resumeCloseWait()

        if !alreadyClosed {
            lock.lock()
            let callback = onClose
            lock.unlock()
            callback?(gen, code)
        }
    }

    fileprivate func handleComplete(task: URLSessionTask, error: Error?) {
        lock.lock()
        let alreadyOpened = opened
        let alreadyClosed = closed
        let gen = generation
        let host = logHost
        let openWait = openContinuation
        openContinuation = nil
        lock.unlock()

        if alreadyOpened {
            if let error, !alreadyClosed {
                let mapped = Self.mapFailure(error: error, response: task.response)
                logFailure(mapped, host: host)
                lock.lock()
                closed = true
                let callback = onFailure
                lock.unlock()
                callback?(gen, mapped)
            }
            resumeCloseWait()
            return
        }

        let mapped = Self.mapFailure(error: error, response: task.response)
        logFailure(mapped, host: host)
        openWait?.resume(returning: .failure(mapped))
        resumeCloseWait()
    }

    private func receiveLoop(socket: URLSessionWebSocketTask, generation: Int) {
        socket.receive { [weak self] result in
            guard let self else { return }
            self.lock.lock()
            let current = self.generation
            let isClosed = self.closed
            let onMessage = self.onMessage
            self.lock.unlock()
            guard current == generation, !isClosed else { return }

            switch result {
            case .success(let message):
                let data: Data?
                switch message {
                case .string(let text):
                    data = Data(text.utf8)
                case .data(let payload):
                    data = payload
                @unknown default:
                    data = nil
                }
                if let data, let decoded = StrutAudioMessages.decodeServerMessage(data) {
                    onMessage?(generation, decoded)
                }
                self.receiveLoop(socket: socket, generation: generation)
            case .failure:
                break
            }
        }
    }

    private func resumeCloseWait() {
        lock.lock()
        closed = true
        let continuation = closeContinuation
        closeContinuation = nil
        lock.unlock()
        continuation?.resume()
    }

    private func retainForDisconnect() {
        Self.disconnectingLock.lock()
        if !Self.disconnecting.contains(where: { $0 === self }) {
            Self.disconnecting.append(self)
        }
        Self.disconnectingLock.unlock()
    }

    private func releaseDisconnect() {
        Self.disconnectingLock.lock()
        Self.disconnecting.removeAll { $0 === self }
        Self.disconnectingLock.unlock()
    }

    private func mapSchemeError(
        _ error: StrutModelInstallError,
        url: URL
    ) -> StrutStreamTransportError {
        if case .disallowedScheme(let scheme, let host) = error {
            return .disallowedScheme(scheme: scheme, host: host)
        }
        return .disallowedScheme(scheme: url.scheme ?? "", host: url.host ?? "")
    }

    private static func mapFailure(
        error: Error?,
        response: URLResponse?
    ) -> StrutStreamTransportError {
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 {
                return .rejectedAuth(code: 401)
            }
            return .upgradeFailed(code: http.statusCode)
        }
        let nsError = (error as NSError?) ?? NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorUnknown
        )
        if nsError.code == NSURLErrorUserAuthenticationRequired {
            return .rejectedAuth(code: nsError.code)
        }
        if response == nil {
            return .rejectedAuth(code: nsError.code)
        }
        return .upgradeFailed(code: nsError.code)
    }

    private func logFailure(_ error: StrutStreamTransportError, host: String) {
        let code = error.logCode
        switch error {
        case .rejectedAuth:
            AppLogger.shared.log(
                level: .error,
                message: "[StrutDictation] auth failure status=\(code) host=\(host) path=/audio/stream"
            )
        default:
            AppLogger.shared.log(
                level: .error,
                message: "[StrutDictation] transport failure code=\(code) host=\(host) path=/audio/stream"
            )
        }
    }
}

// MARK: - URLSession delegate (separate object to avoid session ↔ transport cycle)

private final class StrutWebSocketDelegateProxy: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    weak var owner: URLSessionStrutStreamTransport?

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        owner?.handleOpen()
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        owner?.handlePeerClose(code: closeCode.rawValue)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        owner?.handleComplete(task: task, error: error)
    }
}
