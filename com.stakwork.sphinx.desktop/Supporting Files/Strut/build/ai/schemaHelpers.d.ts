import { z } from "zod";
export interface FieldDesc {
    name: string;
    kind: "string" | "number" | "boolean" | "enum" | "json";
    required: boolean;
    default?: unknown;
    enumValues?: string[];
}
export declare function zodToFields(schema: z.ZodTypeAny): FieldDesc[];
