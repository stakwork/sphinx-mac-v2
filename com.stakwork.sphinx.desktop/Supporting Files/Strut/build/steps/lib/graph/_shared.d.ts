import type { StepContext } from "../../../core.js";
import type { StrutCapabilities } from "../../../capabilities.js";
import type { GraphBackend } from "../../../graph/backend.js";
export type { GraphBackend };
/**
 * The `graph/*` steps are thin plumbing over strut's own Neo4j graph backend
 * (`src/graph/*`, plans/jarvis-graph-compat.md) — the strut-native twins of
 * the lab's `jarvis/*` steps: same step names, input schemas, and output
 * shapes, so a workflow swaps backends by step type
 * (`jarvis/graph-search` ↔ `graph/graph-search`). No jarvis in the loop;
 * everything written follows jarvis's conventions so a jarvis mounted on
 * the same database later treats the `Strut` domain as native.
 *
 * Config (all via `ctx.services.secrets`, secret store → env fallback; the
 * same names + defaults as the mcp host's own Neo4j client, so a local
 * Neo4j needs nothing and a deployment's existing vars just work):
 *   - `NEO4J_URI`             — bolt:// URI; else `bolt://<NEO4J_HOST>`
 *     (`NEO4J_HOST` default `localhost:7687`).
 *   - `NEO4J_USER` / `NEO4J_PASSWORD` — credentials (default neo4j / testtest).
 *   - `NEO4J_DATABASE`        — optional database name.
 *   - `STRUT_GRAPH_NAMESPACE`  — default jarvis namespace (default "default").
 *   - `STRUT_GRAPH_EMBEDDINGS` — "off" disables the local MiniLM embedder
 *     (writes leave vectors NULL; search is fulltext-only).
 *   - `STRUT_GRAPH_SEED_ONTOLOGY` — "1" also seeds the bundled jarvis
 *     ontology on first open (add-only), so a STANDALONE Neo4j can host
 *     jarvis-typed data (Document, EvalSet, …) with no jarvis process.
 *
 * The backend is opened once per config and cached process-wide; the first
 * open runs the boot obligations (domain seeding + embedding backfill).
 * Per the lib dependency convention the backend module (and with it
 * neo4j-driver) is imported lazily here, inside `run()`, never at module
 * top level.
 */
export declare function graphCtx(ctx?: StepContext<StrutCapabilities>): Promise<GraphBackend>;
export interface EdgeWriteArgs {
    edge_type: string;
    source_ref_id: string;
    target_ref_id: string;
    edge_data?: Record<string, unknown>;
    weight?: number;
    /** jarvis `create_schema_if_missing`: when the (source type, edge, target
     *  type) triple has no edge schema, register one between the endpoint
     *  types and retry once. */
    create_schema_if_missing?: boolean;
}
/** Write one edge through the backend, honouring `create_schema_if_missing`
 *  the way jarvis's edge endpoint does. Throws the writer's error otherwise. */
export declare function writeEdge(b: GraphBackend, a: EdgeWriteArgs): Promise<import("../../../index.js").EdgeWriteResult>;
/** The `code` of a `GraphValidationError` / `GraphReadError`, else undefined.
 *  Duck-typed on `name` so this module never imports the graph classes. */
export declare function graphErrorCode(e: unknown): string | undefined;
/** Render a graph error as a plain string the agent can read (the same
 *  convention the jarvis/* steps use for HTTP failures). */
export declare function errText(step: string, e: unknown): string;
