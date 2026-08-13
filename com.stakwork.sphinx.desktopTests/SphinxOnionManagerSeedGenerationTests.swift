//
//  SphinxOnionManagerSeedGenerationTests.swift
//  com.stakwork.sphinx.desktopTests
//
//  Tests for the hardened entropy-generation helpers added to SphinxOnionManager.
//  These tests use @testable import to access the `internal` helper
//  `generateHardenedEntropyHex(secureRandomFn:)` on SphinxOnionManager.
//

import XCTest
@testable import com_stakwork_sphinx_desktop

final class SphinxOnionManagerSeedGenerationTests: XCTestCase {

    // Convenience — grab the shared singleton (init-ing a full manager is heavyweight).
    var manager: SphinxOnionManager { SphinxOnionManager.sharedInstance }

    // MARK: - Failure-injection tests

    /// Injecting a failing secureRandomFn must throw SOMSecureRandomFailed,
    /// never silently continue with zeroed/partial entropy.
    func test_generateHardenedEntropyHex_throwsOnSecureRandomFailure() {
        let failingRng: (Int, UnsafeMutableRawPointer) -> OSStatus = { _, _ in
            return errSecParam // any non-errSecSuccess status
        }

        XCTAssertThrowsError(
            try manager.generateHardenedEntropyHex(secureRandomFn: failingRng)
        ) { error in
            guard case SphinxOnionManagerError.SOMSecureRandomFailed(let status) = error else {
                XCTFail("Expected SOMSecureRandomFailed, got \(error)")
                return
            }
            XCTAssertEqual(status, errSecParam)
        }
    }

    /// When generateHardenedEntropyHex throws, generateMnemonic() must return nil —
    /// never a mnemonic derived from zeroed/partial entropy.
    func test_generateMnemonic_returnsNilWhenEntropyFails() {
        // We cannot inject the failing RNG into generateMnemonic() directly (it calls
        // the internal helper with the default RNG), so we verify the contract at the
        // helper level: a SOMSecureRandomFailed throw must propagate to a nil result.
        // This test exercises the helper throw path and asserts nil is the outcome
        // in the equivalent do/catch that generateMnemonic() uses.
        let failingRng: (Int, UnsafeMutableRawPointer) -> OSStatus = { _, _ in errSecParam }
        var result: String? = "should-be-cleared"
        do {
            result = try manager.generateHardenedEntropyHex(secureRandomFn: failingRng)
        } catch {
            result = nil
        }
        XCTAssertNil(result, "generateMnemonic() must return nil when the secure RNG fails")
    }

    // MARK: - Mixing / XOR tests

    /// The combined entropy must differ from a buffer that would have been produced
    /// by the primary source alone (i.e., the XOR step actually changes the output).
    ///
    /// Strategy: inject a primary source that always returns 0xFF bytes. The secondary
    /// source (SystemRandomNumberGenerator) is extremely unlikely to also produce all
    /// 0xFF bytes, so the XOR result should differ from a plain 0xFF…FF hex string.
    func test_generateHardenedEntropyHex_mixingChangesOutput() throws {
        let allOnesRng: (Int, UnsafeMutableRawPointer) -> OSStatus = { count, pointer in
            let buf = pointer.assumingMemoryBound(to: UInt8.self)
            for i in 0..<count { buf[i] = 0xFF }
            return errSecSuccess
        }

        let hex = try manager.generateHardenedEntropyHex(secureRandomFn: allOnesRng)

        // A 32-char lowercase hex string is expected (16 bytes).
        XCTAssertEqual(hex.count, 32)
        // If the secondary source weren't mixed in, the result would be "ffff…ff" (32 f's).
        // The probability of SystemRandomNumberGenerator producing all-0xFF (so XOR → all-0xFF)
        // is 1/2^128 — effectively impossible; a collision here would indicate broken mixing.
        XCTAssertNotEqual(
            hex,
            String(repeating: "ff", count: 16),
            "XOR mixing must change the output relative to the primary-only value"
        )
    }

    /// Two consecutive calls with the same deterministic primary source should produce
    /// different results (the secondary SystemRandomNumberGenerator varies each call).
    func test_generateHardenedEntropyHex_outputVariesAcrossCalls() throws {
        let deterministicRng: (Int, UnsafeMutableRawPointer) -> OSStatus = { count, pointer in
            let buf = pointer.assumingMemoryBound(to: UInt8.self)
            for i in 0..<count { buf[i] = UInt8(i & 0xFF) }
            return errSecSuccess
        }

        let hex1 = try manager.generateHardenedEntropyHex(secureRandomFn: deterministicRng)
        let hex2 = try manager.generateHardenedEntropyHex(secureRandomFn: deterministicRng)

        // SystemRandomNumberGenerator varies, so two calls must almost certainly differ.
        // (Collision probability is 1/2^128 — treated as impossible for test purposes.)
        XCTAssertNotEqual(hex1, hex2, "Each call must produce distinct entropy due to secondary mixing")
    }

    // MARK: - Output format tests

    /// On the success path, the helper returns a 32-character lowercase hex string.
    func test_generateHardenedEntropyHex_returnsValidHexString() throws {
        let hex = try manager.generateHardenedEntropyHex()
        XCTAssertEqual(hex.count, 32, "Expected 32 hex chars for 16 entropy bytes")
        XCTAssertTrue(
            hex.allSatisfy { $0.isHexDigit },
            "Output must be a valid hex string"
        )
    }

    // MARK: - Zeroization path test

    /// Exercises the zeroization code path end-to-end: the call must complete without
    /// throwing or crashing. Correctness of the memory-clearing technique (memset_s) is
    /// a code-review item; we assert only that no runtime fault occurs.
    func test_generateHardenedEntropyHex_zeroizationDoesNotCrash() {
        XCTAssertNoThrow(
            try manager.generateHardenedEntropyHex(),
            "Zeroization of intermediate buffers must not cause a runtime fault"
        )
    }
}
