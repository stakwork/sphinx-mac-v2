//
//  AIAgentManager+HiveGraphTool.swift
//  Sphinx
//
//  Created on 2026-06-16.
//  Copyright © 2026 Sphinx. All rights reserved.
//

import Foundation
import SwiftAISDK

// MARK: - JSON Value (supports nested objects for tool call output)

/// Minimal recursive Codable value supporting strings and nested dicts.
/// Used for ToolCall.output so `payload` / `meta` can be nested objects.
enum CodableJSONValue: Codable {
    case string(String)
    case object([String: CodableJSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode([String: CodableJSONValue].self) { self = .object(d) }
        else { self = .string(try c.decode(String.self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .object(let d): try c.encode(d)
        }
    }

    var stringValue: String? { if case .string(let s) = self { return s }; return nil }
}

extension Dictionary where Key == String, Value == CodableJSONValue {
    func string(for key: String) -> String? { self[key]?.stringValue }
}

// MARK: - Codable Models

extension AIAgentManager {

    struct CanvasChatMessage: Codable {
        let role: String           // "user" or "assistant"
        let content: String
        var toolCalls: [ToolCall]?
        var approvalResult: ApprovalResult?
    }

    struct ToolCall: Codable {
        let id: String?            // toolCallId from SSE (e.g. "toulu_01RZ8...")
        let toolName: String
        let status: String?        // "output-available" once output is known
        var input: [String: String]?
        var output: [String: CodableJSONValue]?

        // Custom encoding: omit nil-optional fields entirely (avoid sending JSON null to server)
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(id, forKey: .id)
            try container.encode(toolName, forKey: .toolName)
            try container.encodeIfPresent(status, forKey: .status)
            try container.encodeIfPresent(input, forKey: .input)
            try container.encodeIfPresent(output, forKey: .output)
        }
    }

    struct ProposalOutput: Codable {
        let proposalId: String
        let kind: String
        let title: String
        let description: String?
    }

    struct ApprovalIntent: Codable {
        let proposalId: String
        let currentRef: String?
    }

    struct RejectionIntent: Codable {
        let proposalId: String
    }

    struct ApprovalResult: Codable {
        let approved: Bool            // synthesized: true on decode (server success), false for rejection
        let proposalId: String
        let kind: String?
        let createdEntityId: String?
        let landedOn: String?
        let landedOnName: String?
        let featureUrl: String?       // built client-side from createdEntityId + workspace slug
        let summaryText: String?      // extracted from SSE body + feature URL

        // CodingKeys excludes app-side fields (approved, featureUrl, summaryText)
        enum CodingKeys: String, CodingKey {
            case proposalId, kind, createdEntityId, landedOn, landedOnName
        }

        // Server response has no `approved` field — presence of a valid decode = success.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            proposalId      = try c.decode(String.self, forKey: .proposalId)
            kind            = try c.decodeIfPresent(String.self, forKey: .kind)
            createdEntityId = try c.decodeIfPresent(String.self, forKey: .createdEntityId)
            landedOn        = try c.decodeIfPresent(String.self, forKey: .landedOn)
            landedOnName    = try c.decodeIfPresent(String.self, forKey: .landedOnName)
            approved        = true
            featureUrl      = nil
            summaryText     = nil
        }

        // Enrich a decoded result with client-side URL and summary text
        init(enriching result: ApprovalResult, featureUrl: String?, summaryText: String?) {
            approved        = result.approved
            proposalId      = result.proposalId
            kind            = result.kind
            createdEntityId = result.createdEntityId
            landedOn        = result.landedOn
            landedOnName    = result.landedOnName
            self.featureUrl  = featureUrl
            self.summaryText = summaryText
        }

        // Synthetic constructor used for rejection (no server body)
        init(approved: Bool, proposalId: String) {
            self.approved        = approved
            self.proposalId      = proposalId
            self.kind            = nil
            self.createdEntityId = nil
            self.landedOn        = nil
            self.landedOnName    = nil
            self.featureUrl      = nil
            self.summaryText     = nil
        }
    }

    struct PendingProposal: Codable {
        let proposalId: String
        let kind: String
        let title: String
        let description: String?
        let toolCallId: String?       // SSE toolCallId, used when building the approval transcript
        let rawInput: [String: String]? // Full input dict from tool-input-available event
    }

    // MARK: - Approve/Reject input structs

    struct ApproveProposalInput: Codable, Sendable {
        let proposalId: String
    }

    struct RejectProposalInput: Codable, Sendable {
        let proposalId: String
    }
}

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

