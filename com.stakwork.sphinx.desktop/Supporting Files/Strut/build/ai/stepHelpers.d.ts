import type { StepRegistry } from "../core.js";
import type { WorkspaceStore } from "../workspace.js";
/**
 * The subset of dependencies the step-explorer helpers need. Both the chat
 * builder's `AiDeps` and the authoring capability satisfy it structurally.
 */
export interface StepExplorerDeps {
    workspace: Pick<WorkspaceStore, "listSteps" | "getStepSource">;
    registry: StepRegistry;
}
export declare function lsSteps(path: string, deps: StepExplorerDeps): Promise<{
    error: string;
    entries?: undefined;
} | {
    entries: string[];
    error?: undefined;
}>;
export declare function searchSteps(query: string, deps: StepExplorerDeps): Promise<{
    matches: {
        type: string;
        description?: string;
    }[];
}>;
/**
 * Read the source code for a lib or custom step through the workspace
 * boundary. Returns undefined for core steps (the AI gets their schema and
 * description instead) or anything the store has no source for.
 */
export declare function readStepSource(type: string, deps: StepExplorerDeps): Promise<string | undefined>;
