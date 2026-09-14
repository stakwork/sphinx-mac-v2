import { z } from "zod";
declare const _default: import("../../../core.js").StepDef<"graph/graph-neighbors", z.ZodObject<{
    ref_id: z.ZodString;
    edge_type: z.ZodOptional<z.ZodArray<z.ZodString>>;
    node_type: z.ZodOptional<z.ZodArray<z.ZodString>>;
    namespace: z.ZodOptional<z.ZodString>;
}, z.core.$strip>, z.ZodAny, unknown>;
export default _default;
