/**
 * Resume journal (RUN_CONTROL_SPEC §5) — the event log already contains
 * everything a resume needs: every completed step's `step.end` carries its
 * `output`, keyed by a deterministic `path`. This module turns a run's
 * events into the `{ path → output }` journal `runWorkflow` replays from,
 * and implements the `from` invalidation ("re-run from this step", §5.2).
 */
/** Completed units: last `step.end` per path wins — a resumed log may carry
 *  a pre-failure entry AND a post-resume re-execution for the same path. */
export function buildJournal(events) {
    const journal = {};
    for (const event of events) {
        if (event.type === "step.end")
            journal[event.path] = event.output;
    }
    return journal;
}
/** The run's original input, params, and recorded workflow hash, from
 *  `run.start` — a durable resume re-invokes with exactly these. */
export function readRunStart(events) {
    const start = events.find((e) => e.type === "run.start");
    if (!start)
        return null;
    return {
        input: start.input,
        workflowHash: start.workflowHash,
        params: start.params,
        paramOverrides: start.paramOverrides,
        parentRunId: start.parentRunId,
    };
}
/**
 * §5.2 `from`: forced invalidation. Drop `from`'s own subtree, its ancestor
 * container entries (so containers re-execute and re-reach it), the later
 * iterations of any enclosing `loop` (sequential — they consumed its
 * output), and the transitive dependents of every step on the ancestor
 * chain at its own flow level. Everything left in the journal replays.
 */
export async function invalidateFrom(journal, from, entryFlow, resolver) {
    const kept = { ...journal };
    const dropped = new Set();
    const warnings = [];
    const dropExact = (key) => {
        if (key in kept) {
            delete kept[key];
            dropped.add(key);
        }
    };
    const dropSubtree = (prefix) => {
        for (const key of Object.keys(kept)) {
            if (key === prefix || key.startsWith(`${prefix}/`) || key.startsWith(`${prefix}#`)) {
                delete kept[key];
                dropped.add(key);
            }
        }
    };
    const prefix = `${entryFlow.name}/`;
    if (!from.startsWith(prefix)) {
        throw new Error(`from path "${from}" is not under workflow "${entryFlow.name}"`);
    }
    const segments = from.slice(prefix.length).split("/");
    // Walk the ancestor chain level by level. At each level we know the flow's
    // steps, so we can compute same-level transitive dependents; descending
    // requires resolving the container's child flow (subflow → its workflow;
    // foreach/loop → their body, which may itself be a subflow).
    let flow = entryFlow;
    let pathPrefix = entryFlow.name; // path up to (excluding) the current segment
    for (let level = 0; level < segments.length; level++) {
        const segment = segments[level];
        const hash = segment.indexOf("#");
        const stepId = hash >= 0 ? segment.slice(0, hash) : segment;
        const iteration = hash >= 0 ? Number(segment.slice(hash + 1)) : undefined;
        const segmentPath = `${pathPrefix}/${segment}`;
        const stepPath = `${pathPrefix}/${stepId}`;
        const isLast = level === segments.length - 1;
        if (!flow) {
            warnings.push(`could not resolve the flow at "${pathPrefix}" — dependents of "${segment}" at that level may replay stale outputs`);
            // Still drop the target subtree + remaining ancestor entries coarsely.
            dropExact(stepPath);
            if (!isLast) {
                dropExact(segmentPath);
                pathPrefix = segmentPath;
                continue;
            }
            dropSubtree(segmentPath);
            break;
        }
        const step = flow.steps.find((s) => s.id === stepId);
        if (!step) {
            throw new Error(`from path "${from}": step "${stepId}" not found in workflow "${flow.name}"`);
        }
        // Same-level transitive dependents of this ancestor: they consumed its
        // output, so they re-execute.
        for (const dep of transitiveDependents(flow.steps, stepId)) {
            dropSubtree(`${pathPrefix}/${dep}`);
        }
        // Enclosing `loop` iterations are SEQUENTIAL: later iterations consumed
        // this one's `$current`, so invalidating #i invalidates every #j > i.
        // (`foreach` iterations are independent — siblings replay.)
        if (iteration !== undefined && step.type === "loop") {
            for (const key of Object.keys(kept)) {
                const m = keyIteration(key, stepPath);
                if (m !== null && m > iteration)
                    dropSubtree(`${stepPath}#${m}`);
            }
        }
        if (isLast) {
            // The target itself: subtree (exact + iterations + descendants).
            dropSubtree(segmentPath);
            if (iteration !== undefined)
                dropExact(stepPath); // container entry too
            break;
        }
        // An ancestor container: drop its own completed entries (whole-step and,
        // when the path descends through an iteration, that iteration's entry) so
        // it re-executes down to the target — sibling iterations stay journaled.
        dropExact(stepPath);
        if (iteration !== undefined)
            dropExact(segmentPath);
        flow = await childFlowOf(step, resolver);
        pathPrefix = segmentPath;
    }
    return { journal: kept, dropped: [...dropped].sort(), warnings };
}
/** `#i` of `key` when it is exactly `<stepPath>#<i>` or a descendant of it. */
function keyIteration(key, stepPath) {
    if (!key.startsWith(`${stepPath}#`))
        return null;
    const rest = key.slice(stepPath.length + 1);
    const end = rest.search(/[/#]/);
    const n = Number(end === -1 ? rest : rest.slice(0, end));
    return Number.isInteger(n) ? n : null;
}
/** Transitive dependents of `stepId` under the runner's dependency
 *  semantics: explicit `depends`, or implicit previous-step. */
export function transitiveDependents(steps, stepId) {
    const depsOf = new Map();
    for (let i = 0; i < steps.length; i++) {
        const s = steps[i];
        depsOf.set(s.id, s.depends != null
            ? Array.isArray(s.depends)
                ? s.depends
                : [s.depends]
            : i > 0
                ? [steps[i - 1].id]
                : []);
    }
    const dependents = new Set();
    let grew = true;
    while (grew) {
        grew = false;
        for (const s of steps) {
            if (dependents.has(s.id) || s.id === stepId)
                continue;
            const deps = depsOf.get(s.id);
            if (deps.some((d) => d === stepId || dependents.has(d))) {
                dependents.add(s.id);
                grew = true;
            }
        }
    }
    return dependents;
}
/** Resolve the flow a path descends INTO through `step`: a subflow's target
 *  workflow, or a foreach/loop whose body is a subflow. Only statically
 *  named targets resolve (no `{{ }}`); anything else → null (the caller
 *  records a warning and degrades to coarse dropping). */
async function childFlowOf(step, resolver) {
    let target = step;
    if (step.type === "foreach" || step.type === "loop") {
        const body = step.config["body"];
        if (!body || body.type !== "subflow")
            return null;
        target = body;
    }
    if (target.type !== "subflow" || !resolver)
        return null;
    const name = target.config["workflow"];
    const version = target.config["version"];
    if (typeof name !== "string" || name.includes("{{"))
        return null;
    try {
        return typeof version === "string" && !version.includes("{{")
            ? await resolver.getWorkflowVersion(name, version)
            : await resolver.getWorkflow(name);
    }
    catch {
        return null;
    }
}
//# sourceMappingURL=journal.js.map