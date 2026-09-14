import type { TokenUsageForCost } from "aieo";
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
/** The shape aieo's `computeSessionCost(provider, usage, modelId?)` prices —
 *  `computeSessionCost(provider, usageForCost(u))` is the whole cost calc. */
export declare function usageForCost(u: TokenUsage): TokenUsageForCost;
