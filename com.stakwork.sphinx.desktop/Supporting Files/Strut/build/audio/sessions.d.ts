import type { SttWord } from "./stt.js";
export type SessionEntry = {
    type: "final";
    t: string;
    index: number;
    text: string;
    words: SttWord[];
    model: string;
    hotwords: string | null;
} | {
    type: "correction";
    t: string;
    index: number;
    text: string;
};
export interface SessionInfo {
    id: string;
    updatedAt: string;
    bytes: number;
}
export declare class SessionStore {
    readonly dir: string;
    constructor(dataDir: string);
    private pathOf;
    append(id: string, entry: SessionEntry): Promise<void>;
    list(): Promise<SessionInfo[]>;
    /** The index the next final in this session should carry. */
    nextIndex(id: string): Promise<number>;
    /** All entries in order, or null when the session doesn't exist. */
    get(id: string): Promise<SessionEntry[] | null>;
}
