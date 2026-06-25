//
//  AIAgentManager+HiveGraphTool.swift
//  Sphinx
//
//  Created on 2026-06-16.
//  Copyright © 2026 Sphinx. All rights reserved.
//

import Foundation
import SwiftAISDK

// MARK: - HiveGraphBridge

/// Bridges GraphChatSSEManager delegate callbacks to a CheckedContinuation.
private class HiveGraphBridge: GraphChatSSEDelegate {

    var continuation: CheckedContinuation<String, Never>?
    var sseManager: GraphChatSSEManager?
    var buffer: String = ""
    var resumed: Bool = false

    // Tool call capture — toolCallId is the SSE id (e.g. "toolu_01RZ8…")
    var capturedToolCalls: [(name: String, toolCallId: String, inputStr: String, outputStr: String)] = []

    func onTextDelta(_ delta: String) {
        buffer += delta
    }

    func onFinish() {
        guard !resumed else { return }
        resumed = true
        let result = buffer.isEmpty ? "No response." : buffer
        print("AIAgent [HiveGraph] SSE finished, buffer length: \(buffer.count)")
        sseManager?.stopStream()
        continuation?.resume(returning: result)
    }

    func onError(_ text: String) {
        guard !resumed else { return }
        resumed = true
        print("AIAgent [HiveGraph] SSE error: \(text)")
        sseManager?.stopStream()
        continuation?.resume(returning: "Hive graph error: \(text)")
    }

    /// Fired for `tool-input-available` events.
    /// For propose_* tools the input already contains proposalId, kind, title etc.,
    /// so we can create a synthetic tool call entry immediately — no need to wait for
    /// a tool-result event that may never arrive.
    func onToolInputAvailable(_ toolName: String, _ toolCallId: String, _ input: String) {
        let proposalPrefixes = ["propose_feature", "propose_initiative", "propose_milestone"]
        guard proposalPrefixes.contains(where: { toolName.hasPrefix($0) }) else { return }

        // Upsert: avoid duplicates if both tool-input-available and tool-call fire.
        if let idx = capturedToolCalls.indices.last(where: { capturedToolCalls[$0].name == toolName && capturedToolCalls[$0].toolCallId.isEmpty }) {
            capturedToolCalls[idx] = (name: toolName, toolCallId: toolCallId, inputStr: input, outputStr: capturedToolCalls[idx].outputStr)
        } else if !capturedToolCalls.contains(where: { $0.name == toolName && $0.toolCallId == toolCallId }) {
            capturedToolCalls.append((name: toolName, toolCallId: toolCallId, inputStr: input, outputStr: ""))
        }
        print("AIAgent [HiveGraph] onToolInputAvailable captured propose tool: \(toolName) id: \(toolCallId)")
    }

    func onToolCall(_ toolName: String, _ input: String) {
        // Upsert: if a slot already exists for this name (from a prior tool-result arriving
        // out of order or a duplicate call event), update it; otherwise append.
        if let idx = capturedToolCalls.indices.last(where: { capturedToolCalls[$0].name == toolName && capturedToolCalls[$0].inputStr.isEmpty }) {
            capturedToolCalls[idx] = (name: toolName, toolCallId: capturedToolCalls[idx].toolCallId, inputStr: input, outputStr: capturedToolCalls[idx].outputStr)
        } else {
            capturedToolCalls.append((name: toolName, toolCallId: "", inputStr: input, outputStr: ""))
        }
    }

    func onToolOutputAvailable(_ toolName: String, _ output: String) {
        if let idx = capturedToolCalls.indices.last(where: { capturedToolCalls[$0].name == toolName }) {
            capturedToolCalls[idx] = (name: toolName, toolCallId: capturedToolCalls[idx].toolCallId, inputStr: capturedToolCalls[idx].inputStr, outputStr: output)
        } else {
            // tool-result arrived before tool-call (or tool-call was missing) — create an entry
            capturedToolCalls.append((name: toolName, toolCallId: "", inputStr: "", outputStr: output))
        }
    }
}

// MARK: - AIAgentManager+HiveGraphTool

extension AIAgentManager {

    // MARK: - JSON Helpers

    /// Parse a JSON string (possibly double-encoded) into a flat [String: String] dict.
    /// Nested objects/arrays are re-serialised as JSON strings so no data is lost.
    static func jsonStringToStringDict(_ jsonStr: String) -> [String: String]? {
        guard !jsonStr.isEmpty else { return nil }
        let trimmed = jsonStr.trimmingCharacters(in: .whitespaces)

        // Attempt parse as JSON object
        func parseDict(from data: Data) -> [String: String]? {
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            var result: [String: String] = [:]
            for (key, value) in obj {
                if let str = value as? String {
                    result[key] = str
                } else if let num = value as? NSNumber {
                    result[key] = num.stringValue
                } else if let nested = try? JSONSerialization.data(withJSONObject: value),
                          let nestedStr = String(data: nested, encoding: .utf8) {
                    result[key] = nestedStr
                }
            }
            return result.isEmpty ? nil : result
        }

        if let data = trimmed.data(using: .utf8) {
            // Direct parse
            if let dict = parseDict(from: data) { return dict }
            // Handle double-encoded: the string is itself a JSON-encoded string wrapping an object
            if let inner = try? JSONSerialization.jsonObject(with: data) as? String,
               let innerData = inner.data(using: .utf8),
               let dict = parseDict(from: innerData) { return dict }
        }
        return nil
    }

