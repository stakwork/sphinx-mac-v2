/**
 * Deployment-scoped secret store — the persistence behind the `secrets`
 * capability (see `capabilities.ts`). Steps still read credentials through
 * the read-only `ctx.services.secrets.get(name)` boundary (which keeps
 * cassette scrubbing working); this module is the *admin* side that lets a
 * UI / API create, list, and delete the values that boundary serves.
 *
 * Scope is deployment-global (one store per workspace), matching the
 * `STRUT_API_KEY` single-trust-domain model — NOT per-user. The mutating
 * endpoints are gated by `STRUT_API_KEY` (see `createStrut.ts`).
 *
 * **At-rest encryption.** Values are encrypted with AES-256-GCM using a key
 * derived (scrypt) from `STRUT_SECRET_KEY`. A random per-file salt is stored
 * in the header. Without `STRUT_SECRET_KEY` set, a fixed dev passphrase is
 * used and a one-time warning is logged — the on-disk file is then only
 * obfuscated, not meaningfully protected. Set `STRUT_SECRET_KEY` in any real
 * deployment.
 */
/** Metadata about a stored secret. Deliberately never includes the value —
 *  `list()` and the `GET /secrets` endpoint return only this shape. */
export interface SecretInfo {
    name: string;
    createdAt: string;
    updatedAt: string;
}
/**
 * Admin interface for managing secrets. The step-facing read path
 * (`SecretsCapability.get`) is intentionally separate and narrower; build it
 * over a store with `secretsCapability(store)` in `capabilities.ts`.
 */
export interface SecretStore {
    /** Read a secret value (decrypted), or undefined if not set. */
    get(name: string): Promise<string | undefined>;
    /** Create or overwrite a secret. */
    set(name: string, value: string): Promise<void>;
    /** Delete a secret. Returns true if it existed. */
    delete(name: string): Promise<boolean>;
    /** List secret NAMES + metadata — never values. */
    list(): Promise<SecretInfo[]>;
}
export declare function isValidSecretName(name: string): boolean;
export declare function assertValidSecretName(name: string): void;
/** Filesystem-backed, encrypted secret store. Persists a single
 *  `<workspace>/secrets.json` with a random per-file salt + AES-256-GCM
 *  values. The default for the standard server. */
export declare class FileSecretStore implements SecretStore {
    private file;
    private cache;
    constructor(workspaceRoot: string);
    private load;
    private save;
    get(name: string): Promise<string | undefined>;
    set(name: string, value: string): Promise<void>;
    delete(name: string): Promise<boolean>;
    list(): Promise<SecretInfo[]>;
}
/** In-memory secret store. No encryption (nothing hits disk). For tests and
 *  ephemeral / library usage. */
export declare class MemorySecretStore implements SecretStore {
    private map;
    get(name: string): Promise<string | undefined>;
    set(name: string, value: string): Promise<void>;
    delete(name: string): Promise<boolean>;
    list(): Promise<SecretInfo[]>;
}
/** Test-only: reset the one-time no-key warning so tests stay deterministic. */
export declare function _resetSecretWarning(): void;
