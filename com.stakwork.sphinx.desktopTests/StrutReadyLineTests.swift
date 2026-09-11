//
//  StrutReadyLineTests.swift
//  com.stakwork.sphinx.desktopTests
//
//  Pure parser tests for the Strut stdout ready line.
//

import XCTest
@testable import com_stakwork_sphinx_desktop

final class StrutReadyLineTests: XCTestCase {

    private func json(
        event: String = "ready",
        host: String = "127.0.0.1",
        port: Int = 51234,
        key: String = "launch-key"
    ) -> String {
        """
        {"event":"\(event)","host":"\(host)","port":\(port),"key":"\(key)"}
        """
    }

    func testValidReadyLineParsesHostPortKey() {
        let parsed = StrutReadyLine.parse(json())
        XCTAssertEqual(parsed?.host, "127.0.0.1")
        XCTAssertEqual(parsed?.port, 51234)
        XCTAssertEqual(parsed?.key, "launch-key")
    }

    func testValidReadyLine_LocalhostAndIPv6LoopbackAccepted() {
        XCTAssertEqual(
            StrutReadyLine.parse(json(host: "localhost"))?.host,
            "localhost"
        )
        XCTAssertEqual(
            StrutReadyLine.parse(json(host: "::1"))?.host,
            "::1"
        )
        XCTAssertEqual(
            StrutReadyLine.parse(json(host: "[::1]"))?.host,
            "[::1]"
        )
    }

    func testExtraStdoutLinesAreIgnoredUntilValidReady() {
        let text = """
        strut starting
        not json
        {"event":"ready","host":"127.0.0.1","port":51235,"key":"k"}
        leftover
        """
        let parsed = StrutReadyLine.firstValidLine(in: text)
        XCTAssertEqual(parsed?.host, "127.0.0.1")
        XCTAssertEqual(parsed?.port, 51235)
        XCTAssertEqual(parsed?.key, "k")
    }

    func testGarbageOnlyStdoutIsNil() {
        XCTAssertNil(StrutReadyLine.parse("not-json"))
        XCTAssertNil(StrutReadyLine.parse(""))
        XCTAssertNil(StrutReadyLine.parse("   "))
        XCTAssertNil(StrutReadyLine.firstValidLine(in: "hello\nworld"))
    }

    func testMissingFieldsFailToParse() {
        XCTAssertNil(StrutReadyLine.parse(
            #"{"host":"127.0.0.1","port":1,"key":"k"}"#
        ))
        XCTAssertNil(StrutReadyLine.parse(
            #"{"event":"ready","port":1,"key":"k"}"#
        ))
        XCTAssertNil(StrutReadyLine.parse(
            #"{"event":"ready","host":"127.0.0.1","key":"k"}"#
        ))
        XCTAssertNil(StrutReadyLine.parse(
            #"{"event":"ready","host":"127.0.0.1","port":1}"#
        ))
    }

    func testEventNotReadyFailsToParse() {
        XCTAssertNil(StrutReadyLine.parse(json(event: "started")))
        XCTAssertNil(StrutReadyLine.parse(json(event: "Ready")))
        XCTAssertNil(StrutReadyLine.parse(json(event: "")))
    }

    func testNonLoopbackHostIsRejected() {
        XCTAssertNil(StrutReadyLine.parse(json(host: "10.0.0.1")))
        XCTAssertNil(StrutReadyLine.parse(json(host: "example.com")))
        XCTAssertNil(StrutReadyLine.parse(json(host: "0.0.0.0")))
    }

    func testPortBoundsAreRejected() {
        XCTAssertNil(StrutReadyLine.parse(json(port: 0)))
        XCTAssertNil(StrutReadyLine.parse(json(port: 65536)))
        XCTAssertNil(StrutReadyLine.parse(json(port: -1)))
        XCTAssertEqual(StrutReadyLine.parse(json(port: 1))?.port, 1)
        XCTAssertEqual(StrutReadyLine.parse(json(port: 65535))?.port, 65535)
    }

    func testEmptyOrWhitespaceKeyIsRejected() {
        XCTAssertNil(StrutReadyLine.parse(json(key: "")))
        XCTAssertNil(StrutReadyLine.parse(json(key: "   ")))
        XCTAssertNil(StrutReadyLine.parse(json(key: "\t\n")))
    }

    func testKeyAndHostAreTrimmed() {
        let parsed = StrutReadyLine.parse(json(host: "  localhost  ", key: "  abc  "))
        XCTAssertEqual(parsed?.host, "localhost")
        XCTAssertEqual(parsed?.key, "abc")
    }
}
