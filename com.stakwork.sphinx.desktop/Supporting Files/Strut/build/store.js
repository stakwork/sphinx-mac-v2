import { mkdir, writeFile, appendFile, readdir, readFile, open } from "node:fs/promises";
import { join } from "node:path";
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
/** A run is terminal once its log records a `run.end`, `run.error`, or
 *  `run.cancelled` — though a later `run.resumed` REOPENS it (§5.2: a
 *  resumed run appends to the same log past its old terminal event). */
function isTerminal(event) {
    return (event.type === "run.end" ||
        event.type === "run.error" ||
        event.type === "run.cancelled");
}
/** A `run.resumed` marker reopens a log whose previous event was terminal. */
function reopensRun(event) {
    return event.type === "run.resumed";
}
/** Parse one JSONL line, or `undefined` (with a warning) when it is not
 *  valid JSON. A corrupt line — a torn tail from a crash mid-append, or a
 *  line another append got glued onto — belongs to no completed unit, so
 *  readers skip it rather than failing: a run's log must never become
 *  unreadable, or the run is stuck (unresumable, untailable) for good. */
function parseJsonlLine(line, file) {
    try {
        return JSON.parse(line);
    }
    catch {
        console.warn(`[store] skipping corrupt line in ${file} (${line.length} bytes)`);
        return undefined;
    }
}
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
export async function* tailJsonl(file, isTerminal, opts = {}) {
    const intervalMs = opts.intervalMs ?? 250;
    const signal = opts.signal;
    let offset = 0;
    let leftover = "";
    // Deferred-close mode (opts.reopens set): saw a terminal event, close at
    // EOF unless a reopening event arrives first.
    let sawTerminal = false;
    while (true) {
        if (signal?.aborted)
            return;
        let chunk = "";
        try {
            const fh = await open(file, "r");
            try {
                const { size } = await fh.stat();
                if (size > offset) {
                    const buf = Buffer.alloc(size - offset);
                    await fh.read(buf, 0, buf.length, offset);
                    chunk = buf.toString("utf-8");
                    offset = size;
                }
            }
            finally {
                await fh.close();
            }
        }
        catch {
            // File not created yet — poll until it appears.
        }
        if (chunk) {
            leftover += chunk;
            const nl = leftover.lastIndexOf("\n");
            if (nl >= 0) {
                const complete = leftover.slice(0, nl);
                leftover = leftover.slice(nl + 1);
                for (const line of complete.split("\n")) {
                    if (!line)
                        continue;
                    const event = parseJsonlLine(line, file);
                    if (event === undefined)
                        continue; // corrupt line — skip, keep tailing
                    yield event;
                    if (isTerminal(event)) {
                        if (!opts.reopens)
                            return;
                        sawTerminal = true;
                    }
                    else if (sawTerminal && opts.reopens?.(event)) {
                        sawTerminal = false;
                    }
                }
            }
        }
        // After a terminal event: re-check for appended bytes immediately (no
        // poll delay for the common completed-run tail); at EOF, close — unless
        // the producer is live again (a resume re-attached), then keep following.
        if (sawTerminal) {
            if (chunk)
                continue;
            if (!(opts.stillLive?.() ?? false))
                return;
        }
        await sleep(intervalMs);
    }
}
/**
 * Generic `tailEvents` for backends without a native append-following
 * primitive: re-read the run's events on each poll and yield past the index
 * cursor. Same terminal / reopen / `stillLive` semantics as the file tail
 * (`tailJsonl`), which `FileRunStore` keeps because a byte-offset read is
 * cheaper than a full re-read per poll.
 */
export async function* tailFromPolling(store, workflow, runId, opts = {}) {
    const intervalMs = opts.intervalMs ?? 250;
    let cursor = 0;
    let sawTerminal = false;
    while (true) {
        if (opts.signal?.aborted)
            return;
        const events = await store.getRunEvents(workflow, runId);
        const fresh = events.slice(cursor);
        cursor = events.length;
        for (const event of fresh) {
            yield event;
            if (isTerminal(event))
                sawTerminal = true;
            else if (sawTerminal && reopensRun(event))
                sawTerminal = false;
        }
        if (sawTerminal) {
            if (fresh.length > 0)
                continue; // drain immediately, no poll delay
            if (!(opts.stillLive?.() ?? false))
                return;
        }
        await sleep(intervalMs);
    }
}
/** Newest run's start time from the run-id list — run ids are millisecond
 *  timestamps (`generateRunId`), so the max parseable id is the latest.
 *  Shared by backends whose ids follow that convention. */
