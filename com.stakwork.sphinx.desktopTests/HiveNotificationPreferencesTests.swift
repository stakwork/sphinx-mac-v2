//
//  HiveNotificationPreferencesTests.swift
//  com.stakwork.sphinx.desktopTests
//
//  Created on 2026-07-01.
//  Copyright © 2026 Sphinx. All rights reserved.
//

import XCTest
@testable import com_stakwork_sphinx_desktop

class HiveNotificationPreferencesTests: XCTestCase {

    // MARK: - defaultPreferences coverage

    func testDefaultPreferences_ContainsAll11Keys() {
        let defaults = HiveNotificationConstants.defaultPreferences
        let expectedKeys = HiveNotificationConstants.notificationKeys.map { $0.key }
        for key in expectedKeys {
            XCTAssertNotNil(defaults[key], "defaultPreferences should contain key '\(key)'")
        }
        XCTAssertEqual(defaults.count, 11, "defaultPreferences should have exactly 11 entries")
    }

    func testNotificationKeys_Has11Entries() {
        XCTAssertEqual(HiveNotificationConstants.notificationKeys.count, 11)
    }

    func testDefaultValues_MatchSpec() {
        let d = HiveNotificationConstants.defaultPreferences
        XCTAssertEqual(d["TASK_ASSIGNED"],               true)
        XCTAssertEqual(d["FEATURE_ASSIGNED"],            true)
        XCTAssertEqual(d["PLAN_AWAITING_CLARIFICATION"], true)
        XCTAssertEqual(d["PLAN_AWAITING_APPROVAL"],      true)
        XCTAssertEqual(d["PLAN_TASKS_GENERATED"],        true)
        XCTAssertEqual(d["WORKFLOW_HALTED"],              true)
        XCTAssertEqual(d["FEATURE_COMPLETED"],           true)
        XCTAssertEqual(d["FEATURE_DEPLOYED_PRODUCTION"], true)
        XCTAssertEqual(d["TASK_PR_MERGED"],              true)
        XCTAssertEqual(d["GRAPH_CHAT_RESPONSE"],         false)
        XCTAssertEqual(d["WORKSPACE_ACCESS_REQUEST"],    true)
    }

    // MARK: - merged(fetched:) — merge logic

    func testMerge_FetchedValuesOverrideDefaults() {
        // GRAPH_CHAT_RESPONSE defaults to false; server says true
        let fetched: [String: Bool] = [
            "GRAPH_CHAT_RESPONSE": true,
            "TASK_ASSIGNED": false
        ]
        let result = HiveNotificationConstants.merged(fetched: fetched)
        XCTAssertEqual(result["GRAPH_CHAT_RESPONSE"], true,  "Fetched value should override default false")
        XCTAssertEqual(result["TASK_ASSIGNED"],        false, "Fetched value should override default true")
    }

    func testMerge_MissingKeysFallBackToDefaults() {
        // Server returns only one key; rest should come from defaults
        let fetched: [String: Bool] = ["TASK_ASSIGNED": false]
        let result = HiveNotificationConstants.merged(fetched: fetched)

        // Known keys not in fetched retain default values
        XCTAssertEqual(result["FEATURE_ASSIGNED"],            true)
        XCTAssertEqual(result["PLAN_AWAITING_CLARIFICATION"], true)
        XCTAssertEqual(result["PLAN_AWAITING_APPROVAL"],      true)
        XCTAssertEqual(result["PLAN_TASKS_GENERATED"],        true)
        XCTAssertEqual(result["WORKFLOW_HALTED"],              true)
        XCTAssertEqual(result["FEATURE_COMPLETED"],           true)
        XCTAssertEqual(result["FEATURE_DEPLOYED_PRODUCTION"], true)
        XCTAssertEqual(result["TASK_PR_MERGED"],              true)
        XCTAssertEqual(result["GRAPH_CHAT_RESPONSE"],         false)
        XCTAssertEqual(result["WORKSPACE_ACCESS_REQUEST"],    true)
    }

    func testMerge_All11KeysAlwaysPresentInResult() {
        let fetched: [String: Bool] = [:]
        let result = HiveNotificationConstants.merged(fetched: fetched)
        let expectedKeys = HiveNotificationConstants.notificationKeys.map { $0.key }
        for key in expectedKeys {
            XCTAssertNotNil(result[key], "Merged result should always contain key '\(key)'")
        }
    }

    func testMerge_UnknownServerKeyIsPreserved() {
        let fetched: [String: Bool] = ["UNKNOWN_FUTURE_KEY": true]
        let result = HiveNotificationConstants.merged(fetched: fetched)
        XCTAssertEqual(result["UNKNOWN_FUTURE_KEY"], true, "Unknown server keys should be preserved in the merged result")
        // All known defaults still present
        XCTAssertEqual(result.count, 12, "11 defaults + 1 unknown key = 12 entries total")
    }

    func testMerge_EmptyFetchedReturnsDefaults() {
        let result = HiveNotificationConstants.merged(fetched: [:])
        XCTAssertEqual(result, HiveNotificationConstants.defaultPreferences)
    }

    func testMerge_FullServerResponseOverridesAllDefaults() {
        var allFalse: [String: Bool] = [:]
        for (key, _) in HiveNotificationConstants.defaultPreferences {
            allFalse[key] = false
        }
        let result = HiveNotificationConstants.merged(fetched: allFalse)
        for (key, value) in result {
            XCTAssertEqual(value, false, "Key '\(key)' should be false after server override")
        }
    }

    // MARK: - JSON decoding tests

    func testJSONDecode_ValidStringBoolPayload() throws {
        let payload: [String: Bool] = [
            "TASK_ASSIGNED": true,
            "GRAPH_CHAT_RESPONSE": false
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let decoded = (try? JSONSerialization.jsonObject(with: data)) as? [String: Bool]
        XCTAssertNotNil(decoded, "Valid [String: Bool] payload should decode successfully")
        XCTAssertEqual(decoded?["TASK_ASSIGNED"], true)
        XCTAssertEqual(decoded?["GRAPH_CHAT_RESPONSE"], false)
    }

    func testJSONDecode_MalformedPayload_FallsBackToEmptyDict() {
        // Non-boolean values in the JSON — cannot cast to [String: Bool]
        let rawJSON = """
        {"TASK_ASSIGNED": "yes", "GRAPH_CHAT_RESPONSE": 1}
        """.data(using: .utf8)!

        let decoded = (try? JSONSerialization.jsonObject(with: rawJSON)) as? [String: Bool]
        // The cast should fail gracefully, yielding nil (caller falls back to [:])
        XCTAssertNil(decoded, "Mixed-type payload should not cast to [String: Bool]")
    }

    func testJSONDecode_InvalidJSON_FallsBackToEmptyDict() {
        let rawJSON = "not valid json".data(using: .utf8)!
        let decoded = (try? JSONSerialization.jsonObject(with: rawJSON)) as? [String: Bool]
        XCTAssertNil(decoded, "Invalid JSON should not decode and should yield nil")
    }

    func testJSONDecode_EmptyObject_DecodesAsEmptyDict() throws {
        let data = try JSONSerialization.data(withJSONObject: [String: Bool]())
        let decoded = (try? JSONSerialization.jsonObject(with: data)) as? [String: Bool]
        XCTAssertNotNil(decoded)
        XCTAssertTrue(decoded?.isEmpty == true, "Empty JSON object should decode to empty dict")
    }

    func testJSONDecode_AllTruePayload() throws {
        var allTrue: [String: Bool] = [:]
        for (key, _) in HiveNotificationConstants.defaultPreferences {
            allTrue[key] = true
        }
        let data = try JSONSerialization.data(withJSONObject: allTrue)
        let decoded = (try? JSONSerialization.jsonObject(with: data)) as? [String: Bool]
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.count, 11)
        for (key, value) in decoded! {
            XCTAssertEqual(value, true, "Key '\(key)' should be true")
        }
    }
}
