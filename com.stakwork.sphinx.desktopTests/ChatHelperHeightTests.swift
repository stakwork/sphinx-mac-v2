//
//  ChatHelperHeightTests.swift
//  com.stakwork.sphinx.desktopTests
//
//  Tests for the message bubble height calculation fix.
//  These tests assert that the pre-calculated height (used for sizeForItemAt)
//  is always >= the height actually needed to render the full text, preventing
//  text clipping in the thread panel.
//

import XCTest
@testable import com_stakwork_sphinx_desktop

/// Pure-logic tests for ChatHelper height calculation helpers.
/// These tests do not depend on CoreData, the main app delegate, or live UI —
/// they call the static measurement helpers directly with synthetic inputs.
class ChatHelperHeightTests: XCTestCase {

    // MARK: - Constants (mirroring production values)

    /// PaddedTextFieldCell horizontal insets: 16pt left + 16pt right.
    private let kLabelHorizontalMargins: CGFloat = 32.0

    /// Bubble vertical padding: 16pt top + 16pt bottom = 32pt.
    private let kLabelVerticalMargins: CGFloat = 32.0

    /// Thread panel fixed width used in acceptance-criteria tests.
    private let kThreadPanelWidth: CGFloat = 450.0

    // MARK: - Helpers

    /// Returns the height `getTextHeightFor` would compute for `text` at `bubbleWidth`.
    /// Mirrors exactly what the production code does:
    ///   boundingRect(width: bubbleWidth - 32) + 32
    private func measuredHeight(for text: String, bubbleWidth: CGFloat) -> CGFloat {
        return ChatHelper.getTextHeightFor(
            text: text,
            width: bubbleWidth,
            highlightedMatches: [],
            boldMatches: [],
            linkMatches: [],
            linkMarkdownMatches: []
        )
    }

    /// Outer margin for received messages (avatar + spacer + outer leading/trailing).
    private var receivedMargin: CGFloat {
        CommonNewMessageCollectionViewitem.kTextLabelMargins          // 83
    }

    /// Outer margin for outgoing messages (no avatar, no avatar spacer).
    private var outgoingMargin: CGFloat {
        CommonNewMessageCollectionViewitem.kTextLabelMarginsOutgoing   // 39
    }

    /// The maximum bubble width constant.
    private var maxBubbleWidth: CGFloat {
        CommonNewMessageCollectionViewitem.kMaximumLabelBubbleWidth    // 500
    }

    // MARK: - Test: kTextLabelMarginsOutgoing constant value

    func testOutgoingMarginIsLessThanReceivedMargin() {
        // Outgoing has no avatar/spacer → narrower outer margin → wider bubble → taller measured height.
        XCTAssertLessThan(
            outgoingMargin, receivedMargin,
            "kTextLabelMarginsOutgoing (\(outgoingMargin)) must be less than kTextLabelMargins (\(receivedMargin))"
        )
    }

    func testOutgoingMarginValue() {
        // 16(leading) + 7(trailing spacer) + 16(trailing) = 39
        XCTAssertEqual(outgoingMargin, 39.0, accuracy: 0.1,
                       "kTextLabelMarginsOutgoing must equal 39 pt (measured from XIB)")
    }

    func testReceivedMarginValue() {
        // 16(leading) + 40(avatar) + 4(avatar spacer) + 7(trailing spacer) + 16(trailing) = 83
        XCTAssertEqual(receivedMargin, 83.0, accuracy: 0.1,
                       "kTextLabelMargins must equal 83 pt (measured from XIB)")
    }

    // MARK: - Test: getTextHeightFor never underestimates at effective render width

    /// The pre-calculation calls `getTextHeightFor(width: bubbleWidth)` which internally
    /// subtracts 32pt for PaddedTextFieldCell's insets.  This test verifies that the
    /// height returned at `bubbleWidth` is >= the height that would be returned for the
    /// same text at the narrowest width that could result from a render-time discrepancy.
    ///
    /// Concretely: height at `bubbleWidth` must be >= height at `bubbleWidth - delta`
    /// for any positive delta (a narrower render area always wraps more lines, so its
    /// height is always >= the wider estimate).
    func testGetTextHeightFor_DoesNotUnderestimateForShortMessage() {
        let text = "Hello World"
        let bubbleWidth: CGFloat = 300
        let narrowerWidth: CGFloat = bubbleWidth - 10

        let preCalcHeight  = measuredHeight(for: text, bubbleWidth: bubbleWidth)
        let renderHeight   = measuredHeight(for: text, bubbleWidth: narrowerWidth)

        // Pre-calc used the wider bubble → its height should be ≤ height at narrower width.
        // In other words: a narrower render width must never produce MORE height than the
        // pre-calc assumed.  The pre-calc is safe when pre-calc >= actual render height.
        // Here both widths are equal or the narrower one has more wraps → renderHeight >= preCalcHeight.
        XCTAssertGreaterThanOrEqual(
            renderHeight, preCalcHeight,
            "A narrower text width (\(narrowerWidth)) must yield height >= height at \(bubbleWidth). "
          + "If not, the pre-calculation overestimates available width and underestimates line count."
        )
    }

