import { z } from "zod";
import type { StrutCapabilities } from "../../../capabilities.js";
declare const _default: import("../../../core.js").StepDef<"github/fetch-pr", z.ZodObject<{
    owner: z.ZodString;
    repo: z.ZodString;
    pull_number: z.ZodNumber;
    token: z.ZodOptional<z.ZodString>;
    limits: z.ZodPrefault<z.ZodObject<{
        maxPatchLines: z.ZodDefault<z.ZodNumber>;
        maxFiles: z.ZodDefault<z.ZodNumber>;
        maxDescriptionChars: z.ZodDefault<z.ZodNumber>;
        maxCommentChars: z.ZodDefault<z.ZodNumber>;
        maxComments: z.ZodDefault<z.ZodNumber>;
        maxReviews: z.ZodDefault<z.ZodNumber>;
    }, z.core.$strip>>;
}, z.core.$strip>, z.ZodObject<{
    markdown: z.ZodString;
    pr: z.ZodObject<{
        number: z.ZodNumber;
        title: z.ZodString;
        mergedAt: z.ZodNullable<z.ZodString>;
        author: z.ZodString;
        htmlUrl: z.ZodString;
        additions: z.ZodNumber;
        deletions: z.ZodNumber;
        changedFiles: z.ZodNumber;
    }, z.core.$strip>;
}, z.core.$strip>, StrutCapabilities>;
export default _default;
