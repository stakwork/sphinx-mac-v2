import { z } from "zod";
declare const _default: import("../../core.js").StepDef<"foreach", z.ZodObject<{
    items: z.ZodAny;
    body: z.ZodAny;
    maxIterations: z.ZodOptional<z.ZodNumber>;
    concurrency: z.ZodOptional<z.ZodNumber>;
}, z.core.$strip>, z.ZodAny, unknown>;
export default _default;
