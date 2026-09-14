import { mkdir, writeFile, appendFile, readFile, readdir, rm, } from "node:fs/promises";
import { join } from "node:path";
import { tailJsonl } from "./store.js";
/** A turn is terminal once its log records a `chat.end` or `chat.error`. */
export function isChatTerminal(e) {
    return e.type === "chat.end" || e.type === "chat.error";
}
// ── Tool-result truncation (token hygiene for long autonomous loops) ────────
/** Default per-string cap for `truncateToolMessages`. Env
 *  `STRUT_CHAT_TOOL_RESULT_MAX_CHARS` overrides it; `0` disables truncation. */
export const DEFAULT_TOOL_RESULT_MAX_CHARS = 50_000;
/** Resolve the tool-result cap from the environment (see above). */
export function toolResultMaxCharsFromEnv() {
    const raw = process.env["STRUT_CHAT_TOOL_RESULT_MAX_CHARS"];
    if (raw === undefined || raw === "")
        return DEFAULT_TOOL_RESULT_MAX_CHARS;
    const n = Number(raw);
    return Number.isFinite(n) && n >= 0 ? n : DEFAULT_TOOL_RESULT_MAX_CHARS;
}
/**
 * `messages.jsonl` stays lossless on disk (it's the transcript), but the copy
 * re-fed to the model each turn can balloon: a single `repo_overview` or eval
 * result is huge and the model already processed it. Truncate long strings
 * inside `role: "tool"` messages (tool RESULTS) before sending them back.
 * Conservative: only tool messages, only strings over `maxChars`, structure
 * preserved (we just shorten strings + add a marker). Within the turn that
 * ran the tool the model always sees the full result — this only applies to
 * HISTORY replayed on later turns. `maxChars` of `0` disables it.
 */
