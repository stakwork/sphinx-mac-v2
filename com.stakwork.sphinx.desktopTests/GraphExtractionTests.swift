//
//  GraphExtractionTests.swift
//  com.stakwork.sphinx.desktopTests
//
//  Pure tests (no network, no Core Data): deterministic ids with fixed vectors (the iOS
//  port must reproduce them), extraction parsing, skip rules, privacy switch, op building.
//  Vectors are also listed in docs/graph-extraction.md (computed with python uuid.uuid5).
//

import XCTest
@testable import Sphinx

final class GraphExtractionTests: XCTestCase {

    // MARK: IDs

    func testNamespaceConstant() {
        XCTAssertEqual(GraphIdentifiers.namespace.uuidString.lowercased(), "4dcb6314-9c48-5148-b515-af314187e2fa")
    }

    func testNodeIdVectors() {
        let vectors: [(GraphNodeType, String, String)] = [
            (.person, "Alice", "82522da3-8cb7-5883-91a7-5124738e74e8"),
            (.person, "  ALICE   ", "82522da3-8cb7-5883-91a7-5124738e74e8"),
            (.person, "Alice  Smith", "fde501d2-3812-5d61-b796-8655f9149734"),
            (.place, "Paris", "2d0c2181-9fdc-5e0f-8f4a-b297ad6c25ad"),
            (.place, "\u{FF30}\u{FF41}\u{FF52}\u{FF49}\u{FF53}", "2d0c2181-9fdc-5e0f-8f4a-b297ad6c25ad"),   // fullwidth "Paris"
            (.thing, "\u{FB01}le cabinet", "ca9860c5-aca5-5c79-ac9f-7d51cc5ecaa0"),                           // "ﬁ" ligature
            (.thing, "file cabinet", "ca9860c5-aca5-5c79-ac9f-7d51cc5ecaa0"),
            (.person, "Jos\u{00E9} M\u{00FC}ller", "6a102b2d-7c6c-5059-acce-664621026118"),
            (.person, "\u{5F20}\u{4F1F}", "b79b7fb2-7e3a-5cc5-85c4-bd5ed3c1b828"),
            (.topic, "Machine\tLearning", "977b6346-1a8c-5872-9da1-45e97be0e49e")
        ]
        for (type, name, expected) in vectors {
            XCTAssertEqual(GraphIdentifiers.nodeID(type: type, name: name).uuidString.lowercased(), expected, "\(type) \(name)")
        }
    }

    func testNormalization() {
        XCTAssertEqual(GraphIdentifiers.normalize("  Alice \n  SMITH\t"), "alice smith")
        XCTAssertEqual(GraphIdentifiers.normalize("\u{FF21}\u{FF22}"), "ab")
    }

    func testTypeIsPartOfNodeId() {
        XCTAssertNotEqual(
            GraphIdentifiers.nodeID(type: .person, name: "Paris"),
            GraphIdentifiers.nodeID(type: .place, name: "Paris")
        )
    }

    func testEdgeIdVectors() {
        let alice = GraphIdentifiers.nodeID(type: .person, name: "Alice")
        let paris = GraphIdentifiers.nodeID(type: .place, name: "Paris")
        let aliceSmith = GraphIdentifiers.nodeID(type: .person, name: "Alice Smith")
        XCTAssertEqual(
            GraphIdentifiers.edgeID(source: alice, destination: paris, relation: .livesIn).uuidString.lowercased(),
            "1b123321-1220-53ec-8662-0714da9b4253"
        )
        XCTAssertEqual(
            GraphIdentifiers.edgeID(source: aliceSmith, destination: alice, relation: .knows).uuidString.lowercased(),
            "2a5ca767-5e7f-5eba-82f1-21c5cc9ec744"
        )
    }

    func testUuidV5VersionAndVariant() {
        let id = GraphIdentifiers.nodeID(type: .person, name: "Alice").uuidString.lowercased()
        let parts = id.split(separator: "-")
        XCTAssertTrue(parts[2].hasPrefix("5"))
        XCTAssertTrue(["8", "9", "a", "b"].contains(String(parts[3].prefix(1))))
    }

    // MARK: Parsing

    private let validJSON = """
    {"nodes":[{"type":"Person","name":"Alice","properties":{"role":"sister"}},{"type":"Place","name":"Paris"}],
     "edges":[{"source":{"type":"Person","name":"alice"},"relation":"lives_in","target":{"type":"Place","name":"Paris"}}]}
    """

