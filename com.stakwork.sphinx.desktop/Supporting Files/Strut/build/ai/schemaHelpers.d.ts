import { z } from "zod";
export interface FieldDesc {
    name: string;
    kind: "string" | "number" | "boolean" | "enum" | "json";
    required: boolean;
    default?: unknown;
    enumValues?: string[];
    /** UI hint for a free-text field: a catalog to offer as suggestions
     *  ("llm-models" → GET /llm/models). Set on the Zod schema via
     *  `.meta({ suggest: "llm-models" })`; the value stays free text. */
    suggest?: "llm-models";
}
export declare function zodToFields(schema: z.ZodTypeAny): FieldDesc[];
