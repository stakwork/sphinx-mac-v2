/**
 * Resume journal (RUN_CONTROL_SPEC §5) — the event log already contains
 * everything a resume needs: every completed step's `step.end` carries its
 * `output`, keyed by a deterministic `path`. This module turns a run's
 * events into the `{ path → output }` journal `runWorkflow` replays from,
 * and implements the `from` invalidation ("re-run from this step", §5.2).
 */
import type { Flow, RunEvent, Step } from "./core.js";
import type { SubflowResolver } from "./runner.js";
/** Completed units: last `step.end` per path wins — a resumed log may carry
 *  a pre-failure entry AND a post-resume re-execution for the same path. */
export declare function buildJournal(events: RunEvent[]): Record<string, unknown>;
/** The run's original input, params, and recorded workflow hash, from
 *  `run.start` — a durable resume re-invokes with exactly these. */
export declare function readRunStart(events: RunEvent[]): {
    input: unknown;
    workflowHash?: string;
    params?: Record<string, unknown>;
    paramOverrides?: Record<string, Record<string, unknown>>;
    /** Set for a nested run (§5.3: boot-time auto-resume resumes roots only). */
    parentRunId?: string;
} | null;
export interface InvalidateResult {
    journal: Record<string, unknown>;
    /** Journal keys dropped (forced to re-execute), sorted. */
    dropped: string[];
    /** Levels where dependent-computation was impossible (dynamic subflow
     *  name, missing resolver) — the target subtree is still dropped, but
     *  same-level dependents of that container may replay stale outputs. */
    warnings: string[];
}
/**
 * §5.2 `from`: forced invalidation. Drop `from`'s own subtree, its ancestor
 * container entries (so containers re-execute and re-reach it), the later
 * iterations of any enclosing `loop` (sequential — they consumed its
 * output), and the transitive dependents of every step on the ancestor
 * chain at its own flow level. Everything left in the journal replays.
 */
export declare function invalidateFrom(journal: Record<string, unknown>, from: string, entryFlow: Flow, resolver?: SubflowResolver): Promise<InvalidateResult>;
/** Transitive dependents of `stepId` under the runner's dependency
 *  semantics: explicit `depends`, or implicit previous-step. */
export declare function transitiveDependents(steps: Step[], stepId: string): Set<string>;
