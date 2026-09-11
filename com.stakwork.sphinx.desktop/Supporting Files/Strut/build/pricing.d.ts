export type LLMProvider = "anthropic" | "openai" | "google" | "openrouter" | "xai";
export interface TokenPricing {
    inputTokenPrice: number;
    outputTokenPrice: number;
    cacheReadPrice?: number;
    cacheWritePrice?: number;
}
export declare const TOKEN_PRICING: Record<LLMProvider, TokenPricing>;
/** Normalized, provider-agnostic token counts (flat, addable across calls). */
export interface TokenUsage {
    inputTokens: number;
    cacheReadTokens: number;
    cacheWriteTokens: number;
    outputTokens: number;
    totalTokens: number;
}
export declare function emptyUsage(): TokenUsage;
/**
 * Normalize a Vercel AI SDK `LanguageModelUsage` (the `.usage` / `.totalUsage`
 * on a generate result) into a flat {@link TokenUsage}. Prefers the v6
 * `inputTokenDetails` breakdown (noCache / cacheRead / cacheWrite); falls back
 * to the flat `inputTokens` + deprecated `cachedInputTokens` when details are
 * absent (other providers), treating the remainder as non-cached input.
 */
export declare function usageFromResult(usage: unknown): TokenUsage;
/** Sum two normalized usages (e.g. across multiple LLM calls in one run). */
export declare function addUsage(a: TokenUsage, b: TokenUsage): TokenUsage;
/** Coerce an unknown (e.g. a usage object threaded through a workflow template)
 *  back into a {@link TokenUsage} so it can be safely summed. */
export declare function coerceUsage(usage: unknown): TokenUsage;
/** Dollar cost of a usage at a provider's rates. Unknown providers default to
 *  anthropic pricing; cache prices default to the input price when unset. */
export declare function computeCost(provider: string, usage: TokenUsage): number;
/**
 * Per-generation output-token cap for a provider — an INFRA constant, not a
 * step/workflow config (a workflow author never picks this; a wrong value is
 * only ever a bug). Mirrors mcp's `maxOutputTokensFor`: without an explicit
 * cap the AI SDK's providers default max_tokens to 4096, which truncates a
 * long draft or a large tool call MID-JSON (finish=length) and kills the
 * loop. Anthropic models take 128k; other providers reject max_tokens above
 * the model limit rather than clamping, so they keep a conservative 64k.
 * `STRUT_MAX_OUTPUT_TOKENS` overrides for all providers.
 */
export declare function maxOutputTokensFor(provider?: string): number;
