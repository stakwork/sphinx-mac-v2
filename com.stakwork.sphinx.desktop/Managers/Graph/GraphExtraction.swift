//
//  GraphExtraction.swift
//  sphinx
//
//  Pure pieces of the agent -> graph pipeline: prompt, strict parser/validator for the
//  model output, and the builder turning a validated extraction into GraphOperations
//  (one batch for GraphJournalService.apply). See docs/graph-extraction.md.
//
import Foundation

struct ExtractedNodeRef: Equatable, Sendable {
    let type: GraphNodeType
    let name: String

    var id: UUID { GraphIdentifiers.nodeID(type: type, name: name) }
}

struct ExtractedNode: Equatable, Sendable {
    let type: GraphNodeType
    let name: String
    let properties: [String: String]

    var id: UUID { GraphIdentifiers.nodeID(type: type, name: name) }
}

struct ExtractedEdge: Equatable, Sendable {
    let source: ExtractedNodeRef
    let relation: GraphRelationType
    let target: ExtractedNodeRef
    let properties: [String: String]
}

struct GraphExtraction: Equatable, Sendable {
    let nodes: [ExtractedNode]
    let edges: [ExtractedEdge]
}

enum GraphExtractionParseResult: Equatable, Sendable {
    case valid(GraphExtraction)
    /// Valid JSON with no nodes and no edges: nothing to write.
    case empty
    /// Dropped. The reason is only for logging.
    case invalid(String)
}

enum GraphExtractionPrompt {

    static let maxTextLength = 4000

    static let system = """
    You extract durable personal knowledge about the USER from one chat turn, for a personal knowledge graph.
    Reply with ONE JSON object and nothing else (no prose, no markdown):
    {"nodes":[{"type":"Person|Place|Thing|Topic","name":"...","properties":{"key":"value"}}],
     "edges":[{"source":{"type":"...","name":"..."},"relation":"knows|lives_in|works_at|works_on|interested_in|owns|related_to|located_in","target":{"type":"...","name":"..."},"properties":{}}]}
    Rules:
    - Only facts the user states about themselves, people, places, things or topics in their life. Never invent facts.
    - Do not extract from tool output, questions, commands, or general knowledge.
    - The user themself is the Person named "Me".
    - Every edge endpoint must also appear in "nodes". Property values are strings.
    - If there is nothing worth remembering reply exactly {"nodes":[],"edges":[]}.
    """

    static func userPrompt(userText: String, assistantText: String) -> String {
        return "USER MESSAGE:\n\(String(userText.prefix(maxTextLength)))\n\nASSISTANT REPLY:\n\(String(assistantText.prefix(maxTextLength)))"
    }
}

enum GraphExtractionParser {

    static let maxNodes = 50
    static let maxEdges = 100
    static let maxNameLength = 200

    /// Strips markdown code fences and parses the whole payload. Any invalid item
    /// (unknown type, empty name, dangling edge endpoint, wrong JSON shape) drops the
    /// WHOLE payload, so a malformed item is never written.
    static func parse(_ raw: String) -> GraphExtractionParseResult {
        let text = stripCodeFences(raw)
        guard !text.isEmpty else { return .empty }
        guard
            let data = text.data(using: .utf8),
            let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
            return .invalid("not a JSON object")
        }

        guard let rawNodes = root["nodes"] as? [Any] else { return .invalid("missing nodes array") }
        let rawEdges: [Any]
        if let edges = root["edges"] as? [Any] {
            rawEdges = edges
        } else if root["edges"] == nil || root["edges"] is NSNull {
            rawEdges = []
        } else {
            return .invalid("edges is not an array")
        }

        if rawNodes.isEmpty && rawEdges.isEmpty { return .empty }
        if rawNodes.count > maxNodes || rawEdges.count > maxEdges { return .invalid("too many items") }

        // Nodes, de-duplicated by deterministic id (first display name wins, properties merge).
        var order: [UUID] = []
        var byId: [UUID: ExtractedNode] = [:]
        for item in rawNodes {
            guard let object = item as? [String: Any] else { return .invalid("node is not an object") }
            guard let ref = parseRef(object) else { return .invalid("node has unknown type or empty name") }
            guard let properties = parseProperties(object["properties"]) else {
                return .invalid("node properties invalid")
            }
            let node = ExtractedNode(type: ref.type, name: ref.name, properties: properties)
            if let existing = byId[node.id] {
                byId[node.id] = ExtractedNode(
                    type: existing.type,
                    name: existing.name,
                    properties: existing.properties.merging(properties) { current, _ in current }
                )
            } else {
                order.append(node.id)
                byId[node.id] = node
            }
        }

