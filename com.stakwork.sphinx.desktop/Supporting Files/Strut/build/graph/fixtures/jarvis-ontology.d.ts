/**
 * Snapshot of the jarvis ontology (every `:Schema` node with its flattened
 * properties, every Schema→Schema edge schema, and the About node's
 * hidden_domains), dumped read-only from a jarvis-backend default seed.
 * Used by `seedJarvisOntology` so a standalone strut Neo4j can host the
 * jarvis-typed data the lab pipelines write (Document, EvalSet, …) with no
 * jarvis process. Regenerate by re-dumping from a jarvis DB when the
 * library changes (see plans/jarvis-graph-compat.md).
 */
export interface OntologyFixture {
    source: string;
    schemas: Array<Record<string, unknown>>;
    edge_schemas: Array<{
        source: string;
        edge: string;
        target: string;
        props: Record<string, unknown>;
    }>;
    hidden_domains: string[] | null;
}
export declare const JARVIS_ONTOLOGY: OntologyFixture;
