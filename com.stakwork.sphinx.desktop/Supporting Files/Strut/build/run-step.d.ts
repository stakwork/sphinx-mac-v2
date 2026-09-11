import type { StepRegistry, RunEvent } from "./core.js";
import { type SubflowResolver } from "./runner.js";
import { type CassetteMode } from "./cassette.js";
/**
 * Run a SINGLE step in isolation — the tight inner loop for authoring adapters.
 *
 * Unlike a workflow run (detached, launch+tail), this is synchronous: it wraps
 * the step in an ad-hoc one-step flow, runs it to completion against an
 * in-memory store, and returns the output + events directly — so the chat agent
 * (or a developer) can author → run → fix without wiring anything into a
 * workflow.
 *
 * With `cassette`, external service calls go through the record/replay wrapper:
 *   - `record` — run live, capture every `ctx.services` call to the cassette
 *     file (secrets scrubbed), so the next iteration can…
 *   - `replay` — …serve those calls from the file: offline, deterministic, no
 *     rate limits, no cost, no side effects.
 */
export interface RunStepOptions {
    /** The step's config (same shape as a workflow step's `config`). Templates
     *  like `{{ input.* }}` / `{{ params.* }}` are resolved. */
    config?: Record<string, unknown>;
    /** Workflow input, referenced in config via `{{ input.* }}`. */
    input?: unknown;
    /** Params knobs, referenced via `{{ params.* }}`. */
    params?: Record<string, unknown>;
    /** Record/replay external service calls against a cassette file. */
    cassette?: {
        mode: CassetteMode;
        path: string;
    };
    /** Subflow resolver — only needed if the step itself is a `subflow`. */
    workspace?: SubflowResolver;
}
export interface RunStepResult {
    status: "success" | "error" | "cancelled";
    output?: unknown;
    error?: {
        message: string;
        stack?: string;
    };
    /** Every event the step emitted (start/end/error, plus nested for containers). */
    events: RunEvent[];
    /** Number of recorded service calls (present when a cassette was used). */
    recorded?: number;
}
export declare function runSingleStep(type: string, registry: StepRegistry, services: unknown, opts?: RunStepOptions): Promise<RunStepResult>;
/** Default on-disk location for a step's cassette, under the server's local
 *  data dir (`dataDir` — the workspace root for file-backed deployments). */
export declare function cassettePath(dataDir: string, name: string): string;
