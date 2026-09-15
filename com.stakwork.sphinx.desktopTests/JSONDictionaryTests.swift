//
//  JSONDictionaryTests.swift
//  com.stakwork.sphinx.desktopTests
//
//  Guards JSONSerialization.dictionary against non-dictionary payloads
//  (string fragments, arrays, empty input) so Swift never iterates a
//  bridged NSString as a Dictionary.
//

import XCTest
@testable import com_stakwork_sphinx_desktop

final class JSONDictionaryTests: XCTestCase {

    // MARK: - JSONSerialization.dictionary(from:source:)

    func testHelper_stringFragmentReturnsNil() {
        XCTAssertNil(JSONSerialization.dictionary(from: "\"hi\"", source: "test"))
    }

    func testHelper_arrayReturnsNil() {
        XCTAssertNil(JSONSerialization.dictionary(from: "[]", source: "test"))
    }

    func testHelper_emptyStringReturnsNil() {
        XCTAssertNil(JSONSerialization.dictionary(from: "", source: "test"))
    }

    func testHelper_emptyStringFragmentReturnsNil() {
        XCTAssertNil(JSONSerialization.dictionary(from: "\"\"", source: "test"))
    }

    func testHelper_emptyObjectReturnsEmptyDict() {
        let dict = JSONSerialization.dictionary(from: "{}", source: "test")
        XCTAssertNotNil(dict)
        XCTAssertTrue(dict?.isEmpty ?? false)
    }

    func testHelper_objectReturnsNativeDictSafeToIterate() {
        guard let dict = JSONSerialization.dictionary(from: "{\"a\":1}", source: "test") else {
            XCTFail("expected dictionary")
            return
        }
        XCTAssertEqual(dict["a"] as? Int, 1)

        var iteratedKeys: [String] = []
        for (key, _) in dict {
            iteratedKeys.append(key)
        }
        XCTAssertEqual(iteratedKeys, ["a"])
    }

    func testHelper_forInAndCompactMapValuesDoNotTrap() {
        guard let dict = JSONSerialization.dictionary(
            from: "{\"pk1\":5,\"pk2\":9}",
            source: "lastRead"
        ) else {
            XCTFail("expected dictionary")
            return
        }

        var keys: [String] = []
        for (key, value) in dict {
            keys.append(key)
            _ = value
        }
        XCTAssertEqual(Set(keys), ["pk1", "pk2"])

        let mapped = dict.compactMapValues { $0 as? Int }
        XCTAssertEqual(mapped["pk1"], 5)
        XCTAssertEqual(mapped["pk2"], 9)
    }

    func testHelper_dictionaryRepresentationShapedCopiesUnderCatcher() {
        let ns = NSMutableDictionary()
        ns["AppleLanguages"] = ["en"]
        ns["some-color"] = "#fff"
        ns[NSNumber(value: 42)] = "non-string-key"

        guard let copied = JSONSerialization.dictionary(from: ns, source: "colors.defaults") else {
            XCTFail("expected native dictionary")
            return
        }
        XCTAssertEqual(copied["some-color"] as? String, "#fff")
        XCTAssertEqual(copied["AppleLanguages"] as? [String], ["en"])
        XCTAssertEqual(copied.count, 2)

        var iteratedKeys: [String] = []
        for (key, _) in copied {
            iteratedKeys.append(key)
        }
        XCTAssertEqual(Set(iteratedKeys), ["AppleLanguages", "some-color"])
    }

    // MARK: - SphinxOnionManager.parse(jsonString:source:)

    func testParse_stringFragmentReturnsEmptyDict() {
        let result = SphinxOnionManager.sharedInstance.parse(
            jsonString: "\"hi\"",
            source: "lastRead"
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testParse_arrayFragmentReturnsEmptyDict() {
        let result = SphinxOnionManager.sharedInstance.parse(
            jsonString: "[]",
            source: "muteLevels"
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testParse_validObjectUnchanged() {
        let result = SphinxOnionManager.sharedInstance.parse(
            jsonString: "{\"pk\":7}",
            source: "lastRead"
        )
        XCTAssertEqual(result["pk"] as? Int, 7)
    }

    // MARK: - jsonStringToStringDict

    func testJsonStringToStringDict_validObject() {
        let result = AIAgentManager.jsonStringToStringDict("{\"a\":\"1\"}")
        XCTAssertEqual(result?["a"], "1")
    }

    func testJsonStringToStringDict_doubleEncodedObjectUnwraps() {
        let result = AIAgentManager.jsonStringToStringDict("\"{\\\"a\\\":\\\"1\\\"}\"")
        XCTAssertEqual(result?["a"], "1")
    }

    func testJsonStringToStringDict_stringFragmentReturnsNil() {
        XCTAssertNil(AIAgentManager.jsonStringToStringDict("\"hi\""))
    }

    func testJsonStringToStringDict_emptyReturnsNil() {
        XCTAssertNil(AIAgentManager.jsonStringToStringDict(""))
    }

    // MARK: - anyDictToCodableJSON

    func testAnyDictToCodableJSON_nestedNSStringDoesNotTrap() {
        let dict: [String: Any] = ["name": NSString(string: "alice")]
        let result = AIAgentManager.anyDictToCodableJSON(dict)
        guard case .string(let value) = result["name"] else {
            XCTFail("expected string branch, not nested object")
            return
        }
        XCTAssertEqual(value, "alice")
    }

    func testAnyDictToCodableJSON_nestedObjectRecurses() {
        let nested = NSMutableDictionary()
        nested["b"] = 1
        let dict: [String: Any] = ["a": nested]
        let result = AIAgentManager.anyDictToCodableJSON(dict)
        guard case .object(let inner) = result["a"] else {
            XCTFail("expected nested object")
            return
        }
        XCTAssertNotNil(inner["b"])
    }
}
