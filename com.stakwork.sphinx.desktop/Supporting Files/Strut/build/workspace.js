import { readFile, writeFile, readdir, mkdir, stat, unlink, rmdir, rm } from "node:fs/promises";
import { dirname, join, relative, sep } from "node:path";
import yaml from "js-yaml";
import { z } from "zod";
import { readStepSourceFromDisk } from "./steps/registry.js";
import { contentHash, nextVersionLabel } from "./version.js";
import { evaluateExpr } from "./expr.js";
// Match a `{{ params.<path> }}` reference (and ONLY a params reference) so we can
// resolve param-to-param references at load time without touching `{{ input.* }}`
// or step-output references (which don't exist until run time).
const PARAM_SELF_REF = /\{\{\s*(params(?:\.[\w$]+|\[[^\]]+\])+)\s*\}\}/g;
/**
 * Validate a workflow's YAML before it's published. Catches the single most
 * common authoring footgun: an **unquoted** template value, e.g.
 *
 *   pull_number: {{ input.pull_number }}     # WRONG
 *
 * A leading `{{` is parsed by YAML as a flow-mapping, so the value silently
 * becomes an object (which stringifies to `[object Object]`) instead of the
 * template string. Downstream this surfaces as a baffling "expected number,
 * received object". We detect it on the PARSED structure (so we don't false-
 * positive on `{{ }}` inside block-scalar message bodies) and throw a clear,
 * actionable error pointing at the fix: quote the template.
 */
export function assertValidWorkflowYaml(yamlStr) {
    let parsed;
    try {
        parsed = yaml.load(yamlStr);
    }
    catch (err) {
        throw new Error(`Invalid workflow YAML: ${err instanceof Error ? err.message : String(err)}. ` +
            `A common cause is an unquoted template — always wrap templates in quotes, ` +
            `e.g. pull_number: "{{ input.pull_number }}".`);
    }
    // An unquoted `{{ ... }}` value parses to an object used as a map key, which
    // serializes as the literal "[object Object]". No legitimate config contains
    // that string, so it's a reliable corruption signature.
    if (JSON.stringify(parsed ?? null).includes("[object Object]")) {
        throw new Error(`Workflow YAML has an unquoted template value: a "{{ ... }}" was parsed as a ` +
            `YAML object instead of a string. Wrap every template in quotes, ` +
            `e.g. pull_number: "{{ input.pull_number }}".`);
    }
}
/**
 * Resolve `{{ params.* }}` references that appear INSIDE other param values, so a
 * workflow can factor a shared value into one param and reuse it (e.g. a base
 * `podDomain` referenced by a big prompt param). Walks the params deeply; for
 * each string it substitutes only `params.*` templates (evaluated against the
 * params themselves), leaving every other template intact for run-time
 * resolution. One pass over the ORIGINAL params — chained references aren't
 * re-expanded, and the substitution uses the param DEFAULTS (a per-run override
 * of a referenced param won't retro-edit a value that embedded it). Unknown/erroring
 * refs are left verbatim rather than throwing.
 */
function resolveParamSelfReferences(params) {
    const resolveStr = (s) => s.replace(PARAM_SELF_REF, (whole, expr) => {
        try {
            const val = evaluateExpr(expr, { params });
            if (val === null || val === undefined)
                return "";
            return typeof val === "object" ? JSON.stringify(val) : String(val);
        }
        catch {
            return whole; // leave unresolved on any error
        }
    });
    const walk = (v) => {
        if (typeof v === "string")
            return v.includes("{{") ? resolveStr(v) : v;
        if (Array.isArray(v))
            return v.map(walk);
        if (v && typeof v === "object") {
            const out = {};
            for (const [k, val] of Object.entries(v))
                out[k] = walk(val);
            return out;
        }
        return v;
    };
    return walk(params);
}
/** Parse a stored workflow version's YAML into a runnable `Flow` — the one
 *  loader every `WorkspaceStore` backend shares (param self-references are
 *  resolved once here, at load). */
