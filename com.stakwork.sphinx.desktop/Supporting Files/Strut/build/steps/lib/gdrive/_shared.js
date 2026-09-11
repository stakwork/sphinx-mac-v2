export const DRIVE_READONLY_SCOPE = "https://www.googleapis.com/auth/drive.readonly";
/** Build an authenticated Drive v3 client. Credentials flow through the secrets
 *  capability (UI store → env fallback), explicit `accessToken` config wins.
 *  Returns `haveAuth` so error messages can distinguish "no creds at all" from
 *  "creds present but rejected". See AGENTS.md "Lib step credentials". */
export async function buildDriveClient(accessToken, ctx) {
    const { drive, auth } = await import("@googleapis/drive");
    const secrets = ctx?.services?.secrets;
    const token = accessToken ?? (await secrets?.get("GOOGLE_ACCESS_TOKEN"));
    const saJson = await secrets?.get("GOOGLE_SERVICE_ACCOUNT_JSON");
    let authClient;
    if (token) {
        const oauth = new auth.OAuth2();
        oauth.setCredentials({ access_token: token });
        authClient = oauth;
    }
    else if (saJson) {
        // A pasted service-account JSON key (no expiry — the recommended setup).
        let credentials;
        try {
            credentials = JSON.parse(saJson);
        }
        catch {
            throw new Error("GOOGLE_SERVICE_ACCOUNT_JSON is not valid JSON. Paste the full service-account key file (the JSON object with client_email/private_key) into the secret.");
        }
        authClient = new auth.GoogleAuth({
            credentials,
            scopes: [DRIVE_READONLY_SCOPE],
        });
    }
    else {
        // Application Default Credentials (e.g. GOOGLE_APPLICATION_CREDENTIALS).
        authClient = new auth.GoogleAuth({ scopes: [DRIVE_READONLY_SCOPE] });
    }
    return {
        client: drive({ version: "v3", auth: authClient }),
        haveAuth: Boolean(token || saJson),
    };
}
/** Extract the HTTP status from a googleapis/gaxios error (it lives on
 *  `.status`, `.code`, or `.response.status` depending on the path). */
export function statusOf(err) {
    const e = err;
    const raw = e?.status ?? e?.response?.status ?? e?.code;
    const n = typeof raw === "string" ? Number(raw) : raw;
    return typeof n === "number" && !Number.isNaN(n) ? n : undefined;
}
/** Turn an opaque Drive API error into an actionable one. Google returns 404
 *  both for missing resources and for ones the caller can't see; 401/403 mean
 *  the token is bad or lacks the drive.readonly scope. `resource` is a short
 *  label for the thing being accessed, e.g. `file "abc"` or `file listing`. */
export function describeDriveError(err, resource, haveAuth) {
    const status = statusOf(err);
    const msg = err?.message ?? "";
    // No credentials resolved at all → Application Default Credentials threw.
    if (!haveAuth && /could not load the default credentials/i.test(msg)) {
        return new Error("No Google credentials available. Pass an OAuth `accessToken`, or add a GOOGLE_ACCESS_TOKEN / GOOGLE_SERVICE_ACCOUNT_JSON secret (or set GOOGLE_APPLICATION_CREDENTIALS).");
    }
    switch (status) {
        case 404:
            return new Error(`Google Drive ${resource} not found. The ID may be wrong, or the authenticated account/service account may not have access (share it with them).`);
        case 401:
            return new Error(`Google Drive auth failed (401) for ${resource}. The access token is missing, expired, or invalid — refresh it or re-add the GOOGLE_ACCESS_TOKEN secret.`);
        case 403:
            return new Error(`Google Drive access denied (403) for ${resource}. The credentials lack permission or the drive.readonly scope, or the Drive API is not enabled for the project.`);
        default:
            return err instanceof Error ? err : new Error(String(err));
    }
}
//# sourceMappingURL=_shared.js.map