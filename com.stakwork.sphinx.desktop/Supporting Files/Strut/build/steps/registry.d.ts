import type { AnyStepDef, StepRegistry } from "../core.js";
/** Where a registered step type came from. */
export type StepSource = "core" | "lib" | "custom";
/** Map of step type name → its source tier. */
export type StepSources = Record<string, StepSource>;
/** Result of building the registry: the registry itself plus a parallel
 *  map recording where each step was loaded from. */
export interface RegistryBundle {
    registry: StepRegistry;
    sources: StepSources;
}
export declare const CORE_STEP_TYPES: readonly string[];
/** Directory containing built-in lib steps, resolved relative to this file. */
export declare const LIB_DIR: string;
/** Directory containing built-in core steps, resolved relative to this file. */
export declare const CORE_DIR: string;
/**
 * Read a step's source code from disk. Resolves core, built-in lib, and
 * workspace custom steps (trying both `.ts` and `.js` so it works whether
 * strut runs from source via tsx or from a compiled build). Returns the
 * code plus which tier it came from, or `null` when no file is found.
 *
 * In-code steps injected via `createRegistry([...])` have no on-disk file —
 * those carry their source on the step def itself (`AnyStepDef.source`) and
 * are handled by the caller before falling back to this.
 */
export declare function readStepSourceFromDisk(type: string, customDir: string): Promise<{
    code: string;
    origin: StepSource;
} | null>;
/**
 * Import a step file the way registry discovery does, but return the failure
 * as a MESSAGE instead of a console warning. `null` means the file imports
 * cleanly and default-exports a valid step def. This is the authoring loop's
 * §5.3.4 guard: `loadStepFile` fails silently (a broken step simply doesn't
 * exist), so publish paths call this to hand the error back to the author.
 */
export declare function stepLoadError(filePath: string): Promise<string | null>;
/**
 * Build the complete step registry by merging core steps (statically
 * imported) with lib steps (dynamically imported from `src/steps/lib/`)
 * and custom steps (dynamically imported from `customDir` — the directory
 * `WorkspaceStore.materializeCustomSteps()` returns; omit for core+lib only).
 *
 * Resolution order: core/ → lib/ → custom/. Higher tiers cannot shadow
 * lower ones — a name collision is skipped with a warning.
 *
 * Lib and custom step *files* are loaded with dynamic `import()` at
 * build time (cheap: just schema + metadata). Their heavy SDK deps must
 * be `await import()`-ed inside `run()` so they only load when a step
 * actually executes — see AGENTS.md "Lib step dependency convention".
 *
 * Returns both the registry and a parallel `sources` map so callers can
 * report which tier each step came from without guessing from the name.
 */
export declare function buildRegistry(customDir?: string): Promise<RegistryBundle>;
/**
 * Get the core-only registry (no workspace steps). Useful for testing.
 */
export declare function coreRegistry(): StepRegistry;
/**
 * Build a registry from in-code step definitions, layered on top of the
 * engine-shipped **core** and **lib** steps. For consumers using strut
 * as a library who prefer registering steps in code rather than via
 * filesystem discovery.
 *
 * The resulting registry contains:
 *   - **core/** — 8 built-in steps (http, log, if, loop, foreach,
 *     subflow, llm, wait)
 *   - **lib/** — engine-shipped domain integrations (e.g.
 *     `github/fetch-pr`). Their step *files* are imported here (cheap:
 *     just schema + metadata); their heavy SDK deps are `await import()`-ed
 *     inside `run()`, so they only load when a step actually executes.
 *     See AGENTS.md "Lib step dependency convention".
 *   - whatever you pass in `steps`
 *
 * Workspace **custom/** steps are loaded via `buildRegistry(customDir)`
 * instead — they're never included here.
 *
 * Each step is keyed by its `type` field. Duplicates among `steps`
 * throw. A user step whose `type` collides with a core or lib step
 * shadows it (with a warning), so callers can deliberately override
 * e.g. the built-in `http` step.
 *
 * ```ts
 * const registry = await createRegistry([myStep, anotherStep]);
 * await runWorkflow(flow, input, registry, { services });
 * ```
 */
export declare function createRegistry(steps: AnyStepDef[]): Promise<StepRegistry>;
