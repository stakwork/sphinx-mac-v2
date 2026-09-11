export function testGraphConfig() {
    const uri = process.env["STRUT_TEST_NEO4J_URI"];
    if (!uri)
        return null;
    return {
        uri,
        user: process.env["STRUT_TEST_NEO4J_USER"] ?? "neo4j",
        password: process.env["STRUT_TEST_NEO4J_PASSWORD"] ?? "",
        namespace: process.env["STRUT_TEST_NEO4J_NAMESPACE"] ?? "default",
    };
}
/** Drop every node, relationship, constraint, and index. */
export async function wipeGraph(bolt) {
    await bolt.run(`MATCH (n) DETACH DELETE n`);
    const constraints = await bolt.run(`SHOW CONSTRAINTS YIELD name RETURN name`);
    for (const c of constraints)
        await bolt.run(`DROP CONSTRAINT \`${c["name"]}\` IF EXISTS`);
    const indexes = await bolt.run(`SHOW INDEXES YIELD name, type WHERE type <> 'LOOKUP' RETURN name`);
    for (const i of indexes)
        await bolt.run(`DROP INDEX \`${i["name"]}\` IF EXISTS`);
}
function canon(v) {
    return JSON.stringify(v, (_k, x) => (x && typeof x === "object" && !Array.isArray(x)
        ? Object.fromEntries(Object.entries(x).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)))
        : x));
}
function sortByCanon(xs) {
    return [...xs].sort((a, b) => (canon(a) < canon(b) ? -1 : canon(a) > canon(b) ? 1 : 0));
}
/**
 * Canonical, order-independent picture of the whole database: every node
 * (labels + all properties), every relationship (type + properties + the
 * `type`/`ref_id`/`node_key` of its endpoints), every constraint and index.
 * Deep-equal two snapshots to prove a run was a no-op.
 */
export async function graphSnapshot(bolt) {
    const nodes = await bolt.run(`MATCH (n) RETURN labels(n) AS labels, properties(n) AS properties`);
    const rels = await bolt.run(`MATCH (a)-[r]->(b)
     RETURN type(r) AS type, properties(r) AS properties,
            {type: a.type, ref_id: a.ref_id, node_key: a.node_key} AS from,
            {type: b.type, ref_id: b.ref_id, node_key: b.node_key} AS to`);
    const constraints = await bolt.run(`SHOW CONSTRAINTS YIELD name, type, entityType, labelsOrTypes, properties
     RETURN name, type, entityType, labelsOrTypes, properties`);
    const indexes = await bolt.run(`SHOW INDEXES YIELD name, type, entityType, labelsOrTypes, properties, options
     WHERE type <> 'LOOKUP'
     RETURN name, type, entityType, labelsOrTypes, properties, options`);
    return {
        nodes: sortByCanon(nodes.map((r) => ({ labels: ([...r["labels"]]).sort(), properties: r["properties"] }))),
        rels: sortByCanon(rels.map((r) => ({ type: r["type"], properties: r["properties"], from: r["from"], to: r["to"] }))),
        constraints: sortByCanon(constraints),
        indexes: sortByCanon(indexes),
    };
}
/** Names of all constraints / non-lookup indexes. */
export async function schemaObjectNames(bolt) {
    const c = await bolt.run(`SHOW CONSTRAINTS YIELD name RETURN name`);
    const i = await bolt.run(`SHOW INDEXES YIELD name, type WHERE type <> 'LOOKUP' RETURN name`);
    return { constraints: c.map((r) => r["name"]).sort(), indexes: i.map((r) => r["name"]).sort() };
}
//# sourceMappingURL=test-util.js.map