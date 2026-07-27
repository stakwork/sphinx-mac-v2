//
//  PaddedTextFieldTests.swift
//  com.stakwork.sphinx.desktopTests
//
//  Created on 2026-07-23.
//  Copyright © 2026 Sphinx. All rights reserved.
//

import XCTest
@testable import com_stakwork_sphinx_desktop

/// Unit tests for PaddedTextField.intrinsicContentSize capping behaviour.
///
/// The async `DispatchQueue.main.async { setupPaddedCell() }` dispatch in
/// PaddedTextField's init means PaddedTextFieldCell is NOT yet installed
/// immediately after `init(frame:)`. We drain the main run-loop once so the
/// async block fires before any measurement, then call `setupPaddedCell()`
/// directly to guarantee the cell is present regardless of ordering.
class PaddedTextFieldTests: XCTestCase {

    // MARK: - Helpers

    /// Build a PaddedTextField with a known width and a system font whose
    /// metrics are deterministic in a headless test sandbox (no Roboto-Light).
    private func makeField(width: CGFloat = 300) -> PaddedTextField {
        let frame = NSRect(x: 0, y: 0, width: width, height: 400)
        let field = PaddedTextField(frame: frame)

        // Drain the run-loop so the async `setupPaddedCell()` fires, then call
        // it again directly to make the test deterministic regardless of order.
        RunLoop.main.run(until: Date())
        field.setupPaddedCell()

        // Use system font so the test is independent of Roboto-Light availability.
        field.font = NSFont.systemFont(ofSize: 15)

        // Allow wrapping (matches the thread-message label configuration).
        field.maximumNumberOfLines = 0
        field.lineBreakMode = .byWordWrapping

        return field
    }

    /// Compute the unclamped full-height that `boundingRect` returns for `text`
    /// at the given effective width (field.bounds.width minus hPad).
    private func unclampedHeight(for text: String, field: PaddedTextField) -> CGFloat {
        let hPad = field.contentPadding.left + field.contentPadding.right
        let vPad = field.contentPadding.top  + field.contentPadding.bottom
        let effectiveWidth = field.bounds.width - hPad

        let attrs: [NSAttributedString.Key: Any] = [
            .font: field.font ?? NSFont.systemFont(ofSize: 15)
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let measured = ceil(attrStr.boundingRect(
            with: NSSize(width: effectiveWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).height)
        return measured + vPad
    }

    // MARK: - Tests

    /// When `maximumHeight` is set, `intrinsicContentSize.height` must be
    /// clamped to `maximumHeight` (± 1 pt rounding tolerance) even for a
    /// 10-line string whose unclamped height would be much larger.
    func testMaximumHeight_ClampsTallContent() {
        let field = makeField(width: 300)

        // Build a deterministic 2-line cap height using the field's font.
        let font = field.font ?? NSFont.systemFont(ofSize: 15)
        let lineHeight = font.ascender - font.descender + font.leading
        let twoLineHeight = ceil(lineHeight * 2)

        // A string that spans at least 10 lines at 300pt width.
        let longText = Array(repeating: "The quick brown fox jumps over the lazy dog.", count: 10)
            .joined(separator: " ")

        field.maximumHeight = twoLineHeight
        field.stringValue   = longText
        field.font          = font
        field.invalidateIntrinsicContentSize()

        let ics = field.intrinsicContentSize
        let vPad = field.contentPadding.top + field.contentPadding.bottom

        XCTAssertLessThanOrEqual(
            ics.height,
            twoLineHeight + vPad + 1.0,
            "intrinsicContentSize.height (\(ics.height)) should be ≤ maximumHeight (\(twoLineHeight)) + vPad (\(vPad)) + 1pt tolerance"
        )
    }

    /// When `maximumHeight == 0` (the default — used by non-thread bubble labels),
    /// `intrinsicContentSize.height` must equal the full unclamped `boundingRect`
    /// height. This is the regression guard that ensures regular chat bubbles
    /// are not accidentally capped.
    func testMaximumHeightZero_DoesNotClampLongContent() {
        let field = makeField(width: 300)

        let longText = Array(repeating: "The quick brown fox jumps over the lazy dog.", count: 10)
            .joined(separator: " ")

        // Leave maximumHeight at its default (0).
        XCTAssertEqual(field.maximumHeight, 0, "maximumHeight should default to 0")

        field.stringValue = longText
        field.font = NSFont.systemFont(ofSize: 15)
        field.invalidateIntrinsicContentSize()

        let ics = field.intrinsicContentSize
        let expected = unclampedHeight(for: longText, field: field)

        XCTAssertEqual(
            ics.height,
            expected,
            accuracy: 2.0,
            "With maximumHeight == 0, intrinsicContentSize.height (\(ics.height)) should match full unclamped height (\(expected)) — no capping for regular bubbles"
        )
    }

    /// Verify that `intrinsicContentSize.width` is never set to a nonsense value
    /// derived from `noIntrinsicMetric` (-1). For a wrapping NSTextField, super
    /// returns noIntrinsicMetric for width; the fix must leave it unchanged.
    func testNoIntrinsicMetricWidthIsNotCorrupted() {
        let field = makeField(width: 300)
        field.stringValue = "Short text"
        field.font = NSFont.systemFont(ofSize: 15)
        field.invalidateIntrinsicContentSize()

        let ics = field.intrinsicContentSize
        // A corrupted value (super.width + hPad when super.width == noIntrinsicMetric)
        // would be approximately -1 + 32 = 31. Guard that we never produce that.
        let corruptedValue: CGFloat = NSView.noIntrinsicMetric + (field.contentPadding.left + field.contentPadding.right)
        XCTAssertNotEqual(
            ics.width,
            corruptedValue,
            accuracy: 1.0,
            "intrinsicContentSize.width must not equal noIntrinsicMetric + hPad (~31pt); that collapses the field"
        )
    }

    /// Verify the height cache invalidates when text changes: after changing
    /// `stringValue` + calling `invalidateIntrinsicContentSize()`, the new
    /// height must reflect the new text.
    func testCacheInvalidatesOnTextChange() {
        let field = makeField(width: 300)
        let font = NSFont.systemFont(ofSize: 15)
        field.font = font

        let shortText = "Short"
        let longText  = Array(repeating: "The quick brown fox jumps over the lazy dog.", count: 10)
            .joined(separator: " ")

        field.stringValue = shortText
        field.invalidateIntrinsicContentSize()
        let heightShort = field.intrinsicContentSize.height

        field.stringValue = longText
        field.invalidateIntrinsicContentSize()
        let heightLong = field.intrinsicContentSize.height

        XCTAssertGreaterThan(
            heightLong,
            heightShort,
            "Height for long text (\(heightLong)) must exceed height for short text (\(heightShort)) after cache invalidation"
        )
    }
}
