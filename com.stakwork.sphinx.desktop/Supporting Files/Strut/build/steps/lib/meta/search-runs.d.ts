import { z } from "zod";
declare const _default: import("../../../core.js").StepDef<"meta/search-runs", z.ZodObject<{
    name: z.ZodString;
    pattern: z.ZodString;
    runIds: z.ZodOptional<z.ZodArray<z.ZodString>>;
    runLimit: z.ZodDefault<z.ZodNumber>;
    maxMatches: z.ZodDefault<z.ZodNumber>;
    ignoreCase: z.ZodDefault<z.ZodBoolean>;
}, z.core.$strip>, z.ZodAny, unknown>;
export default _default;
