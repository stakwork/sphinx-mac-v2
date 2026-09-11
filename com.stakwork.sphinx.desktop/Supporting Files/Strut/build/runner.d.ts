import type { Flow, StepRegistry, RunEvent, RunResult } from "./core.js";
import type { RunStore } from "./store.js";
import { RunController } from "./run-control.js";
/**
 * Workspace interface for loading subflows by reference.
 * The real WorkspaceManager satisfies this; tests can stub it.
 */
export interface SubflowResolver {
    getWorkflow(name: string): Promise<Flow>;
    getWorkflowVersion(name: string, version: string): Promise<Flow>;
}
export interface RunOptions<TServices = unknown> {
    runId?: string;
    store?: RunStore;
    /** Called for every event as it happens (for SSE streaming). */
    onEvent?: (event: RunEvent) => void | Promise<void>;
    /** Resolves subflow references to Flow objects. Required if any step uses `subflow`. */
    workspace?: SubflowResolver;
    /** Consumer-defined capabilities bag exposed to every step via
     *  `ctx.services`. Use this to inject environment-specific
     *  implementations (Neo4j vs in-memory store, real vs fake LLM, …)
     *  without changing the workflow or registry. Defaults to `{}`. */
    services?: TServices;
    /** Per-run overrides for the workflow's `params` knobs. Shallow-merged
     *  over `flow.params` defaults, so a trial typically sets just one key
     *  (e.g. `{ systemPrompt: "..." }`). Only applies to the top-level flow;
     *  subflows use their own `params` defaults. Exposed to step configs via
     *  `{{ params.* }}`. */
    params?: Record<string, unknown>;
    /** Per-run overrides keyed by workflow name, applied at EVERY level of the
     *  execution tree (entry flow + nested subflows), unlike `params` which only
     *  reaches the entry flow. Use this to tune a knob that lives in a subflow
     *  (e.g. a prompt in `process-change` invoked two levels down). For each
     *  flow, `paramOverrides[flow.name]` is shallow-merged over that flow's
     *  `params` defaults. Precedence: step `.default()` < flow `params` default
     *  < `paramOverrides[name]` < (entry only) `params`. */
    paramOverrides?: Record<string, Record<string, unknown>>;
    /** Cooperative run control (RUN_CONTROL_SPEC §2.2). Registered at the
     *  launch site; the runner awaits `checkpoint()` at every boundary (between
     *  DAG steps, loop/foreach iterations, retry attempts) and exposes a
     *  unit-scoped view to steps as `ctx.control`. Absent → uncontrolled run
     *  (unit tests, bare embedders), zero overhead. */
    controller?: RunController;
    /** Resume journal (RUN_CONTROL_SPEC §5): completed step outputs keyed by
     *  event path. A step whose path is journaled REPLAYS its output (emitting
     *  `step.replayed`) instead of executing; the first path not in the journal
     *  executes live and everything downstream follows. */
    journal?: Record<string, unknown>;
    /** True when this invocation CONTINUES an interrupted run (§5.2): emits a
     *  `run.resumed` marker instead of a fresh `run.start`, appending to the
     *  same log under the same runId. */
    resume?: boolean;
    /** Content hash of the workflow version being run, recorded on `run.start`
     *  so resume can refuse to replay a journal into a different DAG (§5). */
    workflowHash?: string;
}
export declare function runWorkflow<TServices = unknown>(workflow: Flow, input: unknown, registry: StepRegistry, opts?: RunOptions<TServices>): Promise<RunResult>;
