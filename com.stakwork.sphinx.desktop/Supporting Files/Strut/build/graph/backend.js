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
import { Bolt, graphConfigFromEnv } from "./bolt.js";
import { EdgeWriter } from "./edge-writer.js";
import { MiniLMEmbedder, backfillEmbeddings } from "./embeddings.js";
import { NodeWriter } from "./node-writer.js";
import { seedJarvisOntology } from "./ontology-seed.js";
import { SchemaResolver } from "./schema-resolver.js";
import { seedStrutDomain } from "./schema-seed.js";
import { GraphReader } from "./search.js";
import { migrateVeinToStrut } from "./vein-migration.js";
const cache = new Map();
function keyOf(cfg, opts) {
    const emb = opts.embeddings === false ? "off" : typeof opts.embeddings === "object" ? "custom" : "minilm";
    return [cfg.uri, cfg.user, cfg.database ?? "", cfg.namespace, emb, opts.seedOntology ? "ont" : ""].join("|");
}
/**
 * Open (or reuse) the backend for `cfg`. The first call per config pays for
 * connectivity, seeding, embedder load, and the backfill sweep; later calls
 * get the same instance. A failed open is not cached.
 */
export function openGraphBackend(cfg, opts = {}) {
    const key = keyOf(cfg, opts);
    let p = cache.get(key);
    if (!p) {
        p = open(cfg, opts).catch((e) => {
            cache.delete(key);
            throw e;
        });
        cache.set(key, p);
    }
    return p;
}
/** `openGraphBackend` from `NEO4J_URI`/`NEO4J_USER`/`NEO4J_PASSWORD`/
 *  `STRUT_GRAPH_NAMESPACE`; null when `NEO4J_URI` is unset. */
export function openGraphBackendFromEnv(env = process.env, opts = {}) {
    const cfg = graphConfigFromEnv(env);
    if (!cfg)
        return null;
    const emb = env["STRUT_GRAPH_EMBEDDINGS"];
    const ont = env["STRUT_GRAPH_SEED_ONTOLOGY"];
    return openGraphBackend(cfg, {
        ...opts,
        embeddings: opts.embeddings ?? (emb === "off" || emb === "0" || emb === "false" ? false : true),
        seedOntology: opts.seedOntology ?? (ont === "1" || ont === "true" || ont === "on"),
    });
}
/** Drop every cached backend and close its driver. */
export async function closeGraphBackends() {
    const all = [...cache.values()];
    cache.clear();
    await Promise.all(all.map((p) => p.then((b) => b.bolt.close()).catch(() => undefined)));
}
async function open(cfg, opts) {
    const bolt = new Bolt(cfg);
    try {
        await bolt.verify();
        const embedder = opts.embeddings === false ? undefined : typeof opts.embeddings === "object" ? opts.embeddings : await MiniLMEmbedder.load();
        let seed;
        let veinMigration;
        let ontologySeed;
        let backfill;
        if (!opts.skipBoot) {
            // Legacy names first, so the seed below extends the renamed Schema
            // nodes instead of creating twins beside them.
            veinMigration = await migrateVeinToStrut(bolt);
            if (veinMigration.status === "migrated") {
                console.warn(`[graph] renamed legacy Vein* graph data to Strut*: ${JSON.stringify(veinMigration)}`);
            }
            else if (veinMigration.strays > 0) {
                console.warn(`[graph] ${veinMigration.strays} Domain_vein node(s) carry no Vein type label and were left alone`);
            }
            // Ontology first so a standalone DB gets jarvis's own Thing (with its
            // ref_id) before the Strut domain hangs off it.
            if (opts.seedOntology)
                ontologySeed = await seedJarvisOntology(bolt);
            seed = await seedStrutDomain(bolt);
            if (embedder)
                backfill = await backfillEmbeddings(bolt, embedder);
        }
        const schemas = new SchemaResolver(bolt);
        const backend = {
            cfg,
            bolt,
            nodes: new NodeWriter(bolt, { embedder, resolver: schemas }),
            edges: new EdgeWriter(bolt, { resolver: schemas }),
            reader: new GraphReader(bolt, { embedder, resolver: schemas }),
            schemas,
            embedder,
            seed,
            veinMigration,
            ontologySeed,
            backfill,
            async close() {
                for (const [k, p] of cache)
                    if ((await p.catch(() => null)) === backend)
                        cache.delete(k);
                await bolt.close();
            },
        };
        return backend;
    }
    catch (e) {
        await bolt.close().catch(() => undefined);
        throw e;
    }
}
//# sourceMappingURL=backend.js.map