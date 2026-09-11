import { z } from "zod";
declare const _default: import("../../../core.js").StepDef<"graph/get-ontology", z.ZodObject<{
    domains: z.ZodOptional<z.ZodString>;
    include_edges: z.ZodDefault<z.ZodOptional<z.ZodBoolean>>;
    include_attributes: z.ZodDefault<z.ZodOptional<z.ZodBoolean>>;
}, z.core.$strip>, z.ZodAny, unknown>;
export default _default;
