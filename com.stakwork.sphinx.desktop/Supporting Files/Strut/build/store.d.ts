import type { RunEvent, RunSummary } from "./core.js";
/**
 * Generic tail of an append-only JSONL file: yield every parsed line from the
 * start of the file (history), then follow appends (live) until `isTerminal`
 * returns true for a line, at which point the generator returns. This is the
 * shared engine behind `FileRunStore.tailEvents` (runs) and `FileChatStore`
 * (chat turns) — the background-job reattach model (EVAL_SPEC §8).
 *
 * The append-only log is the ordered source of truth, so the history→live
 * join is race-free: read from a byte offset to EOF, then keep re-reading
 * from the new offset. Partial trailing lines (a write caught mid-flush) are
 * buffered until their newline arrives. One code path serves completed *and*
 * in-flight producers — a completed file drains and returns immediately; a
 * live one polls (`intervalMs`) for appends. Pass an `AbortSignal` (e.g. on
 * client disconnect) to stop early. A file that doesn't exist yet is polled
 * until it appears (race-free with a producer that hasn't written line 1).
 */
export declare function tailJsonl<T>(file: string, isTerminal: (event: T) => boolean, opts?: {
    intervalMs?: number;
    signal?: AbortSignal;
    /** A later event that REOPENS a log whose previous event was terminal
     *  (a resumed run's `run.resumed`, RUN_CONTROL_SPEC §5.2). When set, a
     *  terminal event doesn't end the tail immediately: the tail scans
     *  ahead for a reopening event, and only closes at EOF (or, if
     *  `stillLive` says the producer is live again, keeps following). */
    reopens?: (event: T) => boolean;
    /** Consulted at EOF after a terminal event when `reopens` is set: a live
     *  producer (a registered run controller) means a resume is in flight —
     *  keep following instead of closing. Default: close at EOF. */
    stillLive?: () => boolean;
}): AsyncGenerator<T>;
/** Options for `RunStore.tailEvents`. */
export interface TailOpts {
    /** Poll interval while following a live log (default 250ms). */
    intervalMs?: number;
    /** Stop the tail early (e.g. on client disconnect). */
    signal?: AbortSignal;
    /** Consulted at EOF after a terminal event: a live producer (the server's
     *  registered run controller) means a resume is in flight — keep following
     *  instead of closing. Default: close at EOF. */
    stillLive?: () => boolean;
}
/**
 * The persistence boundary for runs — the full contract, writes AND reads.
 * Every backend (filesystem, memory, a database) implements all of it; the
 * server capability-gates on nothing else. `tailEvents` has a generic
 * polling implementation (`tailFromPolling`) built on `getRunEvents`, so a
 * backend without a native tail implements the five data methods and
 * delegates.
 *
 * Tail contract (RUN_CONTROL_SPEC §5.2): yield the run's history from event
 * 0, then follow appends until a terminal event (`run.end` / `run.error` /
 * `run.cancelled`). A terminal event doesn't close the tail immediately — a
 * later `run.resumed` REOPENS the log (durable resume appends past the old
 * terminal event), so the tail scans ahead and only closes at EOF, or keeps
 * following if `opts.stillLive()` reports a resume in flight.
 */
export interface RunStore {
    append(workflow: string, runId: string, event: RunEvent): Promise<void>;
    finalize(workflow: string, runId: string, summary: RunSummary): Promise<void>;
    /** Run ids for a workflow, newest first. */
    listRuns(workflow: string): Promise<string[]>;
    /** The finalized summary, or null while the run is in flight / if it never
     *  finalized (crash) — callers fall back to `summarizeFromEvents`. */
    getRunSummary(workflow: string, runId: string): Promise<RunSummary | null>;
    /** The full event log (empty for an unknown run). */
    getRunEvents(workflow: string, runId: string): Promise<RunEvent[]>;
    /** History → live tail; see the interface doc for terminality. */
    tailEvents(workflow: string, runId: string, opts?: TailOpts): AsyncGenerator<RunEvent>;
    /** Start time (epoch ms) of the most recent run, or null if never run. */
    lastRunAt(workflow: string): Promise<number | null>;
    /** Heal a log left torn by a crash mid-append (a truncated final line with
     *  no newline) so the next append starts on a fresh line instead of being
     *  glued onto the fragment. Called before a durable resume; returns true
     *  when something was repaired. Optional — backends whose appends are
     *  atomic (in-memory, a database row) have nothing to heal. */
    repairLog?(workflow: string, runId: string): Promise<boolean>;
}
/**
 * Generic `tailEvents` for backends without a native append-following
 * primitive: re-read the run's events on each poll and yield past the index
 * cursor. Same terminal / reopen / `stillLive` semantics as the file tail
 * (`tailJsonl`), which `FileRunStore` keeps because a byte-offset read is
 * cheaper than a full re-read per poll.
 */
export declare function tailFromPolling(store: Pick<RunStore, "getRunEvents">, workflow: string, runId: string, opts?: TailOpts): AsyncGenerator<RunEvent>;
/** Newest run's start time from the run-id list — run ids are millisecond
 *  timestamps (`generateRunId`), so the max parseable id is the latest.
 *  Shared by backends whose ids follow that convention. */
