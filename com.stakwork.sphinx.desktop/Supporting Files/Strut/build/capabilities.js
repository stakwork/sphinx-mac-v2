/**
 * Standard "capabilities" — the small, generic, host-owned services that
 * LLM-authored adapter STEPS build on (see AGENTS.md "step vs service").
 *
 * An adapter step reaches the outside world through `ctx.services.http` (a
 * fetch-like transport) and `ctx.services.secrets` (credential access), never
 * the global `fetch` / `process.env` directly. Routing I/O through these two
 * capabilities is what makes an adapter:
 *   - **recordable** — `http` returns a PLAIN serializable object (a real
 *     `fetch` Response can't be written to a cassette), so the record/replay
 *     wrapper (`cassette.ts`) can capture and replay it; and
 *   - **leak-free** — secrets flow through one boundary, so the recorder knows
 *     exactly which values to scrub out of the cassette.
 *
 * These are the DEFAULT implementations the standard server injects. Consumers
 * using strut as a library can spread them into — or override them within —
 * their own typed services bag.
 */
import { mkdir, readFile, writeFile, readdir } from "node:fs/promises";
import { dirname as pathDirname, join as pathJoin, relative as pathRelative, resolve as pathResolve, sep as pathSep, } from "node:path";
/**
 * Build a secrets capability. Pass either:
 *   - a flat key→value source (defaults to `process.env`), or
 *   - a `SecretReadable` store (e.g. a `SecretStore`), optionally with an
 *     `envFallback` so unset secrets still resolve from `process.env`.
 *
 * The store path is async-aware: a managed secret wins, then the env fallback.
 */
export function secretsCapability(source = process.env, opts = {}) {
    if (typeof source.get === "function") {
        const store = source;
        const fallback = opts.envFallback;
        return {
            async get(name) {
                const v = await store.get(name);
                if (v !== undefined)
                    return v;
                return fallback?.[name];
            },
        };
    }
    const flat = source;
    return {
        async get(name) {
            return flat[name];
        },
    };
}
function appendQuery(url, query) {
    if (!query)
        return url;
    const pairs = Object.entries(query).map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(String(v))}`);
    if (!pairs.length)
        return url;
    return url + (url.includes("?") ? "&" : "?") + pairs.join("&");
}
/** Build an http capability over a `fetch` implementation (defaults to the
 *  global `fetch`). Encodes object bodies as JSON, parses JSON responses, and
 *  returns a plain serializable {@link HttpResponse}. */
export function httpCapability(fetchImpl = globalThis.fetch) {
    if (typeof fetchImpl !== "function") {
        throw new Error("httpCapability: no fetch available — pass a fetch implementation");
    }
    return async (url, opts = {}) => {
        const headers = { ...(opts.headers ?? {}) };
        let body;
        if (opts.body !== undefined) {
            if (typeof opts.body === "string") {
                body = opts.body;
            }
            else {
                body = JSON.stringify(opts.body);
                if (!hasHeader(headers, "content-type")) {
                    headers["content-type"] = "application/json";
                }
            }
        }
        const res = await fetchImpl(appendQuery(url, opts.query), {
            method: opts.method ?? (opts.body !== undefined ? "POST" : "GET"),
            headers,
            body,
            ...(opts.timeout ? { signal: AbortSignal.timeout(opts.timeout) } : {}),
        });
        const outHeaders = {};
        res.headers.forEach((value, key) => {
            outHeaders[key.toLowerCase()] = value;
        });
        const text = await res.text();
        const isJson = (outHeaders["content-type"] ?? "").includes("application/json");
        let parsed = text;
        if (isJson || looksLikeJson(text)) {
            try {
                parsed = JSON.parse(text);
            }
            catch {
                parsed = text;
            }
        }
        return { status: res.status, ok: res.ok, headers: outHeaders, body: parsed };
    };
}
function hasHeader(headers, name) {
    return Object.keys(headers).some((k) => k.toLowerCase() === name);
}
function looksLikeJson(text) {
    const t = text.trim();
    return t.startsWith("{") || t.startsWith("[");
}
/** Reject run ids / relative paths that could escape the RUN's directory
 *  (one run must not reach another run's files). Returns the resolved
 *  absolute path when safe. */
function artifactPath(root, runId, relPath = "") {
    if (!runId || /[/\\]|\.\./.test(runId)) {
        throw new Error(`artifacts: invalid runId "${runId}"`);
    }
    const runDir = pathResolve(root, runId);
    const abs = pathResolve(runDir, relPath);
    if (abs !== runDir && !abs.startsWith(runDir + pathSep)) {
        throw new Error(`artifacts: path escapes the artifact root: ${relPath}`);
    }
    return abs;
}
/** Filesystem-backed artifacts capability rooted at `root`
 *  (`<root>/<runId>/<relPath>`). The default the standard server injects,
 *  rooted at `<workspace>/artifacts`. */
export function fileArtifactsCapability(root) {
    return {
        async dir(runId) {
            const d = artifactPath(root, runId);
            await mkdir(d, { recursive: true });
            return d;
        },
        async write(runId, relPath, content) {
            const abs = artifactPath(root, runId, relPath);
            await mkdir(pathDirname(abs), { recursive: true });
            await writeFile(abs, content);
            return abs;
        },
        async read(runId, relPath) {
            const abs = artifactPath(root, runId, relPath);
            return new Uint8Array(await readFile(abs));
        },
        async list(runId) {
            const d = artifactPath(root, runId);
            let entries;
            try {
                entries = await readdir(d, { recursive: true, withFileTypes: true });
            }
            catch (err) {
                if (err?.code === "ENOENT")
                    return [];
                throw err;
            }
            return entries
                .filter((e) => e.isFile())
                .map((e) => pathRelative(d, pathJoin(e.parentPath, e.name)))
                .sort();
        },
    };
}
/** The default standard services bag: global-fetch http + secrets. Secrets are
 *  env-backed by default; pass `secretStore` for a persisted (UI-managed) store
 *  with `process.env` as fallback. Injected by the standard server; override
 *  per environment as needed. */
export function standardServices(opts = {}) {
    const secrets = opts.secretStore
        ? secretsCapability(opts.secretStore, { envFallback: process.env })
        : secretsCapability(opts.secretsSource);
    return {
        http: httpCapability(opts.fetchImpl),
        secrets,
    };
}
//# sourceMappingURL=capabilities.js.map