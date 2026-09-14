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
import neo4j from "neo4j-driver";
export const DEFAULT_NAMESPACE = "default";
/**
 * Resolve the graph config from an env-like map, with the same names and
 * defaults as the mcp host's own Neo4j client: `NEO4J_URI`, else
 * `bolt://<NEO4J_HOST>`; user/password default to neo4j/testtest. Returns
 * null when neither `NEO4J_URI` nor `NEO4J_HOST` is set — the backend is
 * opt-in for embedders (the `graph/*` steps default to localhost instead).
 */
export function graphConfigFromEnv(env = process.env) {
    const uri = env["NEO4J_URI"] || (env["NEO4J_HOST"] ? `bolt://${env["NEO4J_HOST"]}` : undefined);
    if (!uri)
        return null;
    return {
        uri,
        user: env["NEO4J_USER"] || "neo4j",
        password: env["NEO4J_PASSWORD"] || "testtest",
        namespace: env["STRUT_GRAPH_NAMESPACE"] || DEFAULT_NAMESPACE,
        database: env["NEO4J_DATABASE"] || undefined,
    };
}
/** Wrap a JS number as a Neo4j Integer (see module doc). */
export const int = (n) => neo4j.int(Math.trunc(n));
/** Convert a driver Record to a plain object, unwrapping Node/Relationship
 *  values to their property maps (labels/type exposed alongside). */
export function rowOf(rec) {
    const out = {};
    for (const key of rec.keys)
        out[key] = plain(rec.get(key));
    return out;
}
function plain(v) {
    if (v === null || v === undefined)
        return v;
    if (neo4j.isNode(v)) {
        return { labels: [...v.labels], properties: plainMap(v.properties) };
    }
    if (neo4j.isRelationship(v)) {
        return { type: v.type, properties: plainMap(v.properties) };
    }
    if (neo4j.isInt(v))
        return v.toNumber();
    if (Array.isArray(v))
        return v.map(plain);
    if (typeof v === "object")
        return plainMap(v);
    return v;
}
function plainMap(m) {
    const out = {};
    for (const [k, v] of Object.entries(m))
        out[k] = plain(v);
    return out;
}
export class Bolt {
    cfg;
    driver;
    constructor(cfg) {
        this.cfg = cfg;
        this.driver = neo4j.driver(cfg.uri, neo4j.auth.basic(cfg.user, cfg.password), {
            disableLosslessIntegers: true,
        });
    }
    get namespace() {
        return this.cfg.namespace;
    }
    /** Throws if the server is unreachable or credentials are wrong. */
    async verify() {
        await this.driver.verifyConnectivity();
    }
    session(mode = "WRITE") {
        return this.driver.session({
            database: this.cfg.database,
            defaultAccessMode: mode === "READ" ? neo4j.session.READ : neo4j.session.WRITE,
        });
    }
    /** Run one auto-commit statement and return its rows. Schema statements
     *  (CREATE CONSTRAINT/INDEX) must go through here, not a managed tx. */
    async run(cypher, params = {}) {
        const session = this.session("WRITE");
        try {
            const res = await session.run(cypher, params);
            return res.records.map(rowOf);
        }
        finally {
            await session.close();
        }
    }
    /** Managed write transaction (retried by the driver on transient errors). */
    async write(fn) {
        const session = this.session("WRITE");
        try {
            return await session.executeWrite(fn);
        }
        finally {
            await session.close();
        }
    }
    /** Managed read transaction. */
    async read(fn) {
        const session = this.session("READ");
        try {
            return await session.executeRead(fn);
        }
        finally {
            await session.close();
        }
    }
    async close() {
        await this.driver.close();
    }
}
/** Rows of a statement run inside a managed transaction. */
export async function txRows(tx, cypher, params = {}) {
    const res = await tx.run(cypher, params);
    return res.records.map(rowOf);
}
//# sourceMappingURL=bolt.js.map