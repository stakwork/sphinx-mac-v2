import type { SttService } from "./audio/stt.js";
/** Credential access. The single boundary through which adapters read secrets
 *  (API keys, tokens). Backed by `process.env` by default; back it with a
 *  persisted {@link SecretReadable} (e.g. a `SecretStore`) for UI-managed
 *  secrets — without touching any adapter. */
export interface SecretsCapability {
    get(name: string): Promise<string | undefined>;
}
/** The narrow read surface a secrets capability needs from a backing store —
 *  satisfied by `SecretStore` (secret-store.ts) without importing it here. */
export interface SecretReadable {
    get(name: string): Promise<string | undefined>;
}
/**
 * Build a secrets capability. Pass either:
 *   - a flat key→value source (defaults to `process.env`), or
 *   - a `SecretReadable` store (e.g. a `SecretStore`), optionally with an
 *     `envFallback` so unset secrets still resolve from `process.env`.
 *
 * The store path is async-aware: a managed secret wins, then the env fallback.
 */
export declare function secretsCapability(source?: Record<string, string | undefined> | SecretReadable, opts?: {
    envFallback?: Record<string, string | undefined>;
}): SecretsCapability;
export interface HttpRequestOptions {
    method?: string;
    headers?: Record<string, string>;
    /** Request body. Objects are JSON-encoded (with a default
     *  `content-type: application/json`); strings are sent as-is. */
    body?: unknown;
    /** Query params appended to the URL. */
    query?: Record<string, string | number | boolean>;
    /** Abort the request after this many milliseconds. */
    timeout?: number;
}
/** A plain, fully-serializable HTTP response — deliberately NOT a `fetch`
 *  Response, so it can be written to / replayed from a cassette. `body` is the
 *  parsed JSON when the response is JSON, otherwise the raw text. */
export interface HttpResponse {
    status: number;
    ok: boolean;
    headers: Record<string, string>;
    body: unknown;
}
/** Fetch-like transport. The blessed path for adapter network I/O. */
export type HttpCapability = (url: string, opts?: HttpRequestOptions) => Promise<HttpResponse>;
/** Minimal shape of the global `fetch` we depend on — kept tiny so a fake can
 *  be injected in tests without pulling in DOM lib types. */
export type FetchLike = (url: string, init?: {
    method?: string;
    headers?: Record<string, string>;
    body?: string;
    signal?: AbortSignal;
}) => Promise<{
    status: number;
    ok: boolean;
    headers: {
        forEach(cb: (value: string, key: string) => void): void;
    };
    text(): Promise<string>;
}>;
/** Build an http capability over a `fetch` implementation (defaults to the
 *  global `fetch`). Encodes object bodies as JSON, parses JSON responses, and
 *  returns a plain serializable {@link HttpResponse}. */
export declare function httpCapability(fetchImpl?: FetchLike): HttpCapability;
/**
 * Per-run artifact storage — files a run produces that later steps (and
 * humans, via `GET /artifacts/:runId/…`) reference. The convention: a step
 * writes a file and puts its RELATIVE path in its output; downstream steps
 * resolve it through this capability (or point an `agent` step's `cwd` at
 * `dir(ctx.runId)` so the built-in file tools see the same files).
 *
 * Artifacts are retained after the run ends — they're part of the run's
 * record, not scratch space (`onRunEnd` does not touch them).
 */
export interface ArtifactsCapability {
    /** Absolute path of the run's artifact directory, created on demand. */
    dir(runId: string): Promise<string>;
    /** Write `content` at `relPath` under the run's dir (subdirectories are
     *  created). Returns the absolute path of the written file. */
    write(runId: string, relPath: string, content: string | Uint8Array): Promise<string>;
    /** Read the file at `relPath` under the run's dir, as bytes.
     *  (`Buffer.from(bytes).toString()` for text.) */
    read(runId: string, relPath: string): Promise<Uint8Array>;
    /** Relative paths of every file under the run's dir (recursive, sorted).
     *  `[]` when the run has no artifacts. */
    list(runId: string): Promise<string[]>;
}
/** Filesystem-backed artifacts capability rooted at `root`
 *  (`<root>/<runId>/<relPath>`). The default the standard server injects,
 *  rooted at `<workspace>/artifacts`. */
export declare function fileArtifactsCapability(root: string): ArtifactsCapability;
/** The standard capability shape adapters rely on. Consumers extend this with
 *  their own typed services (graph store, llm client, …). */
export interface StrutCapabilities {
    http: HttpCapability;
    secrets: SecretsCapability;
    /** Per-run artifact files. Present on the standard server (rooted in the
     *  workspace); optional because a bare in-code bag may not carry one. */
    artifacts?: ArtifactsCapability;
    /** Speech-to-text (src/audio). Present on the standard server; a step can
     *  transcribe through it without importing sherpa. Optional because a
     *  bare in-code bag may not carry one. */
    stt?: SttService;
}
/** The default standard services bag: global-fetch http + secrets. Secrets are
 *  env-backed by default; pass `secretStore` for a persisted (UI-managed) store
 *  with `process.env` as fallback. Injected by the standard server; override
 *  per environment as needed. */
export declare function standardServices(opts?: {
    fetchImpl?: FetchLike;
    secretsSource?: Record<string, string | undefined>;
    secretStore?: SecretReadable;
}): StrutCapabilities;
