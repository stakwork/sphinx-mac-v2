import type { RunEvent, RunResult, RunSummary, StepRegistry } from "./core.js";
import type { WorkspaceStore } from "./workspace.js";
import type { RunStore } from "./store.js";
import { type RunStepResult } from "./run-step.js";
import type { CassetteMode } from "./cassette.js";
import type { SecretInfo } from "./secret-store.js";
import { type ValidationResult } from "./validate.js";
/**
 * The AUTHORING core — the workspace's author/test/inspect operations, shared
 * by two consumers:
 *
 *   - the chat builder's AI tools (`ai/tools.ts`) — the human-supervised
 *     authoring surface; and
 *   - the `meta/*` lib steps — the same operations as REGISTRY STEPS, so an
 *     in-workflow agent (`agentTools: ["meta/*"]`) can author, test, and
 *     inspect candidate workflows from inside a run (EVOLVE_SPEC §5).
 *
 * The exported helpers are the shared MECHANISM (conflict checks, strict
 * load-verification, run-history reads). `buildAuthoringCapability` bakes in
 * the meta-surface POLICY on top (EVOLVE_SPEC §6): everything the capability
 * publishes is stamped `publisher: "ai"`, and its publish / run /
 * run-history operations are CLOSED over that stamped set — it refuses to
 * touch, run, or read runs of workflows it didn't publish. A harness
 * workflow's run log records what its grader steps were handed, so
 * run-history reads on unstamped workflows fail closed.
 */
/** The provenance stamp for AI-authored artifacts (steps AND workflows). */
export declare const AI_PUBLISHER = "ai";
/** Drop bulky input/output payloads from an event so a run's event list stays
 *  token-cheap; the caller can re-fetch a specific run's full events if needed. */
export declare function slimEvent(e: RunEvent): {
    error?: {
        message: string;
        stack?: string;
    } | undefined;
    iteration?: number | undefined;
    durationMs?: number | undefined;
    stepType?: string | undefined;
    type: import("./core.js").RunEventType;
    path: string;
};
/** List a workflow's recent runs (newest first) as slim summaries. */
export declare function listRunSummaries(store: Pick<RunStore, "listRuns" | "getRunSummary" | "getRunEvents">, name: string, limit: number): Promise<{
    error?: {
        message: string;
        stack?: string;
    } | undefined;
    runId: string;
    status: "error" | "success" | "cancelled" | undefined;
    startedAt: string | undefined;
    durationMs: number | undefined;
}[]>;
/** Read one run's summary + events (slimmed unless `fullEvents`). */
export declare function readRun(store: Pick<RunStore, "listRuns" | "getRunSummary" | "getRunEvents">, name: string, runId: string, fullEvents: boolean): Promise<{
    error: string;
    workflow?: undefined;
    runId?: undefined;
    summary?: undefined;
    events?: undefined;
} | {
    workflow: string;
    runId: string;
    summary: RunSummary | null;
    events: {
        error?: {
            message: string;
            stack?: string;
        } | undefined;
        iteration?: number | undefined;
        durationMs?: number | undefined;
        stepType?: string | undefined;
        type: import("./core.js").RunEventType;
        path: string;
    }[];
    error?: undefined;
}>;
export interface RunSearchOptions {
    /** Explicit run ids to search (e.g. one eval batch). Default: newest `runLimit` runs. */
    runIds?: string[];
    /** How many recent runs to scan when `runIds` is absent. Default 20. */
    runLimit?: number;
    /** Cap on returned match entries; scanning stops once reached. Default 50. */
    maxMatches?: number;
    /** Case-insensitive matching. Default true (signature hunting favors recall). */
    ignoreCase?: boolean;
}
/** One matching event from a run search. */
export interface RunSearchMatch {
    runId: string;
    path: string;
    type: string;
    stepType?: string;
    /** Matches within this one event (the snippet shows the first). */
    count: number;
    /** The matched text with surrounding context from the event's JSON. */
    snippet: string;
}
/**
 * Grep across a workflow's run event logs — the cross-run question the
 * per-run `readRun` can't answer without N calls and N payloads ("which runs
 * hit `ModuleNotFoundError`, and how often?" — EVOLVE_SPEC §4.2 capture).
 * Each event is matched as its JSON line (the same shape events.jsonl holds),
 * so input/output/error payloads are all searchable; matches come back as
 * (runId, event path, snippet) tuples plus a per-run frequency summary.
 * Scanning stops at `maxMatches` (`truncated: true`) — narrow the pattern or
 * the run window rather than raising the cap.
 */
export declare function searchRunEvents(store: Pick<RunStore, "listRuns" | "getRunSummary" | "getRunEvents">, name: string, pattern: string, opts?: RunSearchOptions): Promise<{
    error: string;
} | {
    truncated?: boolean | undefined;
    note?: string | undefined;
    workflow: string;
    pattern: string;
    runsScanned: number;
    runsWithMatches: {
        runId: string;
        matchingEvents: number;
    }[];
    matches: RunSearchMatch[];
    error?: undefined;
}>;
/** LLMs sometimes pass an object-valued arg as a JSON *string* (e.g.
 *  run_workflow's `input`). The template engine then sees a string, so
 *  `{{ input.owner }}` resolves to undefined and every field fails validation.
 *  Defensively parse a JSON string back into the object/array it represents;
 *  leave anything else untouched. */
export declare function coerceJsonArg(v: unknown): unknown;
/** What both publish paths need. The chat builder's `AiDeps` satisfies it
 *  structurally; the authoring capability builds its own. `getRegistry` must
 *  return a FRESH registry (re-scanned from the workspace). */
export interface StepPublishDeps {
    workspace: WorkspaceStore;
    getRegistry(): Promise<StepRegistry>;
    publishingEnabled?: boolean;
}
export interface StepPublishResult {
    ok?: true;
    error?: string;
    type?: string;
    version?: string;
    changed?: boolean;
    /** Whether the published source actually loaded into the registry. */
    loaded?: boolean;
    /** The import/shape error when `loaded` is false (§5.3.4: a broken step
     *  otherwise fails silently — `loadStepFile` warns and returns null, so the
     *  step simply doesn't exist). */
    loadError?: string;
}
/** Author a NEW custom step (the chat `create_step` / `meta/create-step`
 *  mechanism): refuses existing names and built-in collisions, publishes as
 *  v1, then load-verifies the source and hands any import error back. */
export declare function publishNewStep(deps: StepPublishDeps, name: string, code: string, description?: string, publisher?: string): Promise<StepPublishResult>;
/** Publish a NEW VERSION of an existing custom step (the chat `edit_step` /
 *  `meta/edit-step` mechanism). Pass `requirePublisher` to enforce the meta
 *  ownership rule: only steps stamped with that publisher may be edited. */
export declare function publishStepVersion(deps: StepPublishDeps, type: string, code: string, description?: string, opts?: {
    requirePublisher?: string;
}): Promise<StepPublishResult>;
export interface RunStepArgs {
    config?: Record<string, unknown>;
    input?: unknown;
    params?: Record<string, unknown>;
    cassette?: CassetteMode;
    cassetteName?: string;
}
/**
 * The authoring capability injected as `services.authoring` — what the
 * `meta/*` lib steps are thin plumbing over. Auto-provided by `createStrut`
 * (like `http` / `secrets` / `artifacts`); embedders can inject their own.
 */
export interface AuthoringCapability {
    listSteps(path?: string): Promise<unknown>;
    searchSteps(query: string): Promise<unknown>;
    getStep(type: string): Promise<unknown>;
    createStep(name: string, code: string, description?: string): Promise<StepPublishResult>;
    editStep(type: string, code: string, description?: string): Promise<StepPublishResult>;
    runStep(type: string, args?: RunStepArgs): Promise<RunStepResult | {
        error: string;
    }>;
    listWorkflows(): Promise<unknown>;
    getWorkflow(name: string, version?: string): Promise<unknown>;
    /** Static check of workflow YAML WITHOUT publishing — the chat builder's
     *  `validate_workflow`, for in-run authors (`meta/validate-workflow`). */
    validateWorkflow(yaml: string, name?: string): Promise<ValidationResult>;
    publishWorkflow(name: string, yaml: string, description?: string, category?: string): Promise<unknown>;
    runWorkflow(name: string, input?: unknown, params?: Record<string, unknown>, version?: string, 
    /** `parentRunId` = the calling step's `ctx.runId`, linking the nested
     *  run's controller under the launching run's (subtree control). */
    opts?: {
        parentRunId?: string;
    }): Promise<RunResult | {
        error: string;
    }>;
    listRuns(name: string, limit?: number): Promise<unknown>;
    getRun(name: string, runId: string, fullEvents?: boolean): Promise<unknown>;
    searchRuns(name: string, pattern: string, opts?: RunSearchOptions): Promise<unknown>;
    listSecrets(): Promise<unknown>;
}
export interface AuthoringDeps extends StepPublishDeps {
    store: RunStore;
    /** Local directory for step cassettes (`runStep` record/replay). Optional:
     *  without it, cassette modes report an error instead of recording. */
    dataDir?: string;
    /** Capabilities bag threaded into `runWorkflow` / `runStep` so authored
     *  steps reach `ctx.services` (http, secrets, and any consumer services). */
    services?: unknown;
    /** Read-only view of the deployment's secret store (NAMES only — never
     *  values). Optional: `listSecrets` degrades gracefully when absent. */
    secrets?: {
        list(): Promise<SecretInfo[]>;
    };
    /** Register a nested run as in-flight, creating its RunController —
     *  attached to the launching run's controller when `parentRunId` is given,
     *  so cancelling/pausing the parent reaches this run (RUN_CONTROL_SPEC
     *  §2.2 tree linkage). Also drives the runs listing ("running" vs
     *  "stale"). Optional: embedders without a live server need not care. */
    trackRun?: (workflow: string, runId: string, parentRunId?: string) => {
        controller?: import("./run-control.js").RunController;
        untrack: () => void;
    };
}
export declare function buildAuthoringCapability(deps: AuthoringDeps): AuthoringCapability;
