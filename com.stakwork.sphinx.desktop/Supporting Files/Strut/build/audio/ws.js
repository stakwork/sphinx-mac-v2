import { WebSocketServer } from "ws";
import { apiKeyMatches } from "../auth.js";
export const AUDIO_STREAM_PATH = "/audio/stream";
/** The dictation socket's upgrade handler, for hosts that own the Node
 *  server themselves (e.g. an Express app that bridges `strut.app`). */
export function createAudioUpgradeHandler(stt, opts = {}) {
    const path = (opts.basePath ?? "") + (opts.path ?? AUDIO_STREAM_PATH);
    const wss = new WebSocketServer({ noServer: true });
    const authorize = opts.authorize ?? ((req, url) => apiKeyMatches(req.headers.authorization, url.searchParams.get("key")));
    return {
        path,
        handle(req, socket, head) {
            const url = new URL(req.url ?? "/", "http://localhost");
            if (url.pathname !== path)
                return false;
            if (!authorize(req, url)) {
                socket.write("HTTP/1.1 401 Unauthorized\r\nConnection: close\r\n\r\n");
                socket.destroy();
                return true;
            }
            wss.handleUpgrade(req, socket, head, (ws) => handleSocket(ws, stt));
            return true;
        },
        close: () => wss.close(),
    };
}
/** Attach the dictation socket to a Node http server. Returns a detach fn. */
export function attachAudioWebSocket(server, stt, opts = {}) {
    const handler = createAudioUpgradeHandler(stt, opts);
    const onUpgrade = (req, socket, head) => {
        if (handler.handle(req, socket, head))
            return;
        // Not ours. If nobody else handles upgrades the socket would hang open
        // forever, so answer 404 when we're the only listener.
        if (server.listenerCount("upgrade") === 1) {
            socket.write("HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n");
            socket.destroy();
        }
    };
    server.on("upgrade", onUpgrade);
    return () => {
        server.off("upgrade", onUpgrade);
        handler.close();
    };
}
/** Drive one socket. Exported for tests (any `ws`-shaped socket works). */
export function handleSocket(ws, stt) {
    let stream = null;
    let opening = null;
    let finished = false;
    const send = (msg) => {
        if (ws.readyState === ws.OPEN)
            ws.send(JSON.stringify(msg));
    };
    const fail = (err) => {
        send({ type: "error", error: err instanceof Error ? err.message : String(err) });
        ws.close(1011, "error");
    };
    const emit = (events) => {
        for (const ev of events)
            send(ev);
    };
    ws.on("message", (data, isBinary) => {
        if (finished)
            return;
        if (isBinary) {
            if (!stream) {
                if (opening) {
                    // Audio arriving before the recognizer is ready: wait, then feed.
                    const chunk = toBytes(data);
                    opening.then(() => stream && emit(stream.push(chunk))).catch(fail);
                    return;
                }
                return fail(new Error('send {"type":"start"} before audio'));
            }
            try {
                emit(stream.push(toBytes(data)));
            }
            catch (e) {
                fail(e);
            }
            return;
        }
        let msg;
        try {
            msg = JSON.parse(toBytes(data).toString());
        }
        catch {
            return fail(new Error("expected JSON control message or binary PCM"));
        }
        if (msg.type === "start") {
            if (stream || opening)
                return fail(new Error("stream already started"));
            const { type: _t, ...o } = msg;
            opening = stt
                .openStream(o)
                .then((s) => {
                stream = s;
                send({ type: "ready", model: s.model, partialModel: s.partialModel, hotwords: s.hotwords });
            })
                .catch((e) => {
                opening = null;
                fail(e);
            });
            return;
        }
        if (msg.type === "end") {
            finished = true;
            const finish = async () => {
                if (stream) {
                    try {
                        emit(stream.end());
                    }
                    catch (e) {
                        return fail(e);
                    }
                    // Session finals are on disk before the client can correct them.
                    await stream.flush();
                }
                ws.close(1000, "done");
            };
            if (opening)
                opening.then(finish).catch(fail);
            else
                finish().catch(fail);
            return;
        }
        fail(new Error(`unknown message type ${JSON.stringify(msg.type)}`));
    });
    ws.on("close", () => {
        stream?.close();
        stream = null;
    });
}
function toBytes(data) {
    if (Buffer.isBuffer(data))
        return data;
    if (Array.isArray(data))
        return Buffer.concat(data);
    if (data instanceof ArrayBuffer)
        return Buffer.from(data);
    return Buffer.from(String(data));
}
//# sourceMappingURL=ws.js.map