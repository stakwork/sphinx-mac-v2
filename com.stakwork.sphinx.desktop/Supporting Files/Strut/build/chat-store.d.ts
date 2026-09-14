/**
 * Chat persistence — the server-side store that makes the AI builder a
 * detached "background job" (EVAL_SPEC §8) instead of a connection-bound
 * stream. A chat session is an append-only run with the SAME launch-detached
 * + tail-the-file lifecycle strut uses for workflow runs, PLUS a resumable
 * conversation log so a turn keeps running (and can be re-driven) after the
 * browser closes.
 *
 * Each chat lives in `<workspaceRoot>/chats/<chatId>/` with the deliberate
 * two-file split borrowed from `mcp/src/repo/session.ts`:
 *
 *   meta.json       — { id, title, status, model, createdAt, updatedAt,
 *                       currentTurn }. Cheap listing without parsing the logs.
 *   messages.jsonl  — append-only conversation (AI SDK ModelMessage objects).
 *                     The REPLAYABLE record: re-fed to the agent on the next
 *                     turn and rendered as the transcript. Whole messages only
 *                     — never deltas (keeps replay clean), lossless on disk.
 *   events.jsonl    — append-only fine-grained stream parts (text deltas, tool
 *                     calls/results, step/turn boundaries). The OBSERVABILITY
 *                     stream the SSE tail follows; never re-sent to the model.
 *
 * A chat is long-lived across many turns; the unit with launch+detach+tail
 * semantics is a TURN. Each turn's events carry `turn: N` and end with a
 * `chat.end`/`chat.error`, so the tail stops at the right boundary even when
 * replaying a multi-turn history (see `tailEvents`).
 */
export type ChatStatus = "live" | "done" | "error";
export interface ChatMeta {
    id: string;
    title?: string;
    status: ChatStatus;
    model?: string;
    createdAt: string;
    updatedAt: string;
    /** Index of the most recently launched turn (0-based). */
    currentTurn: number;
    /** Consecutive notification-triggered (non-human) turns since the last
     *  human message. Incremented by the run notifier, reset to 0 by
     *  `POST /chat`; at `STRUT_CHAT_MAX_AUTO_TURNS` the chat parks (see
     *  `ai/notifier.ts`). */
    autoTurns?: number;
}
export type ChatEventType = "text-delta" | "tool-input" | "tool-output" | "step.finish" | "chat.end" | "chat.error";
/** A single fine-grained event in a chat turn's observability stream. */
export interface ChatEvent {
    ts: string;
    chatId: string;
    /** Which user turn this event belongs to (0-based). */
    turn: number;
    type: ChatEventType;
    /** text-delta */
    delta?: string;
    /** tool-input / tool-output */
    toolName?: string;
    toolCallId?: string;
    input?: unknown;
    output?: unknown;
    /** tool-output: the tool threw (output is the error message). */
    isError?: boolean;
    /** chat.error */
    error?: {
        message: string;
    };
}
/** A stored conversation message. Kept opaque (the AI SDK's `ModelMessage`
 *  shape) — the store only reads/writes JSON lines and never interprets it. */
export interface StoredMessage {
    role: string;
    content: unknown;
}
/** A turn is terminal once its log records a `chat.end` or `chat.error`. */
export declare function isChatTerminal(e: ChatEvent): boolean;
export interface ChatStore {
    createChat(init: {
        id: string;
        title?: string;
        model?: string;
    }): Promise<ChatMeta>;
    getMeta(chatId: string): Promise<ChatMeta | null>;
    setMeta(chatId: string, patch: Partial<ChatMeta>): Promise<ChatMeta | null>;
    listChats(): Promise<ChatMeta[]>;
    appendMessages(chatId: string, messages: StoredMessage[]): Promise<void>;
    loadMessages(chatId: string): Promise<StoredMessage[]>;
    appendEvent(chatId: string, event: ChatEvent): Promise<void>;
    /** Tail a single turn's events (history → live) until that turn ends. */
    tailEvents(chatId: string, turn: number, opts?: {
        intervalMs?: number;
        signal?: AbortSignal;
    }): AsyncGenerator<ChatEvent>;
    deleteChat(chatId: string): Promise<void>;
}
/** Default per-string cap for `truncateToolMessages`. Env
 *  `STRUT_CHAT_TOOL_RESULT_MAX_CHARS` overrides it; `0` disables truncation. */
export declare const DEFAULT_TOOL_RESULT_MAX_CHARS = 50000;
/** Resolve the tool-result cap from the environment (see above). */
export declare function toolResultMaxCharsFromEnv(): number;
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
export declare function truncateToolMessages(messages: StoredMessage[], maxChars?: number): StoredMessage[];
export declare class FileChatStore implements ChatStore {
    private workspaceRoot;
    constructor(workspaceRoot: string);
    private chatDir;
    private metaFile;
    createChat(init: {
        id: string;
        title?: string;
        model?: string;
    }): Promise<ChatMeta>;
    getMeta(chatId: string): Promise<ChatMeta | null>;
    setMeta(chatId: string, patch: Partial<ChatMeta>): Promise<ChatMeta | null>;
    listChats(): Promise<ChatMeta[]>;
    appendMessages(chatId: string, messages: StoredMessage[]): Promise<void>;
    loadMessages(chatId: string): Promise<StoredMessage[]>;
    appendEvent(chatId: string, event: ChatEvent): Promise<void>;
    tailEvents(chatId: string, turn: number, opts?: {
        intervalMs?: number;
        signal?: AbortSignal;
    }): AsyncGenerator<ChatEvent>;
    deleteChat(chatId: string): Promise<void>;
}
export declare class MemoryChatStore implements ChatStore {
    metas: Map<string, ChatMeta>;
    messages: Map<string, StoredMessage[]>;
    events: Map<string, ChatEvent[]>;
    createChat(init: {
        id: string;
        title?: string;
        model?: string;
    }): Promise<ChatMeta>;
    getMeta(chatId: string): Promise<ChatMeta | null>;
    setMeta(chatId: string, patch: Partial<ChatMeta>): Promise<ChatMeta | null>;
    listChats(): Promise<ChatMeta[]>;
    appendMessages(chatId: string, messages: StoredMessage[]): Promise<void>;
    loadMessages(chatId: string): Promise<StoredMessage[]>;
    appendEvent(chatId: string, event: ChatEvent): Promise<void>;
    /** Same contract as the file tail: replay the turn's history, then follow
     *  live appends (index cursor + poll) until the turn's terminal event. */
    tailEvents(chatId: string, turn: number, opts?: {
        intervalMs?: number;
        signal?: AbortSignal;
    }): AsyncGenerator<ChatEvent>;
    deleteChat(chatId: string): Promise<void>;
}
/** Generate a chat ID (timestamp + short random, sortable + collision-safe). */
export declare function generateChatId(): string;
