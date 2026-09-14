import type { Flow } from "./core.js";
import type { SubflowResolver } from "./runner.js";
import { type StepSource } from "./steps/registry.js";
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
export declare function assertValidWorkflowYaml(yamlStr: string): void;
/** Parse a stored workflow version's YAML into a runnable `Flow` — the one
 *  loader every `WorkspaceStore` backend shares (param self-references are
 *  resolved once here, at load). */
export declare function flowFromYaml(name: string, version: string, raw: string): Flow;
/** Render publish content (a steps object or raw YAML) to the YAML string
 *  that gets stored — shared by every backend so hashes agree. */
export declare function renderWorkflowYaml(name: string, content: {
    steps: any[];
    params?: Record<string, unknown>;
    promotes?: unknown[];
} | string): string;
export interface WorkflowVersionInfo {
    createdAt: string;
    description?: string;
    /** Content hash of this version's source — internal dedup key for
     *  content-hash publishing. Not the user-facing version id. */
    hash?: string;
}
export interface WorkflowMetadata {
    active: string;
    versions: Record<string, WorkflowVersionInfo>;
    /** Optional grouping label (e.g. an experiment name). Workflow-level, not
     *  version-level: it survives publishes and can be changed at any time via
     *  `setWorkflowCategory`. */
    category?: string;
    /** Optional identifier of the service that published this workflow
     *  (parallels `StepInfo.publisher`). Workflow-level provenance: the
     *  authoring capability stamps everything it publishes `"ai"` and its
     *  publish/run/run-history operations are closed over that stamped set —
     *  see `authoring.ts` and EVOLVE_SPEC §6 (run-history scoping). */
    publisher?: string;
}
export interface StepVersionInfo {
    createdAt: string;
    description?: string;
    /** Content hash of this version's source — internal dedup key. */
    hash?: string;
}
export interface StepInfo {
    /** Active version id (a content hash, e.g. "c-1a2b3c4d5e"). The active
     *  version's source is materialized at `custom/<name>.ts` for the registry
     *  loader; every version (incl. active) is archived under
     *  `steps/_history/<name>/<vid>.ts`. */
    active: string;
    /** All known versions, keyed by content-hash version id. */
    versions: Record<string, StepVersionInfo>;
    /** Optional identifier of the service that published this step.
     *  Used by `deleteStepsByPublisher` for bulk lifecycle ops. */
    publisher?: string;
}
export interface StepDirMetadata {
    /** Keys are full step names with optional slashes (e.g. "gitree/save-feature"). */
    steps: Record<string, StepInfo>;
}
/** Options for the content-hash publishers (`publishWorkflowByContent`,
 *  `publishStep`). */
export interface PublishByContentOptions {
    /** What to do when the content matches an OLDER, non-active version.
     *  `true` (default) re-points active at it — "this exact content should be
     *  live" (the author's intent). `false` leaves the active pointer alone —
     *  the boot-time seeder's setting, so an edit made through the UI/API
     *  survives every reseed until the committed template itself changes (a
     *  never-seen hash still publishes the next `vN` and activates it). */
    reactivateKnown?: boolean;
}
export interface StepVersionsResult {
    active: string;
    versions: string[];
}
export interface WorkflowListEntry {
    name: string;
    activeVersion: string;
    versions: string[];
    description?: string;
    /** Grouping label, if the workflow has one (see WorkflowMetadata.category). */
    category?: string;
    /** Provenance stamp, if any (see WorkflowMetadata.publisher). */
    publisher?: string;
    /** Start time (epoch ms) of the most recent run, if any. Not produced by
     *  the workspace itself (runs are the run store's records) — the server's
     *  `GET /workflows` decorates entries from `RunStore.lastRunAt`. */
    lastRunAt?: number;
}
export interface StepListEntry {
    type: string;
    description?: string;
    createdAt?: string;
    publisher?: string;
}
/**
 * The persistence boundary for workflows and steps — everything the server,
 * the authoring capability, and the chat builder need from "the workspace",
 * with no filesystem in the contract. `FileWorkspaceStore` is the default
 * implementation; a graph-backed one implements the same surface.
 *
 * Two things a workspace deliberately does NOT own: run records (the
 * `RunStore`) and local scratch (artifacts, cassettes, shell cwd — the
 * server's `dataDir`). Custom steps are executable code, so the boundary
 * exposes them two ways: as source text (`getStepSource`) and as an
 * importable directory (`materializeCustomSteps`) for the module loader.
 */