    func testParseValid() {
        guard case .valid(let extraction) = GraphExtractionParser.parse(validJSON) else {
            return XCTFail("expected valid")
        }
        XCTAssertEqual(extraction.nodes.count, 2)
        XCTAssertEqual(extraction.nodes[0].properties, ["role": "sister"])
        XCTAssertEqual(extraction.edges.count, 1)
        XCTAssertEqual(extraction.edges[0].relation, .livesIn)
    }

    func testParseFenced() {
        XCTAssertNotEqual(GraphExtractionParser.parse("```json\n\(validJSON)\n```"), .empty)
        guard case .valid = GraphExtractionParser.parse("```\n\(validJSON)\n```") else {
            return XCTFail("expected valid")
        }
    }

    func testParseEmpty() {
        XCTAssertEqual(GraphExtractionParser.parse(""), .empty)
        XCTAssertEqual(GraphExtractionParser.parse("   "), .empty)
        XCTAssertEqual(GraphExtractionParser.parse("{\"nodes\":[],\"edges\":[]}"), .empty)
        XCTAssertEqual(GraphExtractionParser.parse("```json\n{\"nodes\":[]}\n```"), .empty)
    }

    func testParseInvalid() {
        let bad = [
            "not json",
            "[1,2]",
            "{\"edges\":[]}",
            "{\"nodes\":[{\"type\":\"Person\",\"name\":\"   \"}]}",
            "{\"nodes\":[{\"type\":\"Person\"}]}",
            "{\"nodes\":[{\"type\":\"Person\",\"name\":\"A\",\"properties\":{\"k\":[1]}}]}",
            "{\"nodes\":[\"Alice\"]}",
            // edge endpoint not among nodes
            "{\"nodes\":[{\"type\":\"Person\",\"name\":\"A\"}],\"edges\":[{\"source\":{\"type\":\"Person\",\"name\":\"A\"},\"relation\":\"knows\",\"target\":{\"type\":\"Person\",\"name\":\"B\"}}]}"
        ]
        for text in bad {
            guard case .invalid = GraphExtractionParser.parse(text) else {
                return XCTFail("expected invalid: \(text)")
            }
        }
    }

    func testParseUnknownTypes() {
        guard case .invalid = GraphExtractionParser.parse("{\"nodes\":[{\"type\":\"Animal\",\"name\":\"Rex\"}]}") else {
            return XCTFail("unknown node type must be invalid")
        }
        let unknownRelation = """
        {"nodes":[{"type":"Person","name":"A"},{"type":"Person","name":"B"}],
         "edges":[{"source":{"type":"Person","name":"A"},"relation":"hates","target":{"type":"Person","name":"B"}}]}
        """
        guard case .invalid = GraphExtractionParser.parse(unknownRelation) else {
            return XCTFail("unknown relation must be invalid")
        }
    }

    func testDuplicateNodesMergeById() {
        let json = "{\"nodes\":[{\"type\":\"Person\",\"name\":\"Alice\"},{\"type\":\"Person\",\"name\":\" ALICE \",\"properties\":{\"a\":\"1\"}}]}"
        guard case .valid(let extraction) = GraphExtractionParser.parse(json) else { return XCTFail("expected valid") }
        XCTAssertEqual(extraction.nodes.count, 1)
        XCTAssertEqual(extraction.nodes[0].name, "Alice")
        XCTAssertEqual(extraction.nodes[0].properties, ["a": "1"])
    }

    // MARK: Skip rules

    func testSkipOnError() {
        XCTAssertFalse(GraphExtractionPolicy.shouldExtract(userText: "I live in Paris", toolNames: [], didFail: true))
    }

    func testSkipGreetingsAndSmallTalk() {
        for text in ["", "  ", "hi", "Hello!", "hey there", "Thanks!", "thank you", "ok", "how are you?", "Good morning", "Thanks a lot"] {
            XCTAssertFalse(GraphExtractionPolicy.shouldExtract(userText: text, toolNames: [], didFail: false), text)
        }
    }

    func testExtractPersonalContentWithoutTools() {
        XCTAssertTrue(GraphExtractionPolicy.shouldExtract(userText: "I live in Paris and work at Acme", toolNames: [], didFail: false))
        XCTAssertTrue(GraphExtractionPolicy.shouldExtract(userText: "hi, my sister Alice moved to Berlin", toolNames: [], didFail: false))
    }

