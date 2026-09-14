import { z } from "zod";
declare const _default: import("../../core.js").StepDef<"loop", z.ZodObject<{
    until: z.ZodString;
    maxIterations: z.ZodNumber;
    delayMs: z.ZodOptional<z.ZodNumber>;
    body: z.ZodAny;
}, z.core.$strip>, z.ZodAny, unknown>;
export default _default;