export function lastRunAtFromIds(runIds) {
    let max = null;
    for (const id of runIds) {
        const t = parseInt(id, 10);
        if (!isNaN(t) && (max == null || t > max))
            max = t;
    }
    return max;
}
/**
 * Reconstruct a `PartialRunSummary` from a run's event log. Pure over the
 * events array so it is equally usable on a live tail, a stale run's log,
 * or in tests. Returns null for an empty log (no such run).
 */
export function summarizeFromEvents(workflow, runId, events, status = "stale") {
    if (events.length === 0)
        return null;
    const prefix = `${workflow}/`;
    const isTopLevelStep = (path) => {
        if (!path.startsWith(prefix))
            return false;
        const rest = path.slice(prefix.length);
        return rest.length > 0 && !rest.includes("/") && !rest.includes("#");
    };
    const summary = {
        runId,
        workflow,
        partial: true,
        status,
        eventCount: events.length,
        steps: {},
    };
    for (const e of events) {
        if (e.type === "run.start") {
            summary.startedAt ??= e.ts;
            if (e.input !== undefined)
                summary.input = e.input;
        }
        if ((e.type === "step.end" || e.type === "step.replayed") && isTopLevelStep(e.path)) {
            const stepId = e.path.slice(prefix.length);
            delete summary.steps[stepId]; // re-insert so key order tracks completion order
            summary.steps[stepId] = e.output;
        }
        if (e.type === "step.error") {
            summary.lastError = { path: e.path, message: e.error?.message ?? "unknown", ts: e.ts };
        }
    }
    const last = events[events.length - 1];
    summary.lastEventAt = last.ts;
    summary.lastEvent = { type: last.type, path: last.path, ts: last.ts };
    return summary;
}
// ── Filesystem implementation ──────────────────────────────────────────────
/**
 * Stores runs under `<workspaceRoot>/workflows/<workflow>/runs/<runId>/`.
 * runId is a millisecond timestamp, giving natural sort order and easy pagination.
 */