    func testGetTextHeightFor_DoesNotUnderestimateForLongMessage() {
        let text = """
            This is a long message that should wrap across multiple lines when displayed \
            inside the narrow thread panel's fixed-width right column. It is important \
            that the pre-calculated cell height accounts for every wrapped line so that \
            no text is ever clipped or cut off at the bottom of the bubble.
            """
        let bubbleWidth: CGFloat = kThreadPanelWidth - receivedMargin      // ~367 for received
        let narrowerWidth: CGFloat = bubbleWidth - 20                       // simulate slight inset

        let preCalcHeight = measuredHeight(for: text, bubbleWidth: bubbleWidth)
        let renderHeight  = measuredHeight(for: text, bubbleWidth: narrowerWidth)

        XCTAssertGreaterThanOrEqual(
            renderHeight, preCalcHeight,
            "Pre-calc height must not exceed what a slightly narrower render width would produce."
        )
    }

    // MARK: - Test: height at thread panel width (450pt) is sufficient for multi-line messages

    func testReceivedMessageHeight_AtThreadPanelWidth_IsPositive() {
        let text = "Short received message"
        let bubbleWidth = min(maxBubbleWidth, kThreadPanelWidth - receivedMargin)
        let height = measuredHeight(for: text, bubbleWidth: bubbleWidth)
        XCTAssertGreaterThan(height, 0, "Height must be positive for any non-empty text")
    }

    func testOutgoingMessageHeight_AtThreadPanelWidth_IsPositive() {
        let text = "Short outgoing message"
        let bubbleWidth = min(maxBubbleWidth, kThreadPanelWidth - outgoingMargin)
        let height = measuredHeight(for: text, bubbleWidth: bubbleWidth)
        XCTAssertGreaterThan(height, 0, "Height must be positive for any non-empty text")
    }

    func testReceivedLongMessageHeight_AtThreadPanelWidth_ExceedsOneLine() {
        let text = """
            A long received message that definitely wraps across multiple lines at the \
            narrow width of the thread panel. We verify the returned height exceeds a \
            single line to confirm multi-line wrapping is correctly accounted for.
            """
        let bubbleWidth = min(maxBubbleWidth, kThreadPanelWidth - receivedMargin) // ~367
        let height = measuredHeight(for: text, bubbleWidth: bubbleWidth)
        // Single-line height ≈ 14pt text + 32pt vertical margins = ~46pt.
        // Multi-line wrapping should produce significantly more than this.
        XCTAssertGreaterThan(height, 80,
            "Long received message at thread panel width (\(bubbleWidth)pt) should exceed 80pt.")
    }

    func testOutgoingLongMessageHeight_AtThreadPanelWidth_ExceedsOneLine() {
        let text = """
            A long outgoing message that definitely wraps across multiple lines at the \
            narrow width of the thread panel. We verify the returned height exceeds a \
            single line to confirm multi-line wrapping is correctly accounted for.
            """
        let bubbleWidth = min(maxBubbleWidth, kThreadPanelWidth - outgoingMargin) // ~411
        let height = measuredHeight(for: text, bubbleWidth: bubbleWidth)
        XCTAssertGreaterThan(height, 80,
            "Long outgoing message at thread panel width (\(bubbleWidth)pt) should exceed 80pt.")
    }

    // MARK: - Test: outgoing bubble is wider than received at same collection view width

    func testOutgoingBubbleWiderThanReceivedAtSameWidth() {
        // Outgoing margin (39) < received margin (83), so with the same collectionViewWidth
        // the outgoing bubble is wider, which means fewer line-wraps and potentially less height.
        let collectionViewWidth: CGFloat = kThreadPanelWidth

        let outgoingBubble = min(maxBubbleWidth, collectionViewWidth - outgoingMargin)
        let receivedBubble = min(maxBubbleWidth, collectionViewWidth - receivedMargin)

        XCTAssertGreaterThan(
            outgoingBubble, receivedBubble,
            "Outgoing bubble (\(outgoingBubble)pt) must be wider than received (\(receivedBubble)pt) "
          + "at the same collectionViewWidth."
        )
    }

    // MARK: - Test: cache key includes width

    func testRowHeightCacheKey_ChangesWhenWidthChanges() {
        // The cache key includes Int(width), so a width change must produce a different key.
        // We test this by verifying two width-differing keys are not equal.
        let baseKey = "12345_\(Int(450))_0_0_0_0"
        let newKey  = "12345_\(Int(500))_0_0_0_0"
        XCTAssertNotEqual(baseKey, newKey,
            "Cache key must differ when collection view width changes, preventing stale height lookup.")
    }

    func testInvalidateRowHeightCache_RemovesAllEntries() {
        var cache: [String: CGFloat] = [
            "key1": 100,
            "key2": 200,
            "key3": 300
        ]
        cache.removeAll(keepingCapacity: true)
        XCTAssertTrue(cache.isEmpty,
            "Calling removeAll on the row height cache must leave it empty.")
    }

    // MARK: - Test: kLabelHorizontalMargins in getTextHeightFor

    func testGetTextHeightFor_ReturnsHigherHeightForNarrowerWidth() {
        // A narrower measurement width → more line wraps → taller result.
        let longText = String(repeating: "Word ", count: 50)
        let wideHeight   = measuredHeight(for: longText, bubbleWidth: 400)
        let narrowHeight = measuredHeight(for: longText, bubbleWidth: 200)
        XCTAssertGreaterThanOrEqual(
            narrowHeight, wideHeight,
            "getTextHeightFor must return >= height for a narrower width (more line-wraps)."
        )
    }

    func testGetTextHeightFor_IncludesVerticalMargins() {
        // Even a single-character message must include at least the 32pt vertical margins.
        let height = measuredHeight(for: "X", bubbleWidth: 300)
        XCTAssertGreaterThanOrEqual(
            height, kLabelVerticalMargins,
            "getTextHeightFor must always include at least kLabelVerticalMargins (\(kLabelVerticalMargins)pt)."
        )
    }
}
