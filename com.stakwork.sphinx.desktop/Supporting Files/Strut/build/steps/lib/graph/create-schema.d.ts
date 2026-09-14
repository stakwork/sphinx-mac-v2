import { z } from "zod";
declare const _default: import("../../../core.js").StepDef<"graph/create-schema", z.ZodObject<{
    type: z.ZodString;
    parent: z.ZodDefault<z.ZodOptional<z.ZodString>>;
    attributes: z.ZodRecord<z.ZodString, z.ZodString>;
    node_key: z.ZodOptional<z.ZodString>;
    index: z.ZodOptional<z.ZodArray<z.ZodString>>;
    title_key: z.ZodOptional<z.ZodString>;
    description_key: z.ZodOptional<z.ZodString>;
    domain: z.ZodOptional<z.ZodString>;
    type_description: z.ZodOptional<z.ZodString>;
}, z.core.$strip>, z.ZodAny, unknown>;
export default _default;
