import { Bolt } from "./bolt.js";
import { SchemaResolver, type NodeSchema } from "./schema-resolver.js";
export type GraphValidationCode = "UNKNOWN_TYPE" | "MISSING_REQUIRED" | "UNKNOWN_ATTRIBUTE" | "WRONG_TYPE" | "INVALID_LIST" | "INVALID_DATETIME" | "EMPTY_NODE_KEY_TOKEN" | "NOT_FOUND" | "DUPLICATE_KEY";
export declare class GraphValidationError extends Error {
    readonly code: GraphValidationCode;
    readonly type: string;
    readonly attribute?: string;
    constructor(code: GraphValidationCode, type: string, message: string, attribute?: string);
}
export interface ValidatedNode {
    schema: NodeSchema;
    /** Attribute values as JS primitives (datetime → epoch seconds), with
     *  null/undefined and empty strings dropped. Used for node_key and
     *  Data_Bank composition. */
    values: Record<string, unknown>;
    /** The same values as Neo4j parameter values (ints wrapped). */
    params: Record<string, unknown>;
}
/**
 * The write-time gate. Throws `GraphValidationError` on the first violation
 * and writes nothing. Stricter than jarvis in the safe direction: anything
 * accepted here also passes jarvis's validators. Pass a Strut type name or
 * a resolved `NodeSchema` (from `SchemaResolver`) for any type.
 */
export declare function validateNode(typeOrSchema: string | NodeSchema, data: Record<string, unknown>): ValidatedNode;
/**
 * jarvis `TimeFormatter._convert_to_unix_timestamp`: ISO string (Z accepted)
 * or epoch number; numbers above 10^12 are milliseconds. Always epoch
 * SECONDS as an int. Returns null when unparseable.
 */
export declare function toEpochSeconds(v: unknown): number | null;
export declare const MAX_NODE_KEY_LENGTH = 200;
export declare const NODE_KEY_HASH_LENGTH = 32;
/** `String(v).trim()` → drop spaces → lowercase → strip `[^a-zA-Z0-9\s]`. */
export declare function sanitizeKeyValue(v: unknown): string;
/**
 * `sanitize_node_key` + `_compose_node_key`, verbatim. Property lookup is
 * case-insensitive; a missing property is an error. If the composed key
 * exceeds 200 chars, the value portion collapses to a 32-hex sha256 prefix.
 */
export declare function composeNodeKey(schema: {
    type: string;
    node_key: string;
}, values: Record<string, unknown>): string;
/** jarvis `DATA_BANK_EXCLUDED_FIELDS` — never part of kitchen-sink search text. */
export declare const DATA_BANK_EXCLUDED_FIELDS: Set<string>;
/**
 * `get_search_fields_for_node`: the schema's explicit `index` fields (in
 * declared order) that are present and non-blank; when the schema has no
 * real index (`["node_key"]`) or none of its index fields are usable, fall
 * through to jarvis's priority list + every other non-excluded property.
 */
export declare function searchFieldsFor(schema: NodeSchema, values: Record<string, unknown>): string[];
/** `build_search_text`: values of the chosen fields, trimmed, joined with
 *  "\n" — no field-name prefixes. Null when nothing qualifies. */
export declare function buildSearchText(schema: NodeSchema, values: Record<string, unknown>): {
    text: string | null;
    fields: string[];
};
/** jarvis `render_schema`: `"Input:\n{text}"` for `input_schema`, etc. */
export declare function renderVectorField(prop: string, text: string): string | null;
export interface Embedder {
    /** One 384-float vector per input text, same order. */
    embed(texts: string[]): Promise<number[][]>;
}
export type WriteMode = "create" | "upsert";
export type WriteOutcome = "created" | "existing" | "restored" | "updated";
export interface NodeInput {
    /** Node type — a Strut type (exact) or any jarvis type (resolved
     *  case-insensitively against the live schema). */
    type: string;
    data: Record<string, unknown>;
}
export interface NodeWriteResult {
    ref_id: string;
    node_key: string;
    /** Canonical type label the node was written under. */
    node_type: string;
    outcome: WriteOutcome;
}
export interface NodeWriterOptions {
    embedder?: Embedder;
    /** Shared resolver (one per backend); a private one is created otherwise. */
    resolver?: SchemaResolver;
}
export interface WriteOptions {
    /** Override the backend's default namespace for this write. Must already
     *  be registered when it is not `default` (callers check via
     *  `GraphReader.resolveNamespace`). */
    namespace?: string;
}
export interface NodeUpdate {
    /** Properties to set/overwrite (validated against the schema after
     *  merging over the node's current attributes). */
    set?: Record<string, unknown>;
    /** Attribute names to remove. Required attributes cannot be removed. */
    remove?: string[];
}
export interface NodeUpdateResult {
    ref_id: string;
    node_key: string;
    /** True when the update changed the node_key (identity attrs edited). */
    rekeyed: boolean;
}
interface PreparedNode {
    schema: NodeSchema;
    node_key: string;
    ref_id: string;
    onCreate: Record<string, unknown>;
    onMatch: Record<string, unknown>;
}
export declare class NodeWriter {
    private readonly bolt;
    private readonly opts;
    readonly resolver: SchemaResolver;
    constructor(bolt: Bolt, opts?: NodeWriterOptions);
    /** Validate + compose everything except the MERGE. Exposed for tests and
     *  the batch path. */
    prepare(input: NodeInput, opts?: WriteOptions): Promise<PreparedNode>;
    prepareMany(inputs: NodeInput[], opts?: WriteOptions): Promise<PreparedNode[]>;
    /** Write one node. */
    write(input: NodeInput, mode?: WriteMode, opts?: WriteOptions): Promise<NodeWriteResult>;
    /**
     * Write many nodes (any mix of types) in one transaction — one UNWIND
     * MERGE per type, same resulting state as the single form. Results are in
     * input order. All-or-nothing: a validation error anywhere writes nothing.
     */
    writeMany(inputs: NodeInput[], mode?: WriteMode, opts?: WriteOptions): Promise<NodeWriteResult[]>;
    /**
     * Partial update by ref_id (jarvis `POST /v2/nodes/:ref_id` with
     * `node_data` / `properties_to_be_deleted`): the patch is merged over the
     * node's current attributes, the merged payload is re-validated as a
     * whole, `node_key` is recomposed (an identity edit that collides with
     * another node fails with DUPLICATE_KEY, nothing written), and
     * `Data_Bank` + vectors are rebuilt. Identity stamps (`ref_id`,
     * `namespace`, `date_added_to_graph`) and `is_deleted` are untouched.
     */
    update(ref_id: string, patch: NodeUpdate): Promise<NodeUpdateResult>;
    /** Soft delete (`is_deleted = true`). Scoped to Strut's own nodes. */
    softDelete(ref_id: string): Promise<boolean>;
}
export {};
