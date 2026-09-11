import { Bolt } from "./bolt.js";
import { THING_SCHEMA, type StrutSchema } from "./strut-schemas.js";
export declare const STRUT_MIGRATION_ID = "strut_domain_seed_v1";
export declare const DOMAIN_VECTOR_INDEX: string;
export declare const DOMAIN_FULLTEXT_INDEX_V2: string;
export declare const GLOBAL_VECTOR_INDEX = "text_embeddings_vector_index";
/**
 * Run one schema statement (CREATE CONSTRAINT / INDEX … IF NOT EXISTS),
 * tolerating a pre-existing EQUIVALENT object under a different shape: a
 * jarvis database may carry a plain index on `Data_Bank(ref_id)` where we
 * ask for a uniqueness constraint (Neo4j then refuses: "A constraint cannot
 * be created until the index has been dropped"). jarvis's own seeder logs
 * and continues in that case; so do we — the existing object serves the
 * same purpose and is jarvis-owned. Returns the skip reason, or null.
 */
export declare function schemaStatement(bolt: Bolt, cypher: string): Promise<string | null>;
export interface SeedReport {
    mode: "standalone" | "shared";
    /** Schema types created on this run. */
    createdSchemas: string[];
    /** Existing schemas that were extended with missing keys (add-only). */
    reconciled: Record<string, string[]>;
    /** Edge-schema rows created on this run, as `SRC-[EDGE]->TGT`. */
    createdEdgeSchemas: string[];
    /** Edge-schema rows skipped because an endpoint Schema is absent. */
    skippedEdgeSchemas: string[];
    /** Schema statements skipped because an equivalent jarvis-owned object
     *  already exists under another shape (see `schemaStatement`). */
    skippedSchemaObjects: string[];
}
/**
 * Flatten a schema the way jarvis stores it: core keys and attributes as
 * top-level properties, no `attributes` blob (`schema_crud.py:932,989`).
 * `Thing`'s `name` sits at its top level and flattens the same way.
 */
export declare function flattenSchema(schema: StrutSchema | typeof THING_SCHEMA): Record<string, unknown>;
/** Seed the Strut domain. Safe to call on every boot. */
export declare function seedStrutDomain(bolt: Bolt): Promise<SeedReport>;