export declare function lastRunAtFromIds(runIds: string[]): number | null;
/**
 * A best-effort summary for a run with no `run.json` — in-flight, or
 * orphaned by a crash/restart before `finalize` ran. Everything here is
 * derived from the append-only event log, which IS durable per-step: the
 * run's input from `run.start`, the latest output of every top-level step,
 * and the last error seen anywhere in the tree. `partial: true` is the
 * discriminator — a consumer that needs a terminal result must not treat
 * this as one.
 */
export interface PartialRunSummary {
    runId: string;
    workflow: string;
    partial: true;
    /** Live state when the caller knows it ("running" / "paused"), else
     *  "stale" (no controller — the process that ran it is gone; resumable). */
    status: string;
    startedAt?: string;
    lastEventAt?: string;
    eventCount: number;
    input?: unknown;
    /** Latest completed output per TOP-LEVEL step (path `<wf>/<stepId>` with
     *  no deeper segment and no `#iteration`), in completion order. */
    steps: Record<string, unknown>;
    /** The last `step.error` seen at any depth — where a dead run stopped. */
    lastError?: {
        path: string;
        message: string;
        ts: string;
    };
    /** The last event of any kind — how far the log got. */
    lastEvent?: {
        type: string;
        path: string;
        ts: string;
    };
}
/**
 * Reconstruct a `PartialRunSummary` from a run's event log. Pure over the
 * events array so it is equally usable on a live tail, a stale run's log,
 * or in tests. Returns null for an empty log (no such run).
 */
export declare function summarizeFromEvents(workflow: string, runId: string, events: RunEvent[], status?: string): PartialRunSummary | null;
/**
 * Stores runs under `<workspaceRoot>/workflows/<workflow>/runs/<runId>/`.
 * runId is a millisecond timestamp, giving natural sort order and easy pagination.
 */
export declare class FileRunStore implements RunStore {
    private workspaceRoot;
    constructor(workspaceRoot: string);
    private runDir;
    append(workflow: string, runId: string, event: RunEvent): Promise<void>;
    finalize(workflow: string, runId: string, summary: RunSummary): Promise<void>;
    /** List runs for a workflow, sorted newest first. Returns dir names (timestamps). */
    listRuns(workflow: string): Promise<string[]>;
    /** Read run.json for a specific run. */
    getRunSummary(workflow: string, runId: string): Promise<RunSummary | null>;
    /**
     * Tail a run's event log: yield every event from the start of the file
     * (history), then follow appends (live) until a terminal event
     * (`run.end` / `run.error`) is seen, at which point the generator returns.
     *
     * The append-only log is the ordered source of truth, so the history→live
     * join is naturally race-free: we read from a byte offset to EOF, then
     * keep re-reading from the new offset. Partial trailing lines (a write
     * caught mid-flush) are buffered until their newline arrives. One code path
     * serves completed *and* in-flight runs — a completed run drains the file
     * and returns immediately; a live run polls (`intervalMs`) for appends.
     *
     * The only "polling" is the server noticing appends — invisible to clients.
     * Pass an `AbortSignal` (e.g. on client disconnect) to stop early.
     */
    tailEvents(workflow: string, runId: string, opts?: TailOpts): AsyncGenerator<RunEvent>;
    /** Truncate a torn tail (§5.1): a process killed mid-append — `appendFile`
     *  writes large outputs in several chunks — leaves a partial final line
     *  with no newline. Left alone, the resumed run's first append would be
     *  glued onto it, silently losing that event and making the merged line
     *  unparseable. Drop everything after the last newline; the fragment
     *  belongs to an incomplete unit by definition. */
    repairLog(workflow: string, runId: string): Promise<boolean>;
    /** Read events.jsonl for a specific run. Tolerates corrupt lines — a
     *  torn tail from a crash mid-append (§5.1), or any line that failed to
     *  parse — by skipping them with a warning: an unreadable log would leave
     *  the run stuck (unresumable, unlistable), and a corrupt line never
     *  belongs to a completed unit. */
    getRunEvents(workflow: string, runId: string): Promise<RunEvent[]>;
    lastRunAt(workflow: string): Promise<number | null>;
}
/**
 * A complete ephemeral backend (not just a write-only test stub): run
 * history, SSE reattach, durable resume, and promotions all work over it —
 * the records just don't survive the process.
 */
export declare class MemoryRunStore implements RunStore {
    events: Map<string, RunEvent[]>;
    summaries: Map<string, RunSummary>;
    private key;
    listRuns(workflow: string): Promise<string[]>;
    getRunSummary(workflow: string, runId: string): Promise<RunSummary | null>;
    getRunEvents(workflow: string, runId: string): Promise<RunEvent[]>;
    tailEvents(workflow: string, runId: string, opts?: TailOpts): AsyncGenerator<RunEvent>;
    lastRunAt(workflow: string): Promise<number | null>;
    append(workflow: string, runId: string, event: RunEvent): Promise<void>;
    finalize(workflow: string, runId: string, summary: RunSummary): Promise<void>;
    /** Helper for tests: get events by workflow + runId. */
    getEvents(workflow: string, runId: string): RunEvent[];
    /** Helper for tests: get summary by workflow + runId. */
    getSummary(workflow: string, runId: string): RunSummary | undefined;
}
/** Generate a timestamp-based run ID. */
export declare function generateRunId(): string;
