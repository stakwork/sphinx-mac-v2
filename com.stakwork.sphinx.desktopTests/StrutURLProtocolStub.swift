//
//  StrutURLProtocolStub.swift
//  com.stakwork.sphinx.desktopTests
//
//  URLProtocol stub for StrutConnection health-check tests.
//  Lives only on the test target — do not reuse SphinxErrorReporter's mock.
//

import Foundation

final class StrutURLProtocolStub: URLProtocol {

    struct Response {
        var statusCode: Int?
        var error: Error?
        var body: Data = Data()
    }

    private static let lock = NSLock()
    private static var _response: Response?
    private static var _requests: [URLRequest] = []

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
        _requests = []
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        Self._requests.append(request)
        let stub = Self._response
        Self.lock.unlock()

        if let error = stub?.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        let statusCode = stub?.statusCode ?? 200
        let body = stub?.body ?? Data()
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: nil
              ) else {
            client?.urlProtocol(
                self,
                didFailWithError: URLError(.badURL)
            )
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
