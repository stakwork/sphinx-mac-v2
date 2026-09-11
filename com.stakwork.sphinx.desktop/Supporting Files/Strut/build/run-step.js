import { z } from "zod";
import { runWorkflow } from "./runner.js";
import { MemoryRunStore } from "./store.js";
import { withCassette, loadCassette, saveCassette, } from "./cassette.js";
export async function runSingleStep(type, registry, services, opts = {}) {
    if (!registry[type]) {
        return {
            status: "error",
            error: { message: `Step type "${type}" not found` },
            events: [],
        };
    }
    const flow = {
        name: "__run_step__",
        input: z.any(),
        steps: [{ id: "step", type, config: opts.config ?? {} }],
        ...(opts.params != null ? { params: opts.params } : {}),
    };
    const cassette = opts.cassette ? await loadCassette(opts.cassette.path) : null;
    const runServices = opts.cassette && cassette
        ? withCassette(services, {
            mode: opts.cassette.mode,
            cassette,
        })
        : services;
    const events = [];
    const result = await runWorkflow(flow, opts.input ?? {}, registry, {
        store: new MemoryRunStore(),
        services: runServices,
        workspace: opts.workspace,
        onEvent: (e) => {
            events.push(e);
        },
    });
    // Persist newly-captured calls only when recording.
    if (opts.cassette?.mode === "record" && cassette) {
        await saveCassette(opts.cassette.path, cassette);
    }
    return {
        status: result.status,
        output: result.output,
        error: result.error,
        events,
        ...(cassette ? { recorded: cassette.entries.length } : {}),
    };
}
/** Default on-disk location for a step's cassette, under the server's local
 *  data dir (`dataDir` — the workspace root for file-backed deployments). */
export function cassettePath(dataDir, name) {
    // `name` may contain slashes (namespaced step types) — they become subdirs.
    return `${dataDir}/steps/_cassettes/${name}.json`;
}
//# sourceMappingURL=run-step.js.map