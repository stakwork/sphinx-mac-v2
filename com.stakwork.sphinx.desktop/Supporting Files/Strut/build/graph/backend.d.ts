/**
 * The strut graph backend as one object: a bolt connection plus the writers,
 * the reader, and (optionally) the local embedder — opened once per
 * config and cached, with the boot-time obligations run on open:
 *
 *   1. `migrateVeinToStrut` — one-shot rename of pre-#1664 `Vein*` names;
 *   2. `seedStrutDomain` — schema meta-graph, constraints, indexes (§4);
 *   3. `backfillEmbeddings` — heal any NULL vectors left by a crash (§2).
 *
 * Consumers (the `graph/*` lab steps, a future `Neo4jWorkspaceStore` and
 * run projector) call `openGraphBackend(cfg)` and share the instance.
 */
import { Bolt, type GraphConfig } from "./bolt.js";
import { EdgeWriter } from "./edge-writer.js";
import { type BackfillReport } from "./embeddings.js";
import { NodeWriter, type Embedder } from "./node-writer.js";
import { type OntologySeedReport } from "./ontology-seed.js";
import { SchemaResolver } from "./schema-resolver.js";
import { type SeedReport } from "./schema-seed.js";
import { GraphReader } from "./search.js";
import { type VeinMigrationReport } from "./vein-migration.js";
export interface GraphBackendOptions {
    /** `false` disables embeddings entirely (vectors stay NULL, search is
     *  fulltext-only). Pass an `Embedder` to inject one (tests). Default:
     *  load the local MiniLM model. */
    embeddings?: boolean | Embedder;
    /** Skip the boot-time seed + backfill (tests that manage the DB). */
    skipBoot?: boolean;
    /** Also seed the bundled jarvis ontology (`fixtures/jarvis-ontology.ts`)
     *  — add-only, a no-op on a jarvis-seeded DB — so a standalone Neo4j can
     *  host jarvis-typed data (Document, EvalSet, Concept, …) with no jarvis
     *  process. Env: `STRUT_GRAPH_SEED_ONTOLOGY=1`. */
    seedOntology?: boolean;
}
export interface GraphBackend {
    readonly cfg: GraphConfig;
    readonly bolt: Bolt;
    readonly nodes: NodeWriter;
    readonly edges: EdgeWriter;
    readonly reader: GraphReader;
    /** Live schema resolution shared by the writers and reader. */
    readonly schemas: SchemaResolver;
    readonly embedder: Embedder | undefined;
    /** What the boot-time seed did (undefined when skipped). */
    readonly seed: SeedReport | undefined;
    readonly veinMigration: VeinMigrationReport | undefined;
    readonly ontologySeed: OntologySeedReport | undefined;
    readonly backfill: BackfillReport | undefined;
    close(): Promise<void>;
}
/**
 * Open (or reuse) the backend for `cfg`. The first call per config pays for
 * connectivity, seeding, embedder load, and the backfill sweep; later calls
 * get the same instance. A failed open is not cached.
 */
export declare function openGraphBackend(cfg: GraphConfig, opts?: GraphBackendOptions): Promise<GraphBackend>;
/** `openGraphBackend` from `NEO4J_URI`/`NEO4J_USER`/`NEO4J_PASSWORD`/
 *  `STRUT_GRAPH_NAMESPACE`; null when `NEO4J_URI` is unset. */
export declare function openGraphBackendFromEnv(env?: Record<string, string | undefined>, opts?: GraphBackendOptions): Promise<GraphBackend> | null;
/** Drop every cached backend and close its driver. */
export declare function closeGraphBackends(): Promise<void>;
