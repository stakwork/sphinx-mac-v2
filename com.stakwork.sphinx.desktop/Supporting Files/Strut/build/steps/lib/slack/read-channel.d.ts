import { z } from "zod";
import type { StrutCapabilities } from "../../../capabilities.js";
export interface SlackMessage {
    ts: string;
    user: string;
    text: string;
    threadTs: string | null;
}
declare const _default: import("../../../core.js").StepDef<"slack/read-channel", z.ZodObject<{
    channel: z.ZodString;
    limit: z.ZodDefault<z.ZodNumber>;
    oldest: z.ZodOptional<z.ZodString>;
    latest: z.ZodOptional<z.ZodString>;
    resolveUsers: z.ZodDefault<z.ZodBoolean>;
    token: z.ZodOptional<z.ZodString>;
}, z.core.$strip>, z.ZodObject<{
    markdown: z.ZodString;
    channel: z.ZodString;
    hasMore: z.ZodBoolean;
    messages: z.ZodArray<z.ZodObject<{
        ts: z.ZodString;
        user: z.ZodString;
        text: z.ZodString;
        threadTs: z.ZodNullable<z.ZodString>;
    }, z.core.$strip>>;
}, z.core.$strip>, StrutCapabilities>;
export default _default;
