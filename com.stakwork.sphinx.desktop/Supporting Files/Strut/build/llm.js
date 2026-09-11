// ── LLM model resolution: strut's glue over aieo ────────────────────────────
//
// One place turns a model NAME — an alias ("sonnet"), a full id
// ("claude-opus-4-8"), or the canonical "provider/id" form
// ("openrouter/moonshotai/kimi-k2.6") — into a provider, a concrete id, an
// AI SDK LanguageModel and an output-token cap. The chat builder, the `agent`
// step and the `llm` step all come through here, so provider knowledge lives
// in aieo (`resolve.ts`) and nowhere in strut.
//
// Keys come through the secrets boundary: `ctx.services.secrets.get(name)`
// (secret store first, then env) is handed to aieo as `getSecret` and asked
// by the provider's env-var NAME (ANTHROPIC_API_KEY, OPENAI_API_KEY, …). So a
// key pasted under Secrets in the UI works, and one in env keeps working.
//
// aieo stays lazy-imported: its index pulls every provider SDK at load.
/** Name → everything a caller needs to run. Throws on an unknown provider,
 *  the no-prefix OpenRouter trap ("moonshotai/kimi-k2.6" — write
 *  "openrouter/moonshotai/kimi-k2.6"), or a missing key (the error names
 *  the env var / secret to set). */
export async function resolveModel(opts = {}) {
    const aieo = await import("aieo");
    const secrets = opts.secrets;
    const r = await aieo.resolveModel({
        model: opts.model,
        provider: opts.provider,
        getSecret: secrets ? (name) => secrets.get(name) : undefined,
    });
    return {
        provider: r.provider,
        modelId: r.modelId,
        name: r.name,
        apiKey: r.apiKey,
        model: r.model,
        contextLimit: r.contextLimit,
        maxOutputTokens: strutOutputCap() ?? r.maxOutputTokens,
    };
}
/**
 * Web tools for a resolved provider — the same `web_search` + `web_fetch`
 * on every provider, via aieo: Anthropic's native server-executed tools,
 * an Exa-backed search and a guarded HTTP fetch (public addresses only,
 * every redirect re-checked) everywhere else. One tool name and result
 * shape regardless of which model is driving.
 */
export async function createWebTools(opts) {
    const aieo = await import("aieo");
    // The Exa key only matters where the search shim runs (everything but
    // anthropic, whose tool is native) — don't touch the secret store otherwise.
    const searchApiKey = aieo.resolveSearchBackend(opts.provider) === "exa"
        ? await opts.secrets?.get("EXA_API_KEY")
        : undefined;
    const ws = aieo.createWebSearch({
        provider: opts.provider,
        apiKey: opts.apiKey,
        searchApiKey,
        maxUses: opts.searchMaxUses,
        abortSignal: opts.abortSignal,
    });
    const wf = aieo.createWebFetch({
        provider: opts.provider,
        apiKey: opts.apiKey,
        maxUses: opts.fetchMaxUses,
        abortSignal: opts.abortSignal,
    });
    return {
        tools: {
            ...(ws.tool ? { [aieo.WEB_SEARCH_TOOL_NAME]: ws.tool } : {}),
            ...(wf.tool ? { [aieo.WEB_FETCH_TOOL_NAME]: wf.tool } : {}),
        },
        capture: (c) => {
            ws.capture(c);
            wf.capture(c);
        },
    };
}
/** `STRUT_MAX_OUTPUT_TOKENS`, when set to a positive number. */
function strutOutputCap() {
    const n = Number(process.env["STRUT_MAX_OUTPUT_TOKENS"]);
    return n > 0 ? n : undefined;
}
/** Keyless: the canonical "<provider>/<modelId>" a name resolves to. Same
 *  errors as `resolveModel` minus the key check. */
export async function canonicalModelName(model, provider) {
    const aieo = await import("aieo");
    return aieo.canonicalModelName(model, provider).name;
}
/** aieo's alias catalog with per-provider availability. Never returns key
 *  values — only whether one exists. */
export async function listModelOptions(opts = {}) {
    const aieo = await import("aieo");
    const available = {};
    for (const p of aieo.PROVIDERS) {
        const fromSecrets = opts.secrets ? await opts.secrets.get(aieo.API_KEY_ENV[p]) : undefined;
        available[p] = !!fromSecrets?.trim() || aieo.hasApiKeyForProvider(p);
    }
    let def;
    try {
        def = aieo.canonicalModelName(opts.default).name;
    }
    catch {
        def = opts.default ?? ""; // a misconfigured default still lists the catalog
    }
    return {
        default: def,
        models: aieo.listModels().map((m) => ({
            ...m,
            name: `${m.provider}/${m.modelId}`,
            available: available[m.provider] ?? false,
        })),
        keyNames: { ...aieo.API_KEY_ENV },
    };
}
//# sourceMappingURL=llm.js.map