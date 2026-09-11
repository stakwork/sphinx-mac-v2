import type { Bolt } from "./bolt.js";
import type { SchemaResolver } from "./schema-resolver.js";
export interface NodeSchemaInput {
    /** New type label, e.g. `Evidence`. */
    type: string;
    /** Parent type (must exist as a Schema). Default `Thing`. */
    parent?: string;
    /** Attribute name → jarvis type string (`?` prefix = optional). */
    attributes: Record<string, string>;
    /** `-`-joined attribute tokens that identify a node, e.g. `name` or
     *  `claim_text-speaker_name`. Default `name`. A `<type>-` prefix is
     *  accepted and not doubled. */
    node_key?: string;
    /** Searchable attributes; default = the node_key tokens. */
    index?: string[];
    title_key?: string;
    description_key?: string;
    /** Domain the type belongs to (→ `Domain_<domain>` label). Default `entity`. */
    domain?: string;
    type_description?: string;
}
/** A validated, normalized schema ready to write. */
export interface NodeSchemaPlan {
    type: string;
    parent: string;
    node_key: string;
    tokens: string[];
    index: string[];
    domain: string;
    attributes: Record<string, string>;
    /** The flat `:Schema` node properties (core keys + attributes). */
    flat: Record<string, unknown>;
}
export interface NodeSchemaResult {
    /** True when a new Schema node was written; false when an existing one
     *  was extended (or already had everything). */
    created: boolean;
    ref_id: string;
    type: string;
    parent: string;
    node_key: string;
    /** Attributes added to an existing schema (always empty on create). */
    added: string[];
    /** Full effective attribute map after the write (inherited included). */
    attributes: Record<string, string>;
}
/**
 * Pure validation + normalization of a schema input (no DB). Throws a
 * `GraphValidationError` on the first problem. Existence checks (parent,
 * duplicate type) happen in `createNodeSchema`.
 */
export declare function planNodeSchema(input: NodeSchemaInput): NodeSchemaPlan;
/**
 * Create the schema (or add-only extend an existing non-Strut one). The
 * resolver's caches are invalidated so the next write sees the new type.
 */
export declare function createNodeSchema(bolt: Bolt, resolver: SchemaResolver, input: NodeSchemaInput): Promise<NodeSchemaResult>;
