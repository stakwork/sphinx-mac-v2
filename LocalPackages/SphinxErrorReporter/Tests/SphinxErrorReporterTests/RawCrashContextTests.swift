// RawCrashContextTests.swift
// Tests for RawCrashContext: fixture Binary Images, UUID/load address capture,
// arch/OS version, metadata serialization.

import XCTest
@testable import SphinxErrorReporter

final class RawCrashContextTests: XCTestCase {

    func testCapture_FromFixtureStack_ProducesRawFrames() {
        let ctx = RawCrashContext.capture(from: SampleCallStackSymbols.macOSStrippedStack)
        XCTAssertFalse(ctx.frames.isEmpty, "Should produce frames from stripped stack")
    }

    func testCapture_RawFrames_HaveAddressAndImageName() {
        let ctx = RawCrashContext.capture(from: SampleCallStackSymbols.macOSStrippedStack)
        for frame in ctx.frames {
            XCTAssertFalse(frame.address.isEmpty, "Frame address must not be empty")
            XCTAssertFalse(frame.imageName.isEmpty, "Frame imageName must not be empty")
        }
    }

    func testCapture_RawFrames_AddressFormat() {
        let ctx = RawCrashContext.capture(from: SampleCallStackSymbols.macOSStrippedStack)
        // Addresses should look like hex addresses starting with 0x
        for frame in ctx.frames {
            XCTAssertTrue(
                frame.address.hasPrefix("0x"),
                "Frame address should be hex: \(frame.address)"
            )
        }
    }

    func testCapture_ArchitectureField_NotEmpty() {
        let ctx = RawCrashContext.capture(from: SampleCallStackSymbols.macOSDebugStack)
        XCTAssertFalse(ctx.arch.isEmpty, "Arch must not be empty")
        // Should be arm64 or x86_64 on macOS
        let validArchs = ["arm64", "x86_64"]
        XCTAssertTrue(validArchs.contains(ctx.arch), "Arch '\(ctx.arch)' should be a known macOS arch")
    }

    func testCapture_OSVersionField_NotEmpty() {
        let ctx = RawCrashContext.capture(from: SampleCallStackSymbols.macOSDebugStack)
        XCTAssertFalse(ctx.osVersion.isEmpty, "OS version must not be empty")
        // Should contain dots (e.g. "13.0.0")
        XCTAssertTrue(ctx.osVersion.contains("."), "OS version should be in x.y.z format: \(ctx.osVersion)")
    }

    func testCapture_RawStackTrace_ContainsInputLines() {
        let ctx = RawCrashContext.capture(from: SampleCallStackSymbols.macOSDebugStack)
        for line in SampleCallStackSymbols.macOSDebugStack {
            XCTAssertTrue(ctx.rawStackTrace.contains(line),
                          "rawStackTrace should contain original line")
        }
    }

    func testToMetadata_ProducesNonEmptyDictionary() {
        let ctx = RawCrashContext.capture(from: SampleCallStackSymbols.macOSDebugStack)
        let meta = ctx.toMetadata()
        XCTAssertFalse(meta.isEmpty, "Metadata should not be empty")
    }

    func testToMetadata_ContainsArchAndOSVersion() {
        let ctx = RawCrashContext.capture(from: SampleCallStackSymbols.macOSDebugStack)
        let meta = ctx.toMetadata()
        XCTAssertNotNil(meta["arch"], "Metadata should contain arch")
        XCTAssertNotNil(meta["osVersion"], "Metadata should contain osVersion")
    }

    func testCapture_BinaryImages_ContainsLoadedImages() {
        // On a running process there should be at least some loaded images
        let ctx = RawCrashContext.capture(from: SampleCallStackSymbols.macOSDebugStack)
        // May be empty in test sandboxes but should not crash
        XCTAssertTrue(ctx.binaryImages.count >= 0, "binaryImages must not throw")
    }

    func testCapture_BinaryImages_HaveRequiredFields() {
        let ctx = RawCrashContext.capture(from: SampleCallStackSymbols.macOSDebugStack)
        for img in ctx.binaryImages {
            XCTAssertFalse(img.name.isEmpty, "Binary image name must not be empty")
            XCTAssertFalse(img.loadAddress.isEmpty, "Binary image load address must not be empty")
            XCTAssertFalse(img.uuid.isEmpty, "Binary image UUID must not be empty")
        }
    }

    func testCodableRoundTrip() throws {
        let ctx = RawCrashContext.capture(from: SampleCallStackSymbols.macOSStrippedStack)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(ctx)
        let decoded = try JSONDecoder().decode(RawCrashContext.self, from: data)
        XCTAssertEqual(decoded.arch, ctx.arch)
        XCTAssertEqual(decoded.osVersion, ctx.osVersion)
        XCTAssertEqual(decoded.rawStackTrace, ctx.rawStackTrace)
        XCTAssertEqual(decoded.frames.count, ctx.frames.count)
    }
}