    /// Convert a [String: Any] dict (from JSONSerialization) into [String: CodableJSONValue],
    /// preserving nested dicts as .object cases. Booleans are stored as "true"/"false" strings
    /// to distinguish them from integers (CFGetTypeID check avoids NSNumber ambiguity).
    static func anyDictToCodableJSON(_ dict: [String: Any]) -> [String: CodableJSONValue] {
        var result: [String: CodableJSONValue] = [:]
        for (key, value) in dict {
            if let s = value as? String { result[key] = .string(s) }
            else if let d = value as? [String: Any] { result[key] = .object(anyDictToCodableJSON(d)) }
            else if let n = value as? NSNumber {
                // Distinguish JSON booleans (false→"0", true→"1" via stringValue — wrong)
                // from actual booleans using CFGetTypeID.
                if CFGetTypeID(n) == CFBooleanGetTypeID() {
                    result[key] = .string(n.boolValue ? "true" : "false")
                } else {
                    result[key] = .string(n.stringValue)
                }
            }
        }
        return result
    }

    /// For each assistant message in `messages`, finds the empty-toolName sibling entry
    /// (which carries the full canvas payload with workspaceId) and merges its payload
    /// onto the propose_* entry's output before sending to the approval endpoint.
    static func mergeCanvasPayloads(into messages: [[String: Any]]) -> [[String: Any]] {
        let proposalPrefixes = ["propose_feature", "propose_initiative", "propose_milestone"]
        let booleanPayloadKeys = ["autoRespond"]

        func normalizeBooleans(in payload: inout [String: Any]) {
            for key in booleanPayloadKeys {
                guard let v = payload[key] else { continue }
                switch v {
                case let b as Bool: payload[key] = b
                case let n as NSNumber: payload[key] = n.boolValue
                case let s as String: payload[key] = (s == "1" || s.lowercased() == "true")
                default: payload[key] = false
                }
            }
        }

        return messages.map { msg in
            guard var toolCalls = msg["toolCalls"] as? [[String: Any]] else { return msg }

            // Find the canvas (empty-toolName) sibling and its payload
            let canvasEntry = toolCalls.first(where: { ($0["toolName"] as? String) == "" })
            let canvasOutput = canvasEntry?["output"] as? [String: Any]
            let canvasPayload = canvasOutput?["payload"] as? [String: Any]

            var changed = false
            toolCalls = toolCalls.map { tc in
                guard var output = tc["output"] as? [String: Any] else { return tc }
                var payload = output["payload"] as? [String: Any] ?? [:]
                let tn = tc["toolName"] as? String ?? ""
                let isProposalTool = proposalPrefixes.contains(where: { tn.hasPrefix($0) })

                // Merge canvas payload into propose_* entries
                if isProposalTool, let canvasPayload = canvasPayload {
                    canvasPayload.forEach { payload[$0.key] = $0.value }
                    if let meta = canvasOutput?["meta"] { output["meta"] = meta }
                }

                // Normalize boolean fields across ALL tool call entries
                normalizeBooleans(in: &payload)

                output["payload"] = payload
                var t = tc; t["output"] = output; changed = true
                return t
            }
            if !changed { return msg }
            var m = msg; m["toolCalls"] = toolCalls; return m
        }
    }

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

    // MARK: - Canvas History

    func loadCanvasHistory(orgId: String) {
        guard let data: Data = UserDefaults.Keys.hiveCanvasChatHistoryByOrg.get(),
              let dict = try? JSONDecoder().decode([String: [CanvasChatMessage]].self, from: data)
        else { return }
        canvasChatHistory = dict[orgId] ?? []
    }

