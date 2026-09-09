//
//  StrutAudioMessagesTests.swift
//  com.stakwork.sphinx.desktopTests
//

import XCTest
@testable import com_stakwork_sphinx_desktop

final class StrutAudioMessagesTests: XCTestCase {

    func testEncodeStart_SampleRateIsIntegerRoundedNotTruncated() throws {
        let roundedDown = Int((44100.4 as Double).rounded())
        XCTAssertEqual(roundedDown, 44100)
        let downJSON = try json(StrutAudioMessages.encodeStart(sampleRate: roundedDown))
        XCTAssertEqual(downJSON["type"] as? String, "start")
        XCTAssertEqual(downJSON["sampleRate"] as? Int, 44100)
        XCTAssertFalse(String(data: StrutAudioMessages.encodeStart(sampleRate: roundedDown), encoding: .utf8)!.contains("."))

        let roundedUp = Int((44100.6 as Double).rounded())
        XCTAssertEqual(roundedUp, 44101)
        let upJSON = try json(StrutAudioMessages.encodeStart(sampleRate: roundedUp))
        XCTAssertEqual(upJSON["sampleRate"] as? Int, 44101)
    }

    func testEncodeStart_OmitsOptionalFields() throws {
        let object = try json(StrutAudioMessages.encodeStart(sampleRate: 48000))
        XCTAssertNil(object["model"])
        XCTAssertNil(object["partialModel"])
        XCTAssertNil(object["hotwords"])
        XCTAssertNil(object["session"])
        XCTAssertNil(object["endpoint"])
        XCTAssertEqual(object.count, 2)
    }

    func testEncodeEnd() throws {
        let object = try json(StrutAudioMessages.encodeEnd())
        XCTAssertEqual(object["type"] as? String, "end")
        XCTAssertEqual(object.count, 1)
    }

    func testDecodeReadyPartialFinalError() {
        XCTAssertEqual(
            StrutAudioMessages.decodeServerMessage(Data(#"{"type":"ready"}"#.utf8)),
            .ready
        )
        XCTAssertEqual(
            StrutAudioMessages.decodeServerMessage(Data(#"{"type":"partial","text":"hello"}"#.utf8)),
            .partial(text: "hello")
        )
        XCTAssertEqual(
            StrutAudioMessages.decodeServerMessage(
                Data(#"{"type":"final","text":"world","index":2}"#.utf8)
            ),
            .final(text: "world", index: 2)
        )
        XCTAssertEqual(
            StrutAudioMessages.decodeServerMessage(
                Data(#"{"type":"error","message":"nope"}"#.utf8)
            ),
            .error(message: "nope")
        )
    }

    func testDecodeMalformedOrUnknownReturnsNil() {
        XCTAssertNil(StrutAudioMessages.decodeServerMessage(Data("not-json".utf8)))
        XCTAssertNil(StrutAudioMessages.decodeServerMessage(Data("{}".utf8)))
        XCTAssertNil(StrutAudioMessages.decodeServerMessage(Data(#"{"type":"unknown"}"#.utf8)))
        XCTAssertNil(StrutAudioMessages.decodeServerMessage(Data(#"{"type":"partial"}"#.utf8)))
        XCTAssertNil(StrutAudioMessages.decodeServerMessage(Data(#"{"type":"final"}"#.utf8)))
    }

    private func json(_ data: Data) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }
}
