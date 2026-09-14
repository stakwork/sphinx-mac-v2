import { Hono } from "hono";
import type { Flow, StepRegistry, RunEvent, RunResult } from "./core.js";
import type { RunStore } from "./store.js";
import type { ChatStore } from "./chat-store.js";
import { type WorkspaceStore } from "./workspace.js";
import type { SecretStore } from "./secret-store.js";
import type { GraphBackend } from "./graph/backend.js";
import { type SttService } from "./audio/stt.js";
/**
 * Options for constructing a Strut instance. Everything is optional — pass
 * nothing for the default "filesystem-backed server" behavior, or supply
 * any subset to embed strut in your own app.
 */
export interface StrutOptions<TServices = unknown> {
    /** Persistent store for workflows and steps. Defaults to a new
     *  `FileWorkspaceStore()` (reads `STRUT_WORKSPACE` env, falls back to
     *  `./workspace`). Any `WorkspaceStore` implementation works. */
    workspace?: WorkspaceStore;
    /** Local directory for the inherently-local things: run artifacts,
     *  step cassettes, the chat builder's shell cwd + scratch/. Defaults to
     *  the file workspace's root (so a file-backed deployment keeps one
     *  directory), else `STRUT_WORKSPACE` / `./workspace`. A non-file
     *  workspace can point this at any scratch volume — losing it loses
     *  blobs and cassettes, never workspace records. */
    dataDir?: string;
    /** Step registry. If supplied, used as-is and `rebuildRegistry` becomes
     *  a no-op (the consumer owns step composition). If omitted, strut
     *  discovers steps via `buildRegistry(await workspace.materializeCustomSteps())`. */
    registry?: StepRegistry;
    /** Where to persist run events + summaries. Defaults to a `FileRunStore`
     *  rooted at the workspace path. Pass `new MemoryRunStore()` for
     *  ephemeral / test environments. */
    store?: RunStore;
    /** Consumer-defined capabilities bag exposed to every step via
     *  `ctx.services`. Use this to inject environment-specific
     *  implementations (Neo4j vs in-memory store, real vs fake LLM, …)
     *  without changing the workflow or registry. */
    services?: TServices;
    /** When true, mount the static web UI under `/` (SPA fallback) and
     *  `/assets/*`. Defaults to true. Disable when embedding strut under a
     *  larger app that owns its own UI routes. */
    serveUi?: boolean;
    /** Mount the `POST /chat` AI workflow-builder endpoint. Defaults to
     *  true; disable to avoid pulling in the `ai`/`@ai-sdk/anthropic` deps. */
    enableChat?: boolean;
    /** Where to persist chat sessions (the detached AI-builder background jobs:
     *  `messages.jsonl` + `events.jsonl` + `meta.json`). Defaults to a
     *  `FileChatStore` rooted at the workspace path (or `MemoryChatStore` when
     *  `store` is a `MemoryRunStore`). */
    chatStore?: ChatStore;
    /** Deployment-scoped secret store backing `ctx.services.secrets` and the
     *  `/secrets` admin endpoints. Defaults to an encrypted `FileSecretStore`
     *  rooted at the workspace path (or `MemorySecretStore` when `store` is a
     *  `MemoryRunStore`). The default `secrets` capability reads this store with
     *  `process.env` as fallback. Pass your own `services.secrets` to bypass
     *  entirely (then the `/secrets` endpoints return 501). */
    secretStore?: SecretStore;
    /** Max agent steps (tool-call iterations) per chat turn. Raise for longer
     *  autonomous "let it rip" loops. Defaults to `STRUT_CHAT_MAX_STEPS` or 100. */
    chatMaxSteps?: number;
    /** Default model for the chat agent — any aieo model name: an alias
     *  (`sonnet`, `gpt`, `kimi`), a full id, or `provider/id` (OpenRouter as
     *  `openrouter/org/model`). A per-chat pick (`POST /chat { model }`, the
     *  flyout's picker) overrides it. Defaults to `STRUT_CHAT_MODEL` or
     *  `claude-sonnet-5`. */
    chatModel?: string;
    /** How long the chat agent's `run_workflow` tool waits before a still-
     *  running workflow converts to a DETACHED run (the tool returns a
     *  `{ status: "running", runId }` stub and the chat is woken with a
     *  `[run-notification]` message when the run settles). Defaults to
     *  `STRUT_CHAT_RUN_WAIT_MS` or 60000. */
    chatRunWaitMs?: number;
    /** Max consecutive notification-triggered chat turns since the last human
     *  message before the chat PARKS (notifications still append to the
     *  transcript, but no turn launches until a human replies) — the runaway
     *  guard for autonomous launch→wake→relaunch loops. Defaults to
     *  `STRUT_CHAT_MAX_AUTO_TURNS` or 10. */
    chatMaxAutoTurns?: number;
    /** Boot-time auto-resume of runs cut off by a crash/restart
     *  (RUN_CONTROL_SPEC §5.3). Defaults to ON for a file-backed store unless
     *  `STRUT_AUTO_RESUME=0`; pass `false` to disable, or an object to tune
     *  the guards. Only the NEWEST root run per workflow is considered. */
    autoResume?: boolean | AutoResumeOptions;
    /** The strut graph backend, when the deployment has one (server.ts passes
     *  the one behind its graph-backed workspace). Enables the chat builder's
     *  read-only `graph_query` tool. Omit and the tool isn't offered. */
    graph?: GraphBackend;
    /** Directory containing the built web UI (the `dist` folder). Defaults
     *  to strut's own bundled UI resolved relative to this module, so it
     *  works regardless of the host process's CWD. The built UI uses
     *  relative asset paths, so it can be mounted at any sub-path (e.g.
     *  `/lab`) as long as the host serves it with a trailing slash. */
    webDist?: string;
    /** Speech-to-text (src/audio): the `/audio/*` routes, the `/audio/stream`
     *  WebSocket (attached by `listen()`), and `ctx.services.stt`. Defaults
     *  to a service rooted at `dataDir` with models under `STRUT_MODEL_DIR`;
     *  pass your own, or `false` to mount nothing. The sherpa addon is an
     *  optionalDependency loaded on first use, so the default costs nothing
     *  at boot and the routes answer 501 without it. */
    stt?: SttService | false;
}
export interface AutoResumeOptions {
    /** Ignore cut-off runs whose last event is older than this. Default 7 days. */
    maxAgeMs?: number;
    /** Give up on a run that has already been resumed this many times — a step
     *  that deterministically kills the server must not loop forever. Default 5. */
    maxResumes?: number;
    /** Delay after construction before the scan runs (lets the host finish
     *  booting). Default 3000ms; 0 runs it on the next tick. */
    delayMs?: number;
}
/** One line of the boot-time auto-resume report. */
export interface AutoResumeOutcome {
    workflow: string;
    runId: string;
    action: "resumed" | "finalized" | "skipped";
    reason: string;
}
/**
 * A configured strut instance. Carries the Hono `app` (mount it under your
 * own router, or call `listen()`), the underlying workspace / store /
 * services bag, and a typed `run()` helper that automatically threads
 * `services` into every workflow execution.
 */
