import { Bolt } from "./bolt.js";
import { type OntologyFixture } from "./fixtures/jarvis-ontology.js";
export interface OntologySeedReport {
    createdSchemas: string[];
    createdEdgeSchemas: number;
    domains: string[];
    /** Schema statements skipped over an equivalent pre-existing object. */
    skippedSchemaObjects: string[];
}
/**
 * `get_searchable_attributes_from_schema`: with an explicit index → index
 * fields + title_key + description_key; otherwise every string-typed
 * non-core attribute (plus index/title/description keys).
 */
export declare function searchableAttributesOf(schema: Record<string, unknown>): Set<string>;
export declare function seedJarvisOntology(bolt: Bolt, fixture?: OntologyFixture): Promise<OntologySeedReport>;
