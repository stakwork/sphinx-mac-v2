//
//  GraphIdentifiers.swift
//  sphinx
//
//  Deterministic ids for the personal knowledge graph (see docs/graph-extraction.md).
//  The same entity gets the same id on every device, so no id exchange or merging is needed.
//
//    node id = UUIDv5(namespace, "<nodeType>:<normalizedName>")
//    edge id = UUIDv5(namespace, "<sourceId>:<relationType>:<destinationId>")
//
//  Node type / relation type are the exact raw values of `GraphNodeType` / `GraphRelationType`;
//  UUIDs inside the edge string are lowercase, hyphenated.
//
import Foundation
import CryptoKit

/// Fixed set of node types (schema v1).
enum GraphNodeType: String, CaseIterable, Sendable {
    case person = "Person"
    case place = "Place"
    case thing = "Thing"
    case topic = "Topic"
}

/// Fixed set of relation types (schema v1).
enum GraphRelationType: String, CaseIterable, Sendable {
    case knows = "knows"
    case livesIn = "lives_in"
    case worksAt = "works_at"
    case worksOn = "works_on"
    case interestedIn = "interested_in"
    case owns = "owns"
    case relatedTo = "related_to"
    case locatedIn = "located_in"
}

enum GraphIdentifiers {

    /// Fixed namespace: UUIDv5(NAMESPACE_DNS, "graph.sphinx.chat") = 4dcb6314-9c48-5148-b515-af314187e2fa.
    /// NEVER change it: every id on every device derives from it.
    static let namespace = UUID(uuid: (
        0x4d, 0xcb, 0x63, 0x14, 0x9c, 0x48, 0x51, 0x48,
        0xb5, 0x15, 0xaf, 0x31, 0x41, 0x87, 0xe2, 0xfa
    ))

    /// Unicode NFKC, lowercase, trim, collapse inner whitespace runs to one space.
    static func normalize(_ name: String) -> String {
        let folded = name.precomposedStringWithCompatibilityMapping.lowercased()
        return folded
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func nodeID(type: GraphNodeType, name: String) -> UUID {
        return uuidV5(namespace: namespace, name: "\(type.rawValue):\(normalize(name))")
    }

    static func edgeID(source: UUID, destination: UUID, relation: GraphRelationType) -> UUID {
        let name = "\(source.uuidString.lowercased()):\(relation.rawValue):\(destination.uuidString.lowercased())"
        return uuidV5(namespace: namespace, name: name)
    }

    /// RFC 4122 section 4.3: SHA-1 over namespace bytes + UTF-8 name, first 16 bytes,
    /// version nibble = 5, variant bits = 10.
    static func uuidV5(namespace: UUID, name: String) -> UUID {
        var input = Data(withUnsafeBytes(of: namespace.uuid) { Array($0) })
        input.append(Data(name.utf8))
        var bytes = Array(Insecure.SHA1.hash(data: input).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
