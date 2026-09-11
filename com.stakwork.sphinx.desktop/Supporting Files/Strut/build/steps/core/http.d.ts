import { z } from "zod";
declare const _default: import("../../core.js").StepDef<"http", z.ZodObject<{
    url: z.ZodString;
    method: z.ZodDefault<z.ZodEnum<{
        POST: "POST";
        GET: "GET";
        PUT: "PUT";
        DELETE: "DELETE";
        PATCH: "PATCH";
    }>>;
    body: z.ZodOptional<z.ZodAny>;
    headers: z.ZodOptional<z.ZodRecord<z.ZodString, z.ZodString>>;
    timeout: z.ZodOptional<z.ZodNumber>;
}, z.core.$strip>, z.ZodAny, unknown>;
export default _default;
