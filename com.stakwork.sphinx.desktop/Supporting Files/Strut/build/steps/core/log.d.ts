import { z } from "zod";
declare const _default: import("../../core.js").StepDef<"log", z.ZodObject<{
    message: z.ZodString;
    level: z.ZodDefault<z.ZodEnum<{
        error: "error";
        info: "info";
        warn: "warn";
    }>>;
}, z.core.$strip>, z.ZodString, unknown>;
export default _default;
