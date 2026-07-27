// ErrorReportCodableTests.swift
// Tests for ErrorReport and Frame Codable round-trip, camelCase keys,
// frames/fingerprint omission when nil, and exact Frame JSON key count.

import XCTest
@testable import SphinxErrorReporter

final class ErrorReportCodableTests: XCTestCase {

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = .sortedKeys
        return e
    }()
    private let decoder = JSONDecoder()

    // MARK: - Frame Codable

    func testFrame_FullFields_EncodesAllFourKeys() throws {
        let frame = Frame(filename: "Sphinx/Sources", function: "myFunc()", lineno: 42, inApp: true)
        let data = try encoder.encode(frame)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json.count, 4, "Frame JSON must have exactly 4 keys")
        XCTAssertEqual(json["filename"] as? String, "Sphinx/Sources")
        XCTAssertEqual(json["function"] as? String, "myFunc()")
        XCTAssertEqual(json["lineno"] as? Int, 42)
        XCTAssertEqual(json["inApp"] as? Bool, true)
    }

    func testFrame_OnlyFilename_EncodesOneKey() throws {
        let frame = Frame(filename: "Sphinx/Sources")
        let data = try encoder.encode(frame)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json.count, 1, "Frame with only filename should have exactly 1 key")
        XCTAssertNotNil(json["filename"])
    }

    func testFrame_RoundTrip() throws {
        let frame = Frame(filename: "Sphinx/Sources", function: "doSomething()", lineno: 99, inApp: true)
        let data = try encoder.encode(frame)
        let decoded = try decoder.decode(Frame.self, from: data)
        XCTAssertEqual(decoded.filename, frame.filename)
        XCTAssertEqual(decoded.function, frame.function)
        XCTAssertEqual(decoded.lineno, frame.lineno)
        XCTAssertEqual(decoded.inApp, frame.inApp)
    }

    // MARK: - ErrorReport Codable

    func testErrorReport_RequiredFields_Encode() throws {
        let report = ErrorReport(
            exceptionType: "NSInvalidArgumentException",
            message: "Test message"
        )
        let data = try encoder.encode(report)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["exceptionType"] as? String, "NSInvalidArgumentException")
        XCTAssertEqual(json["message"] as? String, "Test message")
    }

    func testErrorReport_NilFrames_OmittedFromJSON() throws {
        let report = ErrorReport(
            exceptionType: "TestError",
            message: "Something went wrong",
            frames: nil
        )
        let data = try encoder.encode(report)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNil(json["frames"], "frames key must be omitted when nil")
    }

    func testErrorReport_EmptyFrames_OmittedFromJSON() throws {
        let report = ErrorReport(
            exceptionType: "TestError",
            message: "Something went wrong",
            frames: []
        )
        let data = try encoder.encode(report)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNil(json["frames"], "frames key must be omitted when empty array")
    }

    func testErrorReport_NilFingerprint_OmittedFromJSON() throws {
        let report = ErrorReport(
            exceptionType: "TestError",
            message: "msg",
            fingerprint: nil
        )
        let data = try encoder.encode(report)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNil(json["fingerprint"], "fingerprint must be omitted when nil")
    }

    func testErrorReport_WithFingerprint_IncludedInJSON() throws {
        let report = ErrorReport(
            exceptionType: "TestError",
            message: "msg",
            fingerprint: "abc123"
        )
        let data = try encoder.encode(report)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["fingerprint"] as? String, "abc123")
    }

    func testErrorReport_CamelCaseKeys() throws {
        let report = ErrorReport(
            exceptionType: "E",
            message: "m",
            stackTrace: "trace",
            commitSha: "abc",
            repository: "repo"
        )
        let data = try encoder.encode(report)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        // Verify camelCase — not snake_case
        XCTAssertNotNil(json["exceptionType"])
        XCTAssertNil(json["exception_type"])
        XCTAssertNotNil(json["stackTrace"])
        XCTAssertNil(json["stack_trace"])
        XCTAssertNotNil(json["commitSha"])
        XCTAssertNil(json["commit_sha"])
    }

    func testErrorReport_WithFrames_IncludedInJSON() throws {
        let frames = [
            Frame(filename: "Sphinx/Sources", function: "crash()", lineno: 10, inApp: true),
            Frame(filename: "AppKit", inApp: false)
        ]
        let report = ErrorReport(
            exceptionType: "TestCrash",
            message: "Crashed",
            frames: frames
        )
        let data = try encoder.encode(report)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let framesArr = json["frames"] as? [[String: Any]]
        XCTAssertNotNil(framesArr)
        XCTAssertEqual(framesArr?.count, 2)
    }

    func testErrorReport_FullRoundTrip() throws {
        let frames = [Frame(filename: "Sphinx/Sources", function: "f()", lineno: 1, inApp: true)]
        let report = ErrorReport(
            exceptionType: "MyError",
            message: "Something failed",
            stackTrace: "trace here",
            frames: frames,
            environment: "production",
            release: "1.0.0",
            commitSha: "abc123",
            repository: "stakwork/sphinx-mac-v2",
            metadata: ["key": "value"]
        )
        let data = try encoder.encode(report)
        let decoded = try decoder.decode(ErrorReport.self, from: data)
        XCTAssertEqual(decoded.exceptionType, report.exceptionType)
        XCTAssertEqual(decoded.message, report.message)
        XCTAssertEqual(decoded.stackTrace, report.stackTrace)
        XCTAssertEqual(decoded.environment, report.environment)
        XCTAssertEqual(decoded.release, report.release)
        XCTAssertEqual(decoded.commitSha, report.commitSha)
        XCTAssertEqual(decoded.repository, report.repository)
        XCTAssertEqual(decoded.frames?.count, 1)
    }
}
