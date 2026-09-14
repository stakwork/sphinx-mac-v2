/**
 * Record / replay for the services bag — the "safe inner loop" that lets the
 * AI chat author an adapter and hammer on it OFFLINE: record once against the
 * real world, then iterate against the recording (deterministic, no rate
 * limits, no cost, no side effects).
 *
 * It works by wrapping the services bag (the seam every adapter already goes
 * through — see `capabilities.ts`). In `record` mode each service call is run
 * for real and its `(key, args) → result` captured; in `replay` mode the call
 * is served from the recording by matching `(key, args)` instead of hitting the
 * real service.
 *
 * **Secret hygiene.** Secrets enter through one boundary (`services.secrets`).
 * The wrapper canonicalizes every secret VALUE to a stable token
 * (`{{secret:NAME}}`) before anything is written to — or matched against — the
 * cassette, so real keys never reach disk, and record↔replay still match even
 * though replay has no real credentials.
 */
/** One recorded service call. `args`/`result` are post-redaction (secret-safe). */
export interface CassetteEntry {
    /** `"<service>.<method>"`, or just `"<service>"` for a callable service. */
    key: string;
    args: unknown[];
    result?: unknown;
    /** Present instead of `result` when the recorded call threw. */
    error?: string;
}
export interface Cassette {
    entries: CassetteEntry[];
}
export type CassetteMode = "record" | "replay";
export interface WithCassetteOptions {
    mode: CassetteMode;
    /** In `record` mode, entries are appended here. In `replay` mode, calls are
     *  matched against these entries. */
    cassette: Cassette;
    /** Name of the service treated as the secrets boundary (its return values are
     *  canonicalized to tokens and scrubbed from the cassette). Default
     *  `"secrets"`; pass `null` to disable secret handling. */
    secretsService?: string | null;
}
export declare function emptyCassette(): Cassette;
/**
 * Wrap a services bag with record/replay. Returns a structurally-identical bag
 * (same call sites in adapter code) backed by the cassette per `mode`.
 */
export declare function withCassette<TServices extends Record<string, unknown>>(services: TServices, opts: WithCassetteOptions): TServices;
/** Load a cassette from disk, or an empty one if the file doesn't exist. */
export declare function loadCassette(path: string): Promise<Cassette>;
/** Persist a cassette to disk (pretty JSON, creating parent dirs). */
export declare function saveCassette(path: string, cassette: Cassette): Promise<void>;
