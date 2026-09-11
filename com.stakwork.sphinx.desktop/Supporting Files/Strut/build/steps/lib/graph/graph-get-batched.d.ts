import { z } from "zod";
declare const _default: import("../../../core.js").StepDef<"graph/graph-get-batched", z.ZodObject<{
    ref_ids: z.ZodArray<z.ZodString>;
    namespace: z.ZodOptional<z.ZodString>;
}, z.core.$strip>, z.ZodAny, unknown>;
export default _default;
