/**
 * Thin neo4j-driver wrapper for the strut graph backend.
 *
 * Strut talks to Neo4j **directly over bolt** — jarvis is not in the loop —
 * but every byte written follows jarvis's conventions (see
 * `plans/jarvis-graph-compat.md`). This module owns the driver lifecycle and
 * the two integer conventions the rest of `graph/*` relies on:
 *
 *   - **Writes**: a plain JS `number` is sent to Neo4j as a FLOAT. Anything
 *     jarvis stores as a Neo4j Integer (`date_added_to_graph`, `weight`,
 *     every `int`/`datetime` attribute) MUST be wrapped with `int()` before it
 *     goes into a parameter map.
 *   - **Reads**: the driver is configured with `disableLosslessIntegers`, so
 *     integers come back as ordinary JS numbers. No Strut value approaches
 *     2^53 (epoch ms is ~2^41).
 */
import neo4j, { type ManagedTransaction, type Record as Neo4jRecord, type Session } from "neo4j-driver";
export interface GraphConfig {
    /** bolt:// or neo4j:// URI. */
    uri: string;
    user: string;
    password: string;
    /** jarvis data partition every Strut node is written into. */
    namespace: string;
    /** Neo4j database name (omit for the server default). */
    database?: string;
}
export declare const DEFAULT_NAMESPACE = "default";
/**
 * Resolve the graph config from an env-like map, with the same names and
 * defaults as the mcp host's own Neo4j client: `NEO4J_URI`, else
 * `bolt://<NEO4J_HOST>`; user/password default to neo4j/testtest. Returns
 * null when neither `NEO4J_URI` nor `NEO4J_HOST` is set — the backend is
 * opt-in for embedders (the `graph/*` steps default to localhost instead).
 */
export declare function graphConfigFromEnv(env?: Record<string, string | undefined>): GraphConfig | null;
/** Wrap a JS number as a Neo4j Integer (see module doc). */
export declare const int: (n: number) => neo4j.Integer;
export type Params = Record<string, unknown>;
export type Row = Record<string, unknown>;
/** Convert a driver Record to a plain object, unwrapping Node/Relationship
 *  values to their property maps (labels/type exposed alongside). */
export declare function rowOf(rec: Neo4jRecord): Row;
export declare class Bolt {
    readonly cfg: GraphConfig;
    private driver;
    constructor(cfg: GraphConfig);
    get namespace(): string;
    /** Throws if the server is unreachable or credentials are wrong. */
    verify(): Promise<void>;
    session(mode?: "READ" | "WRITE"): Session;
    /** Run one auto-commit statement and return its rows. Schema statements
     *  (CREATE CONSTRAINT/INDEX) must go through here, not a managed tx. */
    run(cypher: string, params?: Params): Promise<Row[]>;
    /** Managed write transaction (retried by the driver on transient errors). */
    write<T>(fn: (tx: ManagedTransaction) => Promise<T>): Promise<T>;
    /** Managed read transaction. */
    read<T>(fn: (tx: ManagedTransaction) => Promise<T>): Promise<T>;
    close(): Promise<void>;
}
/** Rows of a statement run inside a managed transaction. */
export declare function txRows(tx: ManagedTransaction, cypher: string, params?: Params): Promise<Row[]>;
