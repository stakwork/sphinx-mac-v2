//
//  StrutHotwordListTests.swift
//  com.stakwork.sphinx.desktopTests
//

import XCTest
@testable import com_stakwork_sphinx_desktop

final class StrutHotwordListTests: XCTestCase {

    func testBuild_AlwaysIncludesSphinxAndStakwork() {
        XCTAssertEqual(
            StrutHotwordList.build(from: []),
            ["Sphinx", "Stakwork"]
        )
        XCTAssertEqual(
            StrutHotwordList.build(from: ["Alice"]),
            ["Alice", "Sphinx", "Stakwork"]
        )
    }

    func testBuild_DropsEmptyAndWhitespace() {
        XCTAssertEqual(
            StrutHotwordList.build(from: ["", "  ", "\n", "Bob", "\t"]),
            ["Bob", "Sphinx", "Stakwork"]
        )
    }

    func testBuild_CaseInsensitiveDedupesAgainstInput() {
        XCTAssertEqual(
            StrutHotwordList.build(from: ["alice", "Alice", "ALICE"]),
            ["alice", "Sphinx", "Stakwork"]
        )
        XCTAssertEqual(
            StrutHotwordList.build(from: ["sphinx", "STAKWORK"]),
            ["sphinx", "STAKWORK"]
        )
    }

    func testNicknames_KeepsConfirmedNonEmptyContacts() {
        let names = StrutHotwordList.nicknames(from: [
            .init(
                nickname: "Alice",
                isConfirmed: true,
                isOwner: false,
                isAgent: false,
                fromGroup: false,
                pin: nil
            ),
            .init(
                nickname: "  Bob  ",
                isConfirmed: true,
                isOwner: false,
                isAgent: false,
                fromGroup: false,
                pin: nil
            )
        ])
        XCTAssertEqual(names, ["Alice", "Bob"])
    }

    func testNicknames_ExcludesOwnerAgentFromGroupPendingPinHiddenAndEmpty() {
        let names = StrutHotwordList.nicknames(from: [
            .init(
                nickname: "Owner",
                isConfirmed: true,
                isOwner: true,
                isAgent: false,
                fromGroup: false,
                pin: nil
            ),
            .init(
                nickname: "Agent",
                isConfirmed: true,
                isOwner: false,
                isAgent: true,
                fromGroup: false,
                pin: nil
            ),
            .init(
                nickname: "TribeRow",
                isConfirmed: true,
                isOwner: false,
                isAgent: false,
                fromGroup: true,
                pin: nil
            ),
            .init(
                nickname: "Pending",
                isConfirmed: false,
                isOwner: false,
                isAgent: false,
                fromGroup: false,
                pin: nil
            ),
            .init(
                nickname: "Hidden",
                isConfirmed: true,
                isOwner: false,
                isAgent: false,
                fromGroup: false,
                pin: "1234"
            ),
            .init(
                nickname: "   ",
                isConfirmed: true,
                isOwner: false,
                isAgent: false,
                fromGroup: false,
                pin: nil
            ),
            .init(
                nickname: nil,
                isConfirmed: true,
                isOwner: false,
                isAgent: false,
                fromGroup: false,
                pin: nil
            ),
            .init(
                nickname: "KeepMe",
                isConfirmed: true,
                isOwner: false,
                isAgent: false,
                fromGroup: false,
                pin: nil
            )
        ])
        XCTAssertEqual(names, ["KeepMe"])
    }
}
