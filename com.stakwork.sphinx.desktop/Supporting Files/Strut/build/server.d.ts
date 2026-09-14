/**
 * Hono app for the default strut. Returns the same
 * instance on repeated calls. Most code should call `createStrut()`
 * directly and mount `strut.app` — this helper exists for ergonomic
 * scripting and backwards compatibility.
 */
export declare function getApp(): Promise<import("hono").Hono<import("hono/types").BlankEnv, import("hono/types").BlankSchema, "/">>;
/**
 * Boot the default strut server on `port` (defaults to
 * `STRUT_PORT` or `3000`). Equivalent to:
 *
 * ```ts
 * const strut = await createStrut();
 * await strut.listen(port);
 * ```
 */
export declare function startServer(port?: number, host?: string): Promise<number>;
