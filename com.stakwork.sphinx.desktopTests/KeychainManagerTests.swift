//
//  KeychainManagerTests.swift
//  com.stakwork.sphinx.desktopTests
//
//  Host-backed unit tests for KeychainManager. Injects an in-memory
//  KeychainBackingStore — never the real sphinx-app keychain.
//

import XCTest
@testable import com_stakwork_sphinx_desktop

/// In-memory stand-in for KeychainAccessBackingStore. `@unchecked Sendable`
/// because tests mutate a single-thread dictionary, never the system keychain.
final class InMemoryKeychainBackingStore: KeychainBackingStore, @unchecked Sendable {
    private var values: [String: String] = [:]

    func get(_ key: String) throws -> String? {
        values[key]
    }

    func set(_ value: String, key: String) throws {
        values[key] = value
    }

    func remove(_ key: String) throws {
        values.removeValue(forKey: key)
    }
}

final class KeychainManagerTests: XCTestCase {

    private var store: InMemoryKeychainBackingStore!
    private var manager: KeychainManager!

    override func setUp() {
        super.setUp()
        store = InMemoryKeychainBackingStore()
        manager = KeychainManager(store: store)
    }

    override func tearDown() {
        manager = nil
        store = nil
        super.tearDown()
    }

    func testSaveDeleteGet_StrutApiKeyReturnsNil() {
        let key = KeychainManager.KeychainKeys.strutApiKey.rawValue

        XCTAssertTrue(manager.save(value: "launch-secret", forComposedKey: key))
        XCTAssertEqual(manager.getValueFor(composedKey: key), "launch-secret")

        XCTAssertTrue(manager.deleteValueFor(composedKey: key))
        XCTAssertNil(
            manager.getValueFor(composedKey: key),
            "deleteValueFor must remove from the same store used by save/get"
        )
    }

    func testSaveDeleteGet_UsesTheSameBackingStore() {
        let key = KeychainManager.KeychainKeys.strutApiKey.rawValue

        XCTAssertTrue(manager.save(value: "present", forComposedKey: key))
        XCTAssertEqual(try store.get(key), "present")

        XCTAssertTrue(manager.deleteValueFor(composedKey: key))
        XCTAssertNil(try store.get(key))
        XCTAssertNil(manager.getValueFor(composedKey: key))
    }
}