export function flowFromYaml(name, version, raw) {
    const data = yaml.load(raw);
    if (!data || !data.steps) {
        throw new Error(`Invalid workflow YAML for "${name}" version "${version}"`);
    }
    return {
        name: data.name ?? name,
        input: z.any(),
        steps: data.steps,
        // Resolve param-to-param references (`{{ params.* }}` nested inside another
        // param) once at load, so a shared value can be factored into one knob.
        ...(data.params != null ? { params: resolveParamSelfReferences(data.params) } : {}),
        ...(Array.isArray(data.promotes) ? { promotes: data.promotes } : {}),
    };
}
/** Render publish content (a steps object or raw YAML) to the YAML string
 *  that gets stored — shared by every backend so hashes agree. */
export function renderWorkflowYaml(name, content) {
    return typeof content === "string"
        ? content
        : yaml.dump({
            name,
            steps: content.steps,
            ...(content.params != null ? { params: content.params } : {}),
            ...(content.promotes != null ? { promotes: content.promotes } : {}),
        }, { lineWidth: 120, noRefs: true });
}
// ── Filesystem implementation ──────────────────────────────────────────────
export class FileWorkspaceStore {
    root;
    constructor(root) {
        this.root = root ?? process.env["STRUT_WORKSPACE"] ?? "./workspace";
    }
    /** The filesystem root — an implementation detail of THIS store, not part
     *  of `WorkspaceStore`. The server's local scratch (`dataDir`) defaults to
     *  it so file-backed deployments keep one directory. */
    get path() {
        return this.root;
    }
    // ── Workflows ──────────────────────────────────────────────────────────
    async listWorkflows() {
        const workflowsDir = join(this.root, "workflows");
        const entries = await safeReaddir(workflowsDir);
        const results = [];
        for (const entry of entries) {
            if (!entry.isDirectory())
                continue;
            const meta = await this.readWorkflowMetadata(entry.name);
            if (meta) {
                const activeDesc = meta.versions[meta.active]?.description;
                results.push({
                    name: entry.name,
                    activeVersion: meta.active,
                    versions: Object.keys(meta.versions),
                    description: activeDesc,
                    ...(meta.category ? { category: meta.category } : {}),
                    ...(meta.publisher ? { publisher: meta.publisher } : {}),
                });
            }
        }
        return results;
    }
    async getWorkflowMetadata(name) {
        return this.readWorkflowMetadata(name);
    }
    /** Load the active version of a workflow. */
    async getWorkflow(name) {
        const meta = await this.readWorkflowMetadata(name);
        if (!meta) {
            throw new Error(`Workflow "${name}" not found`);
        }
        return this.loadFlowYaml(name, meta.active);
    }
    /** Load a specific version of a workflow. */
    async getWorkflowVersion(name, version) {
        return this.loadFlowYaml(name, version);
    }
    /** Get the raw YAML source for a workflow version. */
    async getWorkflowSource(name, version) {
        const dir = join(this.root, "workflows", name);
        return readFile(join(dir, `${version}.yaml`), "utf-8");
    }
    /** Content hash of a workflow version's source (active version when
     *  omitted) — recorded on `run.start` so resume can refuse to replay a
     *  journal into a different DAG (RUN_CONTROL_SPEC §5). Null when the
     *  workflow/version is unknown: hash recording degrades gracefully for
     *  runs launched from a bare Flow object. */
    async getWorkflowHash(name, version) {
        try {
            const meta = await this.readWorkflowMetadata(name);
            if (!meta)
                return null;
            const v = version ?? meta.active;
            const recorded = meta.versions[v]?.hash;
            if (recorded)
                return recorded;
            return contentHash(await this.getWorkflowSource(name, v));
        }
        catch {
            return null;
        }
    }
    async loadFlowYaml(name, version) {
        const dir = join(this.root, "workflows", name);
        const raw = await readFile(join(dir, `${version}.yaml`), "utf-8");
        return flowFromYaml(name, version, raw);
    }
    /**
     * Create a brand-new workflow at v1. If `<workspace>/workflows/<name>/`
     * already exists, a numeric suffix is appended (`<name>-2`, `<name>-3`, ...)
     * until a free slot is found. Returns the actual name written.
     *
     * Use this for "create" intents (UI's Create Workflow dialog, AI's
     * `create_workflow` tool). For adding a new version to an existing workflow,
     * call `publishWorkflow` directly with the existing name and the next version.
     */
    async createWorkflow(name, content, description, category, publisher) {
        const workflowsDir = join(this.root, "workflows");
        let finalName = name;
        let n = 2;
        while (await pathExists(join(workflowsDir, finalName))) {
            finalName = `${name}-${n++}`;
        }
        // If the YAML embeds a `name:` field, rewrite it so the on-disk name
        // matches the directory — runner.ts keys run storage off `workflow.name`.
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
    /** Publish a new workflow version. Accepts steps array or raw YAML string.
     *  `category` (when provided) updates the workflow-level grouping label;
     *  `publisher` (when provided) sets the workflow-level provenance stamp. */
    async publishWorkflow(name, version, content, description, category, publisher) {
        const dir = join(this.root, "workflows", name);
        await mkdir(dir, { recursive: true });
        const yamlStr = renderWorkflowYaml(name, content);
        assertValidWorkflowYaml(yamlStr);
        await writeFile(join(dir, `${version}.yaml`), yamlStr, "utf-8");
        // Update metadata
        const meta = (await this.readWorkflowMetadata(name)) ?? {
            active: version,
            versions: {},
        };
        meta.versions[version] = {
            createdAt: new Date().toISOString(),
            description,
            hash: contentHash(yamlStr),
        };
        meta.active = version;
        if (category !== undefined)
            meta.category = category;
        if (publisher !== undefined)
            meta.publisher = publisher;
        await writeFile(join(dir, "_metadata.json"), JSON.stringify(meta, null, 2), "utf-8");
    }
    /**
     * Set (or clear, with null/"") a workflow's grouping category. Metadata-only:
     * no new version is published and the YAML content is untouched.
     */
    async setWorkflowCategory(name, category) {
        const meta = await this.readWorkflowMetadata(name);
        if (!meta)
            throw new Error(`Workflow "${name}" not found`);
        if (category)
            meta.category = category;
        else
            delete meta.category;
        await writeFile(join(this.root, "workflows", name, "_metadata.json"), JSON.stringify(meta, null, 2), "utf-8");
    }
    async setActiveVersion(name, version) {
        const meta = await this.readWorkflowMetadata(name);
        if (!meta) {
            throw new Error(`Workflow "${name}" not found`);
        }
        if (!(version in meta.versions)) {
            throw new Error(`Version "${version}" not found for workflow "${name}". Available: ${Object.keys(meta.versions).join(", ")}`);
        }
        meta.active = version;
        const dir = join(this.root, "workflows", name);
        await writeFile(join(dir, "_metadata.json"), JSON.stringify(meta, null, 2), "utf-8");
    }
    /**
     * GENERIC promote primitive: set ONE `param` default on a workflow and
     * publish it as the next sequential version (`vN+1`). Reads the active
     * version's raw YAML and round-trips the WHOLE object (so `steps`, other
     * `params`, and any `promotes` block survive), overwriting only
     * `params[param]`. Returns the new version id plus the `before`/`after`
     * values (the diff surface). This is what "promote a winner" calls once a
     * human approves — nothing here is automatic.
     */
    async setParam(name, param, value) {
        const meta = await this.readWorkflowMetadata(name);
        if (!meta)
            throw new Error(`Workflow "${name}" not found`);
        const raw = await this.getWorkflowSource(name, meta.active);
        const obj = yaml.load(raw) ?? {};
        if (!obj["name"])
            obj["name"] = name;
        const params = obj["params"] && typeof obj["params"] === "object"
            ? obj["params"]
            : {};
        const before = params[param];
        params[param] = value;
        obj["params"] = params;
        const yamlStr = yaml.dump(obj, { lineWidth: 120, noRefs: true });
        const next = nextVersionLabel(Object.keys(meta.versions));
        await this.publishWorkflow(name, next, yamlStr);
        return { version: next, before, after: value };
    }
    /**
     * Publish a workflow keyed by content hash but labeled with a friendly,
     * sequential version id (`v1`, `v2`, …). The hash is an internal dedup key;
     * the version id is what the UI shows. Idempotent: identical content that's
     * already active is a no-op; identical content of an older version re-points
     * active at it (no new version); changed content publishes the next `vN` and
     * activates it, retaining prior versions. This is the content-hash seeder's
     * primitive. Returns the version id and whether anything changed.
     * `opts.reactivateKnown: false` turns the "re-points active" case into a
     * no-op (see `PublishByContentOptions`).
     */
    async publishWorkflowByContent(name, yamlStr, description, category, publisher, opts) {
        const hash = contentHash(yamlStr);
        const meta = await this.readWorkflowMetadata(name);
        if (meta) {
            // Category is metadata-level, so reconcile it even when the content is
            // a no-op — this is how seeders retrofit categories onto existing
            // workspaces at boot.
            if (category !== undefined && meta.category !== category) {
                await this.setWorkflowCategory(name, category);
            }
            const match = Object.entries(meta.versions).find(([, info]) => info.hash === hash);
            if (match) {
                const [vid] = match;
                if (meta.active === vid || opts?.reactivateKnown === false) {
                    return { version: vid, changed: false };
                }
                await this.setActiveVersion(name, vid);
                return { version: vid, changed: true };
            }
        }
        const next = nextVersionLabel(meta ? Object.keys(meta.versions) : []);
        // `publisher` is only ever applied when a version is actually written —
        // never reconciled on the identical-content no-op path above, so
        // republishing a workflow's existing content verbatim cannot re-stamp
        // (and thereby claim) a workflow someone else published.
        await this.publishWorkflow(name, next, yamlStr, description, category, publisher);
        return { version: next, changed: true };
    }
    // ── Steps ──────────────────────────────────────────────────────────────
    /**
     * List user-authored custom steps from `<workspace>/steps/custom/`,
     * recursively. Files starting with `_` are treated as helpers (importable
     * by sibling steps but not registered as their own step type) and are
     * omitted from the result.
     *
     * Lib steps live in the engine source tree and are not listed here.
     *
     * Pass `filter.publisher` to limit results to a specific publisher.
     */
    async listSteps(filter) {
        const customDir = join(this.root, "steps", "custom");
        const meta = await this.readStepMetadata(customDir);
        const results = [];
        const files = await findStepFilesRecursive(customDir);
        for (const file of files) {
            const stepName = stepNameFromFile(file, customDir);
            const info = meta?.steps[stepName];
            if (filter?.publisher && info?.publisher !== filter.publisher)
                continue;
            const activeVer = info ? info.versions[info.active] : undefined;
            results.push({
                type: stepName,
                description: activeVer?.description,
                createdAt: activeVer?.createdAt,
                publisher: info?.publisher,
            });
        }
        return results;
    }
    /**
     * Publish a custom step, keyed by content hash but labeled with a friendly,
     * sequential version id (`v1`, `v2`, …). Writes the active source to
     * `<workspace>/steps/custom/<name>.ts` (what the registry loads) and
     * archives every version under `steps/_history/<name>/<vid>.ts`.
     *
     * `name` may contain slashes to nest the file under subdirectories
     * (e.g. `"gitree/save-feature"` writes to `custom/gitree/save-feature.ts`).
     * Names starting with `_` (or with any path segment starting with `_`)
     * are treated as helper files: they're saved and importable by sibling
     * steps but are skipped by registry discovery.
     *
     * Idempotent by content hash: republishing identical content that's already
     * active is a no-op; identical content of an older version re-activates it
     * (no new version); changed content publishes the next `vN` and activates it
     * while prior versions are retained for rollback.
     *
     * Returns the version id and whether anything changed.
     *
     * Lib steps cannot be published at runtime — they ship with the engine.
     */
    async publishStep(name, code, description, publisher, opts) {
        validateStepName(name);
        const customDir = join(this.root, "steps", "custom");
        const filePath = join(customDir, `${name}.ts`);
        const hash = contentHash(code);
        const meta = (await this.readStepMetadata(customDir)) ?? { steps: {} };
        const existing = meta.steps[name];
        // Content already known → no-op (if active) or re-activate that version
        // (unless the caller opted out of re-activation).
        if (existing) {
            const match = Object.entries(existing.versions).find(([, info]) => info.hash === hash);
            if (match) {
                const [vid] = match;
                let changed = false;
                if (existing.active !== vid && opts?.reactivateKnown !== false) {
                    const archived = await readFile(this.stepVersionPath(name, vid), "utf-8");
                    await mkdir(dirname(filePath), { recursive: true });
                    await writeFile(filePath, archived, "utf-8");
                    existing.active = vid;
                    changed = true;
                }
                if (publisher !== undefined && existing.publisher !== publisher) {
                    existing.publisher = publisher;
                    await this.writeStepMetadata(customDir, meta);
                }
                else if (changed) {
                    await this.writeStepMetadata(customDir, meta);
                }
                return { version: vid, changed };
            }
        }
        // New content → next sequential version. Materialize active source for the
        // registry loader + archive it.
        const vid = nextVersionLabel(existing ? Object.keys(existing.versions) : []);
        await mkdir(dirname(filePath), { recursive: true });
        await writeFile(filePath, code, "utf-8");
        const archivePath = this.stepVersionPath(name, vid);
        await mkdir(dirname(archivePath), { recursive: true });
        await writeFile(archivePath, code, "utf-8");
        meta.steps[name] = {
            active: vid,
            versions: {
                ...(existing?.versions ?? {}),
                [vid]: {
                    createdAt: new Date().toISOString(),
                    hash,
                    ...(description !== undefined ? { description } : {}),
                },
            },
            ...(publisher !== undefined
                ? { publisher }
                : existing?.publisher !== undefined
                    ? { publisher: existing.publisher }
                    : {}),
        };
        await this.writeStepMetadata(customDir, meta);
        return { version: vid, changed: true };
    }
    /** Absolute path to an archived step version source file. */
    stepVersionPath(name, version) {
        return join(this.root, "steps", "_history", name, `${version}.ts`);
    }
    async writeStepMetadata(customDir, meta) {
        await writeFile(join(customDir, "_metadata.json"), JSON.stringify(meta, null, 2), "utf-8");
    }
    /** List a step's versions and its active version id. */
    async listStepVersions(name) {
        validateStepName(name);
        const customDir = join(this.root, "steps", "custom");
        const meta = await this.readStepMetadata(customDir);
        const info = meta?.steps[name];
        if (!info)
            throw new Error(`Step "${name}" not found`);
        return { active: info.active, versions: Object.keys(info.versions) };
    }
    /** Get the archived source for a specific step version. */
    async getStepVersionSource(name, version) {
        validateStepName(name);
        return readFile(this.stepVersionPath(name, version), "utf-8");
    }
    /**
     * Switch a step's active version. Copies the archived version's source
     * into the flat `custom/<name>.ts` the registry loads, and updates the
     * active pointer in metadata.
     */
    async setActiveStepVersion(name, version) {
        validateStepName(name);
        const customDir = join(this.root, "steps", "custom");
        const meta = await this.readStepMetadata(customDir);
        const info = meta?.steps[name];
        if (!meta || !info)
            throw new Error(`Step "${name}" not found`);
        if (!(version in info.versions)) {
            throw new Error(`Version "${version}" not found for step "${name}". Available: ${Object.keys(info.versions).join(", ")}`);
        }
        const code = await readFile(this.stepVersionPath(name, version), "utf-8");
        const filePath = join(customDir, `${name}.ts`);
        await mkdir(dirname(filePath), { recursive: true });
        await writeFile(filePath, code, "utf-8");
        info.active = version;
        await this.writeStepMetadata(customDir, meta);
    }
    /**
     * Delete a single custom step by name. Removes the source file, its
     * version archive, and its metadata entry, then cleans up any empty parent
     * directories within `steps/custom/` so namespace directories disappear
     * once their last step is removed.
     *
     * No-ops silently if the step does not exist.
     */
    async deleteStep(name) {
        validateStepName(name);
        const customDir = join(this.root, "steps", "custom");
        const filePath = join(customDir, `${name}.ts`);
        let removed = false;
        try {
            await unlink(filePath);
            removed = true;
        }
        catch (err) {
            if (err?.code !== "ENOENT")
                throw err;
        }
        // Remove the version archive dir for this step (best-effort).
        await rm(join(this.root, "steps", "_history", name), {
            recursive: true,
            force: true,
        });
        const meta = await this.readStepMetadata(customDir);
        if (meta && meta.steps[name]) {
            delete meta.steps[name];
            await writeFile(join(customDir, "_metadata.json"), JSON.stringify(meta, null, 2), "utf-8");
            removed = true;
        }
        if (removed) {
            await pruneEmptyDirs(dirname(filePath), customDir);
        }
        return removed;
    }
    /**
     * Bulk delete all custom steps published by `publisher`. Returns the list
     * of step names that were removed. Useful for service shutdown:
     * `await ws.deleteStepsByPublisher("mcp-gitree")` on SIGTERM tears down
     * everything a service registered in one call.
     */
    async deleteStepsByPublisher(publisher) {
        const customDir = join(this.root, "steps", "custom");
        const meta = await this.readStepMetadata(customDir);
        if (!meta)
            return [];
        const toDelete = Object.entries(meta.steps)
            .filter(([, info]) => info.publisher === publisher)
            .map(([name]) => name);
        for (const name of toDelete) {
            await this.deleteStep(name);
        }
        return toDelete;
    }
    // ── Step source + code loading ─────────────────────────────────────────
    async getStepSource(type) {
        return readStepSourceFromDisk(type, this.customStepsDir());
    }
    /** Publishing already writes each active custom step to
     *  `<root>/steps/custom/<name>.ts`, so the store IS the materialization. */
    async materializeCustomSteps() {
        const dir = this.customStepsDir();
        await ensureEsmScope(dir);
        return dir;
    }
    customStepsDir() {
        return join(this.root, "steps", "custom");
    }
    // ── Private helpers ────────────────────────────────────────────────────
    async readWorkflowMetadata(name) {
        try {
            const raw = await readFile(join(this.root, "workflows", name, "_metadata.json"), "utf-8");
            return JSON.parse(raw);
        }
        catch {
            return null;
        }
    }
    async readStepMetadata(dir) {
        try {
            const raw = await readFile(join(dir, "_metadata.json"), "utf-8");
            return JSON.parse(raw);
        }
        catch {
            return null;
        }
    }
}
/** Back-compat name for `FileWorkspaceStore` (embedders and docs). */
export { FileWorkspaceStore as WorkspaceManager };
// ── Utilities ──────────────────────────────────────────────────────────────
async function safeReaddir(dir) {
    try {
        return await readdir(dir, { withFileTypes: true });
    }
    catch {
        return [];
    }
}
async function pathExists(p) {
    try {
        await stat(p);
        return true;
    }
    catch {
        return false;
    }
}
/**
 * Validate a custom step name. Allows nested names with slashes
 * (e.g. `gitree/save-feature`) and helper names with leading underscores
 * (e.g. `gitree/_shared`). Rejects path traversal and absolute paths.
 */
export function validateStepName(name) {
    if (!name) {
        throw new Error("Step name cannot be empty");
    }
    if (name.startsWith("/") || name.includes("\\")) {
        throw new Error(`Invalid step name "${name}": must not contain absolute or back-slash paths`);
    }
    if (name.includes("//") || name.endsWith("/") || name.startsWith("/")) {
        throw new Error(`Invalid step name "${name}": malformed path`);
    }
    const segments = name.split("/");
    for (const seg of segments) {
        if (!seg || seg === "." || seg === "..") {
            throw new Error(`Invalid step name "${name}": path traversal not allowed`);
        }
        if (!/^[a-zA-Z_][a-zA-Z0-9_-]*$/.test(seg)) {
            throw new Error(`Invalid step name "${name}": each segment must match [a-zA-Z_][a-zA-Z0-9_-]*`);
        }
    }
}
/**
 * Recursively find step files (`.ts` / `.js`) under `dir`, skipping helper
 * files (`_*`), hidden files, and test files. Returns absolute paths.
 *
 * This mirrors the registry's discovery rules so `listSteps` shows exactly
 * what the registry will load.
 */
async function findStepFilesRecursive(dir) {
    const results = [];
    let entries;
    try {
        entries = await readdir(dir, { withFileTypes: true });
    }
    catch {
        return results;
    }
    for (const e of entries) {
        const full = join(dir, e.name);
        if (e.isDirectory()) {
            if (e.name.startsWith("_") || e.name.startsWith("."))
                continue;
            const nested = await findStepFilesRecursive(full);
            results.push(...nested);
        }
        else if (e.isFile()) {
            if (e.name.startsWith("_") ||
                e.name.startsWith(".") ||
                !(e.name.endsWith(".ts") || e.name.endsWith(".js")) ||
                e.name.endsWith(".test.ts") ||
                e.name.endsWith(".spec.ts"))
                continue;
            results.push(full);
        }
    }
    return results;
}
/**
 * Convert an absolute file path under `baseDir` to a slash-separated step
 * name (extension stripped). E.g. `<base>/gitree/save-feature.ts` → `"gitree/save-feature"`.
 */
function stepNameFromFile(filePath, baseDir) {
    const rel = relative(baseDir, filePath).replace(/\.(ts|js)$/, "");
    return rel.split(sep).join("/");
}
/**
 * Walk upward from `startDir` removing empty directories, stopping when
 * `stopDir` is reached (inclusive boundary — we never remove `stopDir`).
 * Silently ignores non-empty dirs and any errors.
 */
async function pruneEmptyDirs(startDir, stopDir) {
    let dir = startDir;
    while (dir.startsWith(stopDir) && dir !== stopDir) {
        try {
            await rmdir(dir);
        }
        catch {
            return; // not empty, or doesn't exist
        }
        dir = dirname(dir);
    }
}
/**
 * Custom step files are ESM (`import { defineStep } from "strut"`). Node and
 * tsx decide a `.ts` file's format from the nearest package.json, and a
 * workspace outside the strut package tree has none — tsx then falls back to
 * CommonJS and `require("strut")` bypasses the ESM resolve hook that makes
 * the bare specifier work (strut-resolve-hook.ts). A one-line package.json
 * beside the steps pins the format wherever the workspace lives.
 */
export async function ensureEsmScope(dir) {
    await mkdir(dir, { recursive: true });
    const pkg = join(dir, "package.json");
    try {
        await stat(pkg);
    }
    catch {
        await writeFile(pkg, JSON.stringify({ type: "module" }, null, 2) + "\n", "utf-8");
    }
}
//# sourceMappingURL=workspace.js.map