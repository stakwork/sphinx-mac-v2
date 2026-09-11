import type { drive_v3 } from "@googleapis/drive";
import type { StepContext } from "../../../core.js";
import type { StrutCapabilities } from "../../../capabilities.js";
export declare const DRIVE_READONLY_SCOPE = "https://www.googleapis.com/auth/drive.readonly";
/** Build an authenticated Drive v3 client. Credentials flow through the secrets
 *  capability (UI store → env fallback), explicit `accessToken` config wins.
 *  Returns `haveAuth` so error messages can distinguish "no creds at all" from
 *  "creds present but rejected". See AGENTS.md "Lib step credentials". */
export declare function buildDriveClient(accessToken: string | undefined, ctx: StepContext<StrutCapabilities>): Promise<{
    client: drive_v3.Drive;
    haveAuth: boolean;
}>;
/** Extract the HTTP status from a googleapis/gaxios error (it lives on
 *  `.status`, `.code`, or `.response.status` depending on the path). */
export declare function statusOf(err: unknown): number | undefined;
/** Turn an opaque Drive API error into an actionable one. Google returns 404
 *  both for missing resources and for ones the caller can't see; 401/403 mean
 *  the token is bad or lacks the drive.readonly scope. `resource` is a short
 *  label for the thing being accessed, e.g. `file "abc"` or `file listing`. */
export declare function describeDriveError(err: unknown, resource: string, haveAuth: boolean): Error;
