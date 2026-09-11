/**
 * Static validation of workflow YAML — the chat builder's `validate_workflow`
 * tool. Publishing is cheap but every publish is a version, so this is the
 * "compile" step before create_workflow / edit_workflow: it catches what the
 * runner would only surface at run time (or never — a `depends` on a missing
 * id runs the step early with an undefined input; a dependency cycle hangs
 * the run forever). Pure: no I/O; the caller supplies the registry and the
 * workspace's workflow list.
 *
 * Errors are things that would fail or hang at run time. Warnings are things
 * that are legal but usually mistakes. Anything that depends on run-time
 * values (a template's resolved type) is out of scope — template-valued
 * config fields are skipped when checking against the step's schema.
 */
import yaml from "js-yaml";
import { TemplateError, exprRoots, hasTemplates, templateExprs } from "./expr.js";
import { assertValidWorkflowYaml } from "./workspace.js";
/** Render a result as the one-paragraph refusal a publish tool returns —
 *  what went wrong, where, and what to do next. */
export function formatValidationErrors(r, verb = "published") {
    const list = r.errors.map((e) => (e.path ? `${e.path}: ${e.message}` : e.message)).join("\n- ");
    return (`Not ${verb}: the workflow YAML has ${r.errors.length} validation error${r.errors.length === 1 ? "" : "s"} ` +
        `(nothing was written; no version was created).\n- ${list}\n` +
        `Fix these and call again — validate_workflow re-checks without publishing.`);
}
/** Step ids must be expression identifiers, or templates can't reference them. */
const ID_RE = /^[A-Za-z_][A-Za-z0-9_]*$/;
/** Step types the runner special-cases; their `body` is a nested Step. */
const BODY_STEPS = new Set(["loop", "foreach"]);
export function validateWorkflowYaml(source, opts) {
    const errors = [];
    const warnings = [];
    const done = (name, steps = []) => ({
        ok: errors.length === 0,
        errors,
        warnings,
        summary: { name, steps: steps.length, stepTypes: [...new Set(collectTypes(steps))].sort() },
    });
    try {
        assertValidWorkflowYaml(source);
    }
    catch (e) {
        errors.push({ path: "", message: e instanceof Error ? e.message : String(e) });
        return done();
    }
    const data = yaml.load(source);
    if (!data || typeof data !== "object" || Array.isArray(data)) {
        errors.push({ path: "", message: "Workflow YAML must be a mapping with `name` and `steps`." });
        return done();
    }
    if ((typeof data.name !== "string" || !data.name) && !opts.name) {
        errors.push({ path: "name", message: "`name` is required (kebab-case string)." });
    }
    if (!Array.isArray(data.steps) || data.steps.length === 0) {
        errors.push({ path: "steps", message: "`steps` must be a non-empty list." });
        return done(data.name);
    }
    if (data.params != null && (typeof data.params !== "object" || Array.isArray(data.params))) {
        errors.push({ path: "params", message: "`params` must be a mapping of knob → default." });
    }
    const steps = data.steps;
    const ids = new Set();
    // ── Pass 1: shape + ids ─────────────────────────────────────────────────
    steps.forEach((s, i) => {
        const p = `steps[${i}]`;
        if (!s || typeof s !== "object") {
            errors.push({ path: p, message: "Step must be a mapping with `id` and `type`." });
            return;
        }
        if (typeof s.id !== "string" || !s.id) {
            errors.push({ path: `${p}.id`, message: "`id` is required." });
        }
        else if (!ID_RE.test(s.id)) {
            errors.push({ path: `${p}.id`, message: `Step id "${s.id}" must be alphanumeric + underscores (templates can't reference "${s.id}").` });
        }
        else if (ids.has(s.id)) {
            errors.push({ path: `${p}.id`, message: `Duplicate step id "${s.id}".` });
        }
        else
            ids.add(s.id);
    });
    // ── Pass 2: deps graph (cycles + unknown ids) ───────────────────────────
    const depsOf = new Map();
    steps.forEach((s, i) => {
        if (!s || typeof s.id !== "string")
            return;
        const p = `steps[${i}]`;
        let deps;
        if (s.depends == null)
            deps = i > 0 && typeof steps[i - 1]?.id === "string" ? [steps[i - 1].id] : [];
        else if (typeof s.depends === "string")
            deps = [s.depends];
        else if (Array.isArray(s.depends) && s.depends.every((d) => typeof d === "string"))
            deps = s.depends;
        else {
            errors.push({ path: `${p}.depends`, message: "`depends` must be a step id or a list of step ids." });
            deps = [];
        }
        for (const d of deps) {
            if (d === s.id)
                errors.push({ path: `${p}.depends`, message: `Step "${s.id}" depends on itself.` });
            else if (!ids.has(d)) {
                errors.push({
                    path: `${p}.depends`,
                    message: `Step "${s.id}" depends on unknown step "${d}" (the runner would start it immediately with an undefined input). Known ids: ${[...ids].join(", ")}.`,
                });
            }
        }
        depsOf.set(s.id, deps.filter((d) => ids.has(d) && d !== s.id));
    });
    const cycle = findCycle(depsOf);
    if (cycle) {
        errors.push({ path: "steps", message: `Dependency cycle: ${cycle.join(" → ")} (the run would hang forever).` });
    }
    const ancestors = ancestorsOf(depsOf);
    // ── Pass 3: per-step semantics ──────────────────────────────────────────
    const globals = ["input", "params"];
    const stepById = new Map(steps.filter((s) => s && typeof s.id === "string").map((s) => [s.id, s]));
    steps.forEach((s, i) => {
        if (!s || typeof s !== "object")
            return;
        const p = `steps[${i}]`;
        const id = typeof s.id === "string" ? s.id : `#${i}`;
        // `when` only means something with an `if` gate upstream.
        if (s.when != null) {
            if (typeof s.when !== "boolean") {
                errors.push({ path: `${p}.when`, message: "`when` must be true or false." });
            }
            else {
                const deps = depsOf.get(id) ?? [];
                if (deps.length === 0) {
                    errors.push({ path: `${p}.when`, message: `Step "${id}" has \`when\` but no \`depends\` — it would always be skipped.` });
                }
                else if (!deps.some((d) => stepById.get(d)?.type === "if")) {
                    warnings.push({
                        path: `${p}.when`,
                        message: `Step "${id}" has \`when\` but none of its depends (${deps.join(", ")}) is an \`if\` gate — it is skipped unless a dependency returns a boolean.`,
                    });
                }
            }
        }
        checkStep(s, p, {
            roots: [...globals, ...ids],
            upstream: new Set([...globals, ...(ancestors.get(id) ?? [])]),
            extraRoots: [],
        });
    });
    return done(data.name, steps);
    function checkStep(s, p, scope) {
        if (typeof s.type !== "string" || !s.type) {
            errors.push({ path: `${p}.type`, message: "`type` is required." });
            return;
        }
        const def = opts.registry[s.type];
        if (!def) {
            errors.push({ path: `${p}.type`, message: `Unknown step type "${s.type}" (call search_steps / list_steps; author it with create_step if it doesn't exist).` });
            return;
        }
        const config = (s.config ?? {});
        if (typeof config !== "object" || Array.isArray(config)) {
            errors.push({ path: `${p}.config`, message: "`config` must be a mapping." });
            return;
        }
        // Templates: syntax (token-level) + roots. A loop/foreach `body` is a
        // nested step checked below with its loop variables in scope; a loop's
        // own `until` legitimately reads `$current`.
        const isBodyStep = BODY_STEPS.has(s.type);
        const ownExtras = s.type === "loop" ? [...scope.extraRoots, "$current"] : scope.extraRoots;
        const allRoots = new Set([...scope.roots, ...ownExtras]);
        const upstream = new Set([...scope.upstream, ...ownExtras]);
        const ownConfig = isBodyStep ? Object.fromEntries(Object.entries(config).filter(([k]) => k !== "body")) : config;
        walkStrings(ownConfig, `${p}.config`, (str, path) => {
            if (!hasTemplates(str))
                return;
            for (const expr of templateExprs(str)) {
                let roots;
                try {
                    roots = exprRoots(expr);
                }
                catch (e) {
                    errors.push({ path, message: `Template syntax error in "{{${expr}}}": ${e instanceof TemplateError ? e.message : String(e)}` });
                    continue;
                }
                for (const r of roots) {
                    if (!allRoots.has(r)) {
                        errors.push({
                            path,
                            message: `Template references unknown root "${r}" in "{{${expr.trim()}}}". Valid roots here: ${[...allRoots].join(", ")}.`,
                        });
                    }
                    else if (!upstream.has(r)) {
                        warnings.push({
                            path,
                            message: `Template references step "${r}" which is not an upstream dependency of this step — its output may not exist yet. Add it to \`depends\`.`,
                        });
                    }
                }
            }
        });
        // Nested steps: loop/foreach body, onError fallback.
        if (isBodyStep) {
            const body = config["body"];
            if (!body || typeof body !== "object" || !body.type) {
                errors.push({ path: `${p}.config.body`, message: `${s.type} step requires a \`body\` step ({ id, type, config }).` });
            }
            else {
                const vars = s.type === "foreach" ? ["$current", "$index"] : ["$current"];
                checkStep(body, `${p}.config.body`, { ...scope, extraRoots: [...scope.extraRoots, ...vars] });
            }
            if (s.type === "loop" && config["until"] == null) {
                errors.push({ path: `${p}.config.until`, message: "loop step requires an `until` expression." });
            }
            if (s.type === "foreach" && config["items"] == null) {
                errors.push({ path: `${p}.config.items`, message: "foreach step requires `items`." });
            }
        }
        if (s.options != null) {
            const o = s.options;
            const retry = o["retry"];
            if (retry != null && (typeof retry !== "object" || typeof retry["max"] !== "number" || typeof retry["delayMs"] !== "number")) {
                errors.push({ path: `${p}.options.retry`, message: "`retry` must be { max: number, delayMs: number }." });
            }
            const onError = o["onError"];
            if (onError != null) {
                if (typeof onError !== "object" || !onError.type) {
                    errors.push({ path: `${p}.options.onError`, message: "`onError` must be a step ({ id, type, config })." });
                }
                else {
                    checkStep(onError, `${p}.options.onError`, { ...scope, extraRoots: [...scope.extraRoots, "$error"] });
                }
            }
        }
        // Subflow target must exist (when named literally).
        if (s.type === "subflow" && opts.workflows) {
            const wf = config["workflow"];
            if (typeof wf === "string" && !hasTemplates(wf)) {
                const entry = opts.workflows.find((w) => w.name === wf);
                if (!entry && wf === opts.name) {
                    // Self-recursion before/while publishing — resolvable at run time.
                }
                else if (!entry) {
                    errors.push({ path: `${p}.config.workflow`, message: `Subflow target "${wf}" is not a published workflow (list_workflows to see what exists).` });
                }
                else {
                    const v = config["version"];
                    if (typeof v === "string" && !hasTemplates(v) && !entry.versions.includes(v)) {
                        errors.push({ path: `${p}.config.version`, message: `Subflow "${wf}" has no version "${v}". Available: ${entry.versions.join(", ")}.` });
                    }
                }
            }
        }
        // Config vs the step's input schema, skipping template-valued fields
        // (they resolve at run time) — the body/onError steps are checked above.
        if (isBodyStep)
            return;
        const parsed = def.input.safeParse(config);
        if (!parsed.success) {
            for (const issue of parsed.error.issues) {
                if (pathIsTemplated(config, issue.path))
                    continue;
                const at = issue.path.length ? `${p}.config.${issue.path.join(".")}` : `${p}.config`;
                errors.push({ path: at, message: `${issue.message}${issue.path.length ? "" : " (config)"} — call get_step("${s.type}") for the exact fields.` });
            }
        }
        const known = objectKeys(def.input);
        if (known) {
            for (const k of Object.keys(config)) {
                if (!known.has(k)) {
                    warnings.push({ path: `${p}.config.${k}`, message: `Unknown config field "${k}" for step type "${s.type}" — it is ignored. Known fields: ${[...known].join(", ")}.` });
                }
            }
        }
    }
}
// ── Pure helpers ────────────────────────────────────────────────────────────
function collectTypes(steps) {
    const out = [];
    const visit = (s) => {
        if (!s || typeof s !== "object" || typeof s.type !== "string")
            return;
        out.push(s.type);
        const body = s.config?.["body"];
        if (BODY_STEPS.has(s.type))
            visit(body);
        visit(s.options?.onError);
    };
    steps.forEach(visit);
    return out;
}
/** First cycle found in the deps graph as a path (a → b → a), else null. */
function findCycle(deps) {
    const state = new Map(); // 1 visiting, 2 done
    const stack = [];
    const visit = (n) => {
        const st = state.get(n);
        if (st === 2)
            return null;
        if (st === 1)
            return [...stack.slice(stack.indexOf(n)), n];
        state.set(n, 1);
        stack.push(n);
        for (const d of deps.get(n) ?? []) {
            const c = visit(d);
            if (c)
                return c;
        }
        stack.pop();
        state.set(n, 2);
        return null;
    };
    for (const n of deps.keys()) {
        const c = visit(n);
        if (c)
            return c;
    }
    return null;
}
/** Transitive dependencies per step (cycle-safe). */
function ancestorsOf(deps) {
    const memo = new Map();
    const visit = (n, seen) => {
        const hit = memo.get(n);
        if (hit)
            return hit;
        const out = new Set();
        if (seen.has(n))
            return out;
        seen.add(n);
        for (const d of deps.get(n) ?? []) {
            out.add(d);
            for (const a of visit(d, seen))
                out.add(a);
        }
        memo.set(n, out);
        return out;
    };
    const result = new Map();
    for (const n of deps.keys())
        result.set(n, visit(n, new Set()));
    return result;
}
function walkStrings(v, path, fn) {
    if (typeof v === "string")
        fn(v, path);
    else if (Array.isArray(v))
        v.forEach((x, i) => walkStrings(x, `${path}[${i}]`, fn));
    else if (v && typeof v === "object") {
        for (const [k, x] of Object.entries(v))
            walkStrings(x, `${path}.${k}`, fn);
    }
}
/** True when the value at `path` (or any container on the way) is a template
 *  string — its run-time type is unknowable here. */
function pathIsTemplated(config, path) {
    let cur = config;
    for (const seg of path) {
        if (typeof cur === "string")
            return hasTemplates(cur);
        if (cur == null || typeof cur !== "object")
            return false;
        cur = cur[seg];
    }
    return typeof cur === "string" && hasTemplates(cur);
}
/** Top-level keys of a z.object schema (through pipes/refinements), else null. */
function objectKeys(schema) {
    const def = schema?._def;
    if (!def)
        return null;
    if (def.type === "object")
        return new Set(Object.keys(def.shape ?? {}));
    if (def.type === "pipe")
        return objectKeys(def.in);
    return null;
}
//# sourceMappingURL=validate.js.map