import { z } from "zod";
import type { StrutCapabilities } from "../../../capabilities.js";
declare const _default: import("../../../core.js").StepDef<"gdrive/export-file", z.ZodObject<{
    fileId: z.ZodString;
    accessToken: z.ZodOptional<z.ZodString>;
    exportMimeType: z.ZodOptional<z.ZodString>;
    maxChars: z.ZodDefault<z.ZodNumber>;
}, z.core.$strip>, z.ZodObject<{
    content: z.ZodString;
    truncated: z.ZodBoolean;
    file: z.ZodObject<{
        id: z.ZodString;
        name: z.ZodString;
        mimeType: z.ZodString;
        modifiedTime: z.ZodNullable<z.ZodString>;
        size: z.ZodNullable<z.ZodNumber>;
        webViewLink: z.ZodNullable<z.ZodString>;
    }, z.core.$strip>;
}, z.core.$strip>, StrutCapabilities>;
export default _default;
