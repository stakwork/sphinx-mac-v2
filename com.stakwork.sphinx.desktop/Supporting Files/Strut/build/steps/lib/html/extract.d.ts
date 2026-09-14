import { z } from "zod";
import type { StrutCapabilities } from "../../../capabilities.js";
/**
 * HTML → readable-text extraction over `html-to-text` (tolerant of malformed
 * markup; renders real text tables — financial filings live in tables).
 * LLM-authored adapter steps should compose this instead of hand-rolling
 * regex stripping (see AGENTS.md "step vs service").
 */
/** Grab <title> — html-to-text skips <head>, so pull it out separately. */
export declare function extractTitle(html: string): string | null;
declare const _default: import("../../../core.js").StepDef<"html/extract", z.ZodObject<{
    url: z.ZodOptional<z.ZodString>;
    html: z.ZodOptional<z.ZodString>;
    headers: z.ZodOptional<z.ZodRecord<z.ZodString, z.ZodString>>;
    maxChars: z.ZodDefault<z.ZodNumber>;
    timeout: z.ZodOptional<z.ZodNumber>;
}, z.core.$strip>, z.ZodObject<{
    text: z.ZodString;
    title: z.ZodNullable<z.ZodString>;
    length: z.ZodNumber;
    truncated: z.ZodBoolean;
    status: z.ZodNullable<z.ZodNumber>;
}, z.core.$strip>, StrutCapabilities>;
export default _default;
