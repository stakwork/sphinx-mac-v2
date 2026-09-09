//
//  StrutTranscriptTests.swift
//  com.stakwork.sphinx.desktopTests
//

import XCTest
@testable import com_stakwork_sphinx_desktop

final class StrutTranscriptTests: XCTestCase {

    func testPartialReplacesLiveText() {
        var state = StrutTranscriptState()
        state.apply(partial: "hel")
        XCTAssertEqual(state.liveText, "hel")
        XCTAssertEqual(state.committedText, "")

        state.apply(partial: "hello")
        XCTAssertEqual(state.liveText, "hello")
        XCTAssertEqual(state.committedText, "")
    }

    func testSequentialFinalsJoinWithSingleSpace() {
        var state = StrutTranscriptState()
        XCTAssertEqual(state.apply(final: "hello"), "hello")
        XCTAssertEqual(state.apply(final: "world"), "hello world")
        XCTAssertEqual(state.committedText, "hello world")
        XCTAssertEqual(state.liveText, "")
    }

    func testPunctuationOnlyFinalGluesWithoutSpace() {
        var state = StrutTranscriptState()
        state.apply(partial: "hello")
        XCTAssertEqual(state.apply(final: "hello"), "hello")
        XCTAssertEqual(state.apply(final: "."), "hello.")
        XCTAssertEqual(state.committedText, "hello.")
        XCTAssertEqual(state.liveText, "")
    }

    func testWhitespacePunctuationIsPunctuationOnly() {
        var state = StrutTranscriptState()
        _ = state.apply(final: "ok")
        XCTAssertEqual(state.apply(final: " ! "), "ok!")
    }
}
