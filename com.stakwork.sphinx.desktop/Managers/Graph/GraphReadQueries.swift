//
//  GraphReadQueries.swift
//  sphinx
//
//  Read-side value types and pure query logic for the personal knowledge graph
//  (job 3: recall). The stores (Ladybug and the in-memory fake) both answer the
//  GraphStore read methods with these functions over their node/edge data, so the
//  behaviour is identical and testable without Ladybug. Nothing here writes.
//
//  Names are matched with `GraphIdentifiers.normalize` (the same normalization that
//  derives node ids); there is no second normalization.
//
import Foundation

/// A node decoded from its stored payload `{"type", "properties": {"name", "aliases", ...}}`.
struct GraphNodeRecord: Sendable, Equatable {
    var id: UUID
    var kind: String
    var name: String
    var aliases: [String]
    /// Free-form properties other than `name` and `aliases`, values rendered as strings.
    var properties: [String: String]

    init(id: UUID, kind: String, name: String, aliases: [String] = [], properties: [String: String] = [:]) {
        self.id = id
        self.kind = kind
        self.name = name
        self.aliases = aliases
        self.properties = properties
    }

    /// Returns nil if the payload is not a JSON object.
    init?(id: UUID, node: GraphStoredNode) {
        guard
            let data = node.payload.data(using: .utf8),
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        let props = object["properties"] as? [String: Any] ?? [:]
        self.id = id
        self.kind = node.kind
        self.name = (props["name"] as? String) ?? ""
        self.aliases = (props["aliases"] as? [String]) ?? []
        var rest: [String: String] = [:]
        for (key, value) in props where key != "name" && key != "aliases" {
            if let text = value as? String {
                rest[key] = text
            } else if let number = value as? NSNumber {
                rest[key] = number.stringValue
            }
        }
        self.properties = rest
    }

    var displayName: String { name.isEmpty ? "(unnamed)" : name }
}

/// One edge seen from a node.
struct GraphRelation: Sendable, Equatable {
    var edgeId: UUID
    var type: String
    /// The node at the other end.
    var otherId: UUID
    var otherName: String
    /// true: this node -> other; false: other -> this node.
    var outgoing: Bool
}

/// A node with its degree (number of incident edges) and its relations.
struct GraphRankedNode: Sendable, Equatable {
    var node: GraphNodeRecord
    var degree: Int
    /// Sorted by relation type, other name, edge id.
    var relations: [GraphRelation]
}

/// An edge reached by a hop walk, with both endpoint names for readable output.
struct GraphWalkEdge: Sendable, Equatable {
    var edgeId: UUID
    var type: String
    var srcId: UUID
    var srcName: String
    var dstId: UUID
    var dstName: String
    /// 1 = touches the start node, 2 = touches a hop-1 neighbor.
    var depth: Int
}

/// Result of a hop walk: every reached node once (start excluded) and every traversed edge once.
struct GraphNeighborhood: Sendable, Equatable {
    var nodes: [GraphNodeRecord] = []
    var edges: [GraphWalkEdge] = []
}

enum GraphReadQueries {

    static let maxHops = 2

    /// Nodes whose normalized name or any normalized alias equals the normalized query
    /// (exact group first), then those that merely contain it. Each group is sorted by
    /// lowercase name then id so results are deterministic. Empty query -> [].
    static func findNodes(in snapshot: GraphStoreSnapshot, query: String, limit: Int) -> [GraphNodeRecord] {
        let needle = GraphIdentifiers.normalize(query)
        guard !needle.isEmpty, limit > 0 else { return [] }

        var exact: [GraphNodeRecord] = []
        var partial: [GraphNodeRecord] = []
        for (id, stored) in snapshot.nodes {
            guard let record = GraphNodeRecord(id: id, node: stored) else { continue }
            let names = ([record.name] + record.aliases).map(GraphIdentifiers.normalize).filter { !$0.isEmpty }
            if names.contains(needle) {
                exact.append(record)
            } else if names.contains(where: { $0.contains(needle) }) {
                partial.append(record)
            }
        }
        return Array((sorted(exact) + sorted(partial)).prefix(limit))
    }

