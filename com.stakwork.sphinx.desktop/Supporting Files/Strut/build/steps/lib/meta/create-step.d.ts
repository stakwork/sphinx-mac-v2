import { z } from "zod";
declare const _default: import("../../../core.js").StepDef<"meta/create-step", z.ZodObject<{
    name: z.ZodString;
    code: z.ZodString;
    description: z.ZodOptional<z.ZodString>;
}, z.core.$strip>, z.ZodAny, unknown>;
export default _default;
