import type { Flow } from "../core.js";
import { type PublishByContentOptions, type StepListEntry, type StepVersionsResult, type WorkflowListEntry, type WorkflowMetadata, type WorkspaceStore } from "../workspace.js";
import { type StepSource } from "../steps/registry.js";
import type { GraphBackend } from "./backend.js";
export interface Neo4jWorkspaceStoreOptions {
    /** Where active custom steps are written for the module loader. Default:
     *  a per-(uri, namespace) dir under the OS temp dir. */
    materializeDir?: string;
}
export declare class Neo4jWorkspaceStore implements WorkspaceStore {
    private readonly backend;
    private readonly ns;
    private readonly materializeDir;
    constructor(backend: GraphBackend, opts?: Neo4jWorkspaceStoreOptions);
    private workflowRow;
    private versionRows;
    listWorkflows(): Promise<WorkflowListEntry[]>;
    getWorkflowMetadata(name: string): Promise<WorkflowMetadata | null>;
    private versionByLabel;
    private activeVersion;
    getWorkflow(name: string): Promise<Flow>;
    getWorkflowVersion(name: string, version: string): Promise<Flow>;
    getWorkflowSource(name: string, version: string): Promise<string>;
    getWorkflowHash(name: string, version?: string): Promise<string | null>;
    createWorkflow(name: string, content: {
        steps: any[];
        params?: Record<string, unknown>;
    } | string, description?: string, category?: string, publisher?: string): Promise<{
        name: string;
        version: string;
    }>;
    publishWorkflow(name: string, version: string, content: {
        steps: any[];
        params?: Record<string, unknown>;
        promotes?: unknown[];
    } | string, description?: string, category?: string, publisher?: string): Promise<void>;
    /** The one write path behind publish/publishByContent/setParam: ensure the
     *  version node exists (creating, restoring, or re-labeling it), then
     *  point the workflow at it. */
    private writeVersion;
    /** Point the workflow node (creating it if needed) at a version: mirror the
     *  version's description onto the workflow, swap the ACTIVE_VERSION edge. */
    private activate;
    /** USES_STEP → every custom step the version references; DEPENDS_ON →
     *  every workflow its subflow steps call. Only targets that exist are
     *  linked (the graph pays off in "which workflows use step X"). */
    private linkVersionDeps;
    publishWorkflowByContent(name: string, yamlStr: string, description?: string, category?: string, publisher?: string, opts?: PublishByContentOptions): Promise<{
        version: string;
        changed: boolean;
    }>;
    setWorkflowCategory(name: string, category: string | null): Promise<void>;
    setActiveVersion(name: string, version: string): Promise<void>;
    setParam(name: string, param: string, value: unknown): Promise<{
        version: string;
        before: unknown;
        after: unknown;
    }>;
    private stepRow;
    private stepVersionRows;
    /** Every visible step with its active version's row (null when the
     *  pointer dangles). Helpers (`_`-prefixed segments) included. */
    private stepsWithActive;
    private static isHelper;
    listSteps(filter?: {
        publisher?: string;
    }): Promise<StepListEntry[]>;
    listStepVersions(name: string): Promise<StepVersionsResult>;
    getStepVersionSource(name: string, version: string): Promise<string>;
    publishStep(name: string, code: string, description?: string, publisher?: string, opts?: PublishByContentOptions): Promise<{
        version: string;
        changed: boolean;
    }>;
    private swapActiveStepEdge;
    setActiveStepVersion(name: string, version: string): Promise<void>;
    deleteStep(name: string): Promise<boolean>;
    deleteStepsByPublisher(publisher: string): Promise<string[]>;
    getStepSource(type: string): Promise<{
        code: string;
        origin: StepSource;
    } | null>;
    /**
     * Write every active custom step (helpers included) to the scratch dir as
     * `<name>.ts`, skipping unchanged files and deleting files for steps that
     * are no longer in the graph, so the loader never imports a stale step.
     * Cheap to call on every registry rebuild.
     */
    materializeCustomSteps(): Promise<string>;
}
