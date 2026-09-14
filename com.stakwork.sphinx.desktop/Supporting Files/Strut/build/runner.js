import { resolveConfig } from "./expr.js";
import { MemoryRunStore, generateRunId } from "./store.js";
import { isCancelledError } from "./run-control.js";
/** Sentinel returned by steps that were skipped because their `when` didn't match. */
const SKIP = Symbol("strut.skip");
function isSkipped(v) {
    return v === SKIP;
}
/** Flatten an Error's `cause` chain into one readable string (`""` when there
 *  is none). Transport failures hide their real diagnosis down this chain —
 *  the thrown message is a bare "terminated" while the socket-level reason
 *  sits on the cause — so an onError step that only sees `message` is blind to
 *  why it failed. Cycle-safe and depth-capped: causes are arbitrary values. */
function causeChain(err) {
    const parts = [];
    const seen = new Set();
    let c = err.cause;
    while (c && !seen.has(c) && parts.length < 5) {
        seen.add(c);
        const e = c;
        const code = e.code ? `${String(e.code)}: ` : "";
        parts.push(`${code}${String(e.message ?? c)}`);
        c = e.cause;
    }
    return parts.join(" <- ");
}
export async function runWorkflow(workflow, input, registry, opts) {
    const runId = opts?.runId ?? generateRunId();
    const store = opts?.store ?? new MemoryRunStore();
    const wfName = workflow.name;
    const startedAt = new Date().toISOString();
    // Default services to an empty object so steps can destructure freely.
    const services = (opts?.services ?? {});
    const onEvent = opts?.onEvent;
    const emit = async (event) => {
        const full = {
            ts: new Date().toISOString(),
            runId,
            path: event.path ?? wfName,
            ...event,
        };
        await store.append(wfName, runId, full);
        await onEvent?.(full);
    };
    // Validate input
    let parsedInput;
    try {
        parsedInput = workflow.input.parse(input);
    }
    catch (err) {
        const error = {
            message: `Input validation failed: ${err instanceof Error ? err.message : String(err)}`,
            stack: err instanceof Error ? err.stack : undefined,
        };
        await emit({ type: "run.error", path: wfName, error });
        const finishedAt = new Date().toISOString();
        await store.finalize(wfName, runId, {
            runId,
            workflow: wfName,
            startedAt,
            finishedAt,
            durationMs: Date.parse(finishedAt) - Date.parse(startedAt),
            status: "error",
            input,
            error,
        });
        return { runId, status: "error", error };
    }
    if (opts?.resume) {
        // Continuing an interrupted run: same runId, same log — the marker both
        // records the gap and reopens tails past an earlier terminal event.
        await emit({ type: "run.resumed", path: wfName });
    }
    else {
        await emit({
            type: "run.start",
            path: wfName,
            input: parsedInput,
            ...(opts?.workflowHash ? { workflowHash: opts.workflowHash } : {}),
            // Tree linkage on disk: a nested run names its parent so boot-time
            // auto-resume can tell roots from children (§5.3).
            ...(opts?.controller?.parent ? { parentRunId: opts.controller.parent.runId } : {}),
            // Recorded so a durable resume re-executes with the same knob values.
            ...(opts?.params ? { params: opts.params } : {}),
            ...(opts?.paramOverrides ? { paramOverrides: opts.paramOverrides } : {}),
        });
    }
    const exec = {
        registry,
        runId,
        emit,
        workspace: opts?.workspace,
        services,
        paramOverrides: opts?.paramOverrides,
        controller: opts?.controller,
        journal: opts?.journal,
    };
    try {
        const output = await executeFlow(workflow, parsedInput, exec, wfName, opts?.params);
        const finishedAt = new Date().toISOString();
        await emit({ type: "run.end", path: wfName, output });
        await store.finalize(wfName, runId, {
            runId,
            workflow: wfName,
            startedAt,
            finishedAt,
            durationMs: Date.parse(finishedAt) - Date.parse(startedAt),
            status: "success",
            input: parsedInput,
            output,
        });
        return { runId, status: "success", output };
    }
    catch (err) {
        const cancelled = isCancelledError(err);
        const error = {
            message: err instanceof Error ? err.message : String(err),
            stack: err instanceof Error ? err.stack : undefined,
        };
        const finishedAt = new Date().toISOString();
        // Cancellation is a DISTINCT outcome, never conflated with error
        // (RUN_CONTROL_SPEC §3): the run finalizes honestly as `cancelled`, its
        // partial outputs stay inspectable in the log, and it is never "stale".
        await emit(cancelled
            ? { type: "run.cancelled", path: wfName }
            : { type: "run.error", path: wfName, error });
        await store.finalize(wfName, runId, {
            runId,
            workflow: wfName,
            startedAt,
            finishedAt,
            durationMs: Date.parse(finishedAt) - Date.parse(startedAt),
            status: cancelled ? "cancelled" : "error",
            input: parsedInput,
            ...(cancelled ? {} : { error }),
        });
        return cancelled ? { runId, status: "cancelled" } : { runId, status: "error", error };
    }
    finally {
        // Generic per-run teardown hook. A consumer's services bag may implement
        // `onRunEnd(runId)` to dispose any per-run resources it allocated during the
        // run (e.g. the lab's headless browser + booted docker stack, keyed by
        // runId). Runs in a `finally` so it fires on BOTH success and error, for
        // EVERY run path (detached launch, in-process `optimizer.run`, tests) —
        // `runWorkflow` is the single choke point, and nested subflows reuse the
        // parent runId so it fires once per top-level run. The runner stays generic:
        // it never names what gets disposed. Guarded so a teardown failure can't mask
        // the run's real result. (Hard kills (SIGKILL) still skip this — identical to
        // any in-process `finally`; that case is handled out-of-band.)
        try {
            await services?.onRunEnd?.(runId);
        }
        catch (teardownErr) {
            console.error(`[runner] onRunEnd hook failed for run ${runId}:`, teardownErr);
        }
    }
}
/**
 * Get the dependency list for a step. If `depends` is set, use it.
 * Otherwise, the step implicitly depends on the previous step in the array
 * (sequential by default).
 */