export interface WorkspaceStore extends SubflowResolver {
    /** Every workflow with its version list. `lastRunAt` is NOT populated
     *  here (runs belong to the run store — the server composes it). */
    listWorkflows(): Promise<WorkflowListEntry[]>;
    getWorkflow(name: string): Promise<Flow>;
    getWorkflowVersion(name: string, version: string): Promise<Flow>;
    /** Raw YAML source of a workflow version (throws when missing). */
    getWorkflowSource(name: string, version: string): Promise<string>;
    /** Content hash of a version's source (active when omitted), or null. */
    getWorkflowHash(name: string, version?: string): Promise<string | null>;
    /** The workflow's metadata record (active version, versions, category,
     *  publisher), or null when the workflow doesn't exist. */
    getWorkflowMetadata(name: string): Promise<WorkflowMetadata | null>;
    createWorkflow(name: string, content: {
        steps: any[];
        params?: Record<string, unknown>;
    } | string, description?: string, category?: string, publisher?: string): Promise<{
        name: string;
        version: string;
    }>;
    publishWorkflow(name: string, version: string, content: {
        steps: any[];
        params?: Record<string, unknown>;
        promotes?: unknown[];
    } | string, description?: string, category?: string, publisher?: string): Promise<void>;
    publishWorkflowByContent(name: string, yamlStr: string, description?: string, category?: string, publisher?: string, opts?: PublishByContentOptions): Promise<{
        version: string;
        changed: boolean;
    }>;
    setWorkflowCategory(name: string, category: string | null): Promise<void>;
    setActiveVersion(name: string, version: string): Promise<void>;
    setParam(name: string, param: string, value: unknown): Promise<{
        version: string;
        before: unknown;
        after: unknown;
    }>;
    listSteps(filter?: {
        publisher?: string;
    }): Promise<StepListEntry[]>;
    publishStep(name: string, code: string, description?: string, publisher?: string, opts?: PublishByContentOptions): Promise<{
        version: string;
        changed: boolean;
    }>;
    listStepVersions(name: string): Promise<StepVersionsResult>;
    getStepVersionSource(name: string, version: string): Promise<string>;
    setActiveStepVersion(name: string, version: string): Promise<void>;
    deleteStep(name: string): Promise<boolean>;
    deleteStepsByPublisher(publisher: string): Promise<string[]>;
    /** A step's source text across all tiers (core / lib ship with the
     *  engine; custom is this store's), or null when none is on record. */
    getStepSource(type: string): Promise<{
        code: string;
        origin: StepSource;
    } | null>;
    /** Ensure every ACTIVE custom step exists as an importable file and
     *  return the directory root — what `buildRegistry(customDir)` loads. A
     *  file-backed store already has it; other backends write to scratch. */
    materializeCustomSteps(): Promise<string>;
}
export declare class FileWorkspaceStore implements WorkspaceStore {
    private root;
    constructor(root?: string);
    /** The filesystem root — an implementation detail of THIS store, not part
     *  of `WorkspaceStore`. The server's local scratch (`dataDir`) defaults to
     *  it so file-backed deployments keep one directory. */
    get path(): string;
    listWorkflows(): Promise<WorkflowListEntry[]>;
    getWorkflowMetadata(name: string): Promise<WorkflowMetadata | null>;
    /** Load the active version of a workflow. */
    getWorkflow(name: string): Promise<Flow>;
    /** Load a specific version of a workflow. */
    getWorkflowVersion(name: string, version: string): Promise<Flow>;
    /** Get the raw YAML source for a workflow version. */
    getWorkflowSource(name: string, version: string): Promise<string>;
    /** Content hash of a workflow version's source (active version when
     *  omitted) — recorded on `run.start` so resume can refuse to replay a
     *  journal into a different DAG (RUN_CONTROL_SPEC §5). Null when the
     *  workflow/version is unknown: hash recording degrades gracefully for
     *  runs launched from a bare Flow object. */
    getWorkflowHash(name: string, version?: string): Promise<string | null>;
    private loadFlowYaml;
    /**
     * Create a brand-new workflow at v1. If `<workspace>/workflows/<name>/`
     * already exists, a numeric suffix is appended (`<name>-2`, `<name>-3`, ...)
     * until a free slot is found. Returns the actual name written.
     *
     * Use this for "create" intents (UI's Create Workflow dialog, AI's
     * `create_workflow` tool). For adding a new version to an existing workflow,
     * call `publishWorkflow` directly with the existing name and the next version.
     */
    createWorkflow(name: string, content: {
        steps: any[];
        params?: Record<string, unknown>;
    } | string, description?: string, category?: string, publisher?: string): Promise<{
        name: string;
        version: string;
    }>;
    /** Publish a new workflow version. Accepts steps array or raw YAML string.
     *  `category` (when provided) updates the workflow-level grouping label;
     *  `publisher` (when provided) sets the workflow-level provenance stamp. */
    publishWorkflow(name: string, version: string, content: {
        steps: any[];
        params?: Record<string, unknown>;
        promotes?: unknown[];
    } | string, description?: string, category?: string, publisher?: string): Promise<void>;
    /**
     * Set (or clear, with null/"") a workflow's grouping category. Metadata-only:
     * no new version is published and the YAML content is untouched.
     */
    setWorkflowCategory(name: string, category: string | null): Promise<void>;
    setActiveVersion(name: string, version: string): Promise<void>;
    /**
     * GENERIC promote primitive: set ONE `param` default on a workflow and
     * publish it as the next sequential version (`vN+1`). Reads the active
     * version's raw YAML and round-trips the WHOLE object (so `steps`, other
     * `params`, and any `promotes` block survive), overwriting only
     * `params[param]`. Returns the new version id plus the `before`/`after`
     * values (the diff surface). This is what "promote a winner" calls once a
     * human approves — nothing here is automatic.
     */
    setParam(name: string, param: string, value: unknown): Promise<{
        version: string;
        before: unknown;
        after: unknown;
    }>;
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
    publishWorkflowByContent(name: string, yamlStr: string, description?: string, category?: string, publisher?: string, opts?: PublishByContentOptions): Promise<{
        version: string;
        changed: boolean;
    }>;
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
    listSteps(filter?: {
        publisher?: string;
    }): Promise<StepListEntry[]>;
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
    publishStep(name: string, code: string, description?: string, publisher?: string, opts?: PublishByContentOptions): Promise<{
        version: string;
        changed: boolean;
    }>;
    /** Absolute path to an archived step version source file. */
    private stepVersionPath;
    private writeStepMetadata;
    /** List a step's versions and its active version id. */
    listStepVersions(name: string): Promise<StepVersionsResult>;
    /** Get the archived source for a specific step version. */
    getStepVersionSource(name: string, version: string): Promise<string>;
    /**
     * Switch a step's active version. Copies the archived version's source
     * into the flat `custom/<name>.ts` the registry loads, and updates the
     * active pointer in metadata.
     */
    setActiveStepVersion(name: string, version: string): Promise<void>;
    /**
     * Delete a single custom step by name. Removes the source file, its
     * version archive, and its metadata entry, then cleans up any empty parent
     * directories within `steps/custom/` so namespace directories disappear
     * once their last step is removed.
     *
     * No-ops silently if the step does not exist.
     */
    deleteStep(name: string): Promise<boolean>;
    /**
     * Bulk delete all custom steps published by `publisher`. Returns the list
     * of step names that were removed. Useful for service shutdown:
     * `await ws.deleteStepsByPublisher("mcp-gitree")` on SIGTERM tears down
     * everything a service registered in one call.
     */
    deleteStepsByPublisher(publisher: string): Promise<string[]>;
    getStepSource(type: string): Promise<{
        code: string;
        origin: StepSource;
    } | null>;
    /** Publishing already writes each active custom step to
     *  `<root>/steps/custom/<name>.ts`, so the store IS the materialization. */
    materializeCustomSteps(): Promise<string>;
    private customStepsDir;
    private readWorkflowMetadata;
    private readStepMetadata;
}
/** Back-compat name for `FileWorkspaceStore` (embedders and docs). */
export { FileWorkspaceStore as WorkspaceManager };
/**
 * Validate a custom step name. Allows nested names with slashes
 * (e.g. `gitree/save-feature`) and helper names with leading underscores
 * (e.g. `gitree/_shared`). Rejects path traversal and absolute paths.
 */
export declare function validateStepName(name: string): void;
/**
 * Custom step files are ESM (`import { defineStep } from "strut"`). Node and
 * tsx decide a `.ts` file's format from the nearest package.json, and a
 * workspace outside the strut package tree has none — tsx then falls back to
 * CommonJS and `require("strut")` bypasses the ESM resolve hook that makes
 * the bare specifier work (strut-resolve-hook.ts). A one-line package.json
 * beside the steps pins the format wherever the workspace lives.
 */
export declare function ensureEsmScope(dir: string): Promise<void>;
