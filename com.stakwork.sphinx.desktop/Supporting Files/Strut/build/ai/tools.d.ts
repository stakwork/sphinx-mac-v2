import { AiDeps } from "./prompts.js";
export declare function buildTools(deps: AiDeps): {
    web_search?: any;
    graph_query?: import("ai").Tool<{
        cypher: string;
        maxRows: number;
        params?: Record<string, any> | undefined;
    }, import("../graph/query.js").ReadQueryResult | {
        error: string;
    }> | undefined;
    bash?: import("ai").Tool<{
        command: string;
        timeoutMs: number;
    }, {
        output: string;
        error?: undefined;
    } | {
        error: string;
        output?: undefined;
    }> | undefined;
    cancel_run?: import("ai").Tool<{
        name: string;
        runId: string;
    }, {
        ok: true;
        runId: string;
        state: string;
    } | {
        ok: false;
        error: string;
    }> | undefined;
    pause_run?: import("ai").Tool<{
        name: string;
        runId: string;
    }, {
        ok: true;
        runId: string;
        state: string;
    } | {
        ok: false;
        error: string;
    }> | undefined;
    resume_run?: import("ai").Tool<{
        name: string;
        runId: string;
    }, {
        ok: true;
        runId: string;
        state: string;
    } | {
        ok: false;
        error: string;
    }> | undefined;
    list_steps: import("ai").Tool<{
        path: string;
    }, {
        error: string;
        entries?: undefined;
    } | {
        entries: string[];
        error?: undefined;
    }>;
    search_steps: import("ai").Tool<{
        query: string;
    }, {
        matches: {
            type: string;
            description?: string;
        }[];
    }>;
    get_step: import("ai").Tool<{
        type: string;
    }, {
        error: string;
        type?: undefined;
        description?: undefined;
        fields?: undefined;
        source?: undefined;
    } | {
        type: string;
        description: string | undefined;
        fields: import("./schemaHelpers.js").FieldDesc[];
        source: string | undefined;
        error?: undefined;
    }>;
    list_secrets: import("ai").Tool<Record<string, never>, {
        error: string;
        secrets?: undefined;
    } | {
        secrets: {
            name: string;
            updatedAt: string;
        }[];
        error?: undefined;
    }>;
    create_step: import("ai").Tool<{
        name: string;
        code: string;
        description?: string | undefined;
    }, import("../authoring.js").StepPublishResult | {
        warning: string;
        ok?: true;
        error?: string;
        type?: string;
        version?: string;
        changed?: boolean;
        loaded?: boolean;
    }>;
    edit_step: import("ai").Tool<{
        type: string;
        code: string;
        description?: string | undefined;
    }, import("../authoring.js").StepPublishResult | {
        warning: string;
        ok?: true;
        error?: string;
        type?: string;
        version?: string;
        changed?: boolean;
        loaded?: boolean;
    }>;
    validate_workflow: import("ai").Tool<{
        yaml: string;
        name?: string | undefined;
    }, import("../validate.js").ValidationResult>;
    create_workflow: import("ai").Tool<{
        name: string;
        yaml: string;
        description?: string | undefined;
        category?: string | undefined;
    }, {
        ok: boolean;
        name: string;
        version: string;
        renamed: boolean;
        requested: string;
    } | {
        error: string;
        validation: import("../validate.js").ValidationResult;
    }>;
    edit_workflow: import("ai").Tool<{
        name: string;
        yaml: string;
        description?: string | undefined;
        category?: string | undefined;
    }, {
        ok: boolean;
        name: string;
        version: string;
        changed: boolean;
    } | {
        error: string;
        validation?: undefined;
    } | {
        error: string;
        validation: import("../validate.js").ValidationResult;
    }>;
    set_workflow_category: import("ai").Tool<{
        name: string;
        category: string | null;
    }, {
        ok: boolean;
        name: string;
        category: string | null;
        error?: undefined;
    } | {
        error: string;
        ok?: undefined;
        name?: undefined;
        category?: undefined;
    }>;
    set_active_version: import("ai").Tool<{
        kind: "workflow" | "step";
        name: string;
        version: string;
    }, {
        error: string;
        ok?: undefined;
        kind?: undefined;
        name?: undefined;
        active?: undefined;
    } | {
        ok: boolean;
        kind: "workflow" | "step";
        name: string;
        active: string;
        error?: undefined;
    }>;
    list_workflows: import("ai").Tool<Record<string, never>, {
        workflows: import("../workspace.js").WorkflowListEntry[];
    }>;
    get_workflow: import("ai").Tool<{
        name: string;
        version?: string | undefined;
    }, {
        error: string;
        name?: undefined;
        version?: undefined;
        activeVersion?: undefined;
        versions?: undefined;
        description?: undefined;
        yaml?: undefined;
    } | {
        name: string;
        version: string;
        activeVersion: string;
        versions: string[];
        description: string | undefined;
        yaml: string;
        error?: undefined;
    }>;
    run_workflow: import("ai").Tool<{
        name: string;
        input?: any;
        params?: Record<string, any> | undefined;
        version?: string | undefined;
    }, import("../core.js").RunResult | {
        ok: boolean;
        error: string;
        status?: undefined;
        detached?: undefined;
        runId?: undefined;
        workflow?: undefined;
        note?: undefined;
    } | {
        status: string;
        detached: boolean;
        runId: string;
        workflow: string;
        note: string;
        ok?: undefined;
        error?: undefined;
    }>;
    run_step: import("ai").Tool<{
        type: string;
        config?: Record<string, any> | undefined;
        input?: any;
        params?: Record<string, any> | undefined;
        cassette?: "record" | "replay" | undefined;
        cassetteName?: string | undefined;
    }, import("../run-step.js").RunStepResult | {
        error: string;
    }>;
    list_runs: import("ai").Tool<{
        name: string;
        limit: number;
    }, {
        workflow: string;
        runs: {
            error?: {
                message: string;
                stack?: string;
            } | undefined;
            runId: string;
            status: "error" | "success" | "cancelled" | undefined;
            startedAt: string | undefined;
            durationMs: number | undefined;
        }[];
    }>;
    get_run: import("ai").Tool<{
        name: string;
        runId: string;
        fullEvents: boolean;
    }, {
        error: string;
        workflow?: undefined;
        runId?: undefined;
        summary?: undefined;
        events?: undefined;
    } | {
        workflow: string;
        runId: string;
        summary: import("../core.js").RunSummary | null;
        events: {
            error?: {
                message: string;
                stack?: string;
            } | undefined;
            iteration?: number | undefined;
            durationMs?: number | undefined;
            stepType?: string | undefined;
            type: import("../core.js").RunEventType;
            path: string;
        }[];
        error?: undefined;
    }>;
    search_runs: import("ai").Tool<{
        name: string;
        pattern: string;
        runLimit: number;
        maxMatches: number;
        ignoreCase: boolean;
        runIds?: string[] | undefined;
    }, {
        error: string;
    } | {
        truncated?: boolean | undefined;
        note?: string | undefined;
        workflow: string;
        pattern: string;
        runsScanned: number;
        runsWithMatches: {
            runId: string;
            matchingEvents: number;
        }[];
        matches: import("../authoring.js").RunSearchMatch[];
        error?: undefined;
    }>;
};
