import { Bolt } from "./bolt.js";
import { SchemaResolver } from "./schema-resolver.js";
import { typeLabelOf } from "./strut-schemas.js";
export { typeLabelOf };
export interface EdgeInput {
    edge: string;
    source_ref_id: string;
    target_ref_id: string;
    /** Extra edge attributes — unvalidated passthrough, as in jarvis. Stamp
     *  keys (`ref_id`, `edge_key`, `weight`, `date_added_to_graph`) may not
     *  be supplied. Plain JS numbers are written as FLOAT; wrap with `int()`
     *  from `bolt.ts` for an Integer. */
    properties?: Record<string, unknown>;
    /** Overrides the `weight: 1` stamp on create (jarvis accepts a caller
     *  weight on POST /v2/edges). Written as an Integer when integral. */
    weight?: number;
}
export interface EdgeWriteResult {
    ref_id: string;
    edge_key: string;
    created: boolean;
    /** The ref_ids the edge actually landed on after alias rewrite. */
    source_ref_id: string;
    target_ref_id: string;
}
/** How `update` finds its edge: by ref_id, or by the (source, EDGE, target) triple. */
export type EdgeLocator = {
    ref_id: string;
} | {
    edge: string;
    source_ref_id: string;
    target_ref_id: string;
};
export interface EdgeUpdate {
    /** Properties to set/overwrite (`undefined` values are skipped). */
    set?: Record<string, unknown>;
    /** Property names to remove. */
    remove?: string[];
}
export interface EdgeUpdateResult {
    ref_id: string;
    edge: string;
    source_ref_id: string;
    target_ref_id: string;
    updated: string[];
    removed: string[];
}
export interface EdgeWriterOptions {
    resolver?: SchemaResolver;
}
/** Registry check for one (source type, edge, target type) triple. */
export declare function isRegisteredEdge(edge: string, sourceType: string, targetType: string): boolean;
export declare function edgeKeyFor(edge: string): string;
/** jarvis `sanitize_edge_key`: each `-`-token of the schema's edge_key
 *  pattern is looked up (case-insensitively) in the edge properties and
 *  sanitized like node_key values. */
export declare function composeEdgeKey(pattern: string, properties: Record<string, unknown>): string;
export declare class EdgeWriter {
    private readonly bolt;
    readonly resolver: SchemaResolver;
    constructor(bolt: Bolt, opts?: EdgeWriterOptions);
    write(input: EdgeInput): Promise<EdgeWriteResult>;
    /**
     * Write many edges in one transaction — one UNWIND MERGE per edge type.
     * Results in input order. All-or-nothing: any validation failure
     * (unknown type, unregistered triple, unresolvable endpoint) writes
     * nothing.
     */
    writeMany(inputs: EdgeInput[]): Promise<EdgeWriteResult[]>;
    /**
     * Patch an existing edge's properties — jarvis `PATCH /v2/edges/:ref_id`
     * (`set_edge_properties`), the one way to change an edge after the
     * ON-CREATE-only MERGE. Located by `ref_id`, or by the
     * `(source, EDGE, target)` triple (alias-rewritten like a write; muted
     * edges are skipped; more than one live edge of that type between the
     * endpoints — distinct edge_keys — is an error: pass the ref_id).
     * Identity stamps (`ref_id`, `edge_key`, `date_added_to_graph`,
     * `unique_source_id`) cannot be set or removed; `weight` can. Numbers
     * write as FLOAT (an integral `weight` as Integer, like create).
     */
    update(where: EdgeLocator, patch: EdgeUpdate): Promise<EdgeUpdateResult>;
    /** Edge soft delete (`is_muted = true`), by edge ref_id. */
    mute(ref_id: string): Promise<boolean>;
    /** Resolve every endpoint's type label and check each triple: Strut
     *  registry for Strut sources, jarvis's allowlist/edge-schema rules for the
     *  rest. Throws on a missing endpoint or disallowed triple. */
    private validateEndpoints;
}
