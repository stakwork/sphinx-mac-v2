import type { ManagedTransaction } from "neo4j-driver";
import { Bolt } from "./bolt.js";
import { type Embedder } from "./node-writer.js";
import type { SchemaResolver } from "./schema-resolver.js";
import { SCHEMA_CORE_PROPERTIES } from "./strut-schemas.js";
export declare const RRF_K = 60;
export declare const RRF_WEIGHTS: Record<string, number>;
export declare const DEFAULT_VECTOR_WEIGHT = 1.2;
export declare const VECTOR_Q_K = 50;
export declare const VECTOR_Q_SIM_FLOOR = 0.4;
export declare const USAGE_TIEBREAK_EPSILON = 0.02;
export declare const SEARCH_CANDIDATE_CAP = 5000;
export declare const DEFAULT_NAMESPACE = "default";
/** `node_visibility_helper.BLOCKED_NODE_STATUSES`. */
export declare const BLOCKED_NODE_STATUSES: string[];
/** jarvis `GENERIC_NODE_PROPERTIES` — stripped from every response
 *  `properties` map. (Distinct from the write-side set in strut-schemas.) */
export declare const RESPONSE_STRIPPED_NODE_PROPERTIES: Set<string>;
/** jarvis `GENERIC_EDGE_PROPERTIES`. */
export declare const RESPONSE_STRIPPED_EDGE_PROPERTIES: Set<string>;
export { SCHEMA_CORE_PROPERTIES };
export interface NodeEnvelope {
    ref_id: string;
    node_type: string | undefined;
    properties: Record<string, unknown>;
    name?: string;
    date_added_to_graph?: number;
    weight?: number;
    score?: number;
    match_type?: string;
    /** `{EDGE_TYPE: count}` when edge counts were requested. */
    edges?: Record<string, number>;
}
export interface EdgeEnvelope {
    source: string;
    target: string;
    ref_id: string;
    edge_type: string;
    weight?: number;
    properties: Record<string, unknown>;
}
export interface SearchParams {
    q?: string;
    input_q?: string;
    output_q?: string;
    /** Node type labels (exact Neo4j labels). */
    types?: string[];
    /** Domain suffixes, e.g. `["strut"]`. Validated against the registry. */
    domains?: string[];
    namespace?: string;
    limit?: number;
    skip?: number;
    include_edge_counts?: boolean;
}
export interface SearchResult {
    nodes: NodeEnvelope[];
    total: number;
    truncated: boolean;
    /** Retriever layers that failed and were skipped (jarvis logs these and
     *  carries on with the other layers — e.g. Lucene's TooManyNestedClauses
     *  when a many-word query meets the 150-property global fulltext index). */
    warnings?: string[];
}
export interface NeighborsParams {
    edge_types?: string[];
    node_types?: string[];
    exclude_node_types?: string[];
    limit?: number;
    /** Explicit namespace pins the edge-count map to that partition. */
    namespace?: string;
    include_edge_counts?: boolean;
}
export interface ConnectionCount {
    edge_type: string;
    target_type: string;
    count: number;
}
export interface SchemaEnvelope {
    [core: string]: unknown;
    type: string;
    attributes: Record<string, unknown>;
    inherited_attributes: Record<string, unknown>;
}
export interface OntologyEdge {
    edge_type: string;
    source_type: string;
    target_type: string;
}
export declare class GraphReadError extends Error {
    readonly code: "INVALID_DOMAIN" | "INVALID_NAMESPACE" | "NOT_FOUND" | "INVALID_INPUT";
    constructor(code: "INVALID_DOMAIN" | "INVALID_NAMESPACE" | "NOT_FOUND" | "INVALID_INPUT", message: string);
}
export declare function escapeLucene(value: string): string;
/** `_build_fulltext_query` (gs=false): one token escaped as-is; several →
 *  each `+`-prefixed (all required). */
export declare function buildFulltextQuery(q: string): string;
/** `_search_fetch_limit`. */
export declare function fetchLimit(limit: number | undefined, skip: number | undefined): number;
/** Python `round()` — half to even. */
export declare function pyRound(x: number, digits?: number): number;
export interface Hit {
    node: HitNode;
    raw_score: number;
}
export interface HitNode {
    labels: string[];
    properties: Record<string, unknown>;
}
export interface RankedEntry {
    node: HitNode;
    sources: Set<string>;
    raw_scores: Record<string, number>;
    score: number;
    best_rank: number;
    extra: {
        score: number;
        match_type: string;
    };
}
/** `_rank_search_hits`: best raw score per ref_id, sorted desc. */
export declare function rankHits(hits: Hit[]): Hit[];
/** `_fuse_search_hits`: weighted RRF, `(-score, best_rank, ref_id)` order,
 *  score normalized to the top entry. */
export declare function fuseHits(fulltext: Hit[], semantic: Hit[], buckets?: Record<string, Hit[]>): RankedEntry[];
export declare function titleMatchMultiplier(qLower: string, valLower: string): number;
/** `_apply_title_key_boost`: multiply by the title-field match tier, re-sort,
 *  re-normalize. `titleKeyFor` resolves a node type's `title_key` (default
 *  `name`). */
