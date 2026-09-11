import { z } from "zod";
import type { StrutCapabilities } from "../../../capabilities.js";
declare const _default: import("../../../core.js").StepDef<"gdrive/list-files", z.ZodObject<{
    folderId: z.ZodOptional<z.ZodString>;
    modifiedAfter: z.ZodOptional<z.ZodString>;
    mimeType: z.ZodOptional<z.ZodString>;
    query: z.ZodOptional<z.ZodString>;
    includeTrashed: z.ZodDefault<z.ZodBoolean>;
    pageSize: z.ZodDefault<z.ZodNumber>;
    pageToken: z.ZodOptional<z.ZodString>;
    orderBy: z.ZodDefault<z.ZodString>;
    accessToken: z.ZodOptional<z.ZodString>;
}, z.core.$strip>, z.ZodObject<{
    files: z.ZodArray<z.ZodObject<{
        id: z.ZodString;
        name: z.ZodString;
        mimeType: z.ZodString;
        modifiedTime: z.ZodNullable<z.ZodString>;
        size: z.ZodNullable<z.ZodNumber>;
        webViewLink: z.ZodNullable<z.ZodString>;
    }, z.core.$strip>>;
    nextPageToken: z.ZodNullable<z.ZodString>;
    newestModifiedTime: z.ZodNullable<z.ZodString>;
}, z.core.$strip>, StrutCapabilities>;
export default _default;
/** Compose a Drive `q` from the convenience filters. Clauses are AND-ed; an
 *  empty result means "no filter" (list everything the creds can see).
 *  Exported for unit testing. */
export declare function buildQuery(cfg: {
    folderId?: string;
    modifiedAfter?: string;
    mimeType?: string;
    includeTrashed: boolean;
}): string;
