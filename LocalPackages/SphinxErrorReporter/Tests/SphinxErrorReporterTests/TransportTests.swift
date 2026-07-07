// TransportTests.swift
// Tests Transport: POST method, Authorization/x-api-key headers, body, error scenarios.
// Uses MockURLProtocol to intercept URLSession without live network calls.

import XCTest
@testable import SphinxErrorReporter

final class TransportTests: XCTestCase {

    private var config: Config!
    private var transport: Transport!
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        config = Config(
            hiveBaseURL: URL(string: "https://hive.sphinx.chat/api")!,
            ingestKey: "hive_test_key_12345",
            mainRepo: "stakwork/sphinx-mac-v2",
            debug: false
        )
        session = MockURLProtocol.makeSession()
        transport = Transport(config: config, session: session)
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    // MARK: - HTTP method

    func testTransport_UsesPOSTMethod() throws {
        let expectation = expectation(description: "Request intercepted")
        var capturedRequest: URLRequest?

        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            expectation.fulfill()
            return MockURLProtocol.successHandler()(request)
        }

        let report = ErrorReport(exceptionType: "TestError", message: "Test")
        transport.send(report)

        waitForExpectations(timeout: 2)
        XCTAssertEqual(capturedRequest?.httpMethod, "POST")
    }

    // MARK: - Auth headers

    func testTransport_SendsAuthorizationBearerHeader() throws {
        let expectation = expectation(description: "Request intercepted")
        var capturedRequest: URLRequest?

        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            expectation.fulfill()
            return MockURLProtocol.successHandler()(request)
        }

        let report = ErrorReport(exceptionType: "TestError", message: "Test")
        transport.send(report)

        waitForExpectations(timeout: 2)
        let authHeader = capturedRequest?.value(forHTTPHeaderField: "Authorization")
        XCTAssertEqual(authHeader, "Bearer hive_test_key_12345",
                       "Authorization header must be 'Bearer <ingestKey>'")
    }

    func testTransport_SendsXApiKeyFallbackHeader() throws {
        let expectation = expectation(description: "Request intercepted")
        var capturedRequest: URLRequest?

        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            expectation.fulfill()
            return MockURLProtocol.successHandler()(request)
        }

        let report = ErrorReport(exceptionType: "TestError", message: "Test")
        transport.send(report)

        waitForExpectations(timeout: 2)
        let xApiKeyHeader = capturedRequest?.value(forHTTPHeaderField: "x-api-key")
        XCTAssertEqual(xApiKeyHeader, "hive_test_key_12345",
                       "x-api-key header must equal ingestKey")
    }

    // MARK: - Endpoint URL

    func testTransport_PostsToCorrectEndpoint() throws {
        let expectation = expectation(description: "Request intercepted")
        var capturedURL: URL?

        MockURLProtocol.requestHandler = { request in
            capturedURL = request.url
            expectation.fulfill()
            return MockURLProtocol.successHandler()(request)
        }

        let report = ErrorReport(exceptionType: "TestError", message: "Test")
        transport.send(report)

        waitForExpectations(timeout: 2)
        XCTAssertEqual(capturedURL?.absoluteString,
                       "https://hive.sphinx.chat/api/webhook/errors")
    }

    // MARK: - Request body

    func testTransport_BodyContainsRequiredFields() throws {
        let expectation = expectation(description: "Request intercepted")
        var capturedBody: Data?

        MockURLProtocol.requestHandler = { request in
            capturedBody = request.httpBody
            expectation.fulfill()
            return MockURLProtocol.successHandler()(request)
        }

        let report = ErrorReport(
            exceptionType: "NSInvalidArgumentException",
            message: "Test message",
            repository: "stakwork/sphinx-mac-v2"
        )
        transport.send(report)

        waitForExpectations(timeout: 2)
        XCTAssertNotNil(capturedBody, "Request must have a body")
        let json = try! JSONSerialization.jsonObject(with: capturedBody!) as! [String: Any]
        XCTAssertEqual(json["exceptionType"] as? String, "NSInvalidArgumentException")
        XCTAssertEqual(json["message"] as? String, "Test message")
        XCTAssertEqual(json["repository"] as? String, "stakwork/sphinx-mac-v2")
    }

    // MARK: - Success / failure handling

    func testTransport_2xx_ReturnsTrue() {
        let expectation = expectation(description: "Completion called")
        MockURLProtocol.requestHandler = MockURLProtocol.successHandler(statusCode: 200)

        let report = ErrorReport(exceptionType: "E", message: "m")
        transport.send(report) { success in
            XCTAssertTrue(success)
            expectation.fulfill()
        }
        waitForExpectations(timeout: 2)
    }

    func testTransport_4xx_ReturnsFalse() {
        let expectation = expectation(description: "Completion called")
        MockURLProtocol.requestHandler = MockURLProtocol.failureHandler(statusCode: 401)

        let report = ErrorReport(exceptionType: "E", message: "m")
        transport.send(report) { success in
            XCTAssertFalse(success)
            expectation.fulfill()
        }
        waitForExpectations(timeout: 2)
    }

    func testTransport_5xx_ReturnsFalse() {
        let expectation = expectation(description: "Completion called")
        MockURLProtocol.requestHandler = MockURLProtocol.failureHandler(statusCode: 500)

        let report = ErrorReport(exceptionType: "E", message: "m")
        transport.send(report) { success in
            XCTAssertFalse(success)
            expectation.fulfill()
        }
        waitForExpectations(timeout: 2)
    }

    func testTransport_NetworkOffline_ReturnsFalse_DoesNotCrash() {
        let expectation = expectation(description: "Completion called")
        MockURLProtocol.requestHandler = MockURLProtocol.offlineHandler()

        let report = ErrorReport(exceptionType: "E", message: "m")
        transport.send(report) { success in
            XCTAssertFalse(success)
            expectation.fulfill()
        }
        waitForExpectations(timeout: 2)
    }

    // MARK: - Content-Type header

    func testTransport_SetsContentTypeJSON() {
        let expectation = expectation(description: "Request intercepted")
        var capturedRequest: URLRequest?

        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            expectation.fulfill()
            return MockURLProtocol.successHandler()(request)
        }

        let report = ErrorReport(exceptionType: "E", message: "m")
        transport.send(report)

        waitForExpectations(timeout: 2)
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Content-Type"),
                       "application/json")
    }
}