    func testSkipToolOnlyTurnsWithoutPersonalContent() {
        XCTAssertFalse(GraphExtractionPolicy.shouldExtract(userText: "read the last messages from Bob", toolNames: ["read_recent_messages"], didFail: false))
        XCTAssertFalse(GraphExtractionPolicy.shouldExtract(userText: "what are we working on?", toolNames: ["query_hive_graph"], didFail: false))
    }

    func testExtractToolTurnWithPersonalCue() {
        XCTAssertTrue(GraphExtractionPolicy.shouldExtract(userText: "I\u{2019}m a designer, tell Bob I\u{2019}ll be late", toolNames: ["send_sphinx_message"], didFail: false))
        XCTAssertTrue(GraphExtractionPolicy.shouldExtract(userText: "Send my wife Anna a message", toolNames: ["send_sphinx_message"], didFail: false))
    }

    // MARK: Privacy switch

    private func makeDefaults() throws -> (UserDefaults, String) {
        let name = "GraphExtractionTests.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: name)), name)
    }

    func testSwitchDefaultsToOnWhenMissing() throws {
        let (defaults, name) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertTrue(GraphExtractionSettings.isEnabled(in: defaults))
    }

    func testSwitchRegisterDefaultAndToggle() throws {
        let (defaults, name) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        GraphExtractionSettings.registerDefaults(in: defaults)
        XCTAssertTrue(defaults.bool(forKey: GraphExtractionSettings.enabledKey))
        GraphExtractionSettings.setEnabled(false, in: defaults)
        XCTAssertFalse(GraphExtractionSettings.isEnabled(in: defaults))
        GraphExtractionSettings.setEnabled(true, in: defaults)
        XCTAssertTrue(GraphExtractionSettings.isEnabled(in: defaults))
    }

    // MARK: Operations

    private func extraction() throws -> GraphExtraction {
        guard case .valid(let value) = GraphExtractionParser.parse(validJSON) else {
            throw GraphJournalError.invalidPayload("fixture")
        }
        return value
    }

    func testOperationsOneBatchNodesBeforeEdges() throws {
        let ops = try GraphExtractionOperations.operations(for: try extraction(), existing: GraphStoreSnapshot())
        XCTAssertEqual(ops.map(\.opType), [.nodeUpsert, .nodeUpsert, .edgeUpsert])
        XCTAssertEqual(ops[0].entityId, GraphIdentifiers.nodeID(type: .person, name: "Alice"))
        XCTAssertEqual(
            ops[2].entityId,
            GraphIdentifiers.edgeID(
                source: GraphIdentifiers.nodeID(type: .person, name: "Alice"),
                destination: GraphIdentifiers.nodeID(type: .place, name: "Paris"),
                relation: .livesIn
            )
        )
    }

    func testOperationsSkipUnchangedAndKeepAlias() throws {
        let ops = try GraphExtractionOperations.operations(for: try extraction(), existing: GraphStoreSnapshot())
        var snapshot = GraphStoreSnapshot()
        for op in ops {
            let mutation = try GraphMutation(opType: op.opType, entityId: op.entityId, payload: op.payload)
            switch mutation {
            case let .upsertNode(id, kind, payload): snapshot.nodes[id] = GraphStoredNode(kind: kind, payload: payload)
            case let .upsertEdge(id, src, dst, type, payload): snapshot.edges[id] = GraphStoredEdge(src: src, dst: dst, type: type, payload: payload)
            default: break
            }
        }
        // Same extraction again: nothing to write.
        XCTAssertTrue(try GraphExtractionOperations.operations(for: try extraction(), existing: snapshot).isEmpty)

        // Display name changes: old name kept as alias.
        let renamed = GraphExtraction(
            nodes: [ExtractedNode(type: .person, name: "ALICE", properties: [:])],
            edges: []
        )
        let renameOps = try GraphExtractionOperations.operations(for: renamed, existing: snapshot)
        XCTAssertEqual(renameOps.count, 1)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: renameOps[0].payload) as? [String: Any])
        let properties = try XCTUnwrap(object["properties"] as? [String: Any])
        XCTAssertEqual(properties["name"] as? String, "ALICE")
        XCTAssertEqual(properties["aliases"] as? [String], ["Alice"])
        XCTAssertEqual(properties["role"] as? String, "sister")
    }
}
