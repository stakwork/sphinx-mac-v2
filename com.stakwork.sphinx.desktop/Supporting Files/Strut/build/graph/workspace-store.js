/**
 * `Neo4jWorkspaceStore` — the graph-backed `WorkspaceStore`
 * (plans/generic-storage.md §7). Workflows, versions, steps, and step
 * versions are nodes in strut's own Neo4j domain (`StrutWorkflow`,
 * `StrutWorkflowVersion`, `StrutStep`, `StrutStepVersion` — the label registry
 * in `strut-schemas.ts`), linked by `VERSION_OF`, `ACTIVE_VERSION`,
 * `USES_STEP`, and `DEPENDS_ON` edges. Every write goes through the
 * jarvis-dialect node/edge writers, so a jarvis mounted on the same database
 * sees native data.
 *
 * Semantics mirror `FileWorkspaceStore` (the conformance suite in
 * `src/test-util/workspace-conformance.ts` is the contract), with one
 * deliberate difference: versions are CONTENT-ADDRESSED. A version node is
 * keyed by `(name, content_hash)`, and the user-facing `v1`/`v2` label is a
 * property on it. Publishing content that already exists under another
 * label re-labels that version instead of duplicating it.
 *
 * Custom step code is executable, so the store also materializes every
 * active custom step into a scratch directory (`materializeCustomSteps`) for
 * the module loader; the graph stays the record.
 *
 * Deletion is soft (`is_deleted = true`) — nothing is ever DETACH DELETEd.
 */
import { mkdir, readdir, readFile, rm, writeFile } from "node:fs/promises";
import { ensureEsmScope } from "../workspace.js";
import { createHash } from "node:crypto";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import yaml from "js-yaml";
import { assertValidWorkflowYaml, flowFromYaml, renderWorkflowYaml, validateStepName, } from "../workspace.js";
import { readStepSourceFromDisk } from "../steps/registry.js";
import { contentHash, nextVersionLabel } from "../version.js";
const NOT_DELETED = (v) => `(${v}.is_deleted IS NULL OR ${v}.is_deleted = false)`;
const isoFromSeconds = (s) => new Date((s ?? 0) * 1000).toISOString();
/** Drop undefined/null values so the writer sees only real attributes. */
function compact(o) {
    const out = {};
    for (const [k, v] of Object.entries(o))
        if (v !== undefined && v !== null)
            out[k] = v;
    return out;
}
/** A patch that makes a node's attributes equal `desired` for the given
 *  keys: set the defined ones, remove the ones now undefined. */
function patchFor(current, desired) {
    const set = {};
    const remove = [];
    for (const [k, v] of Object.entries(desired)) {
        if (v === undefined || v === null || v === "") {
            if (current[k] !== undefined && current[k] !== null)
                remove.push(k);
        }
        else if (current[k] !== v) {
            set[k] = v;
        }
    }
    return Object.keys(set).length || remove.length ? { set, remove } : null;
}
/** Every `{ type, config }` step object in a parsed workflow, at any depth
 *  (loop/if/foreach bodies nest steps inside config). */
