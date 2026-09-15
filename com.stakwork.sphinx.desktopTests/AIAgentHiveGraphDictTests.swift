//
//  AIAgentHiveGraphDictTests.swift
//  com.stakwork.sphinx.desktopTests
//
//  Guards Hive graph dictionary iteration against Cocoa type confusion
//  (NSIndexPath, JSON arrays/strings) so Swift never messages a
//  non-dictionary with countByEnumeratingWithState:. Exercises
//  JSONSerialization.dictionary(from:source:) — the single consolidated
//  safe-dictionary helper (formerly duplicated as AIAgentManager's
//  nsDictionaryAsStringKeyed, merged into JSONSerialization so every call
//  site, including the Sentry telemetry, shares one implementation).
//

import XCTest
@testable import com_stakwork_sphinx_desktop

final class AIAgentHiveGraphDictTests: XCTestCase {

    // MARK: - JSONSerialization.dictionary(from:source:)

    func testHelper_nilReturnsNil() {
        XCTAssertNil(JSONSerialization.dictionary(from: nil, source: "test"))
    }

    func testHelper_jsonArrayReturnsNil() throws {
        let obj = try JSONSerialization.jsonObject(with: Data("[]".utf8))
        XCTAssertNil(JSONSerialization.dictionary(from: obj, source: "test"))
    }

    func testHelper_jsonStringReturnsNil() throws {
        let obj = try JSONSerialization.jsonObject(
            with: Data("\"hi\"".utf8),
            options: .allowFragments
        )
        XCTAssertNil(JSONSerialization.dictionary(from: obj, source: "test"))
    }

    func testHelper_emptyObjectReturnsEmptyDict() throws {
        let obj = try JSONSerialization.jsonObject(with: Data("{}".utf8))
        let result = JSONSerialization.dictionary(from: obj, source: "test")
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.isEmpty ?? false)
    }

    func testHelper_nsIndexPathReturnsNilWithoutThrowing() {
        let path = NSIndexPath()
        let result = JSONSerialization.dictionary(from: path, source: "test")
        XCTAssertNil(result)
    }

    func testHelper_taggedEmptyIndexPathReturnsNilWithoutThrowing() {
        let path = NSIndexPath(indexes: [], length: 0)
        let result = JSONSerialization.dictionary(from: path, source: "test")
        XCTAssertNil(result)
    }

    func testHelper_jsonObjectReturnsNativeDictSafeToIterate() throws {
        let obj = try JSONSerialization.jsonObject(with: Data("{\"a\":1}".utf8))
        XCTAssertTrue(obj is NSDictionary)

        guard let copied = JSONSerialization.dictionary(from: obj, source: "test") else {
            XCTFail("expected native dictionary")
            return
        }
        XCTAssertEqual(copied["a"] as? Int, 1)

        var iteratedKeys: [String] = []
        for (key, _) in copied {
            iteratedKeys.append(key)
        }
        XCTAssertEqual(iteratedKeys, ["a"])
    }

    func testHelper_dropsNonStringKeys() {
        let ns = NSMutableDictionary()
        ns[NSNumber(value: 1)] = "num-key"
        ns["ok"] = "string-key"
        let result = JSONSerialization.dictionary(from: ns, source: "test")
        XCTAssertEqual(result?["ok"] as? String, "string-key")
        XCTAssertEqual(result?.count, 1)
    }

    // MARK: - anyDictToCodableJSON

    func testAnyDictToCodableJSON_nestedObjectRoundTrips() {
        let nested: [String: Any] = ["b": "world"]
        let dict: [String: Any] = ["a": "hello", "nested": nested]
        let result = AIAgentManager.anyDictToCodableJSON(dict)

        guard case .string(let a) = result["a"] else {
            XCTFail("expected string a")
            return
        }
        XCTAssertEqual(a, "hello")

        guard case .object(let inner) = result["nested"],
              case .string(let b) = inner["b"] else {
            XCTFail("expected nested object")
            return
        }
        XCTAssertEqual(b, "world")
    }

    func testAnyDictToCodableJSON_emptyObjectReturnsEmpty() {
        let result = AIAgentManager.anyDictToCodableJSON([:])
        XCTAssertTrue(result.isEmpty)
    }

    func testAnyDictToCodableJSON_nestedEmptyObjectIsEmptyObject() {
        let dict: [String: Any] = ["inner": [String: Any]()]
        let result = AIAgentManager.anyDictToCodableJSON(dict)
        guard case .object(let inner) = result["inner"] else {
            XCTFail("expected nested empty object")
            return
        }
        XCTAssertTrue(inner.isEmpty)
    }

    func testAnyDictToCodableJSON_nestedNSIndexPathSkippedWithoutThrowing() {
        let dict: [String: Any] = ["good": "ok", "bad": NSIndexPath()]
        let result = AIAgentManager.anyDictToCodableJSON(dict)
        guard case .string(let value) = result["good"] else {
            XCTFail("expected string for good key")
            return
        }
        XCTAssertEqual(value, "ok")
        XCTAssertNil(result["bad"])
    }

    func testAnyDictToCodableJSON_jsonObjectRoundTrips() throws {
        let obj = try JSONSerialization.jsonObject(
            with: Data("{\"a\":\"1\",\"nested\":{\"b\":\"2\"}}".utf8)
        )
        guard let copied = JSONSerialization.dictionary(from: obj, source: "test") else {
            XCTFail("expected dictionary")
            return
        }
        let result = AIAgentManager.anyDictToCodableJSON(copied)
        guard case .string(let a) = result["a"] else {
            XCTFail("expected string a")
            return
        }
        XCTAssertEqual(a, "1")
        guard case .object(let nested) = result["nested"],
              case .string(let b) = nested["b"] else {
            XCTFail("expected nested b")
            return
        }
        XCTAssertEqual(b, "2")
    }

    // MARK: - jsonStringToStringDict / parseDict

    func testJsonStringToStringDict_nestedObjectRoundTrips() {
        let result = AIAgentManager.jsonStringToStringDict(
            "{\"a\":\"1\",\"nested\":{\"b\":\"2\"}}"
        )
        XCTAssertEqual(result?["a"], "1")
        XCTAssertNotNil(result?["nested"])
        XCTAssertTrue(result?["nested"]?.contains("b") ?? false)
    }

    func testJsonStringToStringDict_jsonArrayReturnsNil() {
        XCTAssertNil(AIAgentManager.jsonStringToStringDict("[]"))
    }

    func testJsonStringToStringDict_jsonStringReturnsNil() {
        XCTAssertNil(AIAgentManager.jsonStringToStringDict("\"hi\""))
    }

    func testJsonStringToStringDict_emptyObjectReturnsNil() {
        XCTAssertNil(AIAgentManager.jsonStringToStringDict("{}"))
    }

    // MARK: - mergeCanvasPayloads

    func testMergeCanvasPayloads_validPayloadMerges() {
        let messages: [[String: Any]] = [[
            "toolCalls": [
                [
                    "toolName": "",
                    "output": [
                        "payload": ["workspaceId": "ws-1"],
                        "meta": ["workspaceSlug": "alpha"]
                    ]
                ],
                [
                    "toolName": "propose_feature",
                    "output": ["payload": ["proposalId": "p1"]]
                ]
            ]
        ]]
        let merged = AIAgentManager.mergeCanvasPayloads(into: messages)
        let toolCalls = merged[0]["toolCalls"] as? [[String: Any]]
        let propose = toolCalls?.first(where: { ($0["toolName"] as? String) == "propose_feature" })
        let output = propose?["output"] as? [String: Any]
        let payload = output?["payload"] as? [String: Any]
        XCTAssertEqual(payload?["proposalId"] as? String, "p1")
        XCTAssertEqual(payload?["workspaceId"] as? String, "ws-1")
        let meta = output?["meta"] as? [String: Any]
        XCTAssertEqual(meta?["workspaceSlug"] as? String, "alpha")
    }

    func testMergeCanvasPayloads_nsIndexPathPayloadSkippedWithoutThrowing() {
        let messages: [[String: Any]] = [[
            "toolCalls": [
                [
                    "toolName": "",
                    "output": ["payload": NSIndexPath()]
                ],
                [
                    "toolName": "propose_feature",
                    "output": ["payload": ["proposalId": "p1"]]
                ]
            ]
        ]]
        let merged = AIAgentManager.mergeCanvasPayloads(into: messages)
        let toolCalls = merged[0]["toolCalls"] as? [[String: Any]]
        let propose = toolCalls?.first(where: { ($0["toolName"] as? String) == "propose_feature" })
        let output = propose?["output"] as? [String: Any]
        let payload = output?["payload"] as? [String: Any]
        XCTAssertEqual(payload?["proposalId"] as? String, "p1")
        XCTAssertNil(payload?["workspaceId"])
    }
}
