import { rowOf } from "./bolt.js";
export const DEFAULT_MAX_ROWS = 100;
export const HARD_MAX_ROWS = 1000;
export const DEFAULT_TIMEOUT_MS = 15_000;
export const HARD_MAX_TIMEOUT_MS = 60_000;
export const DEFAULT_MAX_STRING = 500;
/** Numeric arrays at least this long are assumed to be embedding vectors. */
const VECTOR_MIN_LEN = 32;
/** Thrown by the pre-check; the message names the offending keyword. */
export class ReadOnlyViolation extends Error {
    keyword;
    name = "ReadOnlyViolation";
    constructor(keyword) {
        super(`graph_query is read-only: "${keyword}" is not allowed. ` +
            "Write through the graph/* steps (create-node, create-triplet, edit-node, …) instead.");
        this.keyword = keyword;
    }
}
// Cypher clauses / procedures that mutate. Word-bounded and checked with
// string literals, backtick identifiers, and comments stripped, so a
// property called `data_set` or a search term 'reset' doesn't trip it.
// `apoc.` is blanket-blocked: many apoc procedures write, and none are
// needed to inspect a graph.
const WRITE_PATTERNS = [
    [/\bCREATE\b/i, "CREATE"],
    [/\bMERGE\b/i, "MERGE"],
    [/\bDELETE\b/i, "DELETE"],
    [/\bDETACH\b/i, "DETACH"],
    [/\bSET\b/i, "SET"],
    [/\bREMOVE\b/i, "REMOVE"],
    [/\bDROP\b/i, "DROP"],
    [/\bFOREACH\b/i, "FOREACH"],
    [/\bLOAD\s+CSV\b/i, "LOAD CSV"],
    [/\bALTER\b/i, "ALTER"],
    [/\b(GRANT|DENY|REVOKE)\b/i, "GRANT/DENY/REVOKE"],
    [/\b(START|STOP)\s+DATABASE\b/i, "START/STOP DATABASE"],
    [/\bapoc\./i, "apoc.*"],
    [/\bdb\.(create|drop|index\.fulltext\.(create|drop)|index\.vector\.create)/i, "db.create*/db.drop*"],
];
/** Strip string literals, backtick identifiers, and comments so keyword
 *  matching only sees real Cypher tokens. */
function stripLiterals(cypher) {
    return cypher
        .replace(/\/\*[\s\S]*?\*\//g, " ")
        .replace(/\/\/[^\n]*/g, " ")
        .replace(/'(?:[^'\\]|\\.)*'/g, "''")
        .replace(/"(?:[^"\\]|\\.)*"/g, '""')
        .replace(/`[^`]*`/g, "``");
}
/** The first write keyword found in `cypher`, or undefined when it looks
 *  read-only. A pre-check only — the READ transaction is the guarantee. */
export function findWriteKeyword(cypher) {
    const bare = stripLiterals(cypher);
    for (const [re, name] of WRITE_PATTERNS)
        if (re.test(bare))
            return name;
    return undefined;
}
/** Shrink a value for the model: truncate long strings, collapse embedding
 *  vectors, recurse into maps/arrays. */
export function compactValue(v, maxString = DEFAULT_MAX_STRING) {
    if (typeof v === "string") {
        return v.length > maxString ? `${v.slice(0, maxString)}… [+${v.length - maxString} chars]` : v;
    }
    if (Array.isArray(v)) {
        if (v.length >= VECTOR_MIN_LEN && v.every((x) => typeof x === "number")) {
            return `[vector: ${v.length} numbers]`;
        }
        return v.map((x) => compactValue(x, maxString));
    }
    if (v && typeof v === "object") {
        const out = {};
        for (const [k, x] of Object.entries(v))
            out[k] = compactValue(x, maxString);
        return out;
    }
    return v;
}
/**
 * Run `cypher` in a READ transaction and return up to `maxRows` compacted
 * rows. Throws `ReadOnlyViolation` on a write keyword; driver errors (syntax,
 * timeout, server-side write rejection) propagate as-is.
 */
export async function readQuery(backend, cypher, opts = {}) {
    const kw = findWriteKeyword(cypher);
    if (kw)
        throw new ReadOnlyViolation(kw);
    const maxRows = Math.min(Math.max(1, Math.trunc(opts.maxRows ?? DEFAULT_MAX_ROWS)), HARD_MAX_ROWS);
    const timeout = Math.min(Math.max(1, Math.trunc(opts.timeoutMs ?? DEFAULT_TIMEOUT_MS)), HARD_MAX_TIMEOUT_MS);
    const maxString = opts.maxStringLength ?? DEFAULT_MAX_STRING;
    const started = Date.now();
    const session = backend.bolt.session("READ");
    try {
        return await session.executeRead(async (tx) => {
            const result = tx.run(cypher, opts.params ?? {});
            const rows = [];
            let columns = [];
            let truncated = false;
            // Stream so a huge result stops at the cap instead of being fetched
            // whole; breaking out of the iterator discards the remainder.
            for await (const rec of result) {
                if (columns.length === 0)
                    columns = rec.keys.map(String);
                if (rows.length >= maxRows) {
                    truncated = true;
                    break;
                }
                rows.push(compactValue(rowOf(rec), maxString));
            }
            if (columns.length === 0)
                columns = (await result.keys()).map(String);
            return { columns, rows, rowCount: rows.length, truncated, elapsedMs: Date.now() - started };
        }, { timeout });
    }
    finally {
        await session.close();
    }
}
//# sourceMappingURL=query.js.map