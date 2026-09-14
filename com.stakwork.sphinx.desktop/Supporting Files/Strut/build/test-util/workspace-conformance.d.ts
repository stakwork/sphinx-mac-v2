import type { WorkspaceStore } from "../workspace.js";
export interface WorkspaceImpl {
    name: string;
    /** Build a fresh, empty store. `dir` is a fresh temp dir the case owns. */
    make: (dir: string) => Promise<WorkspaceStore> | WorkspaceStore;
    /** Reset backend state between cases (graph wipe, …). */
    reset?: () => Promise<void>;
    /** `describe` skip reason (e.g. no live database configured). */
    skip?: string | false;
}
export declare function workspaceConformance(impl: WorkspaceImpl): void;
