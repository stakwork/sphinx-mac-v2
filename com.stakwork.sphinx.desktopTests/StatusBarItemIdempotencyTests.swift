//
//  StatusBarItemIdempotencyTests.swift
//  com.stakwork.sphinx.desktopTests
//
//  Regression guard for the fix that makes addStatusBarItem() idempotent.
//
//  Background: addStatusBarItem() used to unconditionally reassign
//  `statusBarItem = statusBar.statusItem(withLength:)` on every call, which
//  caused ARC to deallocate the previous NSStatusItem and drop the tray icon
//  from the menu bar on every window transition (splash → PIN → dashboard,
//  re-lock → login). The fix adds a `guard statusBarItem == nil else { return }`
//  at the top of the function so the item is created exactly once per app
//  lifetime. This test asserts that invariant holds.
//

import XCTest
@testable import com_stakwork_sphinx_desktop

final class StatusBarItemIdempotencyTests: XCTestCase {

    private var appDelegate: AppDelegate!

    override func setUp() {
        super.setUp()
        appDelegate = AppDelegate()
    }

    override func tearDown() {
        appDelegate = nil
        super.tearDown()
    }

    // MARK: - Idempotency

    /// Calling addStatusBarItem() twice must produce the same NSStatusItem
    /// instance both times. If this test fails it means the guard was removed
    /// or the property was reassigned before the second call.
    func testAddStatusBarItem_IsIdempotent() {
        appDelegate.addStatusBarItem()
        let firstItem = appDelegate.statusBarItem

        appDelegate.addStatusBarItem()
        let secondItem = appDelegate.statusBarItem

        XCTAssertNotNil(firstItem, "statusBarItem must be non-nil after the first call")
        XCTAssertNotNil(secondItem, "statusBarItem must be non-nil after the second call")

        // ObjectIdentifier uniquely identifies the object instance in memory.
        // If they differ, ARC created a second NSStatusItem and the tray icon
        // would have vanished on the second call.
        XCTAssertEqual(
            ObjectIdentifier(firstItem!),
            ObjectIdentifier(secondItem!),
            "addStatusBarItem() must not replace an existing NSStatusItem: " +
            "the same instance must be retained across multiple calls."
        )
    }

    /// A third (or more) invocation must still return the original item,
    /// covering the splash → PIN → dashboard three-call path.
    func testAddStatusBarItem_IsIdempotentAcrossMultipleCalls() {
        appDelegate.addStatusBarItem()
        let originalId = ObjectIdentifier(appDelegate.statusBarItem!)

        for _ in 1...5 {
            appDelegate.addStatusBarItem()
        }

        XCTAssertEqual(
            ObjectIdentifier(appDelegate.statusBarItem!),
            originalId,
            "statusBarItem must remain the same instance across all subsequent calls."
        )
    }

    // MARK: - Badge safety (no crash before first creation)

    /// setBadge(count:) must not crash when called before addStatusBarItem()
    /// has run. Prior to the hardening fix, the force-unwrapped statusBarItem
    /// would trap in this scenario.
    func testSetBadgeCount_BeforeStatusItemCreated_IsNoop() {
        // statusBarItem is nil here (addStatusBarItem has not been called).
        // This must not crash.
        XCTAssertNoThrow(appDelegate.setBadge(count: 3),
            "setBadge(count:) must not crash when statusBarItem is nil")
        XCTAssertNoThrow(appDelegate.setBadge(count: 0),
            "setBadge(count:) must not crash when statusBarItem is nil")
    }

    /// setBadge(count:) must continue to work normally after the status item
    /// has been created.
    func testSetBadgeCount_AfterStatusItemCreated_DoesNotCrash() {
        appDelegate.addStatusBarItem()
        XCTAssertNotNil(appDelegate.statusBarItem)

        XCTAssertNoThrow(appDelegate.setBadge(count: 5),
            "setBadge(count:) must not crash after statusBarItem is created")
        XCTAssertNoThrow(appDelegate.setBadge(count: 0),
            "setBadge(count:) must not crash after statusBarItem is created")
    }
}
