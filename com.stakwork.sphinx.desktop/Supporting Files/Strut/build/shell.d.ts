/**
 * Shared child-process helpers for every place strut shells out (the agent
 * step's repo tools + bash, the chat builder's bash). One implementation so
 * timeout semantics, output capping, and — critically — env scrubbing are
 * identical everywhere.
 *
 * **Env scrubbing.** Children get a MINIMAL environment (`minimalEnv`), not
 * `process.env`: the strut server's env holds exactly the credentials the
 * secrets boundary exists to keep away from models (ANTHROPIC_API_KEY,
 * STRUT_SECRET_KEY, provider keys, …) — a naive spawn would hand them to any
 * model-authored `env`/`printenv` one-liner. Steps get credentials via
 * `ctx.services.secrets`, never ambient env, so scrubbing costs adapters
 * nothing.
 */
import { spawn } from "node:child_process";
/** The scrubbed child env: allowlisted vars from `process.env` only. */
export declare function minimalEnv(): NodeJS.ProcessEnv;
/** Spawn a child, capture stdout with a timeout + output cap. Exit 1 with no
 *  stderr → "No matches found" (grep/rg/find idiom). */
export declare function capture(child: ReturnType<typeof spawn>, timeoutMs: number, maxBytes: number): Promise<string>;
/** Run a program with explicit args (NO shell) — safe for untrusted args like a
 *  search query (no quoting/escaping/injection). Scrubbed env. */
export declare const runCmd: (cmd: string, args: string[], cwd: string, timeoutMs?: number, maxBytes?: number) => Promise<string>;
/** Run an arbitrary shell command string (the `bash` tools need a full shell).
 *  Scrubbed env — model-authored commands never see the server's API keys.
 *
 *  `extraEnv` is the ONE sanctioned widening of the scrubbed env: the agent
 *  step's `secretsEnv` config resolves named secrets via ctx.services.secrets
 *  and injects the VALUES here — into the subprocess env only, never into a
 *  prompt or log (the model writes `$NAME`; the shell expands it at exec
 *  time, and the agent step masks the values out of every tool output before
 *  the model or the event log sees them). Callers other than that path should
 *  not pass it. */
export declare const runShell: (command: string, cwd: string, timeoutMs?: number, maxBytes?: number, extraEnv?: Record<string, string>) => Promise<string>;
