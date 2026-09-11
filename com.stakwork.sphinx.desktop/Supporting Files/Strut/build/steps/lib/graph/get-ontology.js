import { z } from "zod";
import { defineStep } from "../../../core.js";
import { graphCtx, errText } from "./_shared.js";
/** Same reduction as jarvis/get-ontology: filter "*"/deleted schemas, group
 *  node types by (lowercased) domain ("ungrouped" for null), derive the
 *  sorted domains list, and optionally append deduped compact edge triples
 *  sorted by edge_type. */
function buildOntologyPayload(schemaData, includeEdges, includeAttributes) {
    const schemas = schemaData?.schemas ?? [];
    const rawEdges = schemaData?.edges ?? [];
    const nodeTypes = schemas
        .filter((s) => s.type && s.type !== "*" && !s.is_deleted)
        .map((s) => {
        const td = s.type_description ?? "";
        const desc = s.description ?? "";
        return {
            type: s.type,
            _domain: s.domain ? s.domain.toLowerCase() : null,
            description: td.trim() !== "" ? td : desc,
            ...(includeAttributes && {
                attributes: (s.attributes ?? {}),
                inherited_attributes: (s.inherited_attributes ?? {}),
            }),
        };
    });
    const domains = Array.from(new Set(nodeTypes.map((n) => n._domain).filter((d) => d !== null))).sort();
    const grouped = {};
    for (const { _domain, ...entry } of nodeTypes) {
        const key = _domain ?? "ungrouped";
        (grouped[key] ??= []).push(entry);
    }
    if (!includeEdges)
        return { domains, node_types: grouped };
    const edgeSeen = new Set();
    const edges = [];
    for (const e of rawEdges) {
        const triple = { edge_type: e.edge_type, source_type: e.source_type, target_type: e.target_type };
        const key = `${triple.edge_type}|${triple.source_type}|${triple.target_type}`;
        if (!edgeSeen.has(key)) {
            edgeSeen.add(key);
            edges.push(triple);
        }
    }
    edges.sort((a, b) => a.edge_type.localeCompare(b.edge_type));
    return { domains, node_types: grouped, edges };
}
export default defineStep({
    type: "graph/get-ontology",
    description: "Fetch the ontology of the strut knowledge graph: node types grouped by domain " +
        "and the canonical list of valid `domains`. " +
        "Call this once before graph_graph_search to discover valid values for both the `type` and `domains` parameters. " +
        "Node types are grouped by domain key in `node_types[<domain>]`; types with no domain land in the `ungrouped` bucket. " +
        "Pass `domains` to filter results (comma-separated, e.g. 'Strut,Entity'); omit to receive all domains. " +
        "Relationship edges are omitted by default — graph_graph_neighbors returns edge types live as you traverse. " +
        "Set `include_edges` to also get the full relationship map (source_type -> target_type triples). " +
        "Set `include_attributes` to also get each node type's attribute schema (field names, types, required/optional status). " +
        "WILDCARD EDGES: when include_edges is true, an edge entry whose source_type and/or target_type is \"*\" " +
        "means that edge type applies to ANY node type on that side. \"*\" is intentionally absent from node_types — " +
        "it is a backend sentinel, not a real type.",
    input: z.object({
        domains: z
            .string()
            .optional()
            .describe("Comma-separated list of domains to filter results to (e.g. 'Strut,Entity'). " +
            "Omit to receive node types from all domains. Matched case-insensitively."),
        include_edges: z
            .boolean()
            .optional()
            .default(false)
            .describe("Include the full list of relationship edges (source_type/edge_type/target_type triples). " +
            "Off by default — the edge list is large and graph_graph_neighbors surfaces edge types live."),
        include_attributes: z
            .boolean()
            .optional()
            .default(false)
            .describe("Include each node type's attribute schema maps (`attributes` and `inherited_attributes`). " +
            "Off by default to keep the payload lean. A `?` prefix on a value type (e.g. '?string') means optional."),
    }),
    output: z.any(),
    async run(cfg, ctx) {
        try {
            const b = await graphCtx(ctx);
            const domains = cfg.domains?.split(",").map((d) => d.trim()).filter(Boolean);
            const data = await b.reader.listSchemas(domains && domains.length ? { domains } : {});
            return buildOntologyPayload(data, cfg.include_edges ?? false, cfg.include_attributes ?? false);
        }
        catch (e) {
            return errText("graph/get-ontology", e);
        }
    },
});
//# sourceMappingURL=get-ontology.js.map