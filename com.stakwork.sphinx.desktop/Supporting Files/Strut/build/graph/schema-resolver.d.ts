import type { ManagedTransaction } from "neo4j-driver";
import { Bolt } from "./bolt.js";
import { type StrutSchema } from "./strut-schemas.js";
/** jarvis `ApplicationConstant.EDGE_TYPES` — edge types accepted WITHOUT an
 *  edge schema. */
export declare const EDGE_TYPES_ALLOWLIST: Set<string>;
/** The schema shape the writers validate against — Strut registry entries
 *  and DB-resolved jarvis schemas both reduce to this. */
export interface NodeSchema {
    /** Canonical type label. */
    type: string;
    parent?: string;
    node_key: string;
    /** `get_index_fields`: declared index list (a string becomes a one-item
     *  list); `["node_key"]` when unset. */
    index: string[];
    vector_index: string[];
    /** Attribute name → type string (`?`-prefixed = optional). Includes
     *  everything inherited via CHILD_OF. */
    attributes: Record<string, string>;
    title_key?: string;
    description_key?: string;
    /** `Domain_<x>` labels to stamp on nodes of this type (already filtered
     *  by hidden types/domains). */
    domainLabels: string[];
    /** True for Strut's own types (closed registry rules apply). */
    isStrut: boolean;
}
export interface EdgeSchemaMatch {
    source: string;
    target: string;
    edge_type: string;
    properties: Record<string, unknown>;
    via: "exact" | "ancestor" | "wildcard" | "allowlist";
}
export declare class SchemaResolver {
    private readonly bolt;
    private readonly ttlMs;
    private readonly types;
    private readonly schemas;
    private readonly edges;
    private hidden;
    constructor(bolt: Bolt, ttlMs?: number);
    /** Drop every cache (call after seeding or schema edits). */
    invalidate(): void;
    private fresh;
    /**
     * Canonical type for a user-supplied string, or null. Strut types must
     * match exactly (registry); everything else resolves case-insensitively
     * against `Schema.type` first, then live labels — exact case preferred in
     * both. Schema first, because a long-lived jarvis graph carries LEGACY
     * labels that differ only by case (`Evalset` next to `EvalSet`, with no
     * nodes and no Schema): Neo4j keeps them in `db.labels()` forever, and
     * "first label that matches case-insensitively" then canonicalizes to a
     * type that has no Schema, so every write fails UNKNOWN_TYPE while the
     * real schema sits right there.
     */
    resolveType(raw: string, tx?: ManagedTransaction): Promise<string | null>;
    /** The merged schema for a (raw) type, or null when unknown. */
    schema(raw: string, tx?: ManagedTransaction): Promise<NodeSchema | null>;
    private fromDb;
    /** `About.hidden_domains` (lowercased) and `hidden_types`. */
    hiddenSets(tx?: ManagedTransaction): Promise<{
        domains: Set<string>;
        types: Set<string>;
    }>;
    /**
     * Is `source -[edge]-> target` allowed? jarvis's allowlist first, then
     * the edge-schema lookup (exact → ancestor walks → wildcard). Types are
     * canonical labels. Returns the match, or null.
     */
    edgeSchema(edge: string, sourceType: string, targetType: string, tx?: ManagedTransaction): Promise<EdgeSchemaMatch | null>;
    /**
     * `create_schema_if_missing`: register `source -[EDGE]-> target` between
     * two existing `:Schema` nodes (`*` allowed on either side; the sentinel
     * is ensured). Idempotent. Returns whether a new schema edge was created.
     */
    createEdgeSchema(sourceType: string, edge: string, targetType: string): Promise<{
        created: boolean;
        ref_id: string;
    }>;
    private rows;
}
/** A Strut registry schema as a `NodeSchema` (Thing's attributes inherited,
 *  `Domain_strut` unless hidden). */
export declare function fromStrut(strut: StrutSchema, hidden?: {
    domains: Set<string>;
    types: Set<string>;
}): NodeSchema;
/** Every Strut registry schema as `NodeSchema` (no DB, no hidden filtering). */
export declare function strutNodeSchemas(): NodeSchema[];
