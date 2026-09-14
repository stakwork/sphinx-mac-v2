import { PREVIEW_MAX_CHARS } from "./strut-schemas.js";
const emptyReport = () => ({ runs: 0, sessions: 0, toolCalls: 0, chats: 0, turns: 0, edges: 0, accessed: 0, unresolved: 0, skipped: 0 });
/** A bounded text preview of any value — the only shape of payload that
 *  reaches the graph. */
export function preview(v, max = PREVIEW_MAX_CHARS) {
    if (v === undefined || v === null)
        return undefined;
    const s = typeof v === "string" ? v : JSON.stringify(v);
    if (!s)
        return undefined;
    return s.length > max ? `${s.slice(0, max - 1)}…` : s;
}
function compact(o) {
    const out = {};
    for (const [k, v] of Object.entries(o))
        if (v !== undefined && v !== null && v !== "")
            out[k] = v;
    return out;
}
const TERMINAL = new Set(["run.end", "run.error", "run.cancelled"]);
function isTerminalStatus(s) {
    return s === "success" || s === "error" || s === "cancelled";
}
/** Status of a run from its summary, else from the last terminal event in
 *  the log, else "stale" (never finalized — crashed or still in flight). */
function runStatus(summary, events) {
    if (summary)
        return summary.status;
    for (let i = events.length - 1; i >= 0; i--) {
        const e = events[i];
        if (e.type === "run.resumed")
            return "stale";
        if (e.type === "run.end")
            return "success";
        if (e.type === "run.error")
            return "error";
        if (e.type === "run.cancelled")
            return "cancelled";
    }
    return "stale";
}
/** Pure: the nodes one run contributes (no graph access). */
export function projectRunEvents(workflow, runId, events, summary) {
    if (events.length === 0 && !summary)
        return null;
    const start = events.find((e) => e.type === "run.start");
    const status = runStatus(summary, events);
    const lastError = [...events].reverse().find((e) => e.type === "step.error" || e.type === "run.error")?.error;
    const stepEnds = events.filter((e) => e.type === "step.end").length;
    const durationMs = summary?.durationMs;
    const errorMessage = summary?.error?.message ?? lastError?.message;
    const summaryText = errorMessage
        ? `${status}: ${errorMessage}`.slice(0, PREVIEW_MAX_CHARS)
        : `${status} · ${stepEnds} step${stepEnds === 1 ? "" : "s"} completed${durationMs != null ? ` in ${durationMs}ms` : ""}`;
    const logRef = `${workflow}/${runId}`;
    const run = {
        type: "StrutRun",
        data: compact({
            run_id: runId,
            workflow_name: workflow,
            status,
            summary: summaryText,
            started_at: summary?.startedAt ?? start?.ts ?? events[0]?.ts ?? new Date(Number(runId) || Date.now()).toISOString(),
            finished_at: summary?.finishedAt,
            duration_ms: durationMs,
            workflow_hash: start?.workflowHash,
            params_json: start?.params ? JSON.stringify(start.params) : undefined,
            input_preview: preview(summary?.input ?? start?.input),
            output_preview: preview(summary?.output),
            error_message: errorMessage,
            log_ref: logRef,
            unique_source_id: `strutrun:${runId}`,
        }),
    };
    // Agent sessions: every `agent` step.start, paired with its end/error at
    // the same path (+ iteration).
    const sessions = [];
    const sessionPaths = [];
    const keyOf = (e) => `${e.path}${e.iteration != null ? `#${e.iteration}` : ""}`;
    const ends = new Map();
    for (const e of events)
        if ((e.type === "step.end" || e.type === "step.error") && e.stepType === "agent")
            ends.set(keyOf(e), e);
    for (const e of events) {
        if (e.type !== "step.start" || e.stepType !== "agent")
            continue;
        const end = ends.get(keyOf(e));
        const input = (e.input ?? {});
        sessionPaths.push(e.path);
        sessions.push({
            type: "StrutAgentSession",
            data: compact({
                run_id: runId,
                path: keyOf(e),
                step_type: e.stepType,
                model: typeof input["model"] === "string" ? input["model"] : undefined,
                iteration: e.iteration,
                prompt_preview: preview(input["prompt"] ?? input["system"] ?? e.input),
                result_preview: preview(end?.output),
                started_at: e.ts,
                duration_ms: end?.durationMs,
                error_message: end?.error?.message,
                log_ref: logRef,
                unique_source_id: `strutagentsession:${runId}:${keyOf(e)}`,
            }),
        });
    }
    // Tool calls: `tool:<name>` steps nested under a session path, numbered
    // per session in log order. `accessed` is the end event's `nodes` list
    // (the provenance marker), deduplicated by ref_id.
    const toolCalls = [];
    const seqBySession = new Map();
    const toolEnds = new Map();
    for (const e of events)
        if ((e.type === "step.end" || e.type === "step.error") && e.stepType?.startsWith("tool:"))
            toolEnds.set(keyOf(e), e);
    for (const e of events) {
        if (e.type !== "step.start" || !e.stepType?.startsWith("tool:"))
            continue;
        const session = sessionPaths.filter((p) => e.path.startsWith(`${p}/`)).sort((a, b) => b.length - a.length)[0];
        if (!session)
            continue;
        const seq = (seqBySession.get(session) ?? 0) + 1;
        seqBySession.set(session, seq);
        const end = toolEnds.get(keyOf(e));
        const accessed = [];
        const seenRef = new Set();
        for (const n of end?.nodes ?? []) {
            if (!n || typeof n.ref_id !== "string" || !n.ref_id || seenRef.has(n.ref_id))
                continue;
            seenRef.add(n.ref_id);
            accessed.push(n);
        }
        toolCalls.push({
            sessionPath: session,
            accessed,
            node: {
                type: "StrutToolCall",
                data: compact({
                    run_id: runId,
                    path: keyOf(e),
                    seq,
                    tool_name: e.stepType.slice("tool:".length),
                    input_preview: preview(e.input),
                    output_preview: preview(end?.output),
                    started_at: e.ts,
                    duration_ms: end?.durationMs,
                    error_message: end?.error?.message,
                    log_ref: logRef,
                    unique_source_id: `struttoolcall:${runId}:${keyOf(e)}:${seq}`,
                }),
            },
        });
    }
    return { run, sessions, toolCalls, workflowHash: start?.workflowHash };
}
/** Project runs from a `RunStore` into the graph. */
export async function projectRuns(backend, store, opts) {
    const report = emptyReport();
    const ns = backend.cfg.namespace;
    for (const workflow of opts.workflows) {
        let runIds = await store.listRuns(workflow);
        if (opts.limitPerWorkflow != null)
            runIds = runIds.slice(0, opts.limitPerWorkflow);
        if (runIds.length === 0)
            continue;
        // Settled runs already in the graph don't need re-reading.
        let settled = new Set();
        if (opts.skipSettled !== false) {
            const rows = await backend.bolt.run(`MATCH (r:StrutRun {namespace: $ns, workflow_name: $wf}) WHERE r.run_id IN $ids RETURN r.run_id AS id, r.status AS status`, { ns, wf: workflow, ids: runIds });
            settled = new Set(rows.filter((r) => isTerminalStatus(r["status"])).map((r) => r["id"]));
        }
        for (const runId of runIds) {
            if (settled.has(runId)) {
                report.skipped++;
                continue;
            }
            const [events, summary] = await Promise.all([store.getRunEvents(workflow, runId), store.getRunSummary(workflow, runId)]);
            const p = projectRunEvents(workflow, runId, events, summary);
            if (!p)
                continue;
            const nodes = [p.run, ...p.sessions, ...p.toolCalls.map((t) => t.node)];
            const written = await backend.nodes.writeMany(nodes, "upsert");
            const runRef = written[0].ref_id;
            const sessionRef = new Map();
            p.sessions.forEach((s, i) => sessionRef.set(String(s.data["path"]).replace(/#\d+$/, ""), written[1 + i].ref_id));
            report.runs++;
            report.sessions += p.sessions.length;
            report.toolCalls += p.toolCalls.length;
            const edges = [];
            p.sessions.forEach((s) => {
                const ref = sessionRef.get(String(s.data["path"]).replace(/#\d+$/, ""));
                edges.push({ edge: "IN_RUN", source_ref_id: ref, target_ref_id: runRef });
            });
            const toolRef = (i) => written[1 + p.sessions.length + i].ref_id;
            p.toolCalls.forEach((t, i) => {
                edges.push({ edge: "IN_SESSION", source_ref_id: toolRef(i), target_ref_id: sessionRef.get(t.sessionPath) });
            });
            // ACCESSED: only toward nodes this graph actually holds (the edge
            // writer treats a missing endpoint as an error, and a ref may point
            // at another database or a since-deleted node).
            const wanted = new Set(p.toolCalls.flatMap((t) => t.accessed.map((n) => n.ref_id)));
            if (wanted.size) {
                const rows = await backend.bolt.run(`MATCH (n:Data_Bank) WHERE n.ref_id IN $ids RETURN DISTINCT n.ref_id AS ref_id`, { ids: [...wanted] });
                const present = new Set(rows.map((r) => r["ref_id"]));
                p.toolCalls.forEach((t, i) => {
                    for (const n of t.accessed) {
                        if (present.has(n.ref_id)) {
                            edges.push({ edge: "ACCESSED", source_ref_id: toolRef(i), target_ref_id: n.ref_id });
                            report.accessed++;
                        }
                        else
                            report.unresolved++;
                    }
                });
            }
            if (p.workflowHash) {
                const rows = await backend.bolt.run(`MATCH (v:StrutWorkflowVersion {namespace: $ns, name: $wf, content_hash: $h}) RETURN v.ref_id AS ref_id LIMIT 1`, { ns, wf: workflow, h: p.workflowHash });
                if (rows.length)
                    edges.push({ edge: "EXECUTED", source_ref_id: runRef, target_ref_id: rows[0]["ref_id"] });
            }
            if (edges.length) {
                await backend.edges.writeMany(edges);
                report.edges += edges.length;
            }
        }
    }
    return report;
}
// ── Chats ─────────────────────────────────────────────────────────────────
/** Plain text of a stored message's content (string, or AI-SDK parts). */
export function messageText(content) {
    if (typeof content === "string")
        return content;
    if (Array.isArray(content)) {
        const texts = content
            .map((p) => (p && typeof p === "object" && typeof p["text"] === "string" ? p["text"] : ""))
            .filter(Boolean);
        return texts.length ? texts.join("\n") : undefined;
    }
    return undefined;
}
/** Run ids launched from this transcript: every `run_workflow` tool result
 *  carrying a `runId` (deep search — the tool-result envelope shape varies
 *  by SDK version). */
export function spawnedRunIds(messages) {
    const ids = new Set();
    const findRunId = (v, depth = 0) => {
        if (!v || typeof v !== "object" || depth > 8)
            return undefined;
        const o = v;
        if (typeof o["runId"] === "string")
            return o["runId"];
        for (const x of Object.values(o)) {
            const r = findRunId(x, depth + 1);
            if (r)
                return r;
        }
        return undefined;
    };
    const walk = (v, depth = 0) => {
        if (!v || typeof v !== "object" || depth > 8)
            return;
        const o = v;
        if (o["toolName"] === "run_workflow") {
            const id = findRunId(o);
            if (id)
                ids.add(id);
        }
        for (const x of Object.values(o))
            walk(x, depth + 1);
    };
    for (const m of messages)
        if (m.role === "tool" || m.role === "assistant")
            walk(m.content);
    return [...ids];
}
/** Project every chat (and its turns) from a `ChatStore` into the graph. */
export async function projectChats(backend, chatStore) {
    const report = emptyReport();
    const ns = backend.cfg.namespace;
    for (const meta of await chatStore.listChats()) {
        const messages = await chatStore.loadMessages(meta.id);
        const turns = [];
        let turn = -1;
        for (let i = 0; i < messages.length; i++) {
            const m = messages[i];
            if (m.role !== "user")
                continue;
            turn++;
            const assistant = messages.slice(i + 1).find((x) => x.role === "assistant" && messageText(x.content));
            turns.push({
                type: "StrutTurn",
                data: compact({
                    chat_id: meta.id,
                    turn,
                    user_text_preview: preview(messageText(m.content)),
                    assistant_text_preview: preview(assistant ? messageText(assistant.content) : undefined),
                    log_ref: `${meta.id}/${turn}`,
                    unique_source_id: `strutturn:${meta.id}:${turn}`,
                }),
            });
        }
        const chat = {
            type: "StrutChat",
            data: compact({
                chat_id: meta.id,
                title: meta.title,
                summary: preview(turns[0] ? turns[0].data["user_text_preview"] : undefined),
                status: meta.status,
                model: meta.model,
                created_at: meta.createdAt,
                last_active_at: meta.updatedAt,
                turn_count: turns.length,
                log_ref: meta.id,
                unique_source_id: `strutchat:${meta.id}`,
            }),
        };
        const written = await backend.nodes.writeMany([chat, ...turns], "upsert");
        const chatRef = written[0].ref_id;
        report.chats++;
        report.turns += turns.length;
        const edges = turns.map((_, i) => ({ edge: "IN_CHAT", source_ref_id: written[1 + i].ref_id, target_ref_id: chatRef }));
        const runIds = spawnedRunIds(messages);
        if (runIds.length) {
            const rows = await backend.bolt.run(`MATCH (r:StrutRun {namespace: $ns}) WHERE r.run_id IN $ids RETURN r.ref_id AS ref_id`, { ns, ids: runIds });
            for (const r of rows)
                edges.push({ edge: "SPAWNED", source_ref_id: chatRef, target_ref_id: r["ref_id"] });
        }
        if (edges.length) {
            await backend.edges.writeMany(edges);
            report.edges += edges.length;
        }
    }
    return report;
}
/** Runs first (so chats can link to them), then chats. */
export async function projectAll(backend, src, opts = {}) {
    const a = await projectRuns(backend, src.store, { ...opts, workflows: src.workflows });
    const b = src.chatStore ? await projectChats(backend, src.chatStore) : emptyReport();
    return {
        runs: a.runs + b.runs,
        sessions: a.sessions + b.sessions,
        toolCalls: a.toolCalls + b.toolCalls,
        chats: a.chats + b.chats,
        turns: a.turns + b.turns,
        edges: a.edges + b.edges,
        accessed: a.accessed + b.accessed,
        unresolved: a.unresolved + b.unresolved,
        skipped: a.skipped + b.skipped,
    };
}
//# sourceMappingURL=projector.js.map