const ACCESSED_NODES_KEY = "_nodes";
/**
 * Mark a step's output with the graph nodes it touched. The marker is a
 * NON-enumerable own property of the output value (object or array), so it
 * rides along in-process — to `wrapToolsWithEmit`, which lifts it onto the
 * `step.end` event — but never reaches the model, downstream `{{ }}`
 * expressions, or a JSON serializer. Refs are deduplicated by `ref_id`;
 * empty lists and non-object outputs (error strings) are left unmarked.
 * Returns `output` for chaining: `return withAccessedNodes(result, refs)`.
 */
export function withAccessedNodes(output, nodes) {
    if (output === null || typeof output !== "object")
        return output;
    const seen = new Set();
    const list = [];
    for (const n of nodes) {
        if (!n || typeof n.ref_id !== "string" || !n.ref_id || seen.has(n.ref_id))
            continue;
        seen.add(n.ref_id);
        list.push(typeof n.node_type === "string" && n.node_type ? { ref_id: n.ref_id, node_type: n.node_type } : { ref_id: n.ref_id });
    }
    if (list.length === 0)
        return output;
    Object.defineProperty(output, ACCESSED_NODES_KEY, { value: list, enumerable: false, configurable: true, writable: true });
    return output;
}
/** The nodes a step output was marked with (see `withAccessedNodes`), else
 *  undefined. */
export function accessedNodesOf(output) {
    if (output === null || typeof output !== "object")
        return undefined;
    const v = output[ACCESSED_NODES_KEY];
    return Array.isArray(v) && v.length > 0 ? v : undefined;
}
// ── Builder functions ──────────────────────────────────────────────────────
/**
 * Define a new step type. Used in step definition files.
 *
 * ```ts
 * export default defineStep({
 *   type: "http",
 *   input: z.object({ url: z.string() }),
 *   output: z.any(),
 *   async run(cfg, ctx) { ... },
 * });
 * ```
 */
export function defineStep(def) {
    return def;
}
/**
 * Create a step instance for use in a workflow's `steps` array.
 *
 * ```ts
 * step("check", "http", { url: "{{ input.url }}" })
 * step("check", "http", { url: "/health" }, { retry: { max: 3, delayMs: 1000 } })
 * ```
 */
export function step(id, type, config, options) {
    if (!/^[a-zA-Z_][a-zA-Z0-9_]*$/.test(id)) {
        throw new Error(`Invalid step id "${id}": must match [a-zA-Z_][a-zA-Z0-9_]*`);
    }
    const { depends, when, ...opts } = options ?? {};
    const hasOpts = Object.keys(opts).length > 0;
    return {
        id,
        type,
        config,
        ...(depends != null ? { depends } : {}),
        ...(when != null ? { when } : {}),
        ...(hasOpts ? { options: opts } : {}),
    };
}
/**
 * Define a workflow.
 *
 * ```ts
 * export default flow("deploy", {
 *   input: z.object({ service: z.string() }),
 *   steps: [
 *     step("kick", "http", { url: "/deploy", method: "POST" }),
 *     step("done", "log", { message: "deployed {{ input.service }}" }),
 *   ],
 * });
 * ```
 */
export function flow(name, opts) {
    // Validate step id uniqueness within this flow
    const ids = new Set();
    for (const s of opts.steps) {
        if (ids.has(s.id)) {
            throw new Error(`Duplicate step id "${s.id}" in flow "${name}"`);
        }
        ids.add(s.id);
    }
    return {
        name,
        input: opts.input,
        steps: opts.steps,
        ...(opts.params != null ? { params: opts.params } : {}),
    };
}
//# sourceMappingURL=core.js.map