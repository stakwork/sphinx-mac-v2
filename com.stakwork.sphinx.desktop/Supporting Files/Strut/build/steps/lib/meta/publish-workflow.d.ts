import { z } from "zod";
declare const _default: import("../../../core.js").StepDef<"meta/publish-workflow", z.ZodObject<{
    name: z.ZodString;
    yaml: z.ZodString;
    description: z.ZodOptional<z.ZodString>;
    category: z.ZodOptional<z.ZodString>;
}, z.core.$strip>, z.ZodAny, unknown>;
export default _default;