export declare function applyTitleBoost(ranked: RankedEntry[], q: string, titleKeyFor: (type: string | undefined) => string): RankedEntry[];
/** `_apply_usage_tiebreak`: bucket normalized score by epsilon, then
 *  usage_count_30d desc → usage_count desc → best rank → ref_id. */
export declare function applyUsageTiebreak(ranked: RankedEntry[], epsilon?: number): RankedEntry[];
/** `_serialize_node`. */
export declare function serializeNode(n: HitNode, extra?: Record<string, unknown>): NodeEnvelope;
export interface GraphReaderOptions {
    /** Needed for the semantic and field-scoped retrievers; without it search
     *  is fulltext-only (jarvis logs "TEXT_MODEL not loaded" and does the same). */
    embedder?: Embedder;
    /** Canonicalizes `type` filters case-insensitively (jarvis
     *  `resolve_canonical_node_types`); unresolved names are kept verbatim
     *  (they match nothing — jarvis's silent-empty behaviour). */
    resolver?: SchemaResolver;
}
export declare class GraphReader {
    private readonly bolt;
    private readonly opts;
    constructor(bolt: Bolt, opts?: GraphReaderOptions);
    /** Distinct lowercased domains registered by existing Schema nodes. */
    listDomains(tx?: ManagedTransaction): Promise<string[]>;
    /** `About.hidden_domains` (lowercased), [] when unset. */
    hiddenDomains(tx?: ManagedTransaction): Promise<string[]>;
    /** `visible_domain_labels`: `Domain_<d>` for every non-hidden domain. */
    visibleDomainLabels(tx?: ManagedTransaction): Promise<string[]>;
    /** Registered namespaces (jarvis keeps one `:NameSpace` node holding a
     *  lowercased list). `default` is implicit. */
    listNamespaces(): Promise<string[]>;
    /** Idempotent `POST /namespace`: append the lowercased name to the single
     *  `:NameSpace` node's `data` list (creating the node on first use). */
    registerNamespace(name: string): Promise<{
        namespace: string;
        created: boolean;
    }>;
    /** `NameSpaceHelper.get_request_namespace`: `default` always resolves;
     *  anything else must be registered. */
    resolveNamespace(namespace: string | undefined): Promise<string>;
    /** GET /v2/nodes/:ref_id — `{name, node_type, ref_id, properties, weight?}`
     *  or null when absent/hidden. */
    getNode(ref_id: string): Promise<NodeEnvelope | null>;
    /** GET …/connection-counts: `(edge_type, target_type) → count`, scoped to
     *  the node's own namespace unless one is given. */
    connectionCounts(ref_id: string, namespace?: string): Promise<ConnectionCount[]>;
    /** `_batch_edge_type_counts`: `{ref_id: {EDGE_TYPE: count}}`. */
    edgeCounts(ref_ids: string[], namespace: string, pinNamespace?: boolean, tx?: ManagedTransaction): Promise<Record<string, Record<string, number>>>;
    /**
     * GET /v2/nodes/:ref_id?expand=edges&sort_by=importance&limit=…
     * (`node_helper_v2.get_node_edges`, importance branch): 1-hop, ordered by
     * `r.importance` desc before LIMIT, filtered by edge/node type, excluding
     * node types case-insensitively. Returns `{nodes, edges}` with the source
     * node included in `nodes`, like jarvis.
     */
    neighbors(ref_id: string, p?: NeighborsParams): Promise<{
        nodes: NodeEnvelope[];
        edges: EdgeEnvelope[];
    }>;
    /** GET /v2/nodes?q&input_q&output_q… — hybrid search, ported faithfully. */
    search(p: SearchParams): Promise<SearchResult>;
    /** `(label, property)` pairs declaring `vector_index`, from live Schema
     *  nodes (jarvis's discovery) — falls back to the Strut registry so a
     *  strut-only DB needs no extra read. */
    private vectorIndexedPairsLive;
    /**
     * GET /v2/schema (`get_all_schemas`, non-concise): every live schema with
     * ancestor-merged properties split into core keys + `attributes`, parent
     * attributes moved to `inherited_attributes`; plus `edges` (all Schema→
     * Schema relationships, CHILD_OF included) as concise triples. Optional
     * `domains` filter keeps wildcard endpoints.
     */
    listSchemas(opts?: {
        domains?: string[];
        includeDeleted?: boolean;
    }): Promise<{
        schemas: SchemaEnvelope[];
        edges: OntologyEdge[];
    }>;
    /** GET /v2/schema/:type (`format_single_schema`): ancestor-merged
     *  `attributes` (own + inherited) plus an `inherited_attributes` view.
     *  Case-insensitive except `Thing`. */
    getSchema(type: string): Promise<SchemaEnvelope | null>;
    /** Resolve each type name to its canonical label; unresolved kept as-is. */
    private canonicalTypes;
    private rows;
}
/** `_split_schema_properties`. */
export declare function splitSchema(merged: Record<string, unknown>): SchemaEnvelope;
/** `_get_inherited_attributes`: keys the parent also declares move from
 *  `attributes` to `inherited_attributes`. */
export declare function inheritedAttributes(schemas: SchemaEnvelope[]): SchemaEnvelope[];
