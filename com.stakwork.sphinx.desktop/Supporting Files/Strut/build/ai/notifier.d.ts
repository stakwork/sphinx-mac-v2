import type { ChatStore, StoredMessage } from "../chat-store.js";
/**
 * Run-completion notifications for the AI-builder chat — the "wake" half of
 * the dispatch-mode `run_workflow` tool (see `plans/dispatch-run-notifications.md`).
 *
 * When a detached run settles, `deliver` wakes the chat by appending a
 * user-role `[run-notification]` message and launching a new turn via the
 * SAME `launchChatTurn` path a human message uses. If a turn is live in this
 * process, notifications queue and are drained into ONE wake-up turn when it
 * ends (two runs finishing close together → one turn that sees both).
 *
 * Liveness is an in-process set (mirroring `createStrut`'s `activeRuns`), NOT
 * `meta.status` — a crashed process leaves `status: "live"` stale, and
 * pending notifications die with the process anyway (same crash posture as
 * detached runs; no durable delivery).
 *
 * Runaway guard: `ChatMeta.autoTurns` counts consecutive notification-
 * triggered turns since the last human message (`POST /chat` resets it).
 * At the cap the notification is still appended to the transcript (the next
 * human turn sees it) but NO turn is launched — an autonomous loop parks
 * instead of running unbounded.
 */
export declare const NOTIFICATION_PREFIX = "[run-notification]";
export interface RunNotificationInfo {
    workflow: string;
    runId: string;
    status: "success" | "error" | "cancelled";
    durationMs?: number;
    output?: unknown;
    error?: {
        message: string;
    };
}
/** Render a settled run into the slim notification message text. The agent
 *  has `get_run` for full detail, so output is truncated hard. */
export declare function formatRunNotification(info: RunNotificationInfo, maxOutputChars?: number): string;
export interface ChatNotifier {
    /** A turn is live in this process (idempotent). Called at turn launch. */
    turnStarted(chatId: string): void;
    /** The turn finished — drain any notifications queued during it into one
     *  wake-up turn. Called from `launchChatTurn`'s finally. */
    turnEnded(chatId: string): Promise<void>;
    /** Deliver one notification: queue if a turn is live, else wake now. */
    deliver(chatId: string, text: string): Promise<void>;
    /** Is a turn for this chat running in THIS process? The authoritative
     *  liveness check — `meta.status === "live"` on disk can be stale after a
     *  crash/restart (see `createStrut`'s `reconcileStaleChat`). */
    isLive(chatId: string): boolean;
}
export declare function createChatNotifier(opts: {
    chatStore: ChatStore;
    /** Max consecutive notification-triggered turns since the last human
     *  message before the chat parks (notifications append, turns stop). */
    maxAutoTurns: number;
    /** Launch an agent turn — `createStrut` passes `launchChatTurn`. Receives
     *  the truncated model-message copy, exactly like a human-triggered turn. */
    startTurn: (chatId: string, turn: number, modelMessages: StoredMessage[]) => void;
}): ChatNotifier;
