import { HotwordsStore, type Hotword } from "./hotwords.js";
import { type SttModel } from "./models.js";
import { SessionStore } from "./sessions.js";
export interface EngineWaveform {
    samples: Float32Array;
    sampleRate: number;
}
export interface EngineResult {
    text: string;
    tokens?: string[];
    timestamps?: number[];
    start_time?: number;
}
export interface EngineStream {
    acceptWaveform(w: EngineWaveform): void;
    inputFinished(): void;
}
export interface EngineRecognizer {
    createStream(): EngineStream;
    isReady(s: EngineStream): boolean;
    decode(s: EngineStream): void;
    isEndpoint(s: EngineStream): boolean;
    reset(s: EngineStream): void;
    getResult(s: EngineStream): EngineResult;
}
export interface SttEngine {
    OnlineRecognizer: new (config: Record<string, unknown>) => EngineRecognizer;
    readWave(path: string): EngineWaveform;
}
/** Lazy sherpa import; null when the optional addon isn't installed. */
export declare function loadSherpaEngine(): Promise<SttEngine | null>;
export interface SttWord {
    text: string;
    /** Seconds from the start of the stream. */
    start: number;
}
export type SttEvent = {
    type: "partial";
    text: string;
} | {
    type: "final";
    index: number;
    text: string;
    words: SttWord[];
};
export interface EndpointRules {
    /** Trailing silence (s) that ends a segment even with no speech yet. */
    rule1?: number;
    /** Trailing silence (s) after speech that ends a segment. */
    rule2?: number;
    /** Utterance length (s) after which a segment is cut regardless. */
    rule3?: number;
}
export interface SttStreamOptions {
    /** Finals model (hotword-capable). Default `STRUT_STT_MODEL` / catalog default. */
    model?: string;
    /** Fast model for partials; `null` for single-recognizer mode. Default
     *  `STRUT_STT_PARTIAL_MODEL` / catalog default. */
    partialModel?: string | null;
    /** A stored list name, or phrases inline. */
    hotwords?: string | readonly string[] | readonly Hotword[];
    /** Global per-token boost for phrases without their own `:score`. */
    hotwordsScore?: number;
    sampleRate?: number;
    /** Log finals + accept corrections under this id (`SessionStore`). */
    session?: string;
    endpoint?: EndpointRules;
}
export interface SttStream {
    readonly model: string;
    readonly partialModel: string | null;
    readonly hotwords: string | null;
    /** Feed PCM16LE bytes at the stream's sample rate. */
    push(pcm16le: Uint8Array): SttEvent[];
    /** Feed float32 samples (any rate; sherpa resamples). */
    pushSamples(samples: Float32Array, sampleRate: number): SttEvent[];
    /** Flush: pads silence so the last chunk decodes, emits the trailing final. */
    end(): SttEvent[];
    /** Resolves once every session-log write so far has landed — await it
     *  before telling a client it may correct the finals. */
    flush(): Promise<void>;
    close(): void;
}
export interface TranscribeResult {
    text: string;
    segments: {
        text: string;
        words: SttWord[];
    }[];
    model: string;
    hotwords: string | null;
    durationMs: number;
}
export type DownloadProgress = {
    phase: "download";
    received: number;
    total: number;
} | {
    phase: "extract";
} | {
    phase: "done";
};
export interface SttModelStatus extends SttModel {
    installed: boolean;
    /** Which entry env/default resolution picks. */
    default: "model" | "partialModel" | null;
}
export interface SttService {
    readonly modelDir: string;
    readonly hotwords: HotwordsStore;
    readonly sessions: SessionStore;
    /** Whether the sherpa addon loads in this process. */
    available(): Promise<boolean>;
    models(): Promise<SttModelStatus[]>;
    /** Download + verify + extract (idempotent, deduped). Resolves to the dir. */
    ensureModel(id: string, onProgress?: (p: DownloadProgress) => void): Promise<string>;
    openStream(opts?: SttStreamOptions): Promise<SttStream>;
    transcribe(wav: Uint8Array, opts?: Omit<SttStreamOptions, "sampleRate">): Promise<TranscribeResult>;
    /** Append a user's correction to a session's final. */
    correct(session: string, index: number, text: string): Promise<void>;
}
export interface SttServiceOptions {
    /** Local data dir (sessions, hotword lists, temp WAVs). */
    dataDir: string;
    modelDir?: string;
    engine?: () => Promise<SttEngine | null>;
    fetchImpl?: typeof fetch;
    env?: Record<string, string | undefined>;
    log?: (msg: string) => void;
}
export declare function createStt(opts: SttServiceOptions): SttService;
export declare class SttUnavailableError extends Error {
    constructor();
}
/** Group sherpa's subword tokens into words. A token starting with `▁` (or
 *  a space, as the JSON renders it) begins a word. */
export declare function wordsOf(r: EngineResult): SttWord[];
export declare function pcm16ToFloat32(bytes: Uint8Array): Float32Array;
