// ── Public API ─────────────────────────────────────────────────────────────
// Re-export the engine's own zod so consumers define step schemas against
// the exact version `defineStep` and the schema-introspection helpers expect
// (avoids dual zod-version type/runtime mismatches in host apps).
export { z } from "zod";
// Core types and builders
export { flow, step, defineStep, withAccessedNodes, accessedNodesOf, } from "./core.js";
// Runner
export { runWorkflow } from "./runner.js";
// Run control — cancel / pause / resume for run trees (RUN_CONTROL_SPEC.md)
export { RunController, CancelledError, isCancelledError, } from "./run-control.js";
// Resume journal — replay completed step outputs from the event log
export { buildJournal, invalidateFrom, readRunStart, transitiveDependents, } from "./journal.js";
// Expression engine
export { evaluateExpr, resolveTemplate, resolveConfig, hasTemplates, TemplateError, } from "./expr.js";
// Persistence
export { FileRunStore, MemoryRunStore, generateRunId, tailJsonl, tailFromPolling, lastRunAtFromIds, summarizeFromEvents, } from "./store.js";
// Chat persistence (detached AI-builder background jobs)
export { FileChatStore, MemoryChatStore, generateChatId, truncateToolMessages, DEFAULT_TOOL_RESULT_MAX_CHARS, toolResultMaxCharsFromEnv, isChatTerminal, } from "./chat-store.js";
// Registry
export { buildRegistry, coreRegistry, createRegistry, } from "./steps/registry.js";
// Workspace
export { FileWorkspaceStore, WorkspaceManager, } from "./workspace.js";
// Content-hash versioning (internal dedup) + sequential version labels
export { contentHash, nextVersionLabel } from "./version.js";
// LLM token usage + cost (shared by the agent + lab eval/score steps)
export { TOKEN_PRICING, emptyUsage, addUsage, coerceUsage, usageFromResult, computeCost, } from "./pricing.js";
// Standard capabilities — the http + secrets + artifacts services adapter steps build on.
export { standardServices, httpCapability, secretsCapability, fileArtifactsCapability, } from "./capabilities.js";
// Speech-to-text (src/audio): the service behind /audio/*, the dictation
// WebSocket attach for hosts that mount `app` themselves, and the catalog.
export { createStt, loadSherpaEngine, SttUnavailableError, } from "./audio/stt.js";
export { attachAudioWebSocket, createAudioUpgradeHandler, AUDIO_STREAM_PATH, } from "./audio/ws.js";
export { STT_MODELS, DEFAULT_MODEL as DEFAULT_STT_MODEL } from "./audio/models.js";
export { parseHotwords, formatHotwords, HotwordsStore } from "./audio/hotwords.js";
// Secret store — deployment-scoped, encrypted credential persistence behind
// the `secrets` capability + the `/secrets` admin endpoints.
export { FileSecretStore, MemorySecretStore, isValidSecretName, } from "./secret-store.js";
// Record/replay for the services bag (the adapter "safe inner loop").
export { withCassette, emptyCassette, loadCassette, saveCassette, } from "./cassette.js";
// Single-step runner (test one step in isolation, with optional cassette).
export { runSingleStep, cassettePath, } from "./run-step.js";
// Authoring — the workspace's author/test/inspect operations as one
// injectable service: what the meta/* steps are plumbing over. Auto-provided
// by createStrut as `services.authoring`; embedders can build their own.
export { buildAuthoringCapability, AI_PUBLISHER, } from "./authoring.js";
// Strut factory — the primary entry point for library usage.
export { createStrut, } from "./createStrut.js";
// Default filesystem-backed server (a thin wrapper over createStrut).
export { getApp, startServer } from "./server.js";
// Graph backend — jarvis-compatible Neo4j writes/reads over bolt, no jarvis
// in the loop (plans/jarvis-graph-compat.md). Opt-in: nothing here runs
// unless a consumer opens a backend.
export { Bolt, graphConfigFromEnv, int as neo4jInt, } from "./graph/bolt.js";
export { STRUT_SCHEMAS, STRUT_EDGES, STRUT_DOMAIN, STRUT_DOMAIN_LABEL, getStrutSchema, isStrutType, effectiveAttributes, typeLabelOf, } from "./graph/strut-schemas.js";
export { seedStrutDomain } from "./graph/schema-seed.js";
export { migrateVeinToStrut, VeinMigrationCollision } from "./graph/vein-migration.js";
export { NodeWriter, GraphValidationError, validateNode, composeNodeKey, buildSearchText, } from "./graph/node-writer.js";
export { EdgeWriter } from "./graph/edge-writer.js";
export { SchemaResolver, EDGE_TYPES_ALLOWLIST } from "./graph/schema-resolver.js";
export { seedJarvisOntology } from "./graph/ontology-seed.js";
export { JARVIS_ONTOLOGY } from "./graph/fixtures/jarvis-ontology.js";
export { MiniLMEmbedder, backfillEmbeddings, EMBEDDING_DIM } from "./graph/embeddings.js";
export { GraphReader, GraphReadError, } from "./graph/search.js";
export { openGraphBackend, openGraphBackendFromEnv, closeGraphBackends, } from "./graph/backend.js";
// Read-only raw Cypher (the chat builder's graph_query tool).
export { readQuery, findWriteKeyword, compactValue, ReadOnlyViolation } from "./graph/query.js";
// Graph-backed workspace + the run/chat projector (plans/generic-storage.md §7).
export { Neo4jWorkspaceStore } from "./graph/workspace-store.js";
export { graphWorkspaceFromEnv, graphWorkspaceRequested, graphMaterializeDir } from "./graph/wiring.js";
export { projectRuns, projectChats, projectAll, projectRunEvents, } from "./graph/projector.js";
//# sourceMappingURL=index.js.map