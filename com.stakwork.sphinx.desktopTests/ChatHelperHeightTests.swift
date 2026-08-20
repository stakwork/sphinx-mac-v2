//
//  ChatHelperHeightTests.swift
//  com.stakwork.sphinx.desktopTests
//

import XCTest
@testable import sphinx

final class ChatHelperHeightTests: XCTestCase {

    @MainActor
    func testGetTextHeightForMatchesBoundingRectAfterLinkStrip() {
        let text = "Check this out https://hive.sphinx.chat/w/graphmindset/plan/cmt1iwce9000hjt04m755nqc5"
        let width: CGFloat = 500

        // Manually reproduce what the fixed getTextHeightFor does internally
        let rendered = NSMutableAttributedString(
            attributedString: ChatHelper.markdownRenderer.render(text)
        )
        rendered.removeAttribute(.link, range: NSRange(location: 0, length: rendered.length))
        let expected = rendered.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).height

        let actual = ChatHelper.getTextHeightFor(text: text, width: width, useMarkdown: true)

        XCTAssertEqual(actual, expected, accuracy: 1.0,
            "getTextHeightFor must match boundingRect on a .link-stripped string")
    }
}
