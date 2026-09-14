/**
 * Run + chat PROJECTOR (plans/generic-storage.md §7): a post-hoc consumer of
 * any `RunStore` / `ChatStore` that builds the graph's picture of usage —
 * `StrutRun`, `StrutAgentSession`, `StrutToolCall`, `StrutChat`, `StrutTurn`
 * nodes and the `EXECUTED` / `IN_RUN` / `IN_SESSION` / `SPAWNED` /
 * `IN_CHAT` edges — with summaries and a `log_ref` pointer back to the raw
 * log, never full payloads.
 *
 * The raw log stays the store of record (tailing, resume, replay); this is
 * the queryable skeleton on top. Zero coupling to the hot path: run it at
 * boot, on a schedule, as a workflow, or by hand, and re-run it whenever the
 * edge vocabulary grows — every write is an idempotent `upsert` keyed by
 * the node's identity (`unique_source_id` stamped for cheap reconciliation).
 *
 * Provenance: a tool call whose `step.end` carries `nodes` (the convention
 * in plans/generic-storage.md "v2" — graph-touching steps mark their output
 * with `withAccessedNodes`, and `wrapToolsWithEmit` lifts the marker onto
 * the event untruncated) gets one `ACCESSED` edge per node that exists in
 * this graph. Refs the graph doesn't hold (another database, a deleted
 * node) are counted as `unresolved`, never written — explicit over clever.
 *
 * Not projected: `PROMOTED_FROM` — promotions publish a new version without
 * recording the source run.
 */
import type { AccessedNode, RunEvent, RunSummary } from "../core.js";
import type { RunStore } from "../store.js";
import type { ChatStore, StoredMessage } from "../chat-store.js";
import type { GraphBackend } from "./backend.js";
import type { NodeInput } from "./node-writer.js";
export interface ProjectRunsOptions {
    /** Workflows to project. Default: every workflow with runs is unknown to a
     *  bare store, so callers pass the list (e.g. from `workspace.listWorkflows`). */
    workflows: string[];
    /** Newest N runs per workflow (default: all). */
    limitPerWorkflow?: number;
    /** Skip runs the graph already holds with a terminal status (cheap
     *  incremental re-runs; default true). Pass false to force re-projection. */
    skipSettled?: boolean;
}
export interface ProjectReport {
    runs: number;
    sessions: number;
    toolCalls: number;
    chats: number;
    turns: number;
    /** Every edge written, `ACCESSED` included. */
    edges: number;
    /** `ACCESSED` edges written (tool call → node it touched). */
    accessed: number;
    /** Node refs tool calls reported that this graph does not hold — no edge. */
    unresolved: number;
    skipped: number;
}
/** A bounded text preview of any value — the only shape of payload that
 *  reaches the graph. */
export declare function preview(v: unknown, max?: number): string | undefined;
interface RunProjection {
    run: NodeInput;
    sessions: NodeInput[];
    toolCalls: Array<{
        node: NodeInput;
        sessionPath: string;
        accessed: AccessedNode[];
    }>;
    workflowHash?: string;
}
/** Pure: the nodes one run contributes (no graph access). */
export declare function projectRunEvents(workflow: string, runId: string, events: RunEvent[], summary: RunSummary | null): RunProjection | null;
/** Project runs from a `RunStore` into the graph. */
export declare function projectRuns(backend: GraphBackend, store: RunStore, opts: ProjectRunsOptions): Promise<ProjectReport>;
/** Plain text of a stored message's content (string, or AI-SDK parts). */
export declare function messageText(content: unknown): string | undefined;
/** Run ids launched from this transcript: every `run_workflow` tool result
 *  carrying a `runId` (deep search — the tool-result envelope shape varies
 *  by SDK version). */
export declare function spawnedRunIds(messages: StoredMessage[]): string[];
/** Project every chat (and its turns) from a `ChatStore` into the graph. */
export declare function projectChats(backend: GraphBackend, chatStore: ChatStore): Promise<ProjectReport>;
/** Runs first (so chats can link to them), then chats. */
export declare function projectAll(backend: GraphBackend, src: {
    store: RunStore;
    chatStore?: ChatStore;
    workflows: string[];
}, opts?: Omit<ProjectRunsOptions, "workflows">): Promise<ProjectReport>;
export {};