export interface Strut<TServices = unknown> {
    /** Hono app with all strut routes mounted. Mount under your own router
     *  with `parent.route("/strut", strut.app)`, or call `strut.listen(port)`. */
    app: Hono;
    workspace: WorkspaceStore;
    /** Resolved local data directory (see `StrutOptions.dataDir`). */
    dataDir: string;
    store: RunStore;
    /** Deployment-scoped secret store backing `ctx.services.secrets` + the
     *  `/secrets` endpoints. */
    secretStore: SecretStore;
    services: TServices;
    /** Current registry. Reads through the closure so callers always see
     *  the latest after `rebuildRegistry()`. */
    getRegistry: () => StepRegistry;
    /** Re-scan the workspace for newly-published custom steps. No-op when
     *  the instance was constructed with an explicit `registry`. */
    rebuildRegistry: () => Promise<void>;
    /** Resume every run cut off by the previous process (RUN_CONTROL_SPEC
     *  §5.3): the newest root run of each workflow that has a log but no
     *  summary, was not paused or cancelling, is younger than `maxAgeMs`,
     *  and has fewer than `maxResumes` prior resumes. Runs automatically
     *  after boot when `autoResume` is enabled; callable directly. */
    autoResumeStaleRuns: (opts?: AutoResumeOptions) => Promise<AutoResumeOutcome[]>;
    /** Run a workflow by name (resolves through the workspace) or by Flow
     *  object. `services` is auto-injected from the instance; pass a
     *  `services` override in `opts` to use a different bag for one run. */
    run: (workflow: string | Flow, input?: unknown, opts?: StrutRunOptions<TServices>) => Promise<RunResult>;
    /** The speech-to-text service behind `/audio/*` (null when disabled). A
     *  host that mounts `app` itself must call `attachAudioWebSocket(server,
     *  strut.stt)` to get the dictation socket; `listen()` does it. */
    stt: SttService | null;
    /** Boot the Hono server with `@hono/node-server`. Resolves once the
     *  socket is listening, to the *bound* port — so `listen(0)` (or
     *  `STRUT_PORT=0`) lets the OS pick one, which a desktop host that spawns
     *  strut as a child process relies on. `host` (or `STRUT_HOST`) sets the
     *  bind address; unset binds every interface, `127.0.0.1` keeps a local
     *  strut off the LAN. Prints one JSON line on stdout when ready,
     *  `{"event":"ready","port":N,"host":"…"}`, for hosts to parse; with
     *  `STRUT_READY_KEY=1` the line also carries `key` (the `STRUT_API_KEY`),
     *  so a host that spawned strut reads port and credential from one line.
     *  Convenience wrapper — feel free to mount `app` yourself. */
    listen: (port?: number, host?: string) => Promise<number>;
    /** Stop the server started by `listen()` (no-op otherwise). */
    close: () => Promise<void>;
}
export interface StrutRunOptions<TServices = unknown> {
    runId?: string;
    /** Workflow version (only meaningful when `workflow` is a string). */
    version?: string;
    /** The launching run's id (the calling step's `ctx.runId`) — attaches this
     *  run's controller under the parent's, so cancel/pause on the parent
     *  reach it (RUN_CONTROL_SPEC §2.2 tree linkage). */
    parentRunId?: string;
    /** Per-event hook — useful for SSE streaming. */
    onEvent?: (event: RunEvent) => void | Promise<void>;
    /** Override the instance-level services for a single run. */
    services?: TServices;
    /** Per-run overrides for the workflow's `params` knobs (shallow-merged
     *  over the flow's `params` defaults). */
    params?: Record<string, unknown>;
    /** Per-run overrides keyed by workflow name, applied at every level of the
     *  execution tree (entry + nested subflows). See `RunOptions.paramOverrides`. */
    paramOverrides?: Record<string, Record<string, unknown>>;
}
/**
 * Build a configured Strut instance. This is the primary entry point for
 * using strut as a library: pass your registry (or let it be discovered
 * from disk), your services bag, and mount the returned Hono `app`
 * wherever you like.
 *
 * ```ts
 * import { createStrut, createRegistry, defineStep } from "strut";
 *
 * interface MyServices { graph: GraphStore; llm: LLMClient }
 *
 * const strut = await createStrut<MyServices>({
 *   registry: await createRegistry([myStep, anotherStep]),
 *   services: { graph: new Neo4jGraph(), llm: new Anthropic() },
 * });
 *
 * await strut.listen(3000);
 * ```
 *
 * The returned `app` can also be mounted under a parent Hono / Express
 * app — strut owns its routes (`/workflows`, `/steps`, `/chat`, `/health`)
 * but nothing else.
 */
export declare function createStrut<TServices = unknown>(opts?: StrutOptions<TServices>): Promise<Strut<TServices>>;
