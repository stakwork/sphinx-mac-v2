import { z } from "zod";
declare const _default: import("../../../core.js").StepDef<"meta/run-workflow", z.ZodObject<{
    name: z.ZodString;
    input: z.ZodOptional<z.ZodAny>;
    params: z.ZodOptional<z.ZodRecord<z.ZodString, z.ZodAny>>;
    version: z.ZodOptional<z.ZodString>;
}, z.core.$strip>, z.ZodAny, unknown>;
export default _default;