function getDeps(step, index, steps) {
    if (step.depends != null) {
        return Array.isArray(step.depends) ? step.depends : [step.depends];
    }
    // Implicit: depends on previous step (if any)
    if (index > 0)
        return [steps[index - 1].id];
    return [];
}
async function executeFlow(workflow, input, exec, basePath, paramsOverride) {
    // `params` = workflow defaults, shallow-merged with per-run overrides.
    // Exposed to step configs via `{{ params.* }}`. Distinct from `input`.
    //   - `paramOverrides[workflow.name]` applies at every level (entry + nested).
    //   - `paramsOverride` (flat) is only passed for the entry flow.
    // Precedence: flow defaults < keyed override < entry flat override.
    const params = {
        ...(workflow.params ?? {}),
        ...(exec.paramOverrides?.[workflow.name] ?? {}),
        ...(paramsOverride ?? {}),
    };
    const scope = { input, params };
    const steps = workflow.steps;
    if (steps.length === 0)
        return undefined;
    // Build dependency graph
    const depMap = new Map();
    const stepById = new Map();
    for (let i = 0; i < steps.length; i++) {
        const s = steps[i];
        stepById.set(s.id, s);
        depMap.set(s.id, getDeps(s, i, steps));
    }
    // Track completion
    const completed = new Set();
    // Each pending promise resolves with the step's output (or SKIP if skipped),
    // or REJECTS when the step failed — so dependents settle (fail fast) instead
    // of hanging, letting the flow wait for every in-flight branch before it
    // reports its outcome (required for honest cancel/error finalization: no
    // step events land after the terminal event).
    const pending = new Map();
    for (const s of steps) {
        let resolve;
        let reject;
        const promise = new Promise((res, rej) => {
            resolve = res;
            reject = rej;
        });
        // A rejected step promise with no dependents must not surface as an
        // unhandled rejection — the error still propagates via runStep's throw.
        promise.catch(() => { });
        pending.set(s.id, { resolve, reject, promise });
    }
    // Execute a single step once its deps are met
    async function runStep(s) {
        try {
            // Wait for all dependencies, collecting their outputs
            const deps = depMap.get(s.id) ?? [];
            const depOutputs = await Promise.all(deps.map((d) => pending.get(d)?.promise ?? Promise.resolve(undefined)));
            // Skip propagation: if this step has deps and ALL of them were skipped,
            // skip this step too (no useful inputs available).
            // A step with at least one real dep still runs — fan-in pattern.
            // Steps with `when` use gate logic below regardless.
            const hasGate = s.when != null;
            if (deps.length > 0 && !hasGate) {
                const allSkipped = depOutputs.every(isSkipped);
                if (allSkipped) {
                    scope[s.id] = undefined;
                    await exec.emit({
                        type: "step.skipped",
                        path: `${basePath}/${s.id}`,
                        stepType: s.type,
                    });
                    pending.get(s.id).resolve(SKIP);
                    return;
                }
            }
            // Gate check: if `when` is set, find the gate dependency (the one whose
            // boolean output matters). The gate is the dep whose output is boolean —
            // but more precisely, we check ALL non-skipped deps for a boolean that
            // matches `when`. If any boolean dep doesn't match, skip.
            if (hasGate) {
                // Find boolean deps (these are gates) and verify at least one matches.
                // A skipped dep can never satisfy a gate (the gate didn't run).
                let matched = false;
                let sawGate = false;
                for (let i = 0; i < deps.length; i++) {
                    const out = depOutputs[i];
                    if (isSkipped(out))
                        continue;
                    if (typeof out === "boolean") {
                        sawGate = true;
                        if (out === s.when) {
                            matched = true;
                            break;
                        }
                    }
                }
                if (!sawGate || !matched) {
                    // Either no gate ran, or its value doesn't match `when` → skip
                    scope[s.id] = undefined;
                    await exec.emit({
                        type: "step.skipped",
                        path: `${basePath}/${s.id}`,
                        stepType: s.type,
                    });
                    pending.get(s.id).resolve(SKIP);
                    return;
                }
            }
            // Cooperative boundary: between DAG steps (RUN_CONTROL_SPEC §2.1).
            // Blocks while paused; throws CancelledError while cancelling.
            await exec.controller?.checkpoint();
            const stepPath = `${basePath}/${s.id}`;
            const output = await executeStep(s, scope, exec, stepPath);
            scope[s.id] = output;
            completed.add(s.id);
            pending.get(s.id).resolve(output);
        }
        catch (err) {
            pending.get(s.id).reject(err);
            throw err;
        }
    }
    // Launch all steps — each waits for its own deps internally. allSettled (not
    // all) so a failing/cancelled branch doesn't abandon still-executing
    // branches mid-unit: every branch settles (its in-flight unit completes and
    // journals) before the flow reports its outcome.
    const settled = await Promise.allSettled(steps.map((s) => runStep(s)));
    const rejections = settled.filter((r) => r.status === "rejected");
    if (rejections.length > 0) {
        // Prefer a REAL failure over a CancelledError so a genuine error isn't
        // masked when cancellation raced in behind it.
        const real = rejections.find((r) => !isCancelledError(r.reason));
        throw (real ?? rejections[0]).reason;
    }
    // Return last step's output (by array order). If skipped, return undefined.
    const lastOut = scope[steps[steps.length - 1].id];
    return isSkipped(lastOut) ? undefined : lastOut;
}
// ── Internal: execute a single step with retry/onError ─────────────────────
// Control flow steps that manage their own template resolution.
const SELF_RESOLVING_STEPS = new Set(["loop", "foreach", "subflow"]);
const hasOwn = (obj, key) => Object.prototype.hasOwnProperty.call(obj, key);
/** The slice of the resume journal that belongs to one step's own synthetic
 *  iteration events (`<path>#…`) — what a step sees as `ctx.journal`. */
