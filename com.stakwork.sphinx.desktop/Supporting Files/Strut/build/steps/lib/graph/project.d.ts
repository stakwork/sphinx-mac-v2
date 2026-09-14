import { z } from "zod";
declare const _default: import("../../../core.js").StepDef<"graph/project", z.ZodObject<{
    dataDir: z.ZodOptional<z.ZodString>;
    workflows: z.ZodOptional<z.ZodArray<z.ZodString>>;
    limitPerWorkflow: z.ZodOptional<z.ZodNumber>;
    skipSettled: z.ZodOptional<z.ZodBoolean>;
    chats: z.ZodOptional<z.ZodBoolean>;
}, z.core.$strip>, z.ZodAny, unknown>;
export default _default;