export class FileRunStore {
    workspaceRoot;
    constructor(workspaceRoot) {
        this.workspaceRoot = workspaceRoot;
    }
    runDir(workflow, runId) {
        return join(this.workspaceRoot, "workflows", workflow, "runs", runId);
    }
    async append(workflow, runId, event) {
        const dir = this.runDir(workflow, runId);
        await mkdir(dir, { recursive: true });
        const line = JSON.stringify(event) + "\n";
        await appendFile(join(dir, "events.jsonl"), line, "utf-8");
    }
    async finalize(workflow, runId, summary) {
        const dir = this.runDir(workflow, runId);
        await mkdir(dir, { recursive: true });
        await writeFile(join(dir, "run.json"), JSON.stringify(summary, null, 2), "utf-8");
    }
    /** List runs for a workflow, sorted newest first. Returns dir names (timestamps). */
    async listRuns(workflow) {
        const runsDir = join(this.workspaceRoot, "workflows", workflow, "runs");
        try {
            const entries = await readdir(runsDir);
            // Sort descending (newest first) — timestamps sort lexicographically
            return entries.sort((a, b) => b.localeCompare(a));
        }
        catch {
            return [];
        }
    }
    /** Read run.json for a specific run. */
    async getRunSummary(workflow, runId) {
        try {
            const raw = await readFile(join(this.runDir(workflow, runId), "run.json"), "utf-8");
            return JSON.parse(raw);
        }
        catch {
            return null;
        }
    }
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
    async *tailEvents(workflow, runId, opts = {}) {
        const file = join(this.runDir(workflow, runId), "events.jsonl");
        // `run.error`/`run.cancelled` are no longer unconditionally terminal: a
        // later `run.resumed` reopens the stream (historical tails scan ahead;
        // live tails consult `opts.stillLive` — the server's controllers map).
        yield* tailJsonl(file, isTerminal, { ...opts, reopens: reopensRun });
    }
    /** Truncate a torn tail (§5.1): a process killed mid-append — `appendFile`
     *  writes large outputs in several chunks — leaves a partial final line
     *  with no newline. Left alone, the resumed run's first append would be
     *  glued onto it, silently losing that event and making the merged line
     *  unparseable. Drop everything after the last newline; the fragment
     *  belongs to an incomplete unit by definition. */
    async repairLog(workflow, runId) {
        const file = join(this.runDir(workflow, runId), "events.jsonl");
        let fh;
        try {
            fh = await open(file, "r+");
        }
        catch {
            return false; // no log yet — nothing to heal
        }
        try {
            const { size } = await fh.stat();
            if (size === 0)
                return false;
            const tail = Buffer.alloc(1);
            await fh.read(tail, 0, 1, size - 1);
            if (tail[0] === 0x0a)
                return false; // ends in "\n" — intact
            // Walk back to the last newline (reading in blocks from the end).
            const block = 64 * 1024;
            let end = size;
            let cut = 0;
            while (end > 0) {
                const start = Math.max(0, end - block);
                const buf = Buffer.alloc(end - start);
                await fh.read(buf, 0, buf.length, start);
                const nl = buf.lastIndexOf(0x0a);
                if (nl >= 0) {
                    cut = start + nl + 1;
                    break;
                }
                end = start;
            }
            await fh.truncate(cut);
            console.warn(`[store] repaired torn tail of ${workflow}/${runId}: dropped ${size - cut} bytes after the last complete event`);
            return true;
        }
        finally {
            await fh.close();
        }
    }
    /** Read events.jsonl for a specific run. Tolerates corrupt lines — a
     *  torn tail from a crash mid-append (§5.1), or any line that failed to
     *  parse — by skipping them with a warning: an unreadable log would leave
     *  the run stuck (unresumable, unlistable), and a corrupt line never
     *  belongs to a completed unit. */
    async getRunEvents(workflow, runId) {
        const file = join(this.runDir(workflow, runId), "events.jsonl");
        let raw;
        try {
            raw = await readFile(file, "utf-8");
        }
        catch {
            return [];
        }
        const events = [];
        for (const line of raw.split("\n")) {
            if (!line.trim())
                continue;
            const event = parseJsonlLine(line, file);
            if (event !== undefined)
                events.push(event);
        }
        return events;
    }
    async lastRunAt(workflow) {
        return lastRunAtFromIds(await this.listRuns(workflow));
    }
}
// ── In-memory implementation ───────────────────────────────────────────────
/**
 * A complete ephemeral backend (not just a write-only test stub): run
 * history, SSE reattach, durable resume, and promotions all work over it —
 * the records just don't survive the process.
 */
export class MemoryRunStore {
    events = new Map();
    summaries = new Map();
    key(workflow, runId) {
        return `${workflow}/${runId}`;
    }
    async listRuns(workflow) {
        const prefix = `${workflow}/`;
        const ids = new Set();
        for (const k of this.events.keys())
            if (k.startsWith(prefix))
                ids.add(k.slice(prefix.length));
        for (const k of this.summaries.keys())
            if (k.startsWith(prefix))
                ids.add(k.slice(prefix.length));
        return [...ids].sort((a, b) => b.localeCompare(a));
    }
    async getRunSummary(workflow, runId) {
        return this.summaries.get(this.key(workflow, runId)) ?? null;
    }
    async getRunEvents(workflow, runId) {
        return [...(this.events.get(this.key(workflow, runId)) ?? [])];
    }
    tailEvents(workflow, runId, opts = {}) {
        return tailFromPolling(this, workflow, runId, opts);
    }
    async lastRunAt(workflow) {
        return lastRunAtFromIds(await this.listRuns(workflow));
    }
    async append(workflow, runId, event) {
        const k = this.key(workflow, runId);
        if (!this.events.has(k)) {
            this.events.set(k, []);
        }
        this.events.get(k).push(event);
    }
    async finalize(workflow, runId, summary) {
        this.summaries.set(this.key(workflow, runId), summary);
    }
    /** Helper for tests: get events by workflow + runId. */
    getEvents(workflow, runId) {
        return this.events.get(this.key(workflow, runId)) ?? [];
    }
    /** Helper for tests: get summary by workflow + runId. */
    getSummary(workflow, runId) {
        return this.summaries.get(this.key(workflow, runId));
    }
}
/** Generate a timestamp-based run ID. */
export function generateRunId() {
    return Date.now().toString();
}
//# sourceMappingURL=store.js.map