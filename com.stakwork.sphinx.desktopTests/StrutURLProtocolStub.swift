//
//  StrutURLProtocolStub.swift
//  com.stakwork.sphinx.desktopTests
//
//  URLProtocol stub for Strut tests. Path-aware map (method + path) with a
//  global fallback so existing StrutConnectionTests keep working.
//  SSE routes deliver ordered chunks via successive `didLoad` calls.
//

import Foundation

final class StrutURLProtocolStub: URLProtocol {

    struct Response {
        var statusCode: Int?
        var error: Error?
        var body: Data = Data()
        var headers: [String: String]? = nil
        var sseChunks: [Data]? = nil
        var redirectLocation: String? = nil
    }

    private static let lock = NSLock()
    private static var _response: Response?
    private static var _routes: [String: Response] = [:]
    private static var _requests: [URLRequest] = []

    private var cancelled = false

    static var response: Response? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _response
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _response = newValue
        }
    }

    static var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return _requests
    }

    static var lastRequest: URLRequest? {
        requests.last
    }

    static var requestCount: Int {
        requests.count
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        _response = nil
        _routes = [:]
        _requests = []
    }

    /// Register a one-shot or SSE response for an exact method + path pair.
    /// `path` may be with or without a leading `/`.
    static func stub(method: String, path: String, response: Response) {
        lock.lock()
        defer { lock.unlock() }
        _routes[routeKey(method: method, path: path)] = response
    }

    static func stubJSON(
        method: String,
        path: String,
        statusCode: Int = 200,
        object: Any
    ) {
        let body = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        stub(
            method: method,
            path: path,
            response: Response(statusCode: statusCode, body: body)
        )
    }

    static func stubSSE(
        method: String,
        path: String,
        statusCode: Int = 200,
        chunks: [Data]
    ) {
        stub(
            method: method,
            path: path,
            response: Response(
                statusCode: statusCode,
                headers: ["Content-Type": "text/event-stream"],
                sseChunks: chunks
            )
        )
    }

    static func authorizationValues() -> [String] {
        requests.compactMap { $0.value(forHTTPHeaderField: "Authorization") }
    }

    static func recordedPaths() -> [String] {
        requests.compactMap { $0.url?.path }
    }

    static func recordedMethods() -> [String] {
        requests.compactMap { $0.httpMethod }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        var recorded = request
        if recorded.httpBody == nil, let body = Self.readBodyStream(request) {
            recorded.httpBody = body
        }
        Self._requests.append(recorded)
        let stub = Self.lookupLocked(request)
        Self.lock.unlock()

        if let error = stub?.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        var headers = stub?.headers ?? [:]
        if let location = stub?.redirectLocation {
            headers["Location"] = location
        }

        let statusCode = stub?.statusCode ?? (stub?.redirectLocation != nil ? 302 : 200)

        guard let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers.isEmpty ? nil : headers
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        if let location = stub?.redirectLocation,
           let redirectURL = URL(string: location) {
            var redirected = URLRequest(url: redirectURL)
            redirected.httpMethod = request.httpMethod
            // Copy headers so session-delegate tests can assert Authorization
            // is stripped on same-host follows (URLSession would copy them).
            if let headers = request.allHTTPHeaderFields {
                for (key, value) in headers {
                    redirected.setValue(value, forHTTPHeaderField: key)
                }
            }
            client?.urlProtocol(
                self,
                wasRedirectedTo: redirected,
                redirectResponse: response
            )
            if cancelled { return }
            // Session did not cancel — complete with the 3xx so tests never hang.
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if cancelled { return }

        if let chunks = stub?.sseChunks {
            for chunk in chunks {
                if cancelled { return }
                client?.urlProtocol(self, didLoad: chunk)
            }
        } else {
            client?.urlProtocol(self, didLoad: stub?.body ?? Data())
        }

        if cancelled { return }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        cancelled = true
    }

    /// URLSession often streams `httpBody` as `httpBodyStream`. Copy it so
    /// tests can assert JSON without depending on that internal choice.
    private static func readBodyStream(_ request: URLRequest) -> Data? {
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data.isEmpty ? nil : data
    }

    private static func lookupLocked(_ request: URLRequest) -> Response? {
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? ""
        if let routed = _routes[routeKey(method: method, path: path)] {
            return routed
        }
        return _response
    }

    private static func routeKey(method: String, path: String) -> String {
        let normalized: String
        if path.isEmpty {
            normalized = "/"
        } else if path.hasPrefix("/") {
            normalized = path
        } else {
            normalized = "/" + path
        }
        return "\(method.uppercased()) \(normalized)"
    }
}

enum StrutSSEFixture {
    static func event(_ name: String, json: String) -> Data {
        Data("event: \(name)\ndata: \(json)\n\n".utf8)
    }

    static func progress(received: Int, total: Int, phase: String? = nil) -> Data {
        var object: [String: Any] = ["received": received, "total": total]
        if let phase {
            object["phase"] = phase
        }
        let json = (try? JSONSerialization.data(withJSONObject: object))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return event("progress", json: json)
    }

    static func done() -> Data {
        event("done", json: "{}")
    }

    static func error(_ message: String) -> Data {
        event("error", json: "{\"error\":\"\(message)\"}")
    }
}
