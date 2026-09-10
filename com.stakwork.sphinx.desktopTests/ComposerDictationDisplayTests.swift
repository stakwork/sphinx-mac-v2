//
//  ComposerDictationDisplayTests.swift
//  com.stakwork.sphinx.desktopTests
//

import XCTest
@testable import com_stakwork_sphinx_desktop

final class ComposerDictationDisplayTests: XCTestCase {

    func testPrefixPreservedAfterResetAndStart() {
        var display = ComposerDictationDisplay()
        display.setPrefix("stale")
        display.apply(final: "gone")

        display.reset()
        display.setPrefix("Already typed")
        display.apply(final: "hello")

        XCTAssertTrue(display.fieldText.hasPrefix("Already typed"))
        XCTAssertEqual(display.fieldText, "Already typed hello")
        XCTAssertFalse(display.fieldText.contains("stale"))
        XCTAssertFalse(display.fieldText.contains("gone"))
    }

    func testSequentialFinalsJoinWithSingleSpace() {
        var display = ComposerDictationDisplay()
        display.apply(final: "hello")
        display.apply(final: "world")
        XCTAssertEqual(display.fieldText, "hello world")
    }

    func testPartialReplacesPreviousPartial() {
        var display = ComposerDictationDisplay()
        display.setPrefix("Note")
        display.apply(partial: "hel")
        XCTAssertEqual(display.fieldText, "Note hel")

        display.apply(partial: "hello")
        XCTAssertEqual(display.fieldText, "Note hello")
        XCTAssertFalse(display.fieldText.contains("helhello"))
        XCTAssertFalse(display.fieldText.contains("hel hello"))
    }

    func testEmptyPrefixHasNoLeadingSpace() {
        var display = ComposerDictationDisplay()
        display.setPrefix("")
        display.apply(final: "hello")
        XCTAssertEqual(display.fieldText, "hello")

        display.apply(partial: "world")
        XCTAssertEqual(display.fieldText, "hello world")
        XCTAssertFalse(display.fieldText.hasPrefix(" "))
    }

    func testPunctuationGlueAtPrefixBoundary() {
        var display = ComposerDictationDisplay()
        display.setPrefix("Hello")
        display.apply(final: ".")
        XCTAssertEqual(display.fieldText, "Hello.")
        XCTAssertNotEqual(display.fieldText, "Hello .")
    }

    func testCommittedTextExcludesPrefixAndLivePartial() {
        var display = ComposerDictationDisplay()
        display.setPrefix("Note")
        display.apply(final: "hello")
        display.apply(partial: "wor")

        XCTAssertEqual(display.committedText, "hello")
        XCTAssertEqual(display.fieldText, "Note hello wor")
        XCTAssertFalse(display.committedText.contains("Note"))
        XCTAssertFalse(display.committedText.contains("wor"))
    }
}
