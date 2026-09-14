import { z } from "zod";
declare const _default: import("../../../core.js").StepDef<"graph/edit-edge", z.ZodObject<{
    edge_ref_id: z.ZodOptional<z.ZodString>;
    source_ref_id: z.ZodOptional<z.ZodString>;
    edge_type: z.ZodOptional<z.ZodString>;
    target_ref_id: z.ZodOptional<z.ZodString>;
    edge_data: z.ZodOptional<z.ZodRecord<z.ZodString, z.ZodAny>>;
    properties_to_be_deleted: z.ZodOptional<z.ZodArray<z.ZodString>>;
}, z.core.$strip>, z.ZodAny, unknown>;
export default _default;
