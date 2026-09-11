import type { StepContext } from "../../../core.js";
import type { StrutCapabilities } from "../../../capabilities.js";
/** Resolve a Slack bot token: explicit config wins, else the SLACK_BOT_TOKEN
 *  secret (UI-managed store → env). Throws an actionable error if neither. */
export declare function slackToken(explicit: string | undefined, ctx: StepContext<StrutCapabilities>): Promise<string>;
/** Call a Slack Web API method and return its (ok:true) payload.
 *
 *  Slack is unusual: it returns HTTP 200 even on logical failures, signalling
 *  the real outcome in the JSON body (`{ ok: false, error: "channel_not_found" }`).
 *  So we check `body.ok`, NOT the HTTP status, and map the common `error`
 *  codes to actionable messages. */
export declare function slackCall(ctx: StepContext<StrutCapabilities>, method: string, token: string, opts?: {
    body?: unknown;
    query?: Record<string, string | number | boolean>;
}): Promise<Record<string, unknown>>;
/** Map a Slack `error` code to an actionable Error. Unknown codes pass through
 *  verbatim so nothing is swallowed. */
export declare function describeSlackError(error: string, method: string): Error;
