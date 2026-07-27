// MockURLProtocol.swift
// URLProtocol stub for intercepting URLSession requests in tests.
// Simulates success (2xx), 4xx/5xx, and offline scenarios.

import Foundation

final class MockURLProtocol: URLProtocol, @unchecked Sendable {

    // MARK: - Configuration (set per-test)

    /// The handler to invoke when a request is intercepted.
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    // MARK: - URLProtocol

    override class func canInit(with request: URLRequest) -> Bool {
        return true  // Intercept all requests
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: MockError.noHandler)
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    // MARK: - Helpers

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    static func successHandler(statusCode: Int = 200) -> (URLRequest) throws -> (HTTPURLResponse, Data) {
        return { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }
    }

    static func failureHandler(statusCode: Int) -> (URLRequest) throws -> (HTTPURLResponse, Data) {
        return { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }
    }

    static func offlineHandler() -> (URLRequest) throws -> (HTTPURLResponse, Data) {
        return { _ in
            throw MockError.networkOffline
        }
    }
}

enum MockError: Error {
    case noHandler
    case networkOffline
}