    /// Breadth-first walk over edges in both directions, `hops` clamped to 1...2.
    /// Cycles are fine: a node is visited once and an edge is reported once.
    static func neighbors(in snapshot: GraphStoreSnapshot, of start: UUID, hops: Int) -> GraphNeighborhood {
        let depthLimit = min(max(hops, 1), maxHops)
        guard snapshot.nodes[start] != nil else { return GraphNeighborhood() }

        let names = nodeNames(snapshot)
        var adjacency: [UUID: [(id: UUID, edge: GraphStoredEdge)]] = [:]
        for (edgeId, edge) in snapshot.edges {
            adjacency[edge.src, default: []].append((edgeId, edge))
            if edge.dst != edge.src { adjacency[edge.dst, default: []].append((edgeId, edge)) }
        }

        var visited: Set<UUID> = [start]
        var seenEdges = Set<UUID>()
        var frontier: [UUID] = [start]
        var result = GraphNeighborhood()

        for depth in 1...depthLimit {
            var next: [UUID] = []
            for nodeId in frontier {
                let incident = (adjacency[nodeId] ?? []).sorted { lhs, rhs in
                    if lhs.edge.type != rhs.edge.type { return lhs.edge.type < rhs.edge.type }
                    let ln = names[otherEnd(lhs.edge, nodeId)] ?? "", rn = names[otherEnd(rhs.edge, nodeId)] ?? ""
                    if ln != rn { return ln < rn }
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                for (edgeId, edge) in incident {
                    let other = otherEnd(edge, nodeId)
                    guard snapshot.nodes[other] != nil else { continue }
                    if seenEdges.insert(edgeId).inserted {
                        result.edges.append(GraphWalkEdge(
                            edgeId: edgeId,
                            type: edge.type,
                            srcId: edge.src,
                            srcName: names[edge.src] ?? "",
                            dstId: edge.dst,
                            dstName: names[edge.dst] ?? "",
                            depth: depth
                        ))
                    }
                    if visited.insert(other).inserted {
                        next.append(other)
                        if let stored = snapshot.nodes[other], let record = GraphNodeRecord(id: other, node: stored) {
                            result.nodes.append(record)
                        }
                    }
                }
            }
            frontier = next
        }
        return result
    }

    /// All nodes, degree descending, then name, then id. (Recency is a journal concern
    /// and is applied by the service on top of this base order, see `GraphRecallRanking`.)
    static func rankedNodes(in snapshot: GraphStoreSnapshot) -> [GraphRankedNode] {
        let names = nodeNames(snapshot)
        var relations: [UUID: [GraphRelation]] = [:]
        for (edgeId, edge) in snapshot.edges {
            guard snapshot.nodes[edge.src] != nil, snapshot.nodes[edge.dst] != nil else { continue }
            relations[edge.src, default: []].append(GraphRelation(
                edgeId: edgeId, type: edge.type, otherId: edge.dst, otherName: names[edge.dst] ?? "", outgoing: true))
            relations[edge.dst, default: []].append(GraphRelation(
                edgeId: edgeId, type: edge.type, otherId: edge.src, otherName: names[edge.src] ?? "", outgoing: false))
        }
        var ranked: [GraphRankedNode] = []
        for (id, stored) in snapshot.nodes {
            guard let record = GraphNodeRecord(id: id, node: stored) else { continue }
            let rels = (relations[id] ?? []).sorted { lhs, rhs in
                if lhs.type != rhs.type { return lhs.type < rhs.type }
                if lhs.otherName != rhs.otherName { return lhs.otherName < rhs.otherName }
                return lhs.edgeId.uuidString < rhs.edgeId.uuidString
            }
            ranked.append(GraphRankedNode(node: record, degree: rels.count, relations: rels))
        }
        return ranked.sorted { lhs, rhs in
            if lhs.degree != rhs.degree { return lhs.degree > rhs.degree }
            return nameOrder(lhs.node, rhs.node)
        }
    }

    // MARK: Helpers

    private static func nodeNames(_ snapshot: GraphStoreSnapshot) -> [UUID: String] {
        var names: [UUID: String] = [:]
        for (id, stored) in snapshot.nodes {
            names[id] = GraphNodeRecord(id: id, node: stored)?.displayName ?? "(unnamed)"
        }
        return names
    }

    private static func otherEnd(_ edge: GraphStoredEdge, _ node: UUID) -> UUID {
        edge.src == node ? edge.dst : edge.src
    }

    static func nameOrder(_ lhs: GraphNodeRecord, _ rhs: GraphNodeRecord) -> Bool {
        let ln = lhs.name.lowercased(), rn = rhs.name.lowercased()
        if ln != rn { return ln < rn }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func sorted(_ nodes: [GraphNodeRecord]) -> [GraphNodeRecord] {
        nodes.sorted(by: nameOrder)
    }
}