function sliceJournal(journal, path) {
    if (!journal)
        return undefined;
    const prefix = `${path}#`;
    let out;
    for (const key of Object.keys(journal)) {
        if (key.startsWith(prefix))
            (out ??= {})[key] = journal[key];
    }
    return out;
}
async function executeStep(step, scope, exec, path) {
    // Resume replay (RUN_CONTROL_SPEC §5): a step whose path has a journaled
    // output replays it — zero cost, no side effects re-executed. Emitted as
    // `step.replayed`, never a fake `step.end` (honest timings). The first path
    // NOT in the journal executes live below.
    if (exec.journal && hasOwn(exec.journal, path)) {
        const output = exec.journal[path];
        await exec.emit({ type: "step.replayed", path, stepType: step.type, output });
        return output;
    }
    const maxRetries = step.options?.retry?.max ?? 0;
    const retryDelay = step.options?.retry?.delayMs ?? 0;
    let lastError;
    for (let attempt = 0; attempt <= maxRetries; attempt++) {
        try {
            if (attempt > 0) {
                await exec.emit({
                    type: "step.retry",
                    path,
                    stepType: step.type,
                    iteration: attempt,
                });
                await sleep(retryDelay);
                // Cooperative boundary: between retry attempts (§2.1).
                await exec.controller?.checkpoint();
            }
            const startTime = Date.now();
            // Control flow steps handle their own config resolution
            // (e.g. loop needs to re-resolve `until` each iteration,
            //  and may reference $current which doesn't exist yet).
            const resolvedConfig = SELF_RESOLVING_STEPS.has(step.type)
                ? step.config
                : resolveConfig(step.config, scope);
            // Container steps don't have a scalar config-as-input, but they DO have
            // a meaningful "summary" input: a subflow's input is what it passes to
            // the child workflow; a foreach's input is the array it iterates. Emit
            // that so the run flyout shows the left column (items / child input).
            // (`loop` repeats until a condition — no natural input.)
            const startInput = SELF_RESOLVING_STEPS.has(step.type)
                ? step.type === "subflow"
                    ? resolveConfig(step.config["input"], scope)
                    : step.type === "foreach"
                        ? resolveConfig(step.config["items"], scope)
                        : undefined
                : resolvedConfig;
            await exec.emit({
                type: "step.start",
                path,
                stepType: step.type,
                input: startInput,
            });
            // Execute based on step type
            const output = await dispatchStep(step, resolvedConfig, scope, exec, path);
            const durationMs = Date.now() - startTime;
            await exec.emit({
                type: "step.end",
                path,
                stepType: step.type,
                output,
                durationMs,
            });
            return output;
        }
        catch (err) {
            // Cancellation is NOT the error path (§3): never retried, never
            // diverted into onError — the branch stops at this boundary.
            if (isCancelledError(err))
                throw err;
            lastError = err instanceof Error ? err : new Error(String(err));
            if (attempt === maxRetries) {
                // All retries exhausted
                if (step.options?.onError) {
                    // Run fallback step
                    const errorScope = {
                        ...scope,
                        // `cause` carries the diagnosis for wrapped failures — a severed
                        // stream surfaces as a bare "terminated" whose underlying socket
                        // reason (ECONNRESET, body timeout, …) lives only on the cause.
                        // Flattened to a string so an onError step can log or persist it.
                        $error: {
                            message: lastError.message,
                            stack: lastError.stack,
                            cause: causeChain(lastError),
                        },
                    };
                    try {
                        const fallbackOutput = await executeStep(step.options.onError, errorScope, exec, `${path}/onError`);
                        return fallbackOutput;
                    }
                    catch (fallbackErr) {
                        // Fallback itself failed
                        await exec.emit({
                            type: "step.error",
                            path,
                            stepType: step.type,
                            error: {
                                message: lastError.message,
                                stack: lastError.stack,
                            },
                        });
                        throw fallbackErr;
                    }
                }
                await exec.emit({
                    type: "step.error",
                    path,
                    stepType: step.type,
                    error: {
                        message: lastError.message,
                        stack: lastError.stack,
                    },
                });
                throw lastError;
            }
        }
    }
    // Should not reach here
    throw lastError ?? new Error("Unknown error");
}
// ── Internal: dispatch to the correct step handler ─────────────────────────
async function dispatchStep(step, resolvedConfig, scope, exec, path) {
    // Handle core control flow steps specially
    switch (step.type) {
        case "loop":
            return executeLoop(step, scope, exec, path);
        case "foreach":
            return executeForeach(step, scope, exec, path);
        case "subflow":
            return executeSubflow(step, scope, exec, path);
        default: {
            // Look up in registry
            const def = exec.registry[step.type];
            if (!def) {
                throw new Error(`Unknown step type: "${step.type}"`);
            }
            // Validate config against step's input schema.
            // Default to {} when no config is provided in the YAML.
            const validConfig = def.input.parse(resolvedConfig ?? {});
            const stepJournal = sliceJournal(exec.journal, path);
            const ctx = {
                runId: exec.runId,
                path,
                scope,
                input: scope["input"],
                emit: exec.emit,
                services: exec.services,
                registry: exec.registry,
                // Unit-scoped control: a parked `ctx.control.checkpoint()` releases
                // this unit so the subtree can quiesce (§2.2 threading).
                ...(exec.controller ? { control: exec.controller.forUnit() } : {}),
                ...(stepJournal ? { journal: stepJournal } : {}),
            };
            if (exec.controller) {
                // checkpoint → beginUnit with no interleaving await, so a pause can
                // never observe a false quiesce between the two.
                await exec.controller.checkpoint();
                exec.controller.beginUnit();
            }
            try {
                return await def.run(validConfig, ctx);
            }
            finally {
                exec.controller?.endUnit();
            }
        }
    }
}
// ── Control flow implementations ───────────────────────────────────────────
async function executeLoop(step, scope, exec, path) {
    // Resolve scalar config values (but not `until` or `body` which need per-iteration resolution)
    const maxIterations = resolveConfig(step.config["maxIterations"], scope);
    const delayMs = resolveConfig(step.config["delayMs"], scope) ?? 0;
    const untilExpr = step.config["until"]; // raw template, re-evaluated each iteration
    // Use the raw (unresolved) body step — we re-resolve its config each iteration
    const rawBody = step.config["body"];
    let current = undefined;
    for (let i = 0; i < maxIterations; i++) {
        // Cooperative boundary: between loop iterations (§2.1).
        await exec.controller?.checkpoint();
        const iterPath = `${path}#${i}`;
        // Resume replay of a completed iteration (§5): the `until` condition is
        // still re-evaluated against the replayed `$current`, reconstructing the
        // loop's original control flow.
        if (exec.journal && hasOwn(exec.journal, iterPath)) {
            current = exec.journal[iterPath];
            await exec.emit({
                type: "step.replayed",
                path: iterPath,
                stepType: rawBody.type,
                output: current,
                iteration: i,
            });
            const done = resolveConfig(untilExpr, { ...scope, $current: current });
            if (done)
                return current;
            continue;
        }
        // Make $current available in scope for template resolution
        const iterScope = { ...scope, $current: current };
        // Resolve the body step's config with this iteration's scope
        const resolvedBodyConfig = resolveConfig(rawBody.config, iterScope);
        await exec.emit({
            type: "step.start",
            path: iterPath,
            stepType: rawBody.type,
            iteration: i,
            input: resolvedBodyConfig,
        });
        const startTime = Date.now();
        current = await dispatchStep(rawBody, resolvedBodyConfig, iterScope, exec, iterPath);
        await exec.emit({
            type: "step.end",
            path: iterPath,
            stepType: rawBody.type,
            output: current,
            durationMs: Date.now() - startTime,
            iteration: i,
        });
        if (delayMs > 0 && i < maxIterations - 1) {
            await sleep(delayMs);
        }
        // Evaluate the `until` condition with updated $current
        const untilScope = { ...scope, $current: current };
        const done = resolveConfig(untilExpr, untilScope);
        if (done)
            return current;
    }
    throw new Error(`Loop "${step.id}" exceeded maxIterations (${maxIterations}) without until becoming true`);
}
/**
 * Execute a `foreach` step: resolve `items` to an array, run `body` once
 * per item, and return the collected outputs as an array (in input order).
 *
 * Per-iteration scope exposes:
 *   - `$current` — the current item
 *   - `$index`   — the zero-based position
 *
 * Body config is re-resolved each iteration so templates referencing
 * `$current` / `$index` see the right values.
 *
 * `concurrency: N` (default 1) runs up to N iterations at once through a
 * bounded worker pool. Results stay in input order, each iteration keeps its
 * own `#i` event path (so journal replay and per-iteration inspection are
 * unchanged), and the cooperative checkpoint moves to just before each
 * iteration STARTS — pause parks new starts while in-flight iterations
 * drain, cancel stops the pool at the same boundary. The practical ceiling
 * is usually the targets the body talks to (rate limits), not CPU — set it
 * per call site, low.
 */
async function executeForeach(step, scope, exec, path) {
    // Resolve `items` once against the parent scope. A non-negative integer N
    // means "iterate 0..N-1" ($current = $index) — the range form the template
    // language deliberately cannot construct (e.g. `items: {{ params.samples }}`
    // to repeat a body a parameterized number of times).
    const itemsResolved = resolveConfig(step.config["items"], scope);
    if (!Array.isArray(itemsResolved) &&
        !(typeof itemsResolved === "number" && Number.isInteger(itemsResolved) && itemsResolved >= 0)) {
        throw new Error(`foreach step "${step.id}" requires "items" to resolve to an array or a non-negative integer, got ${itemsResolved === null
            ? "null"
            : typeof itemsResolved === "object"
                ? "object"
                : typeof itemsResolved === "number"
                    ? `number (${itemsResolved})`
                    : typeof itemsResolved}`);
    }
    const items = Array.isArray(itemsResolved)
        ? itemsResolved
        : Array.from({ length: itemsResolved }, (_, i) => i);
    const maxIterations = step.config["maxIterations"] != null
        ? resolveConfig(step.config["maxIterations"], scope)
        : undefined;
    if (maxIterations !== undefined && items.length > maxIterations) {
        throw new Error(`foreach step "${step.id}" received ${items.length} items, which exceeds maxIterations (${maxIterations})`);
    }
    const rawBody = step.config["body"];
    if (!rawBody || typeof rawBody !== "object" || !rawBody.type) {
        throw new Error(`foreach step "${step.id}" requires a "body" step`);
    }
    const concurrencyRaw = step.config["concurrency"] != null
        ? resolveConfig(step.config["concurrency"], scope)
        : 1;
    const concurrency = Math.max(1, Math.floor(Number(concurrencyRaw) || 1));
    const results = new Array(items.length);
    const runIteration = async (i) => {
        // Cooperative boundary: before each iteration STARTS (§2.1) — under a
        // pool, pause parks new starts while in-flight iterations drain.
        await exec.controller?.checkpoint();
        const iterPath = `${path}#${i}`;
        // Resume replay of a completed iteration (§5): a failed iteration re-runs
        // alone — completed ones replay by their `#i` paths.
        if (exec.journal && hasOwn(exec.journal, iterPath)) {
            const output = exec.journal[iterPath];
            await exec.emit({
                type: "step.replayed",
                path: iterPath,
                stepType: rawBody.type,
                output,
                iteration: i,
            });
            results[i] = output;
            return;
        }
        const iterScope = { ...scope, $current: items[i], $index: i };
        const resolvedBodyConfig = resolveConfig(rawBody.config, iterScope);
        await exec.emit({
            type: "step.start",
            path: iterPath,
            stepType: rawBody.type,
            iteration: i,
            input: resolvedBodyConfig,
        });
        const startTime = Date.now();
        const output = await dispatchStep(rawBody, resolvedBodyConfig, iterScope, exec, iterPath);
        await exec.emit({
            type: "step.end",
            path: iterPath,
            stepType: rawBody.type,
            output,
            durationMs: Date.now() - startTime,
            iteration: i,
        });
        results[i] = output;
    };
    if (concurrency === 1) {
        for (let i = 0; i < items.length; i++) {
            await runIteration(i);
        }
        return results;
    }
    // Bounded pool: workers pull the next index off a shared cursor. On the
    // first failure no NEW iterations start; in-flight ones finish (they are
    // mid-spend and aborting a body mid-step isn't supported), then the error
    // that would have surfaced first sequentially — the lowest-index one —
    // propagates. A cancellation always wins over an ordinary error so the run
    // finalizes as cancelled, never as error (RUN_CONTROL_SPEC §3).
    let cursor = 0;
    const failures = [];
    const worker = async () => {
        while (failures.length === 0) {
            const i = cursor++;
            if (i >= items.length)
                return;
            try {
                await runIteration(i);
            }
            catch (err) {
                failures.push({ i, err });
                return;
            }
        }
    };
    await Promise.all(Array.from({ length: Math.min(concurrency, items.length) }, () => worker()));
    if (failures.length > 0) {
        const cancelled = failures.find((f) => isCancelledError(f.err));
        if (cancelled)
            throw cancelled.err;
        failures.sort((a, b) => a.i - b.i);
        throw failures[0].err;
    }
    return results;
}
async function executeSubflow(step, scope, exec, path) {
    // Resolve workflow name, version, and input from parent scope
    const wfName = resolveConfig(step.config["workflow"], scope);
    const version = step.config["version"] != null
        ? resolveConfig(step.config["version"], scope)
        : undefined;
    const childInput = resolveConfig(step.config["input"], scope);
    if (!wfName || typeof wfName !== "string") {
        throw new Error(`subflow step "${step.id}" requires a "workflow" config (workflow name)`);
    }
    if (!exec.workspace) {
        throw new Error(`subflow step "${step.id}" references workflow "${wfName}" but no workspace was provided to runWorkflow`);
    }
    const childFlow = version
        ? await exec.workspace.getWorkflowVersion(wfName, version)
        : await exec.workspace.getWorkflow(wfName);
    // Validate child flow input against its schema
    const validatedInput = childFlow.input.parse(childInput);
    // Thread `paramOverrides` (but NOT the entry-only flat `paramsOverride`) into
    // the child so a keyed override can reach knobs that live in this subflow.
    return executeFlow(childFlow, validatedInput, exec, path);
}
// ── Utilities ──────────────────────────────────────────────────────────────
function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}
//# sourceMappingURL=runner.js.map