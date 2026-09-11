import { z } from "zod";
declare const _default: import("../../../core.js").StepDef<"graph/graph-search", z.ZodObject<{
    q: z.ZodOptional<z.ZodString>;
    input_q: z.ZodOptional<z.ZodString>;
    output_q: z.ZodOptional<z.ZodString>;
    type: z.ZodOptional<z.ZodString>;
    limit: z.ZodDefault<z.ZodOptional<z.ZodNumber>>;
    domains: z.ZodOptional<z.ZodString>;
    namespace: z.ZodOptional<z.ZodString>;
}, z.core.$strip>, z.ZodAny, unknown>;
export default _default;
