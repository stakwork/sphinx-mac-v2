/**
 * Helpers for graph tests that need a live Neo4j.
 *
 * Tests are opt-in: they run only when `STRUT_TEST_NEO4J_URI` is set, and
 * they WIPE that database between cases — point it at a throwaway
 * container, never at a jarvis instance. Example:
 *
 *   docker run -d --name strut-neo4j-test -p 7688:7687 \
 *     -e NEO4J_AUTH=neo4j/struttest neo4j:5
 *   STRUT_TEST_NEO4J_URI=bolt://localhost:7688 STRUT_TEST_NEO4J_PASSWORD=struttest \
 *     npm run test:graph
 */
import { Bolt, type GraphConfig } from "./bolt.js";
export declare function testGraphConfig(): GraphConfig | null;
/** Drop every node, relationship, constraint, and index. */
export declare function wipeGraph(bolt: Bolt): Promise<void>;
export interface GraphSnapshot {
    nodes: Array<{
        labels: string[];
        properties: Record<string, unknown>;
    }>;
    rels: Array<{
        type: string;
        properties: Record<string, unknown>;
        from: unknown;
        to: unknown;
    }>;
    constraints: unknown[];
    indexes: unknown[];
}
/**
 * Canonical, order-independent picture of the whole database: every node
 * (labels + all properties), every relationship (type + properties + the
 * `type`/`ref_id`/`node_key` of its endpoints), every constraint and index.
 * Deep-equal two snapshots to prove a run was a no-op.
 */
export declare function graphSnapshot(bolt: Bolt): Promise<GraphSnapshot>;
/** Names of all constraints / non-lookup indexes. */
export declare function schemaObjectNames(bolt: Bolt): Promise<{
    constraints: string[];
    indexes: string[];
}>;