function collectStepRefs(node, out = []) {
    if (Array.isArray(node)) {
        for (const x of node)
            collectStepRefs(x, out);
    }
    else if (node && typeof node === "object") {
        const o = node;
        if (typeof o["type"] === "string" && typeof o["id"] === "string") {
            out.push({ type: o["type"], config: o["config"] ?? {} });
        }
        for (const v of Object.values(o))
            if (v && typeof v === "object")
                collectStepRefs(v, out);
    }
    return out;
}
export class Neo4jWorkspaceStore {
    backend;
    ns;
    materializeDir;
    constructor(backend, opts = {}) {
        this.backend = backend;
        this.ns = backend.cfg.namespace;
        this.materializeDir =
            opts.materializeDir ??
                join(tmpdir(), "strut-graph-steps", createHash("sha256").update(`${backend.cfg.uri}|${backend.cfg.database ?? ""}|${this.ns}`).digest("hex").slice(0, 16));
    }
    // ── Reads: workflows ───────────────────────────────────────────────────
    async workflowRow(name) {
        const rows = await this.backend.bolt.run(`MATCH (w:StrutWorkflow {namespace: $ns, name: $name}) WHERE ${NOT_DELETED("w")}
       RETURN properties(w) AS p LIMIT 1`, { ns: this.ns, name });
        return rows.length ? rows[0]["p"] : null;
    }
    async versionRows(name) {
        const rows = await this.backend.bolt.run(`MATCH (v:StrutWorkflowVersion {namespace: $ns, name: $name}) WHERE ${NOT_DELETED("v")}
       RETURN properties(v) AS p ORDER BY v.created_at, v.date_added_to_graph`, { ns: this.ns, name });
        return rows.map((r) => r["p"]);
    }
    async listWorkflows() {
        const rows = await this.backend.bolt.run(`MATCH (w:StrutWorkflow {namespace: $ns}) WHERE ${NOT_DELETED("w")}
       OPTIONAL MATCH (v:StrutWorkflowVersion {namespace: $ns, name: w.name}) WHERE ${NOT_DELETED("v")}
       WITH w, v ORDER BY v.created_at, v.date_added_to_graph
       RETURN properties(w) AS w, collect(properties(v)) AS versions ORDER BY w.name`, { ns: this.ns });
        const out = [];
        for (const r of rows) {
            const w = r["w"];
            const versions = r["versions"].filter((v) => v && v.version_label);
            const active = versions.find((v) => v.content_hash === w.active_version);
            out.push({
                name: w.name,
                activeVersion: active?.version_label ?? "",
                versions: versions.map((v) => v.version_label),
                description: active?.description,
                ...(w.category ? { category: w.category } : {}),
                ...(w.publisher ? { publisher: w.publisher } : {}),
            });
        }
        return out;
    }
    async getWorkflowMetadata(name) {
        const w = await this.workflowRow(name);
        if (!w)
            return null;
        const versions = await this.versionRows(name);
        const active = versions.find((v) => v.content_hash === w.active_version);
        const meta = { active: active?.version_label ?? "", versions: {} };
        for (const v of versions) {
            meta.versions[v.version_label] = {
                createdAt: isoFromSeconds(v.created_at),
                ...(v.description !== undefined ? { description: v.description } : {}),
                hash: v.content_hash,
            };
        }
        if (w.category)
            meta.category = w.category;
        if (w.publisher)
            meta.publisher = w.publisher;
        return meta;
    }
    async versionByLabel(name, label) {
        return (await this.versionRows(name)).find((v) => v.version_label === label) ?? null;
    }
    async activeVersion(name) {
        const w = await this.workflowRow(name);
        if (!w)
            throw new Error(`Workflow "${name}" not found`);
        const v = (await this.versionRows(name)).find((x) => x.content_hash === w.active_version);
        if (!v)
            throw new Error(`Workflow "${name}" has no active version`);
        return v;
    }
    async getWorkflow(name) {
        const v = await this.activeVersion(name);
        return flowFromYaml(name, v.version_label, v.source);
    }
    async getWorkflowVersion(name, version) {
        return flowFromYaml(name, version, await this.getWorkflowSource(name, version));
    }
    async getWorkflowSource(name, version) {
        const v = await this.versionByLabel(name, version);
        if (!v)
            throw new Error(`Version "${version}" of workflow "${name}" not found`);
        return v.source;
    }
    async getWorkflowHash(name, version) {
        try {
            const v = version ? await this.versionByLabel(name, version) : await this.activeVersion(name);
            return v?.content_hash ?? null;
        }
        catch {
            return null;
        }
    }
    // ── Writes: workflows ──────────────────────────────────────────────────
    async createWorkflow(name, content, description, category, publisher) {
        let finalName = name;
        let n = 2;
        while (await this.workflowRow(finalName))
            finalName = `${name}-${n++}`;
        let resolvedContent = content;
        if (finalName !== name && typeof content === "string") {
            const parsed = yaml.load(content);
            if (parsed && typeof parsed === "object") {
                parsed.name = finalName;
                resolvedContent = yaml.dump(parsed, { lineWidth: 120, noRefs: true });
            }
        }
        await this.publishWorkflow(finalName, "v1", resolvedContent, description, category, publisher);
        return { name: finalName, version: "v1" };
    }
    async publishWorkflow(name, version, content, description, category, publisher) {
        const yamlStr = renderWorkflowYaml(name, content);
        assertValidWorkflowYaml(yamlStr);
        await this.writeVersion(name, version, yamlStr, description, category, publisher);
    }
    /** The one write path behind publish/publishByContent/setParam: ensure the
     *  version node exists (creating, restoring, or re-labeling it), then
     *  point the workflow at it. */
    async writeVersion(name, label, yamlStr, description, category, publisher) {
        const hash = contentHash(yamlStr);
        const { nodes } = this.backend;
        const existing = (await this.versionRows(name)).find((v) => v.content_hash === hash);
        let versionRef;
        if (existing) {
            // Content-addressed: same content under a new label re-labels.
            const patch = patchFor(existing, {
                version_label: label,
                ...(description !== undefined ? { description } : {}),
            });
            if (patch)
                await nodes.update(existing.ref_id, patch);
            versionRef = existing.ref_id;
        }
        else {
            const parsed = yaml.load(yamlStr) ?? {};
            const r = await nodes.write({
                type: "StrutWorkflowVersion",
                data: compact({
                    name,
                    content_hash: hash,
                    version_label: label,
                    description,
                    created_at: new Date().toISOString(),
                    source: yamlStr,
                    params_json: parsed["params"] != null ? JSON.stringify(parsed["params"]) : undefined,
                    publisher,
                }),
            });
            versionRef = r.ref_id;
        }
        await this.activate(name, { ref_id: versionRef, hash, description }, category, publisher);
        await this.linkVersionDeps(versionRef, yamlStr);
        return (await this.versionRows(name)).find((v) => v.ref_id === versionRef);
    }
    /** Point the workflow node (creating it if needed) at a version: mirror the
     *  version's description onto the workflow, swap the ACTIVE_VERSION edge. */
    async activate(name, version, category, publisher) {
        const { nodes, edges, bolt } = this.backend;
        const w = await this.workflowRow(name);
        let wfRef;
        if (!w) {
            const r = await nodes.write({
                type: "StrutWorkflow",
                data: compact({ name, description: version.description, category, publisher, active_version: version.hash }),
            });
            wfRef = r.ref_id;
        }
        else {
            wfRef = w.ref_id;
            const desired = { active_version: version.hash, description: version.description };
            if (category !== undefined)
                desired["category"] = category;
            if (publisher !== undefined)
                desired["publisher"] = publisher;
            const patch = patchFor(w, desired);
            if (patch)
                await nodes.update(wfRef, patch);
        }
        await edges.write({ edge: "VERSION_OF", source_ref_id: version.ref_id, target_ref_id: wfRef });
        await bolt.run(`MATCH (w:StrutWorkflow {ref_id: $w})-[r:ACTIVE_VERSION]->(v) WHERE v.ref_id <> $v DELETE r`, { w: wfRef, v: version.ref_id });
        await edges.write({ edge: "ACTIVE_VERSION", source_ref_id: wfRef, target_ref_id: version.ref_id });
    }
    /** USES_STEP → every custom step the version references; DEPENDS_ON →
     *  every workflow its subflow steps call. Only targets that exist are
     *  linked (the graph pays off in "which workflows use step X"). */
    async linkVersionDeps(versionRef, yamlStr) {
        let parsed;
        try {
            parsed = yaml.load(yamlStr);
        }
        catch {
            return;
        }
        const refs = collectStepRefs(parsed?.["steps"]);
        const stepTypes = [...new Set(refs.filter((r) => r.type !== "subflow").map((r) => r.type))];
        const subflows = [
            ...new Set(refs.filter((r) => r.type === "subflow" && typeof r.config["workflow"] === "string").map((r) => r.config["workflow"])),
        ];
        const inputs = [];
        if (stepTypes.length) {
            const rows = await this.backend.bolt.run(`MATCH (s:StrutStep {namespace: $ns}) WHERE s.step_type IN $types AND ${NOT_DELETED("s")} RETURN s.ref_id AS ref_id`, { ns: this.ns, types: stepTypes });
            for (const r of rows)
                inputs.push({ edge: "USES_STEP", source_ref_id: versionRef, target_ref_id: r["ref_id"] });
        }
        if (subflows.length) {
            const rows = await this.backend.bolt.run(`MATCH (w:StrutWorkflow {namespace: $ns}) WHERE w.name IN $names AND ${NOT_DELETED("w")} RETURN w.ref_id AS ref_id`, { ns: this.ns, names: subflows });
            for (const r of rows)
                inputs.push({ edge: "DEPENDS_ON", source_ref_id: versionRef, target_ref_id: r["ref_id"] });
        }
        if (inputs.length)
            await this.backend.edges.writeMany(inputs);
    }
    async publishWorkflowByContent(name, yamlStr, description, category, publisher, opts) {
        const hash = contentHash(yamlStr);
        const w = await this.workflowRow(name);
        if (w) {
            if (category !== undefined && (w.category ?? undefined) !== category) {
                await this.setWorkflowCategory(name, category);
            }
            const match = (await this.versionRows(name)).find((v) => v.content_hash === hash);
            if (match) {
                if (w.active_version === hash || opts?.reactivateKnown === false) {
                    return { version: match.version_label, changed: false };
                }
                await this.setActiveVersion(name, match.version_label);
                return { version: match.version_label, changed: true };
            }
        }
        const next = nextVersionLabel((await this.versionRows(name)).map((v) => v.version_label));
        assertValidWorkflowYaml(yamlStr);
        await this.writeVersion(name, next, yamlStr, description, category, publisher);
        return { version: next, changed: true };
    }
    async setWorkflowCategory(name, category) {
        const w = await this.workflowRow(name);
        if (!w)
            throw new Error(`Workflow "${name}" not found`);
        const patch = patchFor(w, { category: category || undefined });
        if (patch)
            await this.backend.nodes.update(w.ref_id, patch);
    }
    async setActiveVersion(name, version) {
        const w = await this.workflowRow(name);
        if (!w)
            throw new Error(`Workflow "${name}" not found`);
        const versions = await this.versionRows(name);
        const v = versions.find((x) => x.version_label === version);
        if (!v) {
            throw new Error(`Version "${version}" not found for workflow "${name}". Available: ${versions.map((x) => x.version_label).join(", ")}`);
        }
        await this.activate(name, { ref_id: v.ref_id, hash: v.content_hash, description: v.description });
    }
    async setParam(name, param, value) {
        const active = await this.activeVersion(name);
        const obj = yaml.load(active.source) ?? {};
        if (!obj["name"])
            obj["name"] = name;
        const params = obj["params"] && typeof obj["params"] === "object" ? obj["params"] : {};
        const before = params[param];
        params[param] = value;
        obj["params"] = params;
        const yamlStr = yaml.dump(obj, { lineWidth: 120, noRefs: true });
        const next = nextVersionLabel((await this.versionRows(name)).map((v) => v.version_label));
        await this.publishWorkflow(name, next, yamlStr);
        return { version: next, before, after: value };
    }
    // ── Reads: steps ───────────────────────────────────────────────────────
    async stepRow(type) {
        const rows = await this.backend.bolt.run(`MATCH (s:StrutStep {namespace: $ns, step_type: $type}) WHERE ${NOT_DELETED("s")} RETURN properties(s) AS p LIMIT 1`, { ns: this.ns, type });
        return rows.length ? rows[0]["p"] : null;
    }
    async stepVersionRows(type) {
        const rows = await this.backend.bolt.run(`MATCH (v:StrutStepVersion {namespace: $ns, step_type: $type}) WHERE ${NOT_DELETED("v")}
       RETURN properties(v) AS p ORDER BY v.created_at, v.date_added_to_graph`, { ns: this.ns, type });
        return rows.map((r) => r["p"]);
    }
    /** Every visible step with its active version's row (null when the
     *  pointer dangles). Helpers (`_`-prefixed segments) included. */
    async stepsWithActive() {
        const rows = await this.backend.bolt.run(`MATCH (s:StrutStep {namespace: $ns}) WHERE ${NOT_DELETED("s")}
       OPTIONAL MATCH (v:StrutStepVersion {namespace: $ns, step_type: s.step_type, content_hash: s.active_version})
       WHERE ${NOT_DELETED("v")}
       RETURN properties(s) AS s, properties(v) AS v ORDER BY s.step_type`, { ns: this.ns });
        return rows.map((r) => ({ step: r["s"], active: r["v"] ?? null }));
    }
    static isHelper(type) {
        return type.split("/").some((seg) => seg.startsWith("_"));
    }
    async listSteps(filter) {
        const out = [];
        for (const { step, active } of await this.stepsWithActive()) {
            if (Neo4jWorkspaceStore.isHelper(step.step_type))
                continue;
            if (filter?.publisher && step.publisher !== filter.publisher)
                continue;
            out.push({
                type: step.step_type,
                description: active?.description,
                createdAt: active ? isoFromSeconds(active.created_at) : undefined,
                publisher: step.publisher,
            });
        }
        return out;
    }
    async listStepVersions(name) {
        validateStepName(name);
        const s = await this.stepRow(name);
        if (!s)
            throw new Error(`Step "${name}" not found`);
        const versions = await this.stepVersionRows(name);
        return {
            active: versions.find((v) => v.content_hash === s.active_version)?.version_label ?? "",
            versions: versions.map((v) => v.version_label),
        };
    }
    async getStepVersionSource(name, version) {
        validateStepName(name);
        const v = (await this.stepVersionRows(name)).find((x) => x.version_label === version);
        if (!v)
            throw new Error(`Version "${version}" of step "${name}" not found`);
        return v.source;
    }
    // ── Writes: steps ──────────────────────────────────────────────────────
    async publishStep(name, code, description, publisher, opts) {
        validateStepName(name);
        const hash = contentHash(code);
        const { nodes } = this.backend;
        const existing = await this.stepRow(name);
        const versions = existing ? await this.stepVersionRows(name) : [];
        if (existing) {
            const match = versions.find((v) => v.content_hash === hash);
            if (match) {
                let changed = false;
                const desired = {};
                if (existing.active_version !== hash && opts?.reactivateKnown !== false) {
                    desired["active_version"] = hash;
                    desired["description"] = match.description;
                    changed = true;
                }
                if (publisher !== undefined && existing.publisher !== publisher)
                    desired["publisher"] = publisher;
                const patch = patchFor(existing, desired);
                if (patch)
                    await nodes.update(existing.ref_id, patch);
                if (changed)
                    await this.swapActiveStepEdge(existing.ref_id, match.ref_id);
                return { version: match.version_label, changed };
            }
        }
        const vid = nextVersionLabel(versions.map((v) => v.version_label));
        const v = await nodes.write({
            type: "StrutStepVersion",
            data: compact({
                step_type: name,
                content_hash: hash,
                version_label: vid,
                description,
                created_at: new Date().toISOString(),
                source: code,
                publisher: publisher ?? existing?.publisher,
            }),
        });
        let stepRef;
        if (!existing) {
            const s = await nodes.write({
                type: "StrutStep",
                data: compact({ step_type: name, description, publisher, active_version: hash }),
            });
            stepRef = s.ref_id;
        }
        else {
            stepRef = existing.ref_id;
            const desired = { active_version: hash, description };
            if (publisher !== undefined)
                desired["publisher"] = publisher;
            const patch = patchFor(existing, desired);
            if (patch)
                await nodes.update(stepRef, patch);
        }
        await this.backend.edges.write({ edge: "VERSION_OF", source_ref_id: v.ref_id, target_ref_id: stepRef });
        await this.swapActiveStepEdge(stepRef, v.ref_id);
        return { version: vid, changed: true };
    }
    async swapActiveStepEdge(stepRef, versionRef) {
        await this.backend.bolt.run(`MATCH (s:StrutStep {ref_id: $s})-[r:ACTIVE_VERSION]->(v) WHERE v.ref_id <> $v DELETE r`, { s: stepRef, v: versionRef });
        await this.backend.edges.write({ edge: "ACTIVE_VERSION", source_ref_id: stepRef, target_ref_id: versionRef });
    }
    async setActiveStepVersion(name, version) {
        validateStepName(name);
        const s = await this.stepRow(name);
        if (!s)
            throw new Error(`Step "${name}" not found`);
        const versions = await this.stepVersionRows(name);
        const v = versions.find((x) => x.version_label === version);
        if (!v) {
            throw new Error(`Version "${version}" not found for step "${name}". Available: ${versions.map((x) => x.version_label).join(", ")}`);
        }
        const patch = patchFor(s, { active_version: v.content_hash, description: v.description });
        if (patch)
            await this.backend.nodes.update(s.ref_id, patch);
        await this.swapActiveStepEdge(s.ref_id, v.ref_id);
    }
    async deleteStep(name) {
        validateStepName(name);
        const s = await this.stepRow(name);
        if (!s)
            return false;
        for (const v of await this.stepVersionRows(name))
            await this.backend.nodes.softDelete(v.ref_id);
        await this.backend.nodes.softDelete(s.ref_id);
        return true;
    }
    async deleteStepsByPublisher(publisher) {
        const names = (await this.stepsWithActive())
            .filter(({ step }) => step.publisher === publisher)
            .map(({ step }) => step.step_type);
        for (const n of names)
            await this.deleteStep(n);
        return names;
    }
    // ── Step source + code loading ─────────────────────────────────────────
    async getStepSource(type) {
        const s = await this.stepRow(type);
        if (s) {
            const v = (await this.stepVersionRows(type)).find((x) => x.content_hash === s.active_version);
            if (v)
                return { code: v.source, origin: "custom" };
        }
        // Core + lib ship with the engine; a non-existent custom dir keeps the
        // disk reader from ever serving a stale materialized file as "custom".
        return readStepSourceFromDisk(type, join(this.materializeDir, ".none"));
    }
    /**
     * Write every active custom step (helpers included) to the scratch dir as
     * `<name>.ts`, skipping unchanged files and deleting files for steps that
     * are no longer in the graph, so the loader never imports a stale step.
     * Cheap to call on every registry rebuild.
     */
    async materializeCustomSteps() {
        const dir = this.materializeDir;
        await mkdir(dir, { recursive: true });
        await ensureEsmScope(dir);
        const wanted = new Map();
        for (const { step, active } of await this.stepsWithActive()) {
            if (active)
                wanted.set(join(dir, `${step.step_type}.ts`), active.source);
        }
        for (const [file, code] of wanted) {
            let current = null;
            try {
                current = await readFile(file, "utf-8");
            }
            catch {
                // absent
            }
            if (current !== code) {
                await mkdir(dirname(file), { recursive: true });
                await writeFile(file, code, "utf-8");
            }
        }
        for (const file of await walkTs(dir)) {
            if (!wanted.has(file))
                await rm(file, { force: true });
        }
        return dir;
    }
}
async function walkTs(dir) {
    let entries;
    try {
        entries = await readdir(dir, { withFileTypes: true });
    }
    catch {
        return [];
    }
    const out = [];
    for (const e of entries) {
        const full = join(dir, e.name);
        if (e.isDirectory())
            out.push(...(await walkTs(full)));
        else if (e.isFile() && e.name.endsWith(".ts"))
            out.push(full);
    }
    return out;
}
//# sourceMappingURL=workspace-store.js.map