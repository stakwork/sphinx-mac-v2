import { z } from "zod";
declare const _default: import("../../../core.js").StepDef<"graph/edit-node", z.ZodObject<{
    ref_id: z.ZodString;
    node_data: z.ZodOptional<z.ZodRecord<z.ZodString, z.ZodAny>>;
    properties_to_be_deleted: z.ZodOptional<z.ZodArray<z.ZodString>>;
    node_type: z.ZodOptional<z.ZodString>;
    type_to_be_deleted: z.ZodOptional<z.ZodArray<z.ZodString>>;
    namespace: z.ZodOptional<z.ZodString>;
}, z.core.$strip>, z.ZodAny, unknown>;
export default _default;
