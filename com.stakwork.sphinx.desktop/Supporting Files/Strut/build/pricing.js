// ── LLM token usage + cost ───────────────────────────────────────────────────
//
// A tiny, provider-aware pricing helper shared by the LLM steps (the core
// `agent` step, plus the lab's eval/reflect + gitsee/score-setup). It normalizes
// the Vercel AI SDK's usage object into a flat { input, cacheRead, cacheWrite,
// output } token count and turns that into a dollar cost.
//
// Pricing table copied from `mcp/src/aieo/src/provider.ts` ($ per 1M tokens).
// Keep it in sync when that table changes.
// $ per 1,000,000 tokens. Source of truth: mcp/src/aieo/src/provider.ts.
export const TOKEN_PRICING = {
    anthropic: {
        inputTokenPrice: 3.0,
        outputTokenPrice: 15.0,
        cacheReadPrice: 0.3,
        cacheWritePrice: 3.75,
    },
    google: {
        inputTokenPrice: 1.25,
        outputTokenPrice: 5.0,
    },
    openai: {
        inputTokenPrice: 2.5,
        outputTokenPrice: 10.0,
    },
    openrouter: {
        inputTokenPrice: 0.6,
        outputTokenPrice: 3.0,
    },
    // Grok has no cache-write charge — writes are billed as ordinary input,
    // so no cacheWritePrice here.
    xai: {
        inputTokenPrice: 3.0,
        outputTokenPrice: 15.0,
        cacheReadPrice: 0.75,
    },
};
export function emptyUsage() {
    return { inputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0, outputTokens: 0, totalTokens: 0 };
}
const num = (v) => (typeof v === "number" && Number.isFinite(v) ? v : 0);
/**
 * Normalize a Vercel AI SDK `LanguageModelUsage` (the `.usage` / `.totalUsage`
 * on a generate result) into a flat {@link TokenUsage}. Prefers the v6
 * `inputTokenDetails` breakdown (noCache / cacheRead / cacheWrite); falls back
 * to the flat `inputTokens` + deprecated `cachedInputTokens` when details are
 * absent (other providers), treating the remainder as non-cached input.
 */
export function usageFromResult(usage) {
    if (!usage || typeof usage !== "object")
        return emptyUsage();
    const u = usage;
    const details = (u.inputTokenDetails ?? {});
    const cacheReadTokens = num(details.cacheReadTokens ?? u.cachedInputTokens);
    const cacheWriteTokens = num(details.cacheWriteTokens);
    // Non-cached input: the detailed noCacheTokens when present, else the flat
    // total input minus what we already accounted as cache read/write.
    const inputTokens = details.noCacheTokens != null
        ? num(details.noCacheTokens)
        : Math.max(0, num(u.inputTokens) - cacheReadTokens - cacheWriteTokens);
    const outputTokens = num(u.outputTokens);
    const totalTokens = num(u.totalTokens) || inputTokens + cacheReadTokens + cacheWriteTokens + outputTokens;
    return { inputTokens, cacheReadTokens, cacheWriteTokens, outputTokens, totalTokens };
}
/** Sum two normalized usages (e.g. across multiple LLM calls in one run). */
export function addUsage(a, b) {
    return {
        inputTokens: a.inputTokens + b.inputTokens,
        cacheReadTokens: a.cacheReadTokens + b.cacheReadTokens,
        cacheWriteTokens: a.cacheWriteTokens + b.cacheWriteTokens,
        outputTokens: a.outputTokens + b.outputTokens,
        totalTokens: a.totalTokens + b.totalTokens,
    };
}
/** Coerce an unknown (e.g. a usage object threaded through a workflow template)
 *  back into a {@link TokenUsage} so it can be safely summed. */
export function coerceUsage(usage) {
    if (!usage || typeof usage !== "object")
        return emptyUsage();
    const u = usage;
    return {
        inputTokens: num(u.inputTokens),
        cacheReadTokens: num(u.cacheReadTokens),
        cacheWriteTokens: num(u.cacheWriteTokens),
        outputTokens: num(u.outputTokens),
        totalTokens: num(u.totalTokens) || num(u.inputTokens) + num(u.cacheReadTokens) + num(u.cacheWriteTokens) + num(u.outputTokens),
    };
}
/** Dollar cost of a usage at a provider's rates. Unknown providers default to
 *  anthropic pricing; cache prices default to the input price when unset. */
export function computeCost(provider, usage) {
    const p = TOKEN_PRICING[provider] ?? TOKEN_PRICING.anthropic;
    const M = 1_000_000;
    return ((usage.inputTokens / M) * p.inputTokenPrice +
        (usage.cacheReadTokens / M) * (p.cacheReadPrice ?? p.inputTokenPrice) +
        (usage.cacheWriteTokens / M) * (p.cacheWritePrice ?? p.inputTokenPrice) +
        (usage.outputTokens / M) * p.outputTokenPrice);
}
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
export function maxOutputTokensFor(provider) {
    const env = Number(process.env["STRUT_MAX_OUTPUT_TOKENS"]);
    if (env > 0)
        return env;
    return provider === "anthropic" ? 128_000 : 64_000;
}
//# sourceMappingURL=pricing.js.map