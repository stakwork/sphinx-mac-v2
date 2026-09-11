import { z } from "zod";
declare const _default: import("../../../core.js").StepDef<"graph/create-batch-triplet", z.ZodObject<{
    triplets: z.ZodArray<z.ZodObject<{
        source_ref_id: z.ZodOptional<z.ZodString>;
        source_type: z.ZodOptional<z.ZodString>;
        source_data: z.ZodOptional<z.ZodRecord<z.ZodString, z.ZodAny>>;
        target_ref_id: z.ZodOptional<z.ZodString>;
        target_type: z.ZodOptional<z.ZodString>;
        target_data: z.ZodOptional<z.ZodRecord<z.ZodString, z.ZodAny>>;
        edge_type: z.ZodString;
        edge_data: z.ZodOptional<z.ZodRecord<z.ZodString, z.ZodAny>>;
        weight: z.ZodOptional<z.ZodNumber>;
        create_schema_if_missing: z.ZodDefault<z.ZodOptional<z.ZodBoolean>>;
    }, z.core.$strip>>;
    namespace: z.ZodOptional<z.ZodString>;
    allow_scratchpad: z.ZodOptional<z.ZodBoolean>;
}, z.core.$strip>, z.ZodAny, unknown>;
export default _default;
