//
//  GraphOperation.swift
//  sphinx
//
//  Value types describing a graph operation (what is journaled) and the
//  engine-level mutation derived from it (what is applied to a GraphStore).
//
import Foundation

enum GraphOpType: Int16, Sendable {
    case nodeUpsert = 0
    case edgeUpsert = 1
    case nodeDelete = 2
    case edgeDelete = 3
}

enum GraphJournalError: Error, Equatable {
    case invalidPayload(String)
    case unknownOpType(Int16)
    case emptyClientId
    case storeNotOpen
}

/// One journaled operation.
///
/// Payload conventions (JSON, UTF-8, the FULL resulting state of the entity):
/// - node upsert: `{"type": "<label>", "properties": {...}}`
/// - edge upsert: `{"src": "<node uuid>", "dst": "<node uuid>", "type": "<label>", "properties": {...}}`
/// - deletes: payload is ignored by the store (tombstone); `{}` by convention.
///
/// `clientId == nil` means "this device" (resolved by the client id provider) and
/// `seq == nil` means "next sequence number for that client". Operations coming
/// from sync replay carry both explicitly.
struct GraphOperation: Sendable, Equatable {
    var clientId: String?
    var seq: Int64?
    var timestamp: Date
    var opType: GraphOpType
    var entityId: UUID
    var payload: Data
    var schemaVersion: Int16

    static let currentSchemaVersion: Int16 = 1

    init(
        clientId: String? = nil,
        seq: Int64? = nil,
        timestamp: Date = Date(),
        opType: GraphOpType,
        entityId: UUID,
        payload: Data,
        schemaVersion: Int16 = GraphOperation.currentSchemaVersion
    ) {
        self.clientId = clientId
        self.seq = seq
        self.timestamp = timestamp
        self.opType = opType
        self.entityId = entityId
        self.payload = payload
        self.schemaVersion = schemaVersion
    }

    // MARK: Builders

    static func upsertNode(id: UUID, type: String, properties: [String: Any] = [:], timestamp: Date = Date()) throws -> GraphOperation {
        let payload = try encode(["type": type, "properties": properties])
        return GraphOperation(timestamp: timestamp, opType: .nodeUpsert, entityId: id, payload: payload)
    }

    static func upsertEdge(id: UUID, src: UUID, dst: UUID, type: String, properties: [String: Any] = [:], timestamp: Date = Date()) throws -> GraphOperation {
        let payload = try encode([
            "src": src.uuidString,
            "dst": dst.uuidString,
            "type": type,
            "properties": properties
        ])
        return GraphOperation(timestamp: timestamp, opType: .edgeUpsert, entityId: id, payload: payload)
    }

    static func deleteNode(id: UUID, timestamp: Date = Date()) -> GraphOperation {
        return GraphOperation(timestamp: timestamp, opType: .nodeDelete, entityId: id, payload: Data("{}".utf8))
    }

    static func deleteEdge(id: UUID, timestamp: Date = Date()) -> GraphOperation {
        return GraphOperation(timestamp: timestamp, opType: .edgeDelete, entityId: id, payload: Data("{}".utf8))
    }

    private static func encode(_ object: [String: Any]) throws -> Data {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw GraphJournalError.invalidPayload("properties are not JSON-serializable")
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}

enum GraphApplyResult: Sendable, Equatable {
    case applied(clientId: String, seq: Int64)
    /// (clientId, seq) was already journaled; nothing was written.
    case duplicate(clientId: String, seq: Int64)
}

/// Engine-level mutation. Always derived from a journaled operation via
/// `init(opType:entityId:payload:)`, so live apply and replay share one derivation.
enum GraphMutation: Sendable, Equatable {
    case upsertNode(id: UUID, kind: String, payload: String)
    case deleteNode(id: UUID)
    case upsertEdge(id: UUID, src: UUID, dst: UUID, type: String, payload: String)
    case deleteEdge(id: UUID)

    init(opType: GraphOpType, entityId: UUID, payload: Data) throws {
        switch opType {
        case .nodeDelete:
            self = .deleteNode(id: entityId)
        case .edgeDelete:
            self = .deleteEdge(id: entityId)
        case .nodeUpsert:
            let (object, text) = try GraphMutation.parse(payload)
            self = .upsertNode(id: entityId, kind: object["type"] as? String ?? "", payload: text)
        case .edgeUpsert:
            let (object, text) = try GraphMutation.parse(payload)
            guard
                let srcString = object["src"] as? String, let src = UUID(uuidString: srcString),
                let dstString = object["dst"] as? String, let dst = UUID(uuidString: dstString),
                let type = object["type"] as? String
            else {
                throw GraphJournalError.invalidPayload("edge payload needs src, dst (UUIDs) and type")
            }
            self = .upsertEdge(id: entityId, src: src, dst: dst, type: type, payload: text)
        }
    }

    private static func parse(_ payload: Data) throws -> ([String: Any], String) {
        guard
            let text = String(data: payload, encoding: .utf8),
            let object = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any]
        else {
            throw GraphJournalError.invalidPayload("payload must be a UTF-8 JSON object")
        }
        return (object, text)
    }
}
