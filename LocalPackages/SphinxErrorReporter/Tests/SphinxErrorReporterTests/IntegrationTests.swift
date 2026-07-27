// IntegrationTests.swift
// Integration tests: SphinxErrorReporter.start() + capture() in macOS app context
// Validates the full pipeline produces a Hive-contract-compliant payload via URLProtocol mock.

import XCTest
@testable import SphinxErrorReporter

final class IntegrationTests: XCTestCase {

    private var mockSession: URLSession!

    override func setUp() {
        super.setUp()
        mockSession = MockURLProtocol.makeSession()
        MockURLProtocol.requestHandler = nil
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        // Reset SDK state between tests
        SphinxErrorReporter.currentConfig = nil
        SphinxErrorReporter.reportStore = nil
        super.tearDown()
    }

    // MARK: - Hive contract compliance

    func testCapture_ProducesHiveContractCompliantPayload() throws {
        let expectation = expectation(description: "Report sent")
        var capturedJSON: [String: Any]?

        MockURLProtocol.requestHandler = { request in
            if let body = request.httpBody {
                capturedJSON = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
            }
            expectation.fulfill()
            return MockURLProtocol.successHandler()(request)
        }

        // Configure with macOS-specific repo
        let config = Config(
            hiveBaseURL: URL(string: "https://hive.sphinx.chat/api")!,
            ingestKey: "hive_mac_test_key",
            mainRepo: "stakwork/sphinx-mac-v2",
            environment: "test",
            release: "2.0.0",
            commitSha: "deadbeef",
            debug: false
        )

        // Manually wire transport with mock session (bypassing full start() to avoid signal handlers)
        let transport = Transport(config: config, session: mockSession)
        let store = ReportStore()
        store.configure(transport: transport, config: config)
        SphinxErrorReporter.currentConfig = config
        SphinxErrorReporter.reportStore = store

        // Trigger a manual capture
        struct MacTestError: Error {
            var localizedDescription: String { "macOS integration test error" }
        }
        SphinxErrorReporter.capture(
            MacTestError(),
            repository: "stakwork/sphinx-mac-v2",
            metadata: ["platform": "macOS", "testName": "IntegrationTests"]
        )

        waitForExpectations(timeout: 3)

        // Validate Hive contract
        XCTAssertNotNil(capturedJSON, "Payload must be sent")

        // Required fields
        XCTAssertNotNil(capturedJSON?["exceptionType"], "exceptionType is required")
        XCTAssertNotNil(capturedJSON?["message"], "message is required")

        // Optional fields that should be present given our config
        XCTAssertEqual(capturedJSON?["repository"] as? String, "stakwork/sphinx-mac-v2")
        XCTAssertEqual(capturedJSON?["environment"] as? String, "test")
        XCTAssertEqual(capturedJSON?["release"] as? String, "2.0.0")
        XCTAssertEqual(capturedJSON?["commitSha"] as? String, "deadbeef")

        // frames key: should be omitted or be a non-empty array (never empty array)
        if let frames = capturedJSON?["frames"] as? [[String: Any]] {
            XCTAssertFalse(frames.isEmpty, "frames must not be empty array — omit instead")
        }

        // No snake_case keys
        XCTAssertNil(capturedJSON?["exception_type"])
        XCTAssertNil(capturedJSON?["stack_trace"])
        XCTAssertNil(capturedJSON?["commit_sha"])
    }

    func testCapture_AuthHeaders_MatchHiveContract() throws {
        let expectation = expectation(description: "Request captured")
        var capturedRequest: URLRequest?

        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            expectation.fulfill()
            return MockURLProtocol.successHandler()(request)
        }

        let config = Config(
            hiveBaseURL: URL(string: "https://hive.sphinx.chat/api")!,
            ingestKey: "hive_mac_secret_key",
            mainRepo: "stakwork/sphinx-mac-v2"
        )

        let transport = Transport(config: config, session: mockSession)
        let store = ReportStore()
        store.configure(transport: transport, config: config)
        SphinxErrorReporter.currentConfig = config
        SphinxErrorReporter.reportStore = store

        SphinxErrorReporter.captureMessage("Test from macOS", exceptionType: "MacTestCapture")

        waitForExpectations(timeout: 3)

        // Auth: Bearer header
        XCTAssertEqual(
            capturedRequest?.value(forHTTPHeaderField: "Authorization"),
            "Bearer hive_mac_secret_key"
        )
        // Fallback header
        XCTAssertEqual(
            capturedRequest?.value(forHTTPHeaderField: "x-api-key"),
            "hive_mac_secret_key"
        )
        // Endpoint
        XCTAssertEqual(
            capturedRequest?.url?.absoluteString,
            "https://hive.sphinx.chat/api/webhook/errors"
        )
        // Method
        XCTAssertEqual(capturedRequest?.httpMethod, "POST")
    }

    func testCapture_WhenNotStarted_DoesNotCrash() {
        // Reset to unstarted state
        SphinxErrorReporter.currentConfig = nil
        SphinxErrorReporter.reportStore = nil

        struct SomeError: Error {}
        // Should silently drop — must not crash
        SphinxErrorReporter.capture(SomeError())
        XCTAssertTrue(true, "capture() when not started must not crash")
    }

    func testCaptureMessage_ProducesCorrectExceptionType() throws {
        let expectation = expectation(description: "Report sent")
        var capturedJSON: [String: Any]?

        MockURLProtocol.requestHandler = { request in
            capturedJSON = try? JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
            expectation.fulfill()
            return MockURLProtocol.successHandler()(request)
        }

        let config = Config(
            hiveBaseURL: URL(string: "https://hive.sphinx.chat/api")!,
            ingestKey: "hive_key",
            mainRepo: "stakwork/sphinx-mac-v2"
        )
        let transport = Transport(config: config, session: mockSession)
        let store = ReportStore()
        store.configure(transport: transport, config: config)
        SphinxErrorReporter.currentConfig = config
        SphinxErrorReporter.reportStore = store

        SphinxErrorReporter.captureMessage(
            "Custom error message",
            exceptionType: "CustomMacOSError"
        )

        waitForExpectations(timeout: 3)

        XCTAssertEqual(capturedJSON?["exceptionType"] as? String, "CustomMacOSError")
        XCTAssertEqual(capturedJSON?["message"] as? String, "Custom error message")
        XCTAssertEqual(capturedJSON?["repository"] as? String, "stakwork/sphinx-mac-v2")
    }

    // MARK: - Delivery off main thread

    func testCapture_DoesNotBlockMainThread() {
        // capture() should return immediately
        MockURLProtocol.requestHandler = { request in
            Thread.sleep(forTimeInterval: 0.5)  // Simulate slow network
            return MockURLProtocol.successHandler()(request)
        }

        let config = Config(
            hiveBaseURL: URL(string: "https://hive.sphinx.chat/api")!,
            ingestKey: "hive_key",
            mainRepo: "stakwork/sphinx-mac-v2"
        )
        let transport = Transport(config: config, session: mockSession)
        let store = ReportStore()
        store.configure(transport: transport, config: config)
        SphinxErrorReporter.currentConfig = config
        SphinxErrorReporter.reportStore = store

        let start = Date()
        SphinxErrorReporter.captureMessage("Non-blocking test")
        let elapsed = Date().timeIntervalSince(start)

        // capture() itself should return in well under 100ms
        XCTAssertLessThan(elapsed, 0.1, "capture() must return immediately (non-blocking)")
    }
}