export function truncateToolMessages(messages, maxChars = toolResultMaxCharsFromEnv()) {
    if (maxChars <= 0)
        return messages;
    const shorten = (s) => s.length > maxChars
        ? `${s.slice(0, maxChars)}\n\n[TRUNCATED: ${s.length} chars — full content is in the chat transcript]`
        : s;
    const walk = (v) => {
        if (typeof v === "string")
            return shorten(v);
        if (Array.isArray(v))
            return v.map(walk);
        if (v && typeof v === "object") {
            const out = {};
            for (const [k, val] of Object.entries(v))
                out[k] = walk(val);
            return out;
        }
        return v;
    };
    return messages.map((m) => m.role === "tool" ? { ...m, content: walk(m.content) } : m);
}
// ── Filesystem implementation ──────────────────────────────────────────────
export class FileChatStore {
    workspaceRoot;
    constructor(workspaceRoot) {
        this.workspaceRoot = workspaceRoot;
    }
    chatDir(chatId) {
        return join(this.workspaceRoot, "chats", chatId);
    }
    metaFile(chatId) {
        return join(this.chatDir(chatId), "meta.json");
    }
    async createChat(init) {
        const now = new Date().toISOString();
        const meta = {
            id: init.id,
            ...(init.title ? { title: init.title } : {}),
            status: "live",
            ...(init.model ? { model: init.model } : {}),
            createdAt: now,
            updatedAt: now,
            currentTurn: -1,
        };
        await mkdir(this.chatDir(init.id), { recursive: true });
        await writeFile(this.metaFile(init.id), JSON.stringify(meta, null, 2), "utf-8");
        return meta;
    }
    async getMeta(chatId) {
        try {
            return JSON.parse(await readFile(this.metaFile(chatId), "utf-8"));
        }
        catch {
            return null;
        }
    }
    async setMeta(chatId, patch) {
        const current = await this.getMeta(chatId);
        if (!current)
            return null;
        const next = { ...current, ...patch, updatedAt: new Date().toISOString() };
        await writeFile(this.metaFile(chatId), JSON.stringify(next, null, 2), "utf-8");
        return next;
    }
    async listChats() {
        const dir = join(this.workspaceRoot, "chats");
        let ids;
        try {
            ids = await readdir(dir);
        }
        catch {
            return [];
        }
        const metas = [];
        for (const id of ids) {
            const meta = await this.getMeta(id);
            if (meta)
                metas.push(meta);
        }
        // Newest first by updatedAt.
        return metas.sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
    }
    async appendMessages(chatId, messages) {
        if (messages.length === 0)
            return;
        await mkdir(this.chatDir(chatId), { recursive: true });
        const lines = messages.map((m) => JSON.stringify(m)).join("\n") + "\n";
        await appendFile(join(this.chatDir(chatId), "messages.jsonl"), lines, "utf-8");
    }
    async loadMessages(chatId) {
        try {
            const raw = await readFile(join(this.chatDir(chatId), "messages.jsonl"), "utf-8");
            return raw
                .split("\n")
                .filter((l) => l.trim())
                .map((l) => JSON.parse(l));
        }
        catch {
            return [];
        }
    }
    async appendEvent(chatId, event) {
        await mkdir(this.chatDir(chatId), { recursive: true });
        await appendFile(join(this.chatDir(chatId), "events.jsonl"), JSON.stringify(event) + "\n", "utf-8");
    }
    async *tailEvents(chatId, turn, opts = {}) {
        const file = join(this.chatDir(chatId), "events.jsonl");
        // Tail the whole file but only stop at THIS turn's terminal, and only
        // surface THIS turn's events — earlier turns' events (and terminals) are
        // replayed-through but filtered out, so a late reattach lands cleanly on
        // the requested turn regardless of how many turns precede it.
        for await (const e of tailJsonl(file, (e) => e.turn === turn && isChatTerminal(e), opts)) {
            if (e.turn === turn)
                yield e;
        }
    }
    async deleteChat(chatId) {
        await rm(this.chatDir(chatId), { recursive: true, force: true });
    }
}
// ── In-memory implementation (for testing) ─────────────────────────────────
export class MemoryChatStore {
    metas = new Map();
    messages = new Map();
    events = new Map();
    async createChat(init) {
        const now = new Date().toISOString();
        const meta = {
            id: init.id,
            ...(init.title ? { title: init.title } : {}),
            status: "live",
            ...(init.model ? { model: init.model } : {}),
            createdAt: now,
            updatedAt: now,
            currentTurn: -1,
        };
        this.metas.set(init.id, meta);
        return meta;
    }
    async getMeta(chatId) {
        return this.metas.get(chatId) ?? null;
    }
    async setMeta(chatId, patch) {
        const current = this.metas.get(chatId);
        if (!current)
            return null;
        const next = { ...current, ...patch, updatedAt: new Date().toISOString() };
        this.metas.set(chatId, next);
        return next;
    }
    async listChats() {
        return [...this.metas.values()].sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
    }
    async appendMessages(chatId, messages) {
        const arr = this.messages.get(chatId) ?? [];
        arr.push(...messages);
        this.messages.set(chatId, arr);
    }
    async loadMessages(chatId) {
        return this.messages.get(chatId) ?? [];
    }
    async appendEvent(chatId, event) {
        const arr = this.events.get(chatId) ?? [];
        arr.push(event);
        this.events.set(chatId, arr);
    }
    /** Same contract as the file tail: replay the turn's history, then follow
     *  live appends (index cursor + poll) until the turn's terminal event. */
    async *tailEvents(chatId, turn, opts = {}) {
        const intervalMs = opts.intervalMs ?? 250;
        let cursor = 0;
        while (true) {
            if (opts.signal?.aborted)
                return;
            const log = this.events.get(chatId) ?? [];
            while (cursor < log.length) {
                const e = log[cursor++];
                if (e.turn !== turn)
                    continue;
                yield e;
                if (isChatTerminal(e))
                    return;
            }
            await new Promise((r) => setTimeout(r, intervalMs));
        }
    }
    async deleteChat(chatId) {
        this.metas.delete(chatId);
        this.messages.delete(chatId);
        this.events.delete(chatId);
    }
}
/** Generate a chat ID (timestamp + short random, sortable + collision-safe). */
export function generateChatId() {
    return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
}
//# sourceMappingURL=chat-store.js.map