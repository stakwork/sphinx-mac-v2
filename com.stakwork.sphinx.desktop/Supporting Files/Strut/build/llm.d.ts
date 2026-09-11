import type { Provider } from "aieo";
import type { SecretsCapability } from "./capabilities.js";
export interface ResolveModelOptions {
    /** alias | id | "provider/id" | "openrouter/org/id". Omit for the provider's default. */
    model?: string;
    /** Explicit provider; otherwise inferred from `model`. */
    provider?: string;
    /** The secrets boundary (`ctx.services.secrets`). Optional — without it
     *  aieo reads `process.env` directly. */
    secrets?: SecretsCapability;
}
export interface ResolvedModel {
    provider: Provider;
    /** Concrete id as the provider knows it (alias resolved, prefix stripped). */
    modelId: string;
    /** Canonical "<provider>/<modelId>" — what `ChatMeta.model` records. */
    name: string;
    /** The key the model was built with — for `createWebTools` (the
     *  anthropic native tools need it). Never log or persist it. */
    apiKey: string;
    /** The AI SDK LanguageModel. Typed loosely so `ai`/aieo stay lazy. */
    model: any;
    contextLimit: number;
    /** Per-generation output cap: aieo's per-provider value (anthropic 128k,
     *  else 64k — without it the SDK's 4096 default truncates big tool calls
     *  mid-JSON), with strut's `STRUT_MAX_OUTPUT_TOKENS` override on top. An
     *  infra constant, never step/workflow config. */
    maxOutputTokens: number;
}
/** Name → everything a caller needs to run. Throws on an unknown provider,
 *  the no-prefix OpenRouter trap ("moonshotai/kimi-k2.6" — write
 *  "openrouter/moonshotai/kimi-k2.6"), or a missing key (the error names
 *  the env var / secret to set). */
export declare function resolveModel(opts?: ResolveModelOptions): Promise<ResolvedModel>;
export interface WebTools {
    /** `web_search` and/or `web_fetch`, ready to spread into a tool set. A
     *  tool is absent when its backend has no key: search off anthropic
     *  needs `EXA_API_KEY` (secret store or env); fetch always builds. */
    tools: Record<string, any>;
    /** Feed each step's content (AI SDK `onStepFinish`) so native results
     *  are recorded on the handles. Optional bookkeeping. */
    capture(stepContent: unknown): void;
}
/**
 * Web tools for a resolved provider — the same `web_search` + `web_fetch`
 * on every provider, via aieo: Anthropic's native server-executed tools,
 * an Exa-backed search and a guarded HTTP fetch (public addresses only,
 * every redirect re-checked) everywhere else. One tool name and result
 * shape regardless of which model is driving.
 */
export declare function createWebTools(opts: {
    provider: Provider;
    /** The resolved LLM key (`ResolvedModel.apiKey`). */
    apiKey?: string;
    /** The secrets boundary — the Exa key (`EXA_API_KEY`) is read through it. */
    secrets?: SecretsCapability;
    /** Max `web_search` calls per run (aieo default 3). */
    searchMaxUses?: number;
    /** Max `web_fetch` calls per run (aieo default 5). */
    fetchMaxUses?: number;
    abortSignal?: AbortSignal;
}): Promise<WebTools>;
/** Keyless: the canonical "<provider>/<modelId>" a name resolves to. Same
 *  errors as `resolveModel` minus the key check. */
export declare function canonicalModelName(model?: string, provider?: string): Promise<string>;
export interface ModelOption {
    provider: Provider;
    alias: string;
    modelId: string;
    /** Canonical name — the value a picker submits. */
    name: string;
    /** The provider's default model. */
    default: boolean;
    /** A key for this provider is configured (secret store or env). */
    available: boolean;
}
export interface ModelCatalog {
    /** The deployment's default chat model, canonical. */
    default: string;
    models: ModelOption[];
    /** provider → the env var / secret NAME that holds its key. */
    keyNames: Record<string, string>;
}
/** aieo's alias catalog with per-provider availability. Never returns key
 *  values — only whether one exists. */
export declare function listModelOptions(opts?: {
    default?: string;
    secrets?: SecretsCapability;
}): Promise<ModelCatalog>;
