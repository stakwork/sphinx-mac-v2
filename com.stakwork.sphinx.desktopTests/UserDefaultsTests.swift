//
//  UserDefaultsTests.swift
//  com.stakwork.sphinx.desktopTests
//
//  Snapshot-then-remove coverage for UserDefaults.deleteAllKeys so a
//  Cocoa-backed dictionaryRepresentation() is never mutated during
//  enumeration (the SIGABRT path on account reset).
//

import XCTest
@testable import com_stakwork_sphinx_desktop

final class UserDefaultsTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "UserDefaultsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        if let suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDeleteAllKeys_RemovesSetKeysWithoutAborting() {
        defaults.set("alpha", forKey: "test.key.a")
        defaults.set(42, forKey: "test.key.b")
        defaults.set(true, forKey: "test.key.c")
        defaults.synchronize()

        XCTAssertEqual(defaults.string(forKey: "test.key.a"), "alpha")
        XCTAssertEqual(defaults.integer(forKey: "test.key.b"), 42)
        XCTAssertTrue(defaults.bool(forKey: "test.key.c"))

        UserDefaults.deleteAllKeys(in: defaults)

        XCTAssertNil(defaults.object(forKey: "test.key.a"))
        XCTAssertNil(defaults.object(forKey: "test.key.b"))
        XCTAssertNil(defaults.object(forKey: "test.key.c"))
    }

    func testDeleteAllKeys_ArraySnapshotSurvivesRemovalDuringLoop() {
        defaults.set("keep-snapshot-safe", forKey: "test.snapshot")
        defaults.synchronize()

        let keys = Array(defaults.dictionaryRepresentation().keys)
        XCTAssertTrue(keys.contains("test.snapshot"))

        for key in keys {
            defaults.removeObject(forKey: key)
        }

        XCTAssertNil(defaults.object(forKey: "test.snapshot"))
        XCTAssertTrue(keys.contains("test.snapshot"))
    }
}
