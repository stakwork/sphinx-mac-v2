import { z } from "zod";
declare const _default: import("../../../core.js").StepDef<"meta/get-run", z.ZodObject<{
    name: z.ZodString;
    runId: z.ZodString;
    fullEvents: z.ZodDefault<z.ZodBoolean>;
}, z.core.$strip>, z.ZodAny, unknown>;
export default _default;