        var edges: [ExtractedEdge] = []
        for item in rawEdges {
            guard
                let object = item as? [String: Any],
                let sourceObject = object["source"] as? [String: Any],
                let targetObject = object["target"] as? [String: Any],
                let source = parseRef(sourceObject),
                let target = parseRef(targetObject)
            else {
                return .invalid("edge is malformed")
            }
            guard
                let relationRaw = object["relation"] as? String,
                let relation = GraphRelationType(rawValue: relationRaw)
            else {
                return .invalid("edge has unknown relation")
            }
            guard byId[source.id] != nil, byId[target.id] != nil else {
                return .invalid("edge endpoint is not an extracted node")
            }
            guard let properties = parseProperties(object["properties"]) else {
                return .invalid("edge properties invalid")
            }
            edges.append(ExtractedEdge(source: source, relation: relation, target: target, properties: properties))
        }

        let nodes = order.compactMap { byId[$0] }
        if nodes.isEmpty { return .empty }
        return .valid(GraphExtraction(nodes: nodes, edges: edges))
    }

    static func stripCodeFences(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("```") else { return text }
        if let firstNewline = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: firstNewline)...])
        } else {
            text = String(text.dropFirst(3))
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasSuffix("```") {
            text = String(text.dropLast(3))
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseRef(_ object: [String: Any]) -> ExtractedNodeRef? {
        guard
            let typeRaw = object["type"] as? String,
            let type = GraphNodeType(rawValue: typeRaw),
            let rawName = object["name"] as? String
        else { return nil }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !GraphIdentifiers.normalize(name).isEmpty, name.count <= maxNameLength else { return nil }
        return ExtractedNodeRef(type: type, name: name)
    }

    /// nil = invalid. Missing/null = empty. Values must be strings, numbers or bools
    /// (stored as strings); a "name" or "aliases" key is reserved and rejected.
    private static func parseProperties(_ value: Any?) -> [String: String]? {
        guard let value = value, !(value is NSNull) else { return [:] }
        guard let object = value as? [String: Any] else { return nil }
        var result: [String: String] = [:]
        for (key, item) in object {
            let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedKey.isEmpty, trimmedKey != "name", trimmedKey != "aliases" else { return nil }
            if let string = item as? String {
                result[trimmedKey] = string
            } else if let number = item as? NSNumber {
                result[trimmedKey] = number.stringValue
            } else {
                return nil
            }
        }
        return result
    }
}

enum GraphExtractionOperations {

    /// Builds ONE batch of operations (nodes first, then edges) with the existing
    /// `GraphOperation` builders. `existing` is the current store content, used to
    /// - keep an old display name as an alias when the name changes,
    /// - keep properties already stored (new values win),
    /// - skip upserts that would not change anything (the same fact is never stored twice).
    static func operations(
        for extraction: GraphExtraction,
        existing: GraphStoreSnapshot,
        timestamp: Date = Date()
    ) throws -> [GraphOperation] {
        var operations: [GraphOperation] = []

        for node in extraction.nodes {
            let id = node.id
            let old = existing.nodes[id].flatMap { propertiesOf(payload: $0.payload) } ?? [:]

            var properties: [String: Any] = old
            for (key, value) in node.properties { properties[key] = value }
            properties["name"] = node.name

            var aliases = (old["aliases"] as? [String]) ?? []
            if let oldName = old["name"] as? String, oldName != node.name, !aliases.contains(oldName) {
                aliases.append(oldName)
            }
            if !aliases.isEmpty { properties["aliases"] = aliases }

            if existing.nodes[id] != nil, NSDictionary(dictionary: properties).isEqual(to: old) { continue }
            operations.append(try GraphOperation.upsertNode(
                id: id, type: node.type.rawValue, properties: properties, timestamp: timestamp
            ))
        }

        var seenEdges = Set<UUID>()
        for edge in extraction.edges {
            let id = GraphIdentifiers.edgeID(source: edge.source.id, destination: edge.target.id, relation: edge.relation)
            guard seenEdges.insert(id).inserted else { continue }
            let old = existing.edges[id].flatMap { propertiesOf(payload: $0.payload) } ?? [:]

            var properties: [String: Any] = old
            for (key, value) in edge.properties { properties[key] = value }

            if existing.edges[id] != nil, NSDictionary(dictionary: properties).isEqual(to: old) { continue }
            operations.append(try GraphOperation.upsertEdge(
                id: id,
                src: edge.source.id,
                dst: edge.target.id,
                type: edge.relation.rawValue,
                properties: properties,
                timestamp: timestamp
            ))
        }
        return operations
    }

    private static func propertiesOf(payload: String) -> [String: Any]? {
        guard
            let data = payload.data(using: .utf8),
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        return object["properties"] as? [String: Any]
    }
}
