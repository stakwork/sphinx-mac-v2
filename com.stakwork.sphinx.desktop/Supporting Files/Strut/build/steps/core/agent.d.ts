import { z } from "zod";
import { type StepContext, type StepRegistry } from "../../core.js";
/**
 * Adaptive directory tree: always show the root (depth 1, every top-level dir +
 * file), then iteratively deepen — try depth 2, 3, … — keeping the deepest
 * rendering that stays under `maxLines`, and stepping back one when a depth busts
 * the budget. Noise dirs (build/deps/generated) are collapsed at every depth.
 * Pure + git-free so it's unit-testable. Returns the chosen text + depth.
 */
export declare function repoTree(files: string[], opts?: {
    maxLines?: number;
    maxDepth?: number;
}): {
    text: string;
    depth: number;
};
/** The Anthropic text-editor tool's input shape (also used by the generic
 *  fallback for non-anthropic providers). All commands operate on a path that
 *  MUST resolve inside `cwd`. */
export interface TextEditInput {
    command: "view" | "create" | "str_replace" | "insert";
    path: string;
    file_text?: string;
    insert_line?: number;
    new_str?: string;
    insert_text?: string;
    old_str?: string;
    view_range?: number[];
}
/**
 * Pure handler for the str_replace-based text editor tool: view / create /
 * str_replace / insert, sandboxed to `cwd`. Mirrors Anthropic's tool contract
 * (1-indexed line numbers, exactly-one-match str_replace, `insert_line` 0 =
 * top-of-file) so it backs both the provider-defined anthropic tool and the
 * generic fallback. Returns a human-readable string (errors as `Error: …`).
 */
export declare function textEdit(input: TextEditInput, roots: string | string[]): string;
/**
 * Expand `agentTools` entries against the registry: a name containing `*` is a
 * glob over registry step types (e.g. `"jarvis/*"` → every jarvis step), so a
 * whole namespace can be granted in one entry and new steps in it are picked
 * up automatically. Plain names pass through untouched (unknown ones still
 * warn in the tool-build loop). Duplicates collapse (first occurrence wins);
 * glob matches are sorted for a stable tool order.
 */
export declare function expandAgentTools(names: string[], registry: StepRegistry): string[];
/**
 * Classify how a finalAnswer-mode tool loop ended. The AI SDK loop stops on
 * ANY turn with no tool call — including a mid-task narration ("now let's
 * copy this…"), observed live losing a 62-minute research session whose
 * deliverable needed two more tool calls.
 *  - "done"      — final_answer was called; nothing to salvage.
 *  - "nudge"     — stopped tool-lessly WITH budget remaining: resume the real
 *                  tool loop once (it can still finish file work), telling the
 *                  model to continue or call final_answer.
 *  - "exhausted" — the step budget is spent: only a no-tools forced answer
 *                  turn is possible.
 */
export declare function classifyFinalAnswerStop(finalFound: boolean, stepsUsed: number, maxSteps: number): "done" | "nudge" | "exhausted";
export declare function degenerateSchemaFields(schema: unknown, output: unknown): string[];
/**
 * Distinguishes a mid-stream CONNECTION death from a real API failure.
 *
 * Once the response headers are in, the SDK's own request-level retry is out
 * of the picture — if the body stream then dies (undici raises a bare
 * `TypeError: terminated`), every result promise on the stream rejects, so an
 * unguarded loop discards the entire session. Observed live: a 34-tool-call
 * case-law research step lost ~12 minutes in when its streaming response
 * socket dropped.
 *
 * Only connection-level faults are resumable. Auth failures, 400s, and schema
 * errors are deterministic — retrying them just burns the budget, so they must
 * still throw. Aborts are excluded deliberately: a paused or cancelled run
 * surfaces as an abort, and resuming one would defeat run control.
 */
