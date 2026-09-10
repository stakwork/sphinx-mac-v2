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

    func testEncodeStart_IncludesSessionWhenNonNil() throws {
        let object = try json(
            StrutAudioMessages.encodeStart(sampleRate: 48000, session: "sess-1")
        )
        XCTAssertEqual(object["session"] as? String, "sess-1")
        XCTAssertNil(object["hotwords"])
        XCTAssertNil(object["model"])
        XCTAssertNil(object["partialModel"])
        XCTAssertNil(object["endpoint"])
    }

    func testEncodeStart_OmitsSessionWhenNil() throws {
        let object = try json(
            StrutAudioMessages.encodeStart(sampleRate: 48000, session: nil, hotwords: nil)
        )
        XCTAssertNil(object["session"])
        XCTAssertNil(object["hotwords"])
        XCTAssertEqual(object.count, 2)
    }

    func testEncodeStart_IncludesHotwordsWhenNonEmpty() throws {
        let object = try json(
            StrutAudioMessages.encodeStart(sampleRate: 48000, hotwords: ["Sphinx", "Alice"])
        )
        XCTAssertEqual(stringArray(object["hotwords"]), ["Sphinx", "Alice"])
        XCTAssertNil(object["session"])
    }

    func testEncodeStart_OmitsHotwordsWhenEmpty() throws {
        let object = try json(
            StrutAudioMessages.encodeStart(sampleRate: 48000, hotwords: [])
        )
        XCTAssertNil(object["hotwords"])
        XCTAssertEqual(object.count, 2)
    }

    func testEncodeStart_IncludesSessionAndHotwordsTogether() throws {
        let object = try json(
            StrutAudioMessages.encodeStart(
                sampleRate: 16000,
                session: "abc",
                hotwords: ["Stakwork"]
            )
        )
        XCTAssertEqual(object["type"] as? String, "start")
        XCTAssertEqual(object["sampleRate"] as? Int, 16000)
        XCTAssertEqual(object["session"] as? String, "abc")
        XCTAssertEqual(stringArray(object["hotwords"]), ["Stakwork"])
        XCTAssertNil(object["model"])
        XCTAssertNil(object["partialModel"])
        XCTAssertNil(object["endpoint"])
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

    private func stringArray(_ value: Any?) -> [String]? {
        if let strings = value as? [String] { return strings }
        return (value as? [Any]) as? [String]
    }
}
