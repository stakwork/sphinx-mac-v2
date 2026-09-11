import { z } from "zod";
declare const _default: import("../../core.js").StepDef<"subflow", z.ZodObject<{
    workflow: z.ZodString;
    version: z.ZodOptional<z.ZodString>;
    input: z.ZodAny;
}, z.core.$strip>, z.ZodAny, unknown>;
export default _default;