export declare function isTransientStreamError(err: unknown): boolean;
/**
 * Turn a list of registry step-types into AI-SDK tools the agent can call — the
 * "tools ARE steps" model. Each step's `input` Zod schema becomes the tool's
 * input schema and its `run` is the executor (validated against that schema).
 *
 * Does NOT emit run events itself — `wrapToolsWithEmit` does that uniformly for
 * built-ins AND registry tools, so there's a single shared call counter and one
 * code path. Pure + offline-testable (inject the `tool` factory + a fake
 * registry; no model/network). Unknown step-types are skipped. Returns a record
 * keyed by the sanitized tool name.
 */
export declare function buildRegistryTools(names: string[] | undefined, registry: StepRegistry | undefined, ctx: StepContext | undefined, toolFactory: (def: any) => unknown): Record<string, unknown>;
/**
 * Wrap EVERY tool's `execute` (built-ins + agentTools) so each call emits a
 * nested `step.start`/`step.end` (or `step.error`) run event at
 * `<agentPath>/NNN-<tool>` with `stepType: "tool:<name>"`. A single shared
 * counter (`NNN`) gives the calls a globally-ordered, sortable path — that's
 * what makes the otherwise-opaque agent loop visible in the events panel / run
 * drill-down. Mutates `tools` in place.
 *
 * No-op when there's no runner ctx (in-code/test) or no path. Skips
 * `final_answer` (terminal, noisy) and any tool with no function `execute`
 * (provider-executed tools like anthropic `web_search`). Output is truncated in
 * the event only (the model still sees the full result) — except the
 * provenance marker: a result marked with `withAccessedNodes` gets its node
 * refs lifted verbatim onto the `step.end` event as `nodes`, the one part of
 * tool output that must survive into the log untruncated because it is data
 * for the graph projector (`ACCESSED` edges), not a preview for humans.
 */
/** Replace every occurrence of each secret value in `text` with a marker.
 *  Plain string splitting (no regex) — values are opaque tokens. */
export declare function maskSecretValues(text: string, values: string[]): string;
/** Recursively mask secret values in every string leaf of a tool result.
 *  Tool outputs are JSON-ish (they get persisted to run events), so a plain
 *  object/array/primitive walk covers them. */
export declare function maskDeep(value: unknown, values: string[]): unknown;
/**
 * Wrap every tool's `execute` so its RESULT is masked before the model (and
 * the event log — this runs inside `wrapToolsWithEmit`'s wrapping) sees it.
 * The complement to `secretsEnv`: values reach the bash SUBPROCESS, and this
 * guarantees they never travel back into the model's context via any tool
 * output — `echo $KEY`, `env`, a curl error echoing the URL, or a file the
 * shell wrote and the editor tool later views. Mutates `tools` in place.
 *
 * What it cannot do: stop the shell itself from SENDING `$KEY` somewhere
 * (egress under prompt injection). That residual is accepted and documented
 * (EVOLVE_SPEC §4.4) — grant secretsEnv only to narrow research agents.
 */
export declare function wrapToolsWithMask(tools: Record<string, any>, secretValues: string[]): void;
export declare function wrapToolsWithEmit(tools: Record<string, any>, ctx: StepContext | undefined): void;
declare const _default: import("../../core.js").StepDef<"agent", z.ZodObject<{
    cwd: z.ZodString;
    system: z.ZodString;
    prompt: z.ZodString;
    finalAnswer: z.ZodOptional<z.ZodString>;
    schema: z.ZodOptional<z.ZodAny>;
    toolFilter: z.ZodDefault<z.ZodArray<z.ZodString>>;
    agentTools: z.ZodDefault<z.ZodArray<z.ZodString>>;
    secretsEnv: z.ZodDefault<z.ZodArray<z.ZodString>>;
    model: z.ZodOptional<z.ZodString>;
    provider: z.ZodOptional<z.ZodString>;
    maxSteps: z.ZodDefault<z.ZodNumber>;
    returnMessages: z.ZodDefault<z.ZodBoolean>;
}, z.core.$strip>, z.ZodAny, unknown>;
export default _default;
