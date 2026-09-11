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
import { createCipheriv, createDecipheriv, randomBytes, scryptSync, } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
// ── name validation ──────────────────────────────────────────────────────
/** Secret names are env-var-style identifiers: letters, digits, underscore,
 *  not starting with a digit. Keeps them safe as keys + matches the
 *  `secrets.get("NAME")` convention. */
const NAME_RE = /^[A-Za-z_][A-Za-z0-9_]*$/;
export function isValidSecretName(name) {
    return NAME_RE.test(name);
}
export function assertValidSecretName(name) {
    if (!isValidSecretName(name)) {
        throw new Error(`invalid secret name "${name}" — use letters, digits, underscore (not starting with a digit)`);
    }
}
// ── encryption helpers ───────────────────────────────────────────────────
const ENV_KEY = "STRUT_SECRET_KEY";
const DEV_PASSPHRASE = "strut-insecure-dev-key";
let warnedNoKey = false;
function passphrase() {
    const v = process.env[ENV_KEY];
    if (v && v.length > 0)
        return v;
    if (!warnedNoKey) {
        warnedNoKey = true;
        console.warn(`[strut] ${ENV_KEY} is not set — secrets are stored with a default key (obfuscated, NOT securely encrypted). Set ${ENV_KEY} in production.`);
    }
    return DEV_PASSPHRASE;
}
function deriveKey(salt) {
    return scryptSync(passphrase(), salt, 32);
}
function encrypt(value, salt) {
    const key = deriveKey(salt);
    const iv = randomBytes(12);
    const cipher = createCipheriv("aes-256-gcm", key, iv);
    const ct = Buffer.concat([cipher.update(value, "utf-8"), cipher.final()]);
    const tag = cipher.getAuthTag();
    return { iv: iv.toString("base64"), tag: tag.toString("base64"), ct: ct.toString("base64") };
}
function decrypt(enc, salt) {
    const key = deriveKey(salt);
    const decipher = createDecipheriv("aes-256-gcm", key, Buffer.from(enc.iv, "base64"));
    decipher.setAuthTag(Buffer.from(enc.tag, "base64"));
    const pt = Buffer.concat([
        decipher.update(Buffer.from(enc.ct, "base64")),
        decipher.final(),
    ]);
    return pt.toString("utf-8");
}
// ── filesystem implementation ────────────────────────────────────────────
/** Filesystem-backed, encrypted secret store. Persists a single
 *  `<workspace>/secrets.json` with a random per-file salt + AES-256-GCM
 *  values. The default for the standard server. */
export class FileSecretStore {
    file;
    cache = null;
    constructor(workspaceRoot) {
        this.file = join(workspaceRoot, "secrets.json");
    }
    async load() {
        if (this.cache)
            return this.cache;
        try {
            const raw = await readFile(this.file, "utf-8");
            this.cache = JSON.parse(raw);
        }
        catch {
            this.cache = { version: 1, salt: randomBytes(16).toString("base64"), secrets: {} };
        }
        return this.cache;
    }
    async save(data) {
        this.cache = data;
        await mkdir(dirname(this.file), { recursive: true });
        await writeFile(this.file, JSON.stringify(data, null, 2), "utf-8");
    }
    async get(name) {
        const data = await this.load();
        const enc = data.secrets[name];
        if (!enc)
            return undefined;
        return decrypt(enc, Buffer.from(data.salt, "base64"));
    }
    async set(name, value) {
        assertValidSecretName(name);
        const data = await this.load();
        const salt = Buffer.from(data.salt, "base64");
        const now = new Date().toISOString();
        const existing = data.secrets[name];
        data.secrets[name] = {
            ...encrypt(value, salt),
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
        };
        await this.save(data);
    }
    async delete(name) {
        const data = await this.load();
        if (!(name in data.secrets))
            return false;
        delete data.secrets[name];
        await this.save(data);
        return true;
    }
    async list() {
        const data = await this.load();
        return Object.entries(data.secrets)
            .map(([name, v]) => ({ name, createdAt: v.createdAt, updatedAt: v.updatedAt }))
            .sort((a, b) => a.name.localeCompare(b.name));
    }
}
// ── in-memory implementation (tests / ephemeral) ──────────────────────────
/** In-memory secret store. No encryption (nothing hits disk). For tests and
 *  ephemeral / library usage. */
export class MemorySecretStore {
    map = new Map();
    async get(name) {
        return this.map.get(name)?.value;
    }
    async set(name, value) {
        assertValidSecretName(name);
        const now = new Date().toISOString();
        const existing = this.map.get(name);
        this.map.set(name, { value, createdAt: existing?.createdAt ?? now, updatedAt: now });
    }
    async delete(name) {
        return this.map.delete(name);
    }
    async list() {
        return [...this.map.entries()]
            .map(([name, v]) => ({ name, createdAt: v.createdAt, updatedAt: v.updatedAt }))
            .sort((a, b) => a.name.localeCompare(b.name));
    }
}
/** Test-only: reset the one-time no-key warning so tests stay deterministic. */
export function _resetSecretWarning() {
    warnedNoKey = false;
}
//# sourceMappingURL=secret-store.js.map