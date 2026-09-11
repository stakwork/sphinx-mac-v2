import type { Context, Next } from "hono";
/** Emit a one-time stderr warning if running without a configured key. */
export declare function warnIfUnconfigured(): void;
/**
 * Hono middleware that gates step-registration mutations on a bearer
 * token matching `STRUT_API_KEY`. Permissive when the env var is unset.
 */
export declare function requireApiKey(c: Context, next: Next): Promise<void | (Response & import("hono").TypedResponse<{
    error: string;
}, 401, "json">)>;
/**
 * Does a request carry the deployment key? Accepts `Authorization: Bearer`
 * and, when the caller passes it, a `?key=` query value — the WebSocket
 * dictation route needs the latter because a browser's WebSocket cannot set
 * headers. Permissive (true) when `STRUT_API_KEY` is unset.
 */
export declare function apiKeyMatches(authorization: string | undefined, queryKey?: string | null): boolean;
/** Test-only: reset the one-time-warning state so tests stay deterministic. */
export declare function _resetAuthState(): void;
