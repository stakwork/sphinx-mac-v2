/**
 * Run control — cancel, pause/resume for run TREES (RUN_CONTROL_SPEC.md §2).
 *
 * One mechanism: every in-flight run has a `RunController` registered at its
 * launch site. Nested launches (meta/run-workflow, the lab's optimizer
 * capability) attach their controller to the launching run's, so controls
 * apply to whole subtrees: cancelling an evolve run cancels its generations
 * and candidates; pausing a single candidate pauses only that candidate.
 *
 * All control is COOPERATIVE, at boundaries: the current unit of work (an LLM
 * call, a grader subprocess) completes — and is paid for, its output landing
 * in the journal — and the run consults `checkpoint()` before starting the
 * next unit. The runner awaits `checkpoint()` between DAG steps, loop/foreach
 * iterations and retry attempts; leaf steps with long internal loops (the
 * agent step's tool loop, evolve-loop's generations) opt in via
 * `ctx.control`.
 */
export type ControlState = "running" | "pausing" | "paused" | "cancelling";
/** Thrown out of `checkpoint()` when the run (or an ancestor) is cancelling.
 *  The runner treats it as a distinct outcome — `status: "cancelled"`, never
 *  the generic error path. Detected structurally (`isCancelledError`) rather
 *  than by `instanceof` because SDK stream plumbing may re-wrap errors. */
export declare class CancelledError extends Error {
    readonly isStrutCancelled = true;
    constructor(runId: string);
}
/** True when `err` is (or wraps, via `cause`) a CancelledError. */
export declare function isCancelledError(err: unknown): boolean;
/** The cooperative surface a step sees as `ctx.control` (a unit-scoped view
 *  of its run's `RunController` — see `RunController.forUnit`). */
export interface RunControl {
    readonly state: ControlState;
    /** Resolves immediately when running; blocks while (effectively) paused;
     *  throws `CancelledError` when (effectively) cancelling. */
    checkpoint(): Promise<void>;
}
export declare class RunController implements RunControl {
    readonly runId: string;
    readonly workflow: string;
    readonly parent?: RunController;
    readonly children: Set<RunController>;
    /** OWN state — the effective state additionally inherits the strictest
     *  ancestor (any ancestor cancelling → cancelling; else any ancestor
     *  pausing → pausing). */
    private own;
    /** Parked `checkpoint()` calls, woken by `poke()` to re-read state. */
    private waiters;
    /** Units of work currently executing between boundaries (leaf step bodies).
     *  A unit-scoped checkpoint releases its unit while parked, so a subtree
     *  with every branch parked at a boundary reads `busy === 0`. */
    private busy;
    constructor(runId: string, workflow: string, parent?: RunController);
    /** Effective state: strictest of self + ancestors; `pausing` reads as
     *  `paused` once the whole subtree is parked. */
    get state(): ControlState;
    private effective;
    /** The cooperative checkpoint (RUN_CONTROL_SPEC §2.2). */
    checkpoint(): Promise<void>;
    /** True when this run AND all descendants are parked at a boundary —
     *  nothing is mid-unit, so a restart loses no in-flight work. */
    quiesced(): boolean;
    /** Idempotent; applies to the whole subtree via the effective-state walk. */
    cancel(): void;
    pause(): void;
    resume(): void;
    /** Mark a unit of work (a leaf step body) as executing. Callers MUST pair
     *  with `endUnit` in a finally. Kept adjacent to a passed `checkpoint()`
     *  (no interleaving await) so pause can never observe a false quiesce
     *  between the two. */
    beginUnit(): void;
    endUnit(): void;
    /** A unit-scoped view for `ctx.control`: its `checkpoint()` releases the
     *  enclosing unit while parked (so an agent step paused between tool calls
     *  counts as quiesced) and re-acquires it before continuing. */
    forUnit(): RunControl;
    /** Unlink from the parent on unregister so a completed nested run stops
     *  counting toward the parent's quiescence. */
    detach(): void;
    /** Wake every parked checkpoint in the subtree to re-evaluate the
     *  effective state (resume releases them; cancel makes them throw; a
     *  waiter still effectively paused re-parks). */
    private poke;
}
