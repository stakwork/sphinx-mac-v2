// FrameBuilderTests.swift
// Tests for FrameBuilder: symbol parsing, inApp classification, repo-relative filenames.
// Includes macOS-specific fixture verifying Sphinx vs AppKit/CoreFoundation frame classification.

import XCTest
@testable import SphinxErrorReporter

final class FrameBuilderTests: XCTestCase {

    // MARK: - macOS in-app classification

    func testMacOS_SphinxFrames_AreInApp() {
        let frames = FrameBuilder.build(
            from: SampleCallStackSymbols.macOSDebugStack,
            mainImageName: "Sphinx"
        )
        XCTAssertNotNil(frames, "Should produce frames from macOS debug stack")
        let sphinxFrames = frames!.filter { $0.filename.contains("Sphinx") || $0.inApp == true }
        XCTAssertFalse(sphinxFrames.isEmpty, "Should have at least one in-app Sphinx frame")

        // First two frames are from Sphinx image
        XCTAssertEqual(frames![0].inApp, true)
        XCTAssertEqual(frames![1].inApp, true)
    }

    func testMacOS_AppKitFrames_AreNotInApp() {
        let frames = FrameBuilder.build(
            from: SampleCallStackSymbols.macOSDebugStack,
            mainImageName: "Sphinx"
        )
        XCTAssertNotNil(frames)

        // AppKit frames (index 2, 3) should be not in-app
        let appKitFrames = frames!.filter { $0.filename == "AppKit" }
        XCTAssertFalse(appKitFrames.isEmpty, "Should have AppKit frames")
        for frame in appKitFrames {
            XCTAssertEqual(frame.inApp, false, "AppKit frames must not be in-app")
        }
    }

    func testMacOS_CoreFoundationFrames_AreNotInApp() {
        let frames = FrameBuilder.build(
            from: SampleCallStackSymbols.macOSDebugStack,
            mainImageName: "Sphinx"
        )
        XCTAssertNotNil(frames)
        let cfFrames = frames!.filter { $0.filename == "CoreFoundation" }
        for frame in cfFrames {
            XCTAssertEqual(frame.inApp, false)
        }
    }

    func testMacOS_InAppFrames_HaveRepoRelativeFilename() {
        let frames = FrameBuilder.build(
            from: SampleCallStackSymbols.macOSDebugStack,
            mainImageName: "Sphinx"
        )
        XCTAssertNotNil(frames)
        let inAppFrames = frames!.filter { $0.inApp == true }
        for frame in inAppFrames {
            // Repo-relative filename should contain the module name, not just raw system path
            XCTAssertTrue(frame.filename.contains("Sphinx"),
                          "In-app frame filename should contain module name: \(frame.filename)")
        }
    }

    // MARK: - Stripped / release stack

    func testMacOS_StrippedStack_ProducesFramesOrNil() {
        // For stripped stacks, frames may be produced with nil function names
        let frames = FrameBuilder.build(
            from: SampleCallStackSymbols.macOSStrippedStack,
            mainImageName: "Sphinx"
        )
        // May be nil or partial — but should NOT crash
        if let frames = frames {
            for frame in frames {
                XCTAssertNotNil(frame.filename, "Each frame must have a filename")
                // function can be nil for stripped frames
            }
        }
        // No assertion on nil — stripped frames may legitimately yield no parseable symbols
    }

    func testMacOS_StrippedStack_InAppClassification_StillWorks() {
        let frames = FrameBuilder.build(
            from: SampleCallStackSymbols.macOSStrippedStack,
            mainImageName: "Sphinx"
        )
        if let frames = frames {
            let sphinxFrames = frames.filter { $0.inApp == true }
            let systemFrames = frames.filter { $0.inApp == false }
            // Sphinx frames exist and are classified correctly even without symbols
            XCTAssertFalse(sphinxFrames.isEmpty, "Stripped Sphinx frames should still be in-app")
            XCTAssertFalse(systemFrames.isEmpty, "System frames should not be in-app")
        }
    }

    // MARK: - iOS fixture (cross-platform validation)

    func testIOS_SphinxFrames_AreInApp() {
        let frames = FrameBuilder.build(
            from: SampleCallStackSymbols.iOSDebugStack,
            mainImageName: "sphinx"   // iOS uses lowercase bundle name
        )
        XCTAssertNotNil(frames)
        XCTAssertEqual(frames![0].inApp, true)
        XCTAssertEqual(frames![1].inApp, true)
    }

    func testIOS_UIKitFrames_AreNotInApp() {
        let frames = FrameBuilder.build(
            from: SampleCallStackSymbols.iOSDebugStack,
            mainImageName: "sphinx"
        )
        XCTAssertNotNil(frames)
        let uiKitFrames = frames!.filter { $0.filename == "UIKitCore" }
        for frame in uiKitFrames {
            XCTAssertEqual(frame.inApp, false)
        }
    }

    // MARK: - Empty / malformed input

    func testEmptyStack_ReturnsNil() {
        let frames = FrameBuilder.build(from: [], mainImageName: "Sphinx")
        XCTAssertNil(frames, "Empty stack should return nil")
    }

    func testMalformedLines_AreSkipped() {
        let malformed = ["", "only_one_part", "two parts"]
        let frames = FrameBuilder.build(from: malformed, mainImageName: "Sphinx")
        XCTAssertNil(frames, "Malformed lines should be skipped, returning nil")
    }

    // MARK: - isAppFrame helper

    func testIsAppFrame_CaseInsensitive() {
        XCTAssertTrue(FrameBuilder.isAppFrame(imageName: "Sphinx", appImageName: "sphinx"))
        XCTAssertTrue(FrameBuilder.isAppFrame(imageName: "SPHINX", appImageName: "Sphinx"))
        XCTAssertFalse(FrameBuilder.isAppFrame(imageName: "AppKit", appImageName: "Sphinx"))
    }

    func testIsAppFrame_EmptyAppImageName_ReturnsFalse() {
        XCTAssertFalse(FrameBuilder.isAppFrame(imageName: "Sphinx", appImageName: ""))
    }
}
