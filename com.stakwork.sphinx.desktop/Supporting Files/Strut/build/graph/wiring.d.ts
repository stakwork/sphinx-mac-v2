import type { GraphBackend, GraphBackendOptions } from "./backend.js";
import { Neo4jWorkspaceStore, type Neo4jWorkspaceStoreOptions } from "./workspace-store.js";
/** Graph unless `STRUT_WORKSPACE_BACKEND=fs` (case-insensitive; `file` /
 *  `filesystem` accepted too). Any other value — including unset or the
 *  legacy `graph` — means graph. */
export declare function graphWorkspaceRequested(env?: Record<string, string | undefined>): boolean;
/** Same default as the mcp host's own Neo4j client and the `graph/*` steps:
 *  a local Neo4j needs nothing configured. */
export declare const DEFAULT_NEO4J_HOST = "localhost:7687";
/**
 * Where the graph store materializes active custom steps for the module
 * loader: INSIDE the data dir, beside where a file workspace would keep
 * `steps/custom`. Custom steps `import "strut"` (and "zod"), and Node resolves
 * that by walking up from the FILE's directory — so the dir must sit in the
 * same tree as the file store's, never under the OS temp dir. Distinct from
 * `steps/custom` so switching backends on one dir can't prune the other's
 * files.
 */
export declare function graphMaterializeDir(dataDir: string): string;
/**
 * Open the graph backend from env and wrap it in a `Neo4jWorkspaceStore`.
 * Connection: `NEO4J_URI`, else `bolt://<NEO4J_HOST>` (default
 * `localhost:7687`); `NEO4J_USER` / `NEO4J_PASSWORD` default to
 * neo4j / testtest — the same resolution as the mcp host, so a deployment's
 * existing vars just work and a local Neo4j needs none. `dataDir` (default
 * `STRUT_WORKSPACE` / `./workspace`) is where custom steps are materialized.
 */
export declare function graphWorkspaceFromEnv(env?: Record<string, string | undefined>, opts?: {
    dataDir?: string;
    backend?: GraphBackendOptions;
    store?: Neo4jWorkspaceStoreOptions;
}): Promise<{
    backend: GraphBackend;
    workspace: Neo4jWorkspaceStore;
}>;
