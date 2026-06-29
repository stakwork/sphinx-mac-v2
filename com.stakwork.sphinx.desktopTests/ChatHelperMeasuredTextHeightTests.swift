//
//  ChatHelperMeasuredTextHeightTests.swift
//  com.stakwork.sphinx.desktopTests
//
//  Unit tests for ChatHelper.measuredTextHeight(for:width:)
//

import XCTest
@testable import com_stakwork_sphinx_desktop

class ChatHelperMeasuredTextHeightTests: XCTestCase {

    // MARK: - Fixtures

    /// Long markdown-like formatted message with headings, bullets, blank lines, and emoji
    let markdownFixture1 = """
    # Getting Started 🚀

    Here's a summary of the key features:

    - **Performance**: Optimized for speed
    - **Reliability**: 99.9% uptime guaranteed
    - **Security**: End-to-end encrypted

    ## Next Steps

    1. Set up your workspace
    2. Invite your team members
    3. Configure integrations

    Let me know if you have any questions! 🎉
    """

    let markdownFixture2 = """
    ## Project Status Update

    The following tasks have been completed:

    - ✅ Initial architecture design
    - ✅ Database schema finalized
    - ⏳ API integration in progress
    - ❌ Frontend not started

    ### Blockers

    There are currently **2 blockers** that need attention:

    1. Missing API credentials for the payment gateway
    2. Unclear requirements for the reporting module

    Please review and provide feedback at your earliest convenience.
    """

    let markdownFixture3 = """
    Hello! 👋

    I've analyzed your request and here's what I found:

    - The issue is caused by an incorrect height calculation
    - The fix involves replacing `boundingRect` with `NSLayoutManager`
    - This affects all formatted messages with multiple paragraphs

    > **Note:** This change is backward compatible and requires no migration.

    Feel free to ask if you need more details! 😊
    """

    let singleLineText = "Hello, world!"
    let plainText = "This is a plain text message without any markdown formatting or special characters."
    let linkHeavyText = "Check out https://sphinx.chat and https://stakwork.com for more details about the platform and its features."
    let emojiOnlyText = "🎉🚀✅❌⏳💡🔥"

    let testWidth: CGFloat = 400.0

    // MARK: - Helper: boundingRect reference (old method)

    private func boundingRectHeight(for string: NSAttributedString, width: CGFloat) -> CGFloat {
        return string.boundingRect(
            with: NSSize(width: width, height: CGFLOAT_MAX),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).height
    }

    private func makeAttributedString(_ text: String) -> NSAttributedString {
        return NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 14)
        ])
    }

    // MARK: - Tests: Markdown fixtures (over-reporting fix)

    func testMarkdownFixture1_measuredLessThanBoundingRect() {
        let attr = makeAttributedString(markdownFixture1)
        let measured = ChatHelper.measuredTextHeight(for: attr, width: testWidth)
        let bounding = boundingRectHeight(for: attr, width: testWidth)
        XCTAssertLessThan(measured, bounding,
            "measuredTextHeight should be strictly less than boundingRect for multi-block markdown (fixture 1)")
    }

    func testMarkdownFixture2_measuredLessThanBoundingRect() {
        let attr = makeAttributedString(markdownFixture2)
        let measured = ChatHelper.measuredTextHeight(for: attr, width: testWidth)
        let bounding = boundingRectHeight(for: attr, width: testWidth)
        XCTAssertLessThan(measured, bounding,
            "measuredTextHeight should be strictly less than boundingRect for multi-block markdown (fixture 2)")
    }

    func testMarkdownFixture3_measuredLessThanBoundingRect() {
        let attr = makeAttributedString(markdownFixture3)
        let measured = ChatHelper.measuredTextHeight(for: attr, width: testWidth)
        let bounding = boundingRectHeight(for: attr, width: testWidth)
        XCTAssertLessThan(measured, bounding,
            "measuredTextHeight should be strictly less than boundingRect for multi-block markdown (fixture 3)")
    }

    func testMarkdownFixture1_matchesLayoutManagerUsedRect() {
        let attr = makeAttributedString(markdownFixture1)
        let measured = ChatHelper.measuredTextHeight(for: attr, width: testWidth)

        // Reproduce the same layout stack to get the reference usedRect
        let textStorage = NSTextStorage(attributedString: attr)
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(containerSize: NSSize(width: testWidth, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = 0
        layoutManager.addTextContainer(container)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: container)
        let expected = ceil(layoutManager.usedRect(for: container).height)

        XCTAssertEqual(measured, expected, accuracy: 1.0,
            "measuredTextHeight must match layoutManager.usedRect height within ±1pt")
    }

    // MARK: - Regression tests: no under-reporting

    func testSingleLine_notUnderReported() {
        let attr = makeAttributedString(singleLineText)
        let measured = ChatHelper.measuredTextHeight(for: attr, width: testWidth)
        XCTAssertGreaterThan(measured, 0, "Single-line message must have positive height")
        // Should be at least one line height (system font 14pt ≈ 17pt line height)
        XCTAssertGreaterThanOrEqual(measured, 10, "Single-line height must not be under-reported")
    }

    func testPlainText_notUnderReported() {
        let attr = makeAttributedString(plainText)
        let measured = ChatHelper.measuredTextHeight(for: attr, width: testWidth)
        XCTAssertGreaterThan(measured, 0, "Plain text message must have positive height")
    }

    func testLinkHeavyText_notUnderReported() {
        let attr = makeAttributedString(linkHeavyText)
        let measured = ChatHelper.measuredTextHeight(for: attr, width: testWidth)
        XCTAssertGreaterThan(measured, 0, "Link-heavy message must have positive height")
    }

    func testEmojiOnly_notUnderReported() {
        let attr = makeAttributedString(emojiOnlyText)
        let measured = ChatHelper.measuredTextHeight(for: attr, width: testWidth)
        XCTAssertGreaterThan(measured, 0, "Emoji-only message must have positive height")
    }

    // MARK: - Edge cases

    func testEmptyString_returnsZero() {
        let attr = makeAttributedString("")
        let measured = ChatHelper.measuredTextHeight(for: attr, width: testWidth)
        XCTAssertEqual(measured, 0, accuracy: 1.0, "Empty string should return ~0 height")
    }

    func testNarrowWidth_stillPositive() {
        let attr = makeAttributedString(markdownFixture1)
        let measured = ChatHelper.measuredTextHeight(for: attr, width: 100)
        XCTAssertGreaterThan(measured, 0, "Narrow width must still produce positive height")
    }
}