    func persistCanvasHistory(orgId: String) {
        var dict: [String: [CanvasChatMessage]] = [:]
        if let data: Data = UserDefaults.Keys.hiveCanvasChatHistoryByOrg.get(),
           let existing = try? JSONDecoder().decode([String: [CanvasChatMessage]].self, from: data) {
            dict = existing
        }
        dict[orgId] = canvasChatHistory
        if let encoded = try? JSONEncoder().encode(dict) {
            UserDefaults.Keys.hiveCanvasChatHistoryByOrg.set(encoded)
            print("AIAgent [HiveGraph] canvas history persisted — \(canvasChatHistory.count) messages")
        }
    }

    func persistPendingProposal() {
        guard let proposal = pendingProposal,
              let data = try? JSONEncoder().encode(proposal) else { return }
        UserDefaults.Keys.hivePendingProposal.set(data)
    }

    func loadPersistedPendingProposal() {
        guard pendingProposal == nil,
              let data: Data = UserDefaults.Keys.hivePendingProposal.get(),
              let proposal = try? JSONDecoder().decode(PendingProposal.self, from: data) else { return }
        pendingProposal = proposal
    }

    func clearPersistedPendingProposal() {
        UserDefaults.Keys.hivePendingProposal.removeValue()
        pendingProposal = nil
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

        // Load persisted canvas history for this org
        loadCanvasHistory(orgId: orgId)

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

        // Step 5: Append to canvas history
        canvasChatHistory.append(CanvasChatMessage(role: "user", content: question))

        // Convert captured tool calls from bridge.
        // For propose_* tools that arrived via tool-input-available (no tool-result follows),
        // synthesise an output dict from the input fields so the server's handleApproval can
        // locate the proposal by proposalId.
        let proposalPrefixSet = ["propose_feature", "propose_initiative", "propose_milestone"]
        let toolCalls: [ToolCall]? = bridge.capturedToolCalls.isEmpty ? nil :
            bridge.capturedToolCalls.map { tc in
                let inputDict = AIAgentManager.jsonStringToStringDict(tc.inputStr)
                // Parse raw output into CodableJSONValue dict (preserves nested objects)
                var outputDict: [String: CodableJSONValue]? = {
                    guard !tc.outputStr.isEmpty,
                          let data = tc.outputStr.data(using: .utf8),
                          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    else { return nil }
                    let d = AIAgentManager.anyDictToCodableJSON(obj)
                    return d.isEmpty ? nil : d
                }()
                // For proposal tools: ensure output.payload contains workspaceId.
                // The server's tool-result event only sends {proposalId, kind, title, description}
                // — no workspaceId. The companion empty-toolName entry carries the full payload.
                // Trigger on missing payload.workspaceId, not on empty output.
                if proposalPrefixSet.contains(where: { tc.name.hasPrefix($0) }),
                   let inputD = inputDict {
                    let hasWorkspaceId: Bool = {
                        guard let payloadVal = outputDict?["payload"],
                              case .object(let p) = payloadVal else { return false }
                        return p["workspaceId"] != nil
                    }()
                    if !hasWorkspaceId {
                        if let companion = bridge.capturedToolCalls.first(where: { $0.name.isEmpty }),
                           !companion.outputStr.isEmpty,
                           let compData = companion.outputStr.data(using: .utf8),
                           let compObj = try? JSONSerialization.jsonObject(with: compData) as? [String: Any] {
                            // Merge companion's payload and meta into existing output
                            var enriched = outputDict ?? [:]
                            let comp = AIAgentManager.anyDictToCodableJSON(compObj)
                            if let payload = comp["payload"] { enriched["payload"] = payload }
                            if let meta = comp["meta"] { enriched["meta"] = meta }
                            if enriched["proposalId"] == nil, let pid = inputD["proposalId"] { enriched["proposalId"] = .string(pid) }
                            if enriched["kind"] == nil {
                                if let rawKind = inputD["kind"] { enriched["kind"] = .string(rawKind) }
                                else if tc.name.hasPrefix("propose_") { enriched["kind"] = .string(String(tc.name.dropFirst("propose_".count))) }
                            }
                            outputDict = enriched.isEmpty ? nil : enriched
                        } else {
                            // No companion — keep existing output but ensure proposalId/kind
                            var enriched = outputDict ?? [:]
                            if enriched["proposalId"] == nil, let pid = inputD["proposalId"] { enriched["proposalId"] = .string(pid) }
                            if enriched["kind"] == nil {
                                if let rawKind = inputD["kind"] { enriched["kind"] = .string(rawKind) }
                                else if tc.name.hasPrefix("propose_") { enriched["kind"] = .string(String(tc.name.dropFirst("propose_".count))) }
                            }
                            outputDict = enriched.isEmpty ? nil : enriched
                        }
                    }
                }
                let tcId = tc.toolCallId.isEmpty ? nil : tc.toolCallId
                let status: String? = (outputDict != nil) ? "output-available" : nil
                return ToolCall(id: tcId, toolName: tc.name, status: status, input: inputDict, output: outputDict)
            }

        let assistantMsg = CanvasChatMessage(role: "assistant", content: result, toolCalls: toolCalls)
        canvasChatHistory.append(assistantMsg)
        persistCanvasHistory(orgId: orgId)
        print("AIAgent [HiveGraph] canvas history updated — \(canvasChatHistory.count) messages")

        // Log all captured tool calls for diagnostics
        for tc in bridge.capturedToolCalls {
            print("AIAgent [HiveGraph] captured tool: \(tc.name) | inputStr: \(tc.inputStr.prefix(200)) | outputStr: \(tc.outputStr.prefix(200))")
        }

        // Step 6: Proposal detection
        let proposalNames: Set<String> = ["propose_feature", "propose_initiative", "propose_milestone"]
        if let tc = assistantMsg.toolCalls?.first(where: { call in proposalPrefixSet.contains(where: { call.toolName.hasPrefix($0) }) || proposalNames.contains(call.toolName) }),
           let pid   = tc.output?.string(for: "proposalId") ?? tc.input?["proposalId"],
           let kind  = tc.output?.string(for: "kind")       ?? tc.input?["kind"],
           let title = tc.output?.string(for: "title")      ?? tc.input?["title"] {
            let desc = tc.output?.string(for: "description") ?? tc.input?["description"]
            pendingProposal = PendingProposal(
                proposalId: pid, kind: kind, title: title,
                description: desc,
                toolCallId: tc.id,
                rawInput: tc.input
            )
            persistPendingProposal()
            print("AIAgent [HiveGraph] proposal detected — id: \(pid), kind: \(kind)")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .aiAgentProposalDetected, object: self.pendingProposal)
            }
            // Inject proposal context into the tool result so the agent LLM
            // knows the proposalId and can call approve_proposal/reject_proposal
            // when the user says "approve it" or "reject it".
            let proposalContext = """

[PROPOSAL CARD DISPLAYED — A native approval card has been shown to the user.]
proposalId: \(pid)
kind: \(kind)
title: \(title)\(desc.map { "\ndescription: \($0)" } ?? "")

To approve this proposal, call approve_proposal with proposalId "\(pid)".
To reject it, call reject_proposal with proposalId "\(pid)".
"""
            return result + proposalContext
        }

        return result
    }

    // MARK: - Approve Proposal Tool

    func buildApproveProposalTool() -> TypedTool<ApproveProposalInput, JSONValue> {
        tool(
            description: "Approve a Jamie proposal. Call this when the user says 'approve', 'yes', 'go ahead', or similar after Jamie proposed a feature/initiative/milestone. The proposalId is shown in the [PROPOSAL CARD DISPLAYED] block that appeared in the query_hive_graph tool result earlier in this conversation — copy it exactly. Never fabricate a proposalId.",
            execute: { [weak self] (input: ApproveProposalInput, _: ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> in
                guard let self = self else { return .value(.string("Agent unavailable.")) }
                return await self.executeApproveProposal(proposalId: input.proposalId)
            }
        )
    }

    func executeApproveProposal(proposalId: String) async -> ToolExecutionResult<JSONValue> {
        let proposalNames: Set<String> = ["propose_feature", "propose_initiative", "propose_milestone"]

        // IDOR guard: proposalId must match the server-originated pendingProposal
        // OR exist in canvasChatHistory (for proposals loaded from persistence on restart).
        let inPending = pendingProposal?.proposalId == proposalId
        let inHistory = canvasChatHistory.contains(where: {
            $0.toolCalls?.contains(where: {
                proposalNames.contains($0.toolName) &&
                ($0.output?.string(for: "proposalId") == proposalId || $0.input?["proposalId"] == proposalId)
            }) == true
        })
        guard inPending || inHistory else {
            print("AIAgent [HiveGraph] approve_proposal: proposal not found — proposalId: \(proposalId)")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .aiAgentProposalActioned, object: "Proposal not found in current conversation.")
            }
            return .value(.string("Proposal not found in current conversation. Cannot approve."))
        }

        // Idempotency: already actioned?
        if let idx = canvasChatHistory.indices.last(where: {
            canvasChatHistory[$0].toolCalls?.contains(where: {
                proposalNames.contains($0.toolName) &&
                ($0.output?.string(for: "proposalId") == proposalId || $0.input?["proposalId"] == proposalId)
            }) == true
        }), canvasChatHistory[idx].approvalResult != nil {
            print("AIAgent [HiveGraph] approve_proposal: already actioned — proposalId: \(proposalId)")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .aiAgentProposalActioned, object: "This proposal has already been actioned.")
            }
            return .value(.string("This proposal has already been actioned."))
        }

        guard let orgId: String = UserDefaults.Keys.hiveOrgId.get(), !orgId.isEmpty,
              let data: Data = UserDefaults.Keys.hiveConversationIdByOrg.get(),
              let dict = try? JSONDecoder().decode([String: String].self, from: data),
              let conversationId = dict[orgId]
        else {
            print("AIAgent [HiveGraph] approve_proposal: missing org context — proposalId: \(proposalId)")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .aiAgentProposalActioned, object: "Missing org context. Please try again.")
            }
            return .value(.string("Missing org context. Cannot approve."))
        }

        let turnId = UUID().uuidString
        let token: String? = await withCheckedContinuation { cont in
            API.sharedInstance.resolveHiveToken(callback: { cont.resume(returning: $0) }, errorCallback: { cont.resume(returning: nil) })
        }
        guard let token = token else {
            print("AIAgent [HiveGraph] approve_proposal: authentication failed — proposalId: \(proposalId)")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .aiAgentProposalActioned, object: "Authentication failed. Please try again.")
            }
            return .value(.string("Authentication failed. Cannot approve."))
        }

        print("AIAgent [HiveGraph] approve_proposal firing — proposalId: \(proposalId), turnId: \(turnId)")

        let workspaceSlugs = await AIAgentManager.fetchWorkspacesAsync().map { $0.compactMap { $0.slug } } ?? []
        let messages = AIAgentManager.mergeCanvasPayloads(
            into: (try? JSONEncoder().encode(canvasChatHistory)).flatMap {
                try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]]
            } ?? []
        )

        // Extract workspaceSlug from the canvas entry's meta (features only)
        let proposalWorkspaceSlug: String? = messages.lazy.compactMap { msg -> String? in
            guard let toolCalls = msg["toolCalls"] as? [[String: Any]],
                  let canvas = toolCalls.first(where: { ($0["toolName"] as? String) == "" }),
                  let output = canvas["output"] as? [String: Any],
                  let meta = output["meta"] as? [String: Any] else { return nil }
            return meta["workspaceSlug"] as? String
        }.first

        let orgGithubLogin: String = UserDefaults.Keys.hiveGithubLogin.get() ?? ""

        return await withCheckedContinuation { cont in
            API.sharedInstance.sendApprovalIntent(
                orgId: orgId,
                conversationId: conversationId,
                turnId: turnId,
                proposalId: proposalId,
                canvasChatMessages: messages,
                workspaceSlugs: workspaceSlugs,
                workspaceSlug: proposalWorkspaceSlug,
                orgGithubLogin: orgGithubLogin,
                token: token
            ) { [weak self] result, errorMsg in
                guard let self = self else {
                    print("AIAgent [HiveGraph] approve_proposal: agent unavailable — proposalId: \(proposalId)")
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .aiAgentProposalActioned, object: "Agent unavailable. Please try again.")
                    }
                    cont.resume(returning: .value(.string("Agent unavailable.")))
                    return
                }
                if let result = result {
                    // Stamp approval result onto the matching assistant message
                    if let idx = self.canvasChatHistory.indices.last(where: {
                        self.canvasChatHistory[$0].toolCalls?.contains(where: {
                            proposalNames.contains($0.toolName) &&
                            ($0.output?.string(for: "proposalId") == proposalId || $0.input?["proposalId"] == proposalId)
                        }) == true
                    }) {
                        let existing = self.canvasChatHistory[idx]
                        self.canvasChatHistory[idx] = CanvasChatMessage(
                            role: existing.role,
                            content: existing.content,
                            toolCalls: existing.toolCalls,
                            approvalResult: result
                        )
                        self.persistCanvasHistory(orgId: orgId)
                    }
                    self.clearPersistedPendingProposal()
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .aiAgentProposalActioned, object: result)
                    }
                    cont.resume(returning: .value(.string("Proposal approved successfully.")))
                } else {
                    let msg = errorMsg ?? "Approval failed. Please try again."
                    print("AIAgent [HiveGraph] approval POST failed: \(msg) — leaving card actionable")
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .aiAgentProposalActioned, object: msg)
                    }
                    cont.resume(returning: .value(.string("Approval failed. Please try again — the card is still actionable.")))
                }
            }
        }
    }

    // MARK: - Reject Proposal Tool

    func buildRejectProposalTool() -> TypedTool<RejectProposalInput, JSONValue> {
        tool(
            description: "Reject a Jamie proposal. Call this when the user says 'reject', 'no', 'cancel', or similar after Jamie proposed a feature/initiative/milestone. The proposalId is shown in the [PROPOSAL CARD DISPLAYED] block that appeared in the query_hive_graph tool result earlier in this conversation — copy it exactly. Never fabricate a proposalId.",
            execute: { [weak self] (input: RejectProposalInput, _: ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> in
                guard let self = self else { return .value(.string("Agent unavailable.")) }
                return await self.executeRejectProposal(proposalId: input.proposalId)
            }
        )
    }

    func executeRejectProposal(proposalId: String) async -> ToolExecutionResult<JSONValue> {
        let proposalNames: Set<String> = ["propose_feature", "propose_initiative", "propose_milestone"]

        // IDOR guard: match against server-originated pendingProposal or persisted canvasChatHistory
        let inPending = pendingProposal?.proposalId == proposalId
        let inHistory = canvasChatHistory.contains(where: {
            $0.toolCalls?.contains(where: {
                proposalNames.contains($0.toolName) &&
                ($0.output?.string(for: "proposalId") == proposalId || $0.input?["proposalId"] == proposalId)
            }) == true
        })
        guard inPending || inHistory else {
            print("AIAgent [HiveGraph] reject_proposal: proposal not found — proposalId: \(proposalId)")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .aiAgentProposalActioned, object: "Proposal not found in current conversation.")
            }
            return .value(.string("Proposal not found in current conversation. Cannot reject."))
        }

        // Idempotency
        if let idx = canvasChatHistory.indices.last(where: {
            canvasChatHistory[$0].toolCalls?.contains(where: {
                proposalNames.contains($0.toolName) &&
                ($0.output?.string(for: "proposalId") == proposalId || $0.input?["proposalId"] == proposalId)
            }) == true
        }), canvasChatHistory[idx].approvalResult != nil {
            print("AIAgent [HiveGraph] reject_proposal: already actioned — proposalId: \(proposalId)")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .aiAgentProposalActioned, object: "This proposal has already been actioned.")
            }
            return .value(.string("This proposal has already been actioned."))
        }

        guard let orgId: String = UserDefaults.Keys.hiveOrgId.get(), !orgId.isEmpty,
              let data: Data = UserDefaults.Keys.hiveConversationIdByOrg.get(),
              let dict = try? JSONDecoder().decode([String: String].self, from: data),
              let conversationId = dict[orgId]
        else {
            print("AIAgent [HiveGraph] reject_proposal: missing org context — proposalId: \(proposalId)")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .aiAgentProposalActioned, object: "Missing org context. Please try again.")
            }
            return .value(.string("Missing org context. Cannot reject."))
        }

        let turnId = UUID().uuidString
        let token: String? = await withCheckedContinuation { cont in
            API.sharedInstance.resolveHiveToken(callback: { cont.resume(returning: $0) }, errorCallback: { cont.resume(returning: nil) })
        }
        guard let token = token else {
            print("AIAgent [HiveGraph] reject_proposal: authentication failed — proposalId: \(proposalId)")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .aiAgentProposalActioned, object: "Authentication failed. Please try again.")
            }
            return .value(.string("Authentication failed. Cannot reject."))
        }

        print("AIAgent [HiveGraph] reject_proposal firing — proposalId: \(proposalId), turnId: \(turnId)")

        let workspaceSlugs = await AIAgentManager.fetchWorkspacesAsync().map { $0.compactMap { $0.slug } } ?? []
        let messages = AIAgentManager.mergeCanvasPayloads(
            into: (try? JSONEncoder().encode(canvasChatHistory)).flatMap {
                try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]]
            } ?? []
        )

        return await withCheckedContinuation { cont in
            API.sharedInstance.sendRejectionIntent(
                orgId: orgId,
                conversationId: conversationId,
                turnId: turnId,
                proposalId: proposalId,
                canvasChatMessages: messages,
                workspaceSlugs: workspaceSlugs,
                token: token
            ) { [weak self] success, errorMsg in
                guard let self = self else {
                    print("AIAgent [HiveGraph] reject_proposal: agent unavailable — proposalId: \(proposalId)")
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .aiAgentProposalActioned, object: "Agent unavailable. Please try again.")
                    }
                    cont.resume(returning: .value(.string("Agent unavailable.")))
                    return
                }
                if success {
                    let rejectionResult = ApprovalResult(approved: false, proposalId: proposalId)
                    if let idx = self.canvasChatHistory.indices.last(where: {
                        self.canvasChatHistory[$0].toolCalls?.contains(where: {
                            proposalNames.contains($0.toolName) &&
                            ($0.output?.string(for: "proposalId") == proposalId || $0.input?["proposalId"] == proposalId)
                        }) == true
                    }) {
                        let existing = self.canvasChatHistory[idx]
                        self.canvasChatHistory[idx] = CanvasChatMessage(
                            role: existing.role,
                            content: existing.content,
                            toolCalls: existing.toolCalls,
                            approvalResult: rejectionResult
                        )
                        self.persistCanvasHistory(orgId: orgId)
                    }
                    self.clearPersistedPendingProposal()
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .aiAgentProposalActioned, object: rejectionResult)
                    }
                    cont.resume(returning: .value(.string("Proposal rejected.")))
                } else {
                    let msg = errorMsg ?? "Rejection failed. Please try again."
                    print("AIAgent [HiveGraph] rejection POST failed: \(msg) — leaving card actionable")
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .aiAgentProposalActioned, object: msg)
                    }
                    cont.resume(returning: .value(.string("Rejection failed. Please try again — the card is still actionable.")))
                }
            }
        }
    }

    // MARK: - Debug Mock Injector

    #if DEBUG
    func injectMockProposal(kind: String = "feature") {
        let mockProposalId = "mock-\(UUID().uuidString)"
        let mock = PendingProposal(
            proposalId: mockProposalId,
            kind: kind,
            title: "[MOCK] Build \(kind) dashboard",
            description: "A mock proposal for UI development.",
            toolCallId: nil,
            rawInput: ["proposalId": mockProposalId, "kind": kind, "title": "[MOCK] Build \(kind) dashboard"]
        )
        pendingProposal = mock
        NotificationCenter.default.post(name: .aiAgentProposalDetected, object: mock)
    }
    #endif
}
