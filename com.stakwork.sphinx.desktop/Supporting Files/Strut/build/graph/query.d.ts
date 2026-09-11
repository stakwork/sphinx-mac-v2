/**
 * Read-only raw Cypher against the strut graph backend — the chat builder's
 * `graph_query` tool (see ai/tools.ts). It exists so the assistant can
 * VERIFY what a workflow's `graph/*` steps actually wrote (counts by type,
 * exact properties, edge fan-out) — questions the typed read steps can't
 * answer (search is ranked + limited; get/neighbors need a ref_id).
 *
 * Deliberately NOT a workflow step: raw Cypher in published YAML would bypass
 * the schema validation and embeddings-on-write the `graph/*` steps exist to
 * provide, and since the workspace itself lives in this graph a stray write
 * corrupts the workflow store, not scratch data. Hence read-only, enforced
 * twice: a keyword pre-check for a clear error, and — the real guarantee —
 * a READ-mode transaction, which the server rejects writes in ("Writing in
 * read access mode not allowed").
 *
 * Output is capped so a `MATCH (n) RETURN n` can't hang the turn or flood
 * the context: a row cap (streamed, so the rest is never fetched), a
 * server-side transaction timeout, long strings truncated, and embedding
 * vectors (any long numeric array) collapsed to a placeholder.
 */
import type { GraphBackend } from "./backend.js";
import { type Params, type Row } from "./bolt.js";
export interface ReadQueryOptions {
    params?: Params;
    /** Max rows returned (default 100, hard max 1000). */
    maxRows?: number;
    /** Server-side transaction timeout in ms (default 15s, hard max 60s). */
    timeoutMs?: number;
    /** Strings longer than this are truncated (default 500). */
    maxStringLength?: number;
}
export interface ReadQueryResult {
    columns: string[];
    rows: Row[];
    /** Rows returned (≤ maxRows). */
    rowCount: number;
    /** True when the query produced more rows than maxRows. */
    truncated: boolean;
    elapsedMs: number;
}
export declare const DEFAULT_MAX_ROWS = 100;
export declare const HARD_MAX_ROWS = 1000;
export declare const DEFAULT_TIMEOUT_MS = 15000;
export declare const HARD_MAX_TIMEOUT_MS = 60000;
export declare const DEFAULT_MAX_STRING = 500;
/** Thrown by the pre-check; the message names the offending keyword. */
export declare class ReadOnlyViolation extends Error {
    readonly keyword: string;
    readonly name = "ReadOnlyViolation";
    constructor(keyword: string);
}
/** The first write keyword found in `cypher`, or undefined when it looks
 *  read-only. A pre-check only — the READ transaction is the guarantee. */
export declare function findWriteKeyword(cypher: string): string | undefined;
/** Shrink a value for the model: truncate long strings, collapse embedding
 *  vectors, recurse into maps/arrays. */
export declare function compactValue(v: unknown, maxString?: number): unknown;
/**
 * Run `cypher` in a READ transaction and return up to `maxRows` compacted
 * rows. Throws `ReadOnlyViolation` on a write keyword; driver errors (syntax,
 * timeout, server-side write rejection) propagate as-is.
 */
export declare function readQuery(backend: GraphBackend, cypher: string, opts?: ReadQueryOptions): Promise<ReadQueryResult>;
