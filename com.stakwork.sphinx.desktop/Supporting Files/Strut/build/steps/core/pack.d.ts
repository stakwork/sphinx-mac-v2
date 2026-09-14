import { z } from "zod";
/**
 * Assemble an object from other steps' outputs. A workflow's output is its
 * LAST step's output, so every workflow that must return more than one
 * step's result needs a step whose only job is to pack fields together —
 * and an `onError` fallback that packs an explicit failure shape instead
 * of killing the run wants the same primitive. The config IS the output:
 * every field is template-resolved by the runner before `run` sees it.
 */
declare const _default: import("../../core.js").StepDef<"pack", z.ZodRecord<z.ZodString, z.ZodAny>, z.ZodAny, unknown>;
export default _default;
