/**
 * One-shot rename of the pre-rename graph domain: `Vein*` → `Strut*`.
 *
 * Before the package was renamed (stakgraph #1664) strut wrote its nodes
 * under `VeinWorkflow`, `VeinStep`, … with `Domain_vein` and node_keys like
 * `veinstep-<type>`. Nothing about those rows changed except the names, so
 * this pass rewrites the names in place and leaves everything else —
 * `ref_id`s, edges, `content_hash`es, embeddings, `Data_Bank` — untouched:
 *
 *   1. guard: refuse (throw) if any rewritten `(node_key, namespace)` is
 *      already held by another node — a database that was booted on the
 *      renamed code and re-published into needs a human, not a merge policy;
 *   2. `:Schema` meta-nodes: `type`, `domain`, `node_key` spec renamed in
 *      place (edge-schema relationships hang off the same nodes). A legacy
 *      Schema whose Strut twin already exists (the seed ran on the renamed
 *      code before this migration existed) is dropped instead — two Schema
 *      nodes for one type would break jarvis;
 *   3. data nodes, per type, in batches: add the `Strut*` + `Domain_strut`
 *      labels, rewrite the node_key prefix, remove the legacy labels;
 *   4. drop every constraint and index on a legacy label — the seed that
 *      runs next recreates them under the new names (jarvis rebuilds its
 *      own `domain_<x>_attribute_index` from `Schema.domain` by itself);
 *   5. stamp the `Migration` ledger so this never scans again.
 *
 * Runs at boot before `seedStrutDomain` (backend.ts). Idempotent at every
 * step, so a crash mid-way is repaired by the next boot. Step sources that
 * `import "vein"` are deliberately NOT rewritten (the content hash is the
 * version's identity); strut-resolve-hook.ts keeps `"vein"` as an alias.
 */
import { Bolt } from "./bolt.js";
export declare const VEIN_MIGRATION_ID = "strut_rename_vein_v1";
export declare const LEGACY_DOMAIN = "Vein";
export declare const LEGACY_DOMAIN_LABEL = "Domain_vein";
export interface LegacyType {
    /** Current label, e.g. `StrutRun`. */
    type: string;
    /** Pre-rename label, e.g. `VeinRun`. */
    legacy: string;
    /** node_key spec from the library, e.g. `strutrun-run_id`. */
    nodeKeySpec: string;
    /** node_key value prefixes: `strutrun-` / `veinrun-`. */
    keyPrefix: string;
    legacyKeyPrefix: string;
}
/** The nine renames, derived from the live library so they cannot drift. */
export declare function legacyTypes(): LegacyType[];
export interface VeinMigrationReport {
    /** `already_done` = ledger row present, nothing scanned; `nothing_to_do` =
     *  scanned, found no legacy names, ledger stamped. */
    status: "migrated" | "already_done" | "nothing_to_do";
    /** Legacy Schema nodes renamed in place (new type names). */
    schemasRenamed: string[];
    /** Legacy Schema nodes dropped because a Strut twin already existed. */
    schemasDropped: string[];
    /** Data nodes relabeled, per new type. */
    relabeled: Record<string, number>;
    droppedConstraints: string[];
    droppedIndexes: string[];
    /** `Domain_vein` nodes left alone because they carry no legacy type label. */
    strays: number;
}
export declare class VeinMigrationCollision extends Error {
    readonly collisions: Array<{
        legacy: string;
        key: string;
        labels: string[];
    }>;
    constructor(collisions: Array<{
        legacy: string;
        key: string;
        labels: string[];
    }>);
}
export declare function migrateVeinToStrut(bolt: Bolt): Promise<VeinMigrationReport>;
