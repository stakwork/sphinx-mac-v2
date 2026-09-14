/**
 * The Strut schema library — a TypeScript mirror of one jarvis schema library
 * (`schema_library.py` in jarvis-backend). Every node type strut writes to the
 * graph is declared here, and ONLY here: the node writer rejects any type not
 * in `STRUT_SCHEMAS`, any attribute not declared on its schema, and any edge
 * not in `STRUT_EDGES` (plan §6).
 *
 * Vocabulary (labels + edges) comes from the label registry in
 * `plans/generic-storage.md`; key/index choices from `jarvis-graph-compat.md`
 * §5. Do not invent labels — every one here was verified absent from jarvis's
 * own library.
 *
 * Attribute grammar (jarvis `_assert_is_valid_schema`):
 *   string | boolean | int | float | datetime | list, optionally `?`-prefixed
 *   for optional. `datetime` values are normalized to epoch SECONDS (int)
 *   before write. jarvis also knows `complex`; strut never uses it.
 */
export type AttrBase = "string" | "boolean" | "int" | "float" | "datetime" | "list";
export type AttrType = AttrBase | `?${AttrBase}`;
export interface StrutSchema {
    type: string;
    parent: "Thing";
    domain: "Strut";
    /** `-`-joined spec: token 0 = type.lower(), then attribute names. */
    node_key: string;
    /** Fields that build `Data_Bank` (search text + `text_embeddings`), in
     *  declared order. Keep large payloads OUT of here. */
    index: string[];
    /** Fields that get their own `{stem}_embeddings` vector + per-label vector
     *  index (jarvis `vector_index`). Only the `input_q`/`output_q` search
     *  types declare this. */
    vector_index?: string[];
    icon: string;
    shape: string;
    primary_color: string;
    secondary_color: string;
    title_key: string;
    description_key: string;
    type_description: string;
    attributes: Record<string, AttrType>;
}
/** One row of the edge registry: (source label, edge type, target label). */
export interface StrutEdgeDef {
    edge: string;
    source: string;
    target: string;
    /** Jarvis schema types outside the Strut domain that this edge points at
     *  (e.g. `Person`, `Thing`). Seeding skips the edge-schema row when the
     *  target Schema node is absent (standalone mode without that type). */
    note?: string;
}
export declare const STRUT_DOMAIN = "Strut";
export declare const STRUT_DOMAIN_LABEL = "Domain_strut";
export declare const THING_TYPE = "Thing";
/**
 * jarvis's root schema, verbatim (`default_schemas.py:11-33`). Seeded only in
 * standalone mode; a jarvis-seeded `Thing` is never touched. `name` sits at
 * the top level in jarvis's dict, so it flattens onto the node like an
 * attribute — every type inherits it.
 */
export declare const THING_SCHEMA: {
    readonly type: "Thing";
    readonly name: "string";
    readonly node_key: "thing-name";
    readonly index: readonly ["name", "description"];
    readonly icon: "NodesIcon";
    readonly shape: "sphere";
    readonly primary_color: "#36292D";
    readonly secondary_color: "#A96755";
    readonly type_description: "The highest-level node in the ontology hierarchy, representing an abstract concept with no direct individual instances";
    readonly title_key: "name";
    readonly description_key: "description";
    readonly attributes: Record<string, AttrType>;
};
/** Attributes every type inherits from `Thing` (jarvis `get_schema` walks
 *  CHILD_OF and unions the parent's flattened keys). */
export declare const THING_INHERITED_ATTRIBUTES: Record<string, AttrType>;
/** jarvis `USAGE_ATTRIBUTES` — never written by jarvis, read by its
 *  `?sort=usage` and search tiebreak. Strut owns updating them. */
export declare const USAGE_ATTRIBUTES: Record<string, AttrType>;
/** Properties jarvis stamps on every node, never declared as attributes and
 *  never accepted from a caller (`GENERIC_NODE_PROPERTIES` + the write-time
 *  system props). */
export declare const GENERIC_NODE_PROPERTIES: Set<string>;
/** jarvis `SCHEMA_CORE_PROPERTIES` — top-level keys of a Schema node that
 *  are NOT attributes (everything else on the node is one). */
export declare const SCHEMA_CORE_PROPERTIES: Set<string>;
/** Attribute names a schema may not declare (jarvis reserved keys). */
export declare const RESERVED_ATTRIBUTE_NAMES: Set<string>;
/** Preview fields are capped so search/embedding text stays light; full
 *  payloads stay in the run/chat log behind `log_ref`. */
export declare const PREVIEW_MAX_CHARS = 500;
export declare const STRUT_SCHEMAS: readonly StrutSchema[];
/** Every (source, edge, target) strut may write. `ACCESSED` is declared
 *  against `Thing` — provenance may point at ANY node — and the writer
 *  accepts any target label for it (plan §6 item 6). */
export declare const STRUT_EDGES: readonly StrutEdgeDef[];
/** Edge types whose declared target is a wildcard (any node label). */
export declare const WILDCARD_TARGET_EDGES: Set<string>;
/** The type label of a node: its labels minus the structural ones. */
export declare function typeLabelOf(labels: string[]): string | undefined;
/** Exact-match lookup (jarvis resolves case-insensitively; we don't). */
export declare function getStrutSchema(type: string): StrutSchema | undefined;
export declare function isStrutType(type: string): boolean;
/** A schema's full attribute map: its own attributes + `Thing`'s. This is
 *  what jarvis's `get_schema` returns (minus the core keys), so it is what
 *  the validator checks payloads against. */
export declare function effectiveAttributes(schema: StrutSchema): Record<string, AttrType>;
export declare function isOptional(t: AttrType): boolean;
export declare function baseType(t: AttrType): AttrBase;
/** `input_schema` → `input`; anything else unchanged (jarvis `stem`). */
export declare function vectorStem(prop: string): string;
/** `{stem}_embeddings` (jarvis `embedding_column`). */
export declare function embeddingColumn(prop: string): string;
/** `{label.lower()}_{stem}_vector_index` (jarvis `vector_index_name`). */
export declare function vectorIndexName(type: string, prop: string): string;
/** Node-key tokens after the type token. */
export declare function nodeKeyFields(schema: StrutSchema): string[];
/**
 * Searchable attributes across the Strut library, per jarvis's tier-1 rule
 * for schemas with an explicit `index` (`get_searchable_attributes_from_schema`):
 * index fields + title_key + description_key. Used to build the domain
 * fulltext index (sorted, plus `node_key` appended by the seeder).
 */
export declare function searchableAttributes(schemas?: readonly StrutSchema[]): string[];
/** (type, property) pairs that declare a per-property vector index. */
export declare function vectorIndexedPairs(schemas?: readonly StrutSchema[]): Array<{
    type: string;
    prop: string;
}>;
/**
 * Structural checks on the library itself (mirrors jarvis `valid_node_key`
 * `schema_validation.py:311-338` + `_assert_is_valid_schema`, tightened):
 * bare-identifier attribute names, no reserved names, every node_key token
 * a REQUIRED attribute, index/vector_index/title/description fields
 * declared, edge types uppercase, edge endpoints known. Throws on the first
 * violation. Runs once at module load so a bad edit fails fast.
 */
export declare function assertLibraryWellFormed(schemas?: readonly StrutSchema[], edges?: readonly StrutEdgeDef[]): void;
