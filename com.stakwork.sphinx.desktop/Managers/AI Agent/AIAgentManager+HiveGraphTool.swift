//
//  AIAgentManager+HiveGraphTool.swift
//  Sphinx
//
//  Created on 2026-06-16.
//  Copyright © 2026 Sphinx. All rights reserved.
//

import Foundation
import SwiftAISDK

// MARK: - Notification Names

extension Notification.Name {
    static let aiAgentProposalDetected = Notification.Name("aiAgentProposalDetected")
    static let aiAgentProposalActioned = Notification.Name("aiAgentProposalActioned")
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
        let toolName: String
        var input: [String: String]?
        var output: [String: String]?
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
        let approved: Bool
        let proposalId: String
        let message: String?
    }

    // Transient — never persisted, rebuilt from canvasChatHistory on each finish
    struct PendingProposal {
        let proposalId: String
        let kind: String
        let title: String
        let description: String?
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

    // Tool call capture
    var capturedToolCalls: [(name: String, inputStr: String, outputStr: String)] = []

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

    func onToolInputAvailable(_ toolName: String, _ input: String) {}

    func onToolCall(_ toolName: String, _ input: String) {
        capturedToolCalls.append((name: toolName, inputStr: input, outputStr: ""))
    }

    func onToolOutputAvailable(_ toolName: String, _ output: String) {
        if let idx = capturedToolCalls.indices.last(where: { capturedToolCalls[$0].name == toolName }) {
            capturedToolCalls[idx].outputStr = output
        }
    }
}

// MARK: - AIAgentManager+HiveGraphTool

extension AIAgentManager {

    // MARK: - JSON Helpers

