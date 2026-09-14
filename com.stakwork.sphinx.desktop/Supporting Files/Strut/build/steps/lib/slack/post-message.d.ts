import { z } from "zod";
import type { StrutCapabilities } from "../../../capabilities.js";
declare const _default: import("../../../core.js").StepDef<"slack/post-message", z.ZodObject<{
    channel: z.ZodString;
    text: z.ZodOptional<z.ZodString>;
    blocks: z.ZodOptional<z.ZodArray<z.ZodRecord<z.ZodString, z.ZodUnknown>>>;
    thread_ts: z.ZodOptional<z.ZodString>;
    token: z.ZodOptional<z.ZodString>;
}, z.core.$strip>, z.ZodObject<{
    ts: z.ZodString;
    channel: z.ZodString;
}, z.core.$strip>, StrutCapabilities>;
export default _default;
