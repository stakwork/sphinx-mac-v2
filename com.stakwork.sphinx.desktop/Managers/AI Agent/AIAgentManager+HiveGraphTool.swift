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
    func onToolCall(_ toolName: String, _ input: String) {}
    func onToolOutputAvailable(_ toolName: String, _ output: String) {}
}

// MARK: - AIAgentManager+HiveGraphTool

extension AIAgentManager {

    struct QueryHiveGraphInput: Codable, Sendable {
        let workspace_name: String
        let question: String
    }

    func buildQueryHiveGraphTool() -> TypedTool<QueryHiveGraphInput, JSONValue> {
        tool(
            description: "Query a Hive workspace knowledge graph by workspace name and question. Use this when the user asks about their codebase, project structure, recent commits, or any information that lives in a Hive workspace graph.",
            execute: { (input: QueryHiveGraphInput, _: ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> in
                let result = await AIAgentManager.executeQueryHiveGraph(
                    workspaceName: input.workspace_name,
                    question: input.question
                )
                return .value(.string(result))
            }
        )
    }

    private static func executeQueryHiveGraph(
        workspaceName: String,
        question: String
    ) async -> String {

        // Step 1: Fetch workspaces
        let workspaces: [Workspace]? = await withCheckedContinuation { continuation in
            API.sharedInstance.fetchWorkspacesWithAuth(
                callback: { continuation.resume(returning: $0) },
                errorCallback: { continuation.resume(returning: nil) }
            )
        }

        guard let workspaces = workspaces, !workspaces.isEmpty else {
            return "Failed to fetch Hive workspaces. Make sure your Hive token is configured."
        }

        // Step 2: Fuzzy-match workspace name using shared resolver
        let (matchedWorkspace, candidates) = resolveWorkspace(query: workspaceName, from: workspaces)
        guard let matchedWorkspace = matchedWorkspace else {
            if candidates.count > 1 {
                return "Multiple workspaces match '\(workspaceName)': \(candidates.joined(separator: ", ")). Please be more specific."
            }
            let names = workspaces.map { $0.name }.joined(separator: ", ")
            return "No Hive workspace found matching '\(workspaceName)'. Available workspaces: \(names)"
        }

        // Prefer slug over UUID (matches what the server expects)
        let slug = matchedWorkspace.slug ?? matchedWorkspace.id

        print("AIAgent [HiveGraph] querying workspace '\(matchedWorkspace.name)' (slug: \(slug)): \(question)")

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

        // Step 4: Stream the graph response
        let bridge = HiveGraphBridge()
        let sseManager = GraphChatSSEManager()
        bridge.sseManager = sseManager
        sseManager.delegate = bridge

        let result: String = await withCheckedContinuation { continuation in
            bridge.continuation = continuation
            sseManager.startStream(
                messages: [["role": "user", "content": question]],
                workspaceSlug: slug,
                token: token
            )
        }

        return result
    }
}