    /// Parse a JSON string into a flat [String: String] dict.
    /// Nested objects/arrays are re-serialised as JSON strings so no data is lost.
    static func jsonStringToStringDict(_ jsonStr: String) -> [String: String]? {
        guard !jsonStr.isEmpty,
              let data = jsonStr.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
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

        // Convert captured tool calls from bridge
        let toolCalls: [ToolCall]? = bridge.capturedToolCalls.isEmpty ? nil :
            bridge.capturedToolCalls.map { tc in
                let inputDict = AIAgentManager.jsonStringToStringDict(tc.inputStr)
                let outputDict = AIAgentManager.jsonStringToStringDict(tc.outputStr)
                return ToolCall(toolName: tc.name, input: inputDict, output: outputDict)
            }

        let assistantMsg = CanvasChatMessage(role: "assistant", content: result, toolCalls: toolCalls)
        canvasChatHistory.append(assistantMsg)
        persistCanvasHistory(orgId: orgId)
        print("AIAgent [HiveGraph] canvas history updated — \(canvasChatHistory.count) messages")

        // Step 6: Proposal detection
        let proposalNames: Set<String> = ["propose_feature", "propose_initiative", "propose_milestone"]
        if let tc = assistantMsg.toolCalls?.first(where: { proposalNames.contains($0.toolName) }),
           let pid   = tc.output?["proposalId"] ?? tc.input?["proposalId"],
           let kind  = tc.output?["kind"]       ?? tc.input?["kind"],
           let title = tc.output?["title"]      ?? tc.input?["title"] {
            let desc = tc.output?["description"] ?? tc.input?["description"]
            pendingProposal = PendingProposal(
                proposalId: pid, kind: kind, title: title,
                description: desc
            )
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
            description: "Approve a proposal from Jamie. Only call this when the user confirms approval of a visible proposal card. Use the proposalId from the current canvasChatHistory — never fabricate one.",
            execute: { [weak self] (input: ApproveProposalInput, _: ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> in
                guard let self = self else { return .value(.string("Agent unavailable.")) }
                return await self.executeApproveProposal(proposalId: input.proposalId)
            }
        )
    }

    func executeApproveProposal(proposalId: String) async -> ToolExecutionResult<JSONValue> {
        let proposalNames: Set<String> = ["propose_feature", "propose_initiative", "propose_milestone"]

        // IDOR guard: proposalId must exist in canvasChatHistory
        guard canvasChatHistory.contains(where: {
            $0.toolCalls?.contains(where: {
                proposalNames.contains($0.toolName) &&
                ($0.output?["proposalId"] == proposalId || $0.input?["proposalId"] == proposalId)
            }) == true
        }) else {
            return .value(.string("Proposal not found in current conversation. Cannot approve."))
        }

        // Idempotency: already actioned?
        if let idx = canvasChatHistory.indices.last(where: {
            canvasChatHistory[$0].toolCalls?.contains(where: {
                proposalNames.contains($0.toolName) &&
                ($0.output?["proposalId"] == proposalId || $0.input?["proposalId"] == proposalId)
            }) == true
        }), canvasChatHistory[idx].approvalResult != nil {
            return .value(.string("This proposal has already been actioned."))
        }

        guard let orgId: String = UserDefaults.Keys.hiveOrgId.get(), !orgId.isEmpty,
              let data: Data = UserDefaults.Keys.hiveConversationIdByOrg.get(),
              let dict = try? JSONDecoder().decode([String: String].self, from: data),
              let conversationId = dict[orgId]
        else {
            return .value(.string("Missing org context. Cannot approve."))
        }

        let turnId = UUID().uuidString
        let token: String? = await withCheckedContinuation { cont in
            API.sharedInstance.resolveHiveToken(callback: { cont.resume(returning: $0) }, errorCallback: { cont.resume(returning: nil) })
        }
        guard let token = token else {
            return .value(.string("Authentication failed. Cannot approve."))
        }

        print("AIAgent [HiveGraph] approve_proposal firing — proposalId: \(proposalId), turnId: \(turnId)")

        let messages = (try? JSONEncoder().encode(canvasChatHistory)).flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]]
        } ?? []

        return await withCheckedContinuation { cont in
            API.sharedInstance.sendApprovalIntent(
                orgId: orgId,
                conversationId: conversationId,
                turnId: turnId,
                proposalId: proposalId,
                canvasChatMessages: messages,
                token: token
            ) { [weak self] result in
                guard let self = self else {
                    cont.resume(returning: .value(.string("Agent unavailable.")))
                    return
                }
                if let result = result {
                    // Stamp approval result onto the matching assistant message
                    if let idx = self.canvasChatHistory.indices.last(where: {
                        self.canvasChatHistory[$0].toolCalls?.contains(where: {
                            proposalNames.contains($0.toolName) &&
                            ($0.output?["proposalId"] == proposalId || $0.input?["proposalId"] == proposalId)
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
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .aiAgentProposalActioned, object: result)
                    }
                    cont.resume(returning: .value(.string("Proposal approved successfully.")))
                } else {
                    print("AIAgent [HiveGraph] approval POST failed — leaving card actionable")
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .aiAgentProposalActioned, object: nil)
                    }
                    cont.resume(returning: .value(.string("Approval failed. Please try again — the card is still actionable.")))
                }
            }
        }
    }

    // MARK: - Reject Proposal Tool

    func buildRejectProposalTool() -> TypedTool<RejectProposalInput, JSONValue> {
        tool(
            description: "Reject a proposal from Jamie. Only call this when the user explicitly rejects a visible proposal card. Use the proposalId from the current canvasChatHistory — never fabricate one.",
            execute: { [weak self] (input: RejectProposalInput, _: ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> in
                guard let self = self else { return .value(.string("Agent unavailable.")) }
                return await self.executeRejectProposal(proposalId: input.proposalId)
            }
        )
    }

    func executeRejectProposal(proposalId: String) async -> ToolExecutionResult<JSONValue> {
        let proposalNames: Set<String> = ["propose_feature", "propose_initiative", "propose_milestone"]

        // IDOR guard
        guard canvasChatHistory.contains(where: {
            $0.toolCalls?.contains(where: {
                proposalNames.contains($0.toolName) &&
                ($0.output?["proposalId"] == proposalId || $0.input?["proposalId"] == proposalId)
            }) == true
        }) else {
            return .value(.string("Proposal not found in current conversation. Cannot reject."))
        }

        // Idempotency
        if let idx = canvasChatHistory.indices.last(where: {
            canvasChatHistory[$0].toolCalls?.contains(where: {
                proposalNames.contains($0.toolName) &&
                ($0.output?["proposalId"] == proposalId || $0.input?["proposalId"] == proposalId)
            }) == true
        }), canvasChatHistory[idx].approvalResult != nil {
            return .value(.string("This proposal has already been actioned."))
        }

        guard let orgId: String = UserDefaults.Keys.hiveOrgId.get(), !orgId.isEmpty,
              let data: Data = UserDefaults.Keys.hiveConversationIdByOrg.get(),
              let dict = try? JSONDecoder().decode([String: String].self, from: data),
              let conversationId = dict[orgId]
        else {
            return .value(.string("Missing org context. Cannot reject."))
        }

        let turnId = UUID().uuidString
        let token: String? = await withCheckedContinuation { cont in
            API.sharedInstance.resolveHiveToken(callback: { cont.resume(returning: $0) }, errorCallback: { cont.resume(returning: nil) })
        }
        guard let token = token else {
            return .value(.string("Authentication failed. Cannot reject."))
        }

        print("AIAgent [HiveGraph] reject_proposal firing — proposalId: \(proposalId), turnId: \(turnId)")

        let messages = (try? JSONEncoder().encode(canvasChatHistory)).flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]]
        } ?? []

        return await withCheckedContinuation { cont in
            API.sharedInstance.sendRejectionIntent(
                orgId: orgId,
                conversationId: conversationId,
                turnId: turnId,
                proposalId: proposalId,
                canvasChatMessages: messages,
                token: token
            ) { [weak self] success in
                guard let self = self else {
                    cont.resume(returning: .value(.string("Agent unavailable.")))
                    return
                }
                if success {
                    let rejectionResult = ApprovalResult(approved: false, proposalId: proposalId, message: nil)
                    if let idx = self.canvasChatHistory.indices.last(where: {
                        self.canvasChatHistory[$0].toolCalls?.contains(where: {
                            proposalNames.contains($0.toolName) &&
                            ($0.output?["proposalId"] == proposalId || $0.input?["proposalId"] == proposalId)
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
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .aiAgentProposalActioned, object: rejectionResult)
                    }
                    cont.resume(returning: .value(.string("Proposal rejected.")))
                } else {
                    print("AIAgent [HiveGraph] rejection POST failed — leaving card actionable")
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .aiAgentProposalActioned, object: nil)
                    }
                    cont.resume(returning: .value(.string("Rejection failed. Please try again — the card is still actionable.")))
                }
            }
        }
    }

    // MARK: - Debug Mock Injector

    #if DEBUG
    func injectMockProposal(kind: String = "feature") {
        let mock = PendingProposal(
            proposalId: "mock-\(UUID().uuidString)",
            kind: kind,
            title: "[MOCK] Build \(kind) dashboard",
            description: "A mock proposal for UI development."
        )
        pendingProposal = mock
        NotificationCenter.default.post(name: .aiAgentProposalDetected, object: mock)
    }
    #endif
}
