/**
 * `GET /audio/stream` — live dictation over a WebSocket
 * (plans/local-desktop-and-stt.md §4.4).
 *
 * Protocol (client → server):
 *   {"type":"start", model?, partialModel?, hotwords?, hotwordsScore?,
 *    sampleRate?, session?, endpoint?}          — SttStreamOptions, verbatim
 *   <binary>                                    — PCM16LE at sampleRate
 *   {"type":"end"}                              — flush; server closes after the final
 * Server → client:
 *   {"type":"ready", model, partialModel, hotwords}
 *   {"type":"partial", text}
 *   {"type":"final", index, text, words}
 *   {"type":"error", error}                     — then close
 *
 * Hono's node-ws adapter doesn't support @hono/node-server 2.x yet, and the
 * upgrade has to happen on the Node server anyway, so this hooks `ws`
 * straight onto the http.Server that `listen()` creates. Strut's first
 * client-to-server streaming route; the SSE-based rest is untouched.
 *
 * Auth: `Authorization: Bearer <STRUT_API_KEY>` or `?key=` — a browser's
 * WebSocket cannot set headers.
 */
import type { IncomingMessage, Server } from "node:http";
import type { Duplex } from "node:stream";
import { type WebSocket } from "ws";
import type { SttService } from "./stt.js";
export declare const AUDIO_STREAM_PATH = "/audio/stream";
export interface AttachOptions {
    /** Mount prefix when strut sits under a parent router (e.g. `/lab`). */
    basePath?: string;
    path?: string;
    /** Replace the default `STRUT_API_KEY` check (Bearer or `?key=`) — a host
     *  that gates strut behind its own credential applies it here, since an
     *  upgrade bypasses its HTTP middleware. */
    authorize?: (req: IncomingMessage, url: URL) => boolean;
}
export interface AudioUpgradeHandler {
    /** Route path this handler owns (`basePath + path`). */
    readonly path: string;
    /** Handle one `upgrade` event. Returns false (and touches nothing) when
     *  the request isn't for this path, so the caller can fall through. */
    handle(req: IncomingMessage, socket: Duplex, head: Buffer): boolean;
    close(): void;
}
/** The dictation socket's upgrade handler, for hosts that own the Node
 *  server themselves (e.g. an Express app that bridges `strut.app`). */
export declare function createAudioUpgradeHandler(stt: SttService, opts?: AttachOptions): AudioUpgradeHandler;
/** Attach the dictation socket to a Node http server. Returns a detach fn. */
export declare function attachAudioWebSocket(server: Server, stt: SttService, opts?: AttachOptions): () => void;
/** Drive one socket. Exported for tests (any `ws`-shaped socket works). */
export declare function handleSocket(ws: WebSocket, stt: SttService): void;
