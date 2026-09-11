import { z } from "zod";
declare const _default: import("../../../core.js").StepDef<"meta/run-step", z.ZodObject<{
    type: z.ZodString;
    config: z.ZodOptional<z.ZodRecord<z.ZodString, z.ZodAny>>;
    input: z.ZodOptional<z.ZodAny>;
    params: z.ZodOptional<z.ZodRecord<z.ZodString, z.ZodAny>>;
    cassette: z.ZodOptional<z.ZodEnum<{
        record: "record";
        replay: "replay";
    }>>;
    cassetteName: z.ZodOptional<z.ZodString>;
}, z.core.$strip>, z.ZodAny, unknown>;
export default _default;
