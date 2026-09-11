import { z } from "zod";
declare const _default: import("../../core.js").StepDef<"llm", z.ZodObject<{
    prompt: z.ZodString;
    schema: z.ZodOptional<z.ZodAny>;
    provider: z.ZodOptional<z.ZodString>;
    model: z.ZodOptional<z.ZodString>;
}, z.core.$strip>, z.ZodAny, unknown>;
export default _default;