    // MARK: - Query Hive Graph Tool Builder

    struct QueryHiveGraphInput: Codable, Sendable {
        let question: String
    }

    func buildQueryHiveGraphTool() -> TypedTool<QueryHiveGraphInput, JSONValue> {
        tool(
            description: "Query the Hive org knowledge graph via Jamie (the Hive AI agent). DEFAULT tool for any Hive question that is analytical, open-ended, or requires org-wide context — features, tasks, workspaces, codebase, architecture, team activity, or project status. Call this proactively WITHOUT waiting for the user to mention 'Jamie'. No workspace name needed. Only skip in favour of specific Hive CRUD tools when the user explicitly requests a targeted operation (list, detail, create, update, archive).",
            execute: { [weak self] (input: QueryHiveGraphInput, _: ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> in
                guard let self = self else { return .value(.string("Agent unavailable.")) }
                let result = await self.executeQueryHiveGraph(question: input.question)
                return .value(.string(result))
            }
        )
    }

    func executeQueryHiveGraph(question: String) async -> String {

        // Step 1: Ensure org slugs are cached (refresh if stale)
        var slugs = AIAgentManager.cachedOrgSlugs()
        if slugs == nil {
            await AIAgentManager.fetchAndCacheOrgSlugs()
            slugs = AIAgentManager.cachedOrgSlugs()
        }
        guard let orgSlugs = slugs, !orgSlugs.isEmpty else {
            return "Hive org not configured. Please check your Hive connection in settings."
        }
        guard let orgId: String = UserDefaults.Keys.hiveOrgId.get(), !orgId.isEmpty else {
            return "Hive org ID not found. Please reconfigure your Hive connection."
        }

        // Step 2: Read persisted conversationId for this org
        let conversationId: String? = {
            guard let data: Data = UserDefaults.Keys.hiveConversationIdByOrg.get(),
                  let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return nil }
            return dict[orgId]
        }()

        // Step 3: Resolve auth token
        let token: String? = await withCheckedContinuation { continuation in
            API.sharedInstance.resolveHiveToken(
                callback: { continuation.resume(returning: $0) },
                errorCallback: { continuation.resume(returning: nil) }
            )
        }
        guard let token = token else {
            return "Hive authentication failed. Please check your Hive configuration."
        }

        // Step 4: Stream via org SSE
        let bridge = HiveGraphBridge()
        let sseManager = GraphChatSSEManager()
        bridge.sseManager = sseManager
        sseManager.delegate = bridge

        let result: String = await withCheckedContinuation { cont in
            bridge.continuation = cont
            sseManager.startOrgStream(
                question: question,
                orgSlugs: orgSlugs,
                orgId: orgId,
                conversationId: conversationId,
                token: token,
                onConversationId: { newCid in
                    var dict: [String: String] = [:]
                    if let data: Data = UserDefaults.Keys.hiveConversationIdByOrg.get(),
                       let existing = try? JSONDecoder().decode([String: String].self, from: data) {
                        dict = existing
                    }
                    dict[orgId] = newCid
                    if let encoded = try? JSONEncoder().encode(dict) {
                        UserDefaults.Keys.hiveConversationIdByOrg.set(encoded)
                    }
                }
            )
        }

        // Step 5: Log all captured tool calls for diagnostics
        for tc in bridge.capturedToolCalls {
            print("AIAgent [HiveGraph] captured tool: \(tc.name) | inputStr: \(tc.inputStr.prefix(200)) | outputStr: \(tc.outputStr.prefix(200))")
        }

        // Step 6: Proposal detection — redirect user to Hive org chat
        let proposalPrefixSet = ["propose_feature", "propose_initiative", "propose_milestone"]
        if let tc = bridge.capturedToolCalls.first(where: { captured in proposalPrefixSet.contains(where: { captured.name.hasPrefix($0) }) }) {
            let inputDict = AIAgentManager.jsonStringToStringDict(tc.inputStr)
            let title = inputDict?["title"] ?? "proposal"
            print("AIAgent [HiveGraph] proposal detected — redirecting to Hive org chat: \(tc.name)")
            return result + "\n\n> Jamie has created a proposal: **\(title)**. To approve or reject it, please open the **Hive org chat**."
        }

        return result
    }

}
