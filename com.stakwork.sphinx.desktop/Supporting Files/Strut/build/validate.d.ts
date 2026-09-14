import type { StepRegistry } from "./core.js";
export interface ValidationIssue {
    /** Where: `steps[2].config.url`, `steps[0].depends`, … */
    path: string;
    message: string;
}
export interface ValidationResult {
    ok: boolean;
    errors: ValidationIssue[];
    warnings: ValidationIssue[];
    summary: {
        name?: string;
        steps: number;
        stepTypes: string[];
    };
}
export interface ValidateOptions {
    registry: StepRegistry;
    /** Published workflows (for subflow targets). Omit to skip that check. */
    workflows?: Array<{
        name: string;
        versions: string[];
    }>;
    /** The name the publish will use. When given, a YAML without `name` is
     *  fine (create_workflow / edit_workflow stamp it in), and a subflow may
     *  reference it (self-recursion) even before the first publish. */
    name?: string;
}
/** Render a result as the one-paragraph refusal a publish tool returns —
 *  what went wrong, where, and what to do next. */
export declare function formatValidationErrors(r: ValidationResult, verb?: string): string;
export declare function validateWorkflowYaml(source: string, opts: ValidateOptions): ValidationResult;
