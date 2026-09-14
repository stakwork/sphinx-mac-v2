import { z } from "zod";
declare const _default: import("../../core.js").StepDef<"wait", z.ZodObject<{
    durationMs: z.ZodDefault<z.ZodNumber>;
    message: z.ZodOptional<z.ZodString>;
}, z.core.$strip>, z.ZodObject<{
    waited: z.ZodNumber;
    message: z.ZodOptional<z.ZodString>;
}, z.core.$strip>, unknown>;
export default _default;
