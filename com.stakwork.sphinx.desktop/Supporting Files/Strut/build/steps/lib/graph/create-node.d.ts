import { z } from "zod";
declare const _default: import("../../../core.js").StepDef<"graph/create-node", z.ZodObject<{
    node_type: z.ZodString;
    node_data: z.ZodRecord<z.ZodString, z.ZodAny>;
    namespace: z.ZodOptional<z.ZodString>;
}, z.core.$strip>, z.ZodAny, unknown>;
export default _default;
