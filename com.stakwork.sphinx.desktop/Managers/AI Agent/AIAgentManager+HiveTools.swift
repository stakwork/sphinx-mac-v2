//
//  AIAgentManager+HiveTools.swift
//  Sphinx
//
//  Created on 2026-06-17.
//  Copyright © 2026 Sphinx. All rights reserved.
//

import Foundation
import SwiftAISDK
import SwiftyJSON

// MARK: - AIAgentManager+HiveTools

extension AIAgentManager {

    // MARK: - Shared Fuzzy Resolution

    private enum HiveItemMatchResult<T> {
        case found(T)
        case ambiguous([String])
        case noMatch
    }

    /// 3-pass fuzzy match on workspace name → slug.
    /// Returns (matched workspace, []) on success, or (nil, [candidates]) on ambiguity/no-match.
    static func resolveWorkspace(query: String, from workspaces: [Workspace]) -> (Workspace?, [String]) {
        let normalizedQuery = hiveNormalizeName(query)

        // Pass 1: exact normalized match
        if let exact = workspaces.first(where: { hiveNormalizeName($0.name) == normalizedQuery }) {
            return (exact, [])
        }

        // Pass 2: case-insensitive contains
        let containsMatches = workspaces.filter { ws in
            hiveNormalizeName(ws.name).contains(normalizedQuery) ||
            normalizedQuery.contains(hiveNormalizeName(ws.name))
        }
        if containsMatches.count == 1 { return (containsMatches[0], []) }
        if containsMatches.count > 1  { return (nil, containsMatches.map { $0.name }) }

        // Pass 3: Levenshtein fuzzy match
        let threshold = max(1, normalizedQuery.count / 4)
        let fuzzyMatches = workspaces
            .map { ws -> (workspace: Workspace, dist: Int) in
                (ws, hiveLevenshtein(hiveNormalizeName(ws.name), normalizedQuery))
            }
            .filter { $0.dist <= threshold }
            .sorted { $0.dist < $1.dist }

        if fuzzyMatches.count == 1 { return (fuzzyMatches[0].workspace, []) }
        if fuzzyMatches.count > 1 {
            if fuzzyMatches[0].dist + 2 <= fuzzyMatches[1].dist {
                return (fuzzyMatches[0].workspace, [])
            }
            return (nil, fuzzyMatches.map { $0.workspace.name })
        }

        return (nil, workspaces.map { $0.name })
    }

    /// Generic fuzzy match on any named item.
    static func resolveHiveItem<T>(query: String, items: [T], name: (T) -> String) -> (match: T?, candidates: [String]) {
        let normalizedQuery = hiveNormalizeName(query)

        if let exact = items.first(where: { hiveNormalizeName(name($0)) == normalizedQuery }) {
            return (exact, [])
        }

        let containsMatches = items.filter { item in
            let n = hiveNormalizeName(name(item))
            return n.contains(normalizedQuery) || normalizedQuery.contains(n)
        }
        if containsMatches.count == 1 { return (containsMatches[0], []) }
        if containsMatches.count > 1  { return (nil, containsMatches.map { name($0) }) }

        let threshold = max(1, normalizedQuery.count / 4)
        let fuzzyMatches = items
            .map { item -> (item: T, dist: Int) in
                (item, hiveLevenshtein(hiveNormalizeName(name(item)), normalizedQuery))
            }
            .filter { $0.dist <= threshold }
            .sorted { $0.dist < $1.dist }

        if fuzzyMatches.count == 1 { return (fuzzyMatches[0].item, []) }
        if fuzzyMatches.count > 1 {
            if fuzzyMatches[0].dist + 2 <= fuzzyMatches[1].dist {
                return (fuzzyMatches[0].item, [])
            }
            return (nil, fuzzyMatches.map { name($0.item) })
        }

        return (nil, items.map { name($0) })
    }

    // MARK: - Helpers (shared with HiveGraphTool via same name space)

    static func hiveNormalizeName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let underscoresAsSpaces = trimmed.replacingOccurrences(of: "_", with: " ")
        let components = underscoresAsSpaces.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        return components.joined(separator: " ").lowercased()
    }

    static func hiveLevenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a), bChars = Array(b)
        let m = aChars.count, n = bChars.count
        if m == 0 { return n }
        if n == 0 { return m }
        var prev = Array(0...n)
        var curr = [Int](repeating: 0, count: n + 1)
        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                curr[j] = aChars[i-1] == bChars[j-1]
                    ? prev[j-1]
                    : 1 + min(prev[j-1], prev[j], curr[j-1])
            }
            prev = curr
        }
        return prev[n]
    }

    // MARK: - Async workspace fetch helper

    private static func fetchWorkspacesAsync() async -> [Workspace]? {
        await withCheckedContinuation { continuation in
            API.sharedInstance.fetchWorkspacesWithAuth(
                callback: { continuation.resume(returning: $0) },
                errorCallback: { continuation.resume(returning: nil) }
            )
        }
    }

    // MARK: - Input Structs

    struct HiveWorkspaceNameInput: Codable, Sendable {
        let workspace_name: String
    }

    struct HiveSearchInput: Codable, Sendable {
        let workspace_name: String
        let query: String
    }

    struct HiveListFeaturesInput: Codable, Sendable {
        let workspace_name: String
    }

    struct HiveFeatureNameInput: Codable, Sendable {
        let workspace_name: String
        let feature_name: String
    }

    struct HiveListTasksInput: Codable, Sendable {
        let workspace_name: String
        let include_archived: Bool?
    }

    struct HiveTaskNameInput: Codable, Sendable {
        let workspace_name: String
        let task_name: String
    }

    struct HiveCreateFeatureInput: Codable, Sendable {
        let workspace_name: String
        let title: String
        let description: String?
    }

    struct HiveUpdateFeatureInput: Codable, Sendable {
        let workspace_name: String
        let feature_name: String
        let title: String?
        let description: String?
    }

    struct HiveTriggerTaskGenInput: Codable, Sendable {
        let workspace_name: String
        let feature_name: String
    }

    struct HiveUpdateTaskStatusInput: Codable, Sendable {
        let workspace_name: String
        let task_name: String
        let status: String
    }

    struct HiveStartTaskInput: Codable, Sendable {
        let workspace_name: String
        let task_name: String
    }

    struct HiveRetryTaskInput: Codable, Sendable {
        let workspace_name: String
        let task_name: String
    }

    struct HiveArchiveTaskInput: Codable, Sendable {
        let workspace_name: String
        let task_name: String
    }

    // MARK: - Tool 1: list_hive_workspaces

    func buildListHiveWorkspacesTool() -> TypedTool<JSONValue, JSONValue> {
        let inputSchema = FlexibleSchema<JSONValue>(
            jsonSchema(.object([
                "type": .string("object"),
                "properties": .object([:]),
                "required": .array([])
            ]))
        )
        return tool(
            description: "List all Hive workspaces the user has access to, including name, slug, description, role, and member count.",
            inputSchema: inputSchema,
            execute: { (_: JSONValue, _: ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> in
                let workspaces: [Workspace]? = await withCheckedContinuation { continuation in
                    API.sharedInstance.fetchWorkspacesWithAuth(
                        callback: { continuation.resume(returning: $0) },
                        errorCallback: { continuation.resume(returning: nil) }
                    )
                }
                guard let workspaces = workspaces else {
                    return .value(.string("Failed to fetch Hive workspaces. Make sure your Hive token is configured."))
                }
                if workspaces.isEmpty {
                    return .value(.string("No Hive workspaces found."))
                }
                let lines = workspaces.map { ws -> String in
                    var parts = ["- \(ws.name)"]
                    if let slug = ws.slug { parts.append("slug: \(slug)") }
                    if let desc = ws.description, !desc.isEmpty { parts.append("description: \(desc)") }
                    if let role = ws.userRole { parts.append("role: \(role)") }
                    parts.append("members: \(ws.memberCount)")
                    return parts.joined(separator: ", ")
                }
                let output = "Hive workspaces (\(workspaces.count)):\n" + lines.joined(separator: "\n")
                return .value(.string(output))
            }
        )
    }

    // MARK: - Tool 2: get_workspace_detail

    func buildGetWorkspaceDetailTool() -> TypedTool<HiveWorkspaceNameInput, JSONValue> {
        tool(
            description: "Get detailed information about a Hive workspace by name, including members list.",
            execute: { (input: HiveWorkspaceNameInput, _: ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> in
                guard let workspaces = await AIAgentManager.fetchWorkspacesAsync() else {
                    return .value(.string("Failed to fetch Hive workspaces."))
                }
                let (ws, candidates) = AIAgentManager.resolveWorkspace(query: input.workspace_name, from: workspaces)
                guard let workspace = ws else {
                    if candidates.isEmpty {
                        return .value(.string("No workspace found matching '\(input.workspace_name)'. Available: \(workspaces.map { $0.name }.joined(separator: ", "))."))
                    }
                    if candidates.count > 1 {
                        return .value(.string("Multiple workspaces match '\(input.workspace_name)': \(candidates.joined(separator: ", ")). Please be more specific."))
                    }
                    return .value(.string("No workspace found matching '\(input.workspace_name)'. Available: \(candidates.joined(separator: ", "))."))
                }

                let slug = workspace.slug ?? workspace.id

                // Fetch detail and members concurrently
                async let detailResult: JSON? = withCheckedContinuation { continuation in
                    API.sharedInstance.fetchWorkspaceDetailWithAuth(
                        slug: slug,
                        callback: { continuation.resume(returning: $0) },
                        errorCallback: { continuation.resume(returning: nil) }
                    )
                }
                async let membersResult: JSON? = withCheckedContinuation { continuation in
                    API.sharedInstance.fetchWorkspaceMembersWithAuth(
                        slug: slug,
                        callback: { continuation.resume(returning: $0) },
                        errorCallback: { continuation.resume(returning: nil) }
                    )
                }
                let (detail, members) = await (detailResult, membersResult)

                var lines: [String] = []
                lines.append("Workspace: \(workspace.name)")
                lines.append("Slug: \(slug)")
                if let desc = workspace.description, !desc.isEmpty { lines.append("Description: \(desc)") }
                if let role = workspace.userRole { lines.append("Your role: \(role)") }
                lines.append("Members: \(workspace.memberCount)")

                if let detail = detail, detail != JSON.null {
                    if let created = detail["createdAt"].string { lines.append("Created: \(created)") }
                    if let updated = detail["updatedAt"].string { lines.append("Updated: \(updated)") }
                }

                if let members = members {
                    let membersArray = members["members"].array ?? members.array ?? []
                    if !membersArray.isEmpty {
                        lines.append("\nMember list:")
                        for m in membersArray.prefix(20) {
                            let name   = m["name"].string ?? m["nickname"].string ?? "(unnamed)"
                            let role   = m["role"].string ?? ""
                            let roleStr = role.isEmpty ? "" : " (\(role))"
                            lines.append("  - \(name)\(roleStr)")
                        }
                        if membersArray.count > 20 { lines.append("  … and \(membersArray.count - 20) more") }
                    }
                }

                return .value(.string(lines.joined(separator: "\n")))
            }
        )
    }

    // MARK: - Tool 3: search_workspace

    func buildSearchWorkspaceTool() -> TypedTool<HiveSearchInput, JSONValue> {
        tool(
            description: "Search within a Hive workspace for tasks, features, or content matching a query.",
            execute: { (input: HiveSearchInput, _: ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> in
                guard let workspaces = await AIAgentManager.fetchWorkspacesAsync() else {
                    return .value(.string("Failed to fetch Hive workspaces."))
                }
                let (ws, candidates) = AIAgentManager.resolveWorkspace(query: input.workspace_name, from: workspaces)
                guard let workspace = ws else {
                    if candidates.count > 1 {
                        return .value(.string("Multiple workspaces match '\(input.workspace_name)': \(candidates.joined(separator: ", ")). Please be more specific."))
                    }
                    return .value(.string("No workspace found matching '\(input.workspace_name)'. Available: \(workspaces.map { $0.name }.joined(separator: ", "))."))
                }

                let slug = workspace.slug ?? workspace.id
                let result: JSON? = await withCheckedContinuation { continuation in
                    API.sharedInstance.searchWorkspaceWithAuth(
                        slug: slug,
                        query: input.query,
                        callback: { continuation.resume(returning: $0) },
                        errorCallback: { continuation.resume(returning: nil) }
                    )
                }

                guard let json = result else {
                    return .value(.string("Search failed for workspace '\(workspace.name)'."))
                }

                let items = json["results"].array ?? json.array ?? []
                if items.isEmpty {
                    return .value(.string("No results found in '\(workspace.name)' for query: '\(input.query)'."))
                }

                let lines = items.prefix(20).map { item -> String in
                    let type_  = item["type"].string ?? "item"
                    let title  = item["title"].string ?? item["name"].string ?? "(untitled)"
                    let status = item["status"].string.map { " [\($0)]" } ?? ""
                    return "- [\(type_)] \(title)\(status)"
                }
                var output = "Search results in '\(workspace.name)' for '\(input.query)' (\(items.count) results):\n"
                output += lines.joined(separator: "\n")
                if items.count > 20 { output += "\n… and \(items.count - 20) more" }
                return .value(.string(output))
            }
        )
    }

    // MARK: - Tool 4: list_features

    func buildListFeaturesTool() -> TypedTool<HiveListFeaturesInput, JSONValue> {
        tool(
            description: "List all features in a Hive workspace.",
            execute: { (input: HiveListFeaturesInput, _: ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> in
                guard let workspaces = await AIAgentManager.fetchWorkspacesAsync() else {
                    return .value(.string("Failed to fetch Hive workspaces."))
                }
                let (ws, candidates) = AIAgentManager.resolveWorkspace(query: input.workspace_name, from: workspaces)
                guard let workspace = ws else {
                    if candidates.count > 1 {
                        return .value(.string("Multiple workspaces match '\(input.workspace_name)': \(candidates.joined(separator: ", ")). Please be more specific."))
                    }
                    return .value(.string("No workspace found matching '\(input.workspace_name)'. Available: \(workspaces.map { $0.name }.joined(separator: ", "))."))
                }

                let result: JSON? = await withCheckedContinuation { continuation in
                    API.sharedInstance.fetchFeaturesWithAuth(
                        workspaceId: workspace.id,
                        callback: { continuation.resume(returning: $0) },
                        errorCallback: { continuation.resume(returning: nil) }
                    )
                }

                guard let json = result else {
                    return .value(.string("Failed to fetch features for workspace '\(workspace.name)'."))
                }

                let features = json["data"].array ?? json.array ?? []
                if features.isEmpty {
                    return .value(.string("No features found in workspace '\(workspace.name)'."))
                }

                let hasMore = json["hasMore"].bool ?? false
                let lines = features.map { f -> String in
                    let id     = f["id"].string ?? "?"
                    let title  = f["title"].string ?? "(untitled)"
                    let status = f["status"].string.map { " [\($0)]" } ?? ""
                    return "- \(title)\(status) (id: \(id))"
                }
                var output = "Features in '\(workspace.name)' (\(features.count)):\n" + lines.joined(separator: "\n")
                if hasMore { output += "\n(More features available — use pagination to fetch more.)" }
                return .value(.string(output))
            }
        )
    }

    // MARK: - Tool 5: get_feature_detail

    func buildGetFeatureDetailTool() -> TypedTool<HiveFeatureNameInput, JSONValue> {
        tool(
            description: "Get detailed information about a specific Hive feature by name within a workspace.",
            execute: { (input: HiveFeatureNameInput, _: ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> in
                guard let workspaces = await AIAgentManager.fetchWorkspacesAsync() else {
                    return .value(.string("Failed to fetch Hive workspaces."))
                }
                let (ws, wsCandidates) = AIAgentManager.resolveWorkspace(query: input.workspace_name, from: workspaces)
                guard let workspace = ws else {
                    if wsCandidates.count > 1 {
                        return .value(.string("Multiple workspaces match '\(input.workspace_name)': \(wsCandidates.joined(separator: ", ")). Please be more specific."))
                    }
                    return .value(.string("No workspace found matching '\(input.workspace_name)'. Available: \(workspaces.map { $0.name }.joined(separator: ", "))."))
                }

                let featuresJson: JSON? = await withCheckedContinuation { continuation in
                    API.sharedInstance.fetchFeaturesWithAuth(
                        workspaceId: workspace.id,
                        callback: { continuation.resume(returning: $0) },
                        errorCallback: { continuation.resume(returning: nil) }
                    )
                }
                guard let json = featuresJson else {
                    return .value(.string("Failed to fetch features for workspace '\(workspace.name)'."))
                }

                let featureItems = json["data"].array ?? json.array ?? []
                let (feature, featureCandidates) = AIAgentManager.resolveHiveItem(
                    query: input.feature_name,
                    items: featureItems,
                    name: { $0["title"].string ?? "" }
                )
                guard let featureJson = feature, let featureId = featureJson["id"].string else {
                    if featureCandidates.count > 1 {
                        return .value(.string("Multiple features match '\(input.feature_name)': \(featureCandidates.joined(separator: ", ")). Please be more specific."))
                    }
                    return .value(.string("No feature found matching '\(input.feature_name)'. Available: \(featureCandidates.joined(separator: ", "))."))
                }

                let detailJson: JSON? = await withCheckedContinuation { continuation in
                    API.sharedInstance.fetchFeatureDetailWithAuth(
                        featureId: featureId,
                        callback: { continuation.resume(returning: $0) },
                        errorCallback: { continuation.resume(returning: nil) }
                    )
                }

                let detail = detailJson ?? featureJson
                var lines: [String] = []
                lines.append("Feature: \(detail["title"].string ?? input.feature_name)")
                lines.append("ID: \(featureId)")
                if let status = detail["status"].string      { lines.append("Status: \(status)") }
                if let priority = detail["priority"].string  { lines.append("Priority: \(priority)") }
                if let desc = detail["description"].string, !desc.isEmpty { lines.append("Description: \(desc)") }
                if let created = detail["createdAt"].string  { lines.append("Created: \(created)") }
                if let updated = detail["updatedAt"].string  { lines.append("Updated: \(updated)") }
                let taskCount = detail["taskCount"].int ?? detail["tasks"].array?.count
                if let tc = taskCount { lines.append("Tasks: \(tc)") }

                return .value(.string(lines.joined(separator: "\n")))
            }
        )
    }

    // MARK: - Tool 6: list_tasks

    func buildListTasksTool() -> TypedTool<HiveListTasksInput, JSONValue> {
        tool(
            description: "List tasks in a Hive workspace. Optionally include archived tasks via include_archived (default false).",
            execute: { (input: HiveListTasksInput, _: ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> in
                guard let workspaces = await AIAgentManager.fetchWorkspacesAsync() else {
                    return .value(.string("Failed to fetch Hive workspaces."))
                }
                let (ws, candidates) = AIAgentManager.resolveWorkspace(query: input.workspace_name, from: workspaces)
                guard let workspace = ws else {
                    if candidates.count > 1 {
                        return .value(.string("Multiple workspaces match '\(input.workspace_name)': \(candidates.joined(separator: ", ")). Please be more specific."))
                    }
                    return .value(.string("No workspace found matching '\(input.workspace_name)'. Available: \(workspaces.map { $0.name }.joined(separator: ", "))."))
                }

                let includeArchived = input.include_archived ?? false
                let tasks: [WorkspaceTask]? = await withCheckedContinuation { continuation in
                    API.sharedInstance.fetchTasksWithAuth(
                        workspaceId: workspace.id,
                        includeArchived: includeArchived,
                        callback: { continuation.resume(returning: $0) },
                        errorCallback: { continuation.resume(returning: nil) }
                    )
                }

                guard let tasks = tasks else {
                    return .value(.string("Failed to fetch tasks for workspace '\(workspace.name)'."))
                }
                if tasks.isEmpty {
                    return .value(.string("No tasks found in workspace '\(workspace.name)'\(includeArchived ? " (including archived)" : "")."))
                }

                let shown = min(tasks.count, 50)
                let hasMore = tasks.count > 50
                let lines = tasks.prefix(50).map { task -> String in
                    var parts = ["- \(task.title)"]
                    parts.append("[\(task.status)]")
                    parts.append("priority: \(task.priority)")
                    if let feature = task.featureTitle { parts.append("feature: \(feature)") }
                    return parts.joined(separator: ", ")
                }
                var output = "Tasks in '\(workspace.name)' (\(tasks.count) total):\n" + lines.joined(separator: "\n")
                if hasMore { output += "\n(Showing \(shown) of \(tasks.count). Use filters to narrow results.)" }
                return .value(.string(output))
            }
        )
    }

    // MARK: - Tool 7: get_task_detail

    func buildGetTaskDetailTool() -> TypedTool<HiveTaskNameInput, JSONValue> {
        tool(
            description: "Get detailed information about a specific Hive task by name within a workspace.",
            execute: { (input: HiveTaskNameInput, _: ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> in
                guard let workspaces = await AIAgentManager.fetchWorkspacesAsync() else {
                    return .value(.string("Failed to fetch Hive workspaces."))
                }
                let (ws, wsCandidates) = AIAgentManager.resolveWorkspace(query: input.workspace_name, from: workspaces)
                guard let workspace = ws else {
                    if wsCandidates.count > 1 {
                        return .value(.string("Multiple workspaces match '\(input.workspace_name)': \(wsCandidates.joined(separator: ", ")). Please be more specific."))
                    }
                    return .value(.string("No workspace found matching '\(input.workspace_name)'. Available: \(workspaces.map { $0.name }.joined(separator: ", "))."))
                }

                let tasks: [WorkspaceTask]? = await withCheckedContinuation { continuation in
                    API.sharedInstance.fetchTasksWithAuth(
                        workspaceId: workspace.id,
                        includeArchived: true,
                        callback: { continuation.resume(returning: $0) },
                        errorCallback: { continuation.resume(returning: nil) }
                    )
                }
                guard let tasks = tasks else {
                    return .value(.string("Failed to fetch tasks for workspace '\(workspace.name)'."))
                }

                let (task, taskCandidates) = AIAgentManager.resolveHiveItem(
                    query: input.task_name,
                    items: tasks,
                    name: { $0.title }
                )
                guard let resolvedTask = task else {
                    if taskCandidates.count > 1 {
                        return .value(.string("Multiple tasks match '\(input.task_name)': \(taskCandidates.joined(separator: ", ")). Please be more specific."))
                    }
                    return .value(.string("No task found matching '\(input.task_name)'. Available: \(taskCandidates.joined(separator: ", "))."))
                }

                let detailJson: JSON? = await withCheckedContinuation { continuation in
                    API.sharedInstance.fetchTaskDetailWithAuth(
                        taskId: resolvedTask.id,
                        callback: { continuation.resume(returning: $0) },
                        errorCallback: { continuation.resume(returning: nil) }
                    )
                }

                var lines: [String] = []
                lines.append("Task: \(resolvedTask.title)")
                lines.append("ID: \(resolvedTask.id)")
                lines.append("Status: \(resolvedTask.status)")
                lines.append("Priority: \(resolvedTask.priority)")
                if let feature = resolvedTask.featureTitle { lines.append("Feature: \(feature)") }
                if let desc = resolvedTask.description, !desc.isEmpty { lines.append("Description: \(desc)") }
                if let assignee = resolvedTask.assigneeName { lines.append("Assignee: \(assignee)") }
                if let wfStatus = resolvedTask.workflowStatus { lines.append("Workflow Status: \(wfStatus)") }
                if let repo = resolvedTask.repositoryName { lines.append("Repository: \(repo)") }
                if let created = resolvedTask.createdAt { lines.append("Created: \(created)") }
                if let updated = resolvedTask.updatedAt { lines.append("Updated: \(updated)") }
                lines.append("Chat Messages: \(resolvedTask.chatMessageCount)")

                if let detail = detailJson {
                    if let extra = detail["podId"].string { lines.append("Pod ID: \(extra)") }
                }

                return .value(.string(lines.joined(separator: "\n")))
            }
        )
    }

    // MARK: - Tool 8: get_task_messages

    func buildGetTaskMessagesTool() -> TypedTool<HiveTaskNameInput, JSONValue> {
        tool(
            description: "Get the chat messages for a specific Hive task. Returns the last 20 messages.",
            execute: { (input: HiveTaskNameInput, _: ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> in
                guard let workspaces = await AIAgentManager.fetchWorkspacesAsync() else {
                    return .value(.string("Failed to fetch Hive workspaces."))
                }
                let (ws, wsCandidates) = AIAgentManager.resolveWorkspace(query: input.workspace_name, from: workspaces)
                guard let workspace = ws else {
                    if wsCandidates.count > 1 {
                        return .value(.string("Multiple workspaces match '\(input.workspace_name)': \(wsCandidates.joined(separator: ", ")). Please be more specific."))
                    }
                    return .value(.string("No workspace found matching '\(input.workspace_name)'. Available: \(workspaces.map { $0.name }.joined(separator: ", "))."))
                }

                let tasks: [WorkspaceTask]? = await withCheckedContinuation { continuation in
                    API.sharedInstance.fetchTasksWithAuth(
                        workspaceId: workspace.id,
                        includeArchived: true,
                        callback: { continuation.resume(returning: $0) },
                        errorCallback: { continuation.resume(returning: nil) }
                    )
                }
                guard let tasks = tasks else {
                    return .value(.string("Failed to fetch tasks for workspace '\(workspace.name)'."))
                }

                let (task, taskCandidates) = AIAgentManager.resolveHiveItem(
                    query: input.task_name,
                    items: tasks,
                    name: { $0.title }
                )
                guard let resolvedTask = task else {
                    if taskCandidates.count > 1 {
                        return .value(.string("Multiple tasks match '\(input.task_name)': \(taskCandidates.joined(separator: ", ")). Please be more specific."))
                    }
                    return .value(.string("No task found matching '\(input.task_name)'. Available: \(taskCandidates.joined(separator: ", "))."))
                }

                let messagesJson: JSON? = await withCheckedContinuation { continuation in
                    API.sharedInstance.fetchTaskMessagesWithAuth(
                        taskId: resolvedTask.id,
                        callback: { continuation.resume(returning: $0) },
                        errorCallback: { continuation.resume(returning: nil) }
                    )
                }
                guard let json = messagesJson else {
                    return .value(.string("Failed to fetch messages for task '\(resolvedTask.title)'."))
                }

                let messages = (json["messages"].array ?? json.array ?? []).suffix(20)
                if messages.isEmpty {
                    return .value(.string("No messages found for task '\(resolvedTask.title)'."))
                }

                let lines = messages.map { msg -> String in
                    let role    = msg["role"].string ?? msg["sender"].string ?? "unknown"
                    let content = msg["content"].string ?? msg["message"].string ?? ""
                    return "[\(role)]: \(content)"
                }
                let output = "Messages for task '\(resolvedTask.title)' (last \(messages.count)):\n" + lines.joined(separator: "\n")
                return .value(.string(output))
            }
        )
    }

    // MARK: - Tool 9: create_feature

    func buildCreateFeatureTool() -> TypedTool<HiveCreateFeatureInput, JSONValue> {
        tool(
            description: "Create a new feature in a Hive workspace. IMPORTANT: Before invoking this tool, describe the action to the user and ask for explicit confirmation. Only invoke after the user confirms.",
            execute: { (input: HiveCreateFeatureInput, _: ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> in
                guard let workspaces = await AIAgentManager.fetchWorkspacesAsync() else {
                    return .value(.string("Failed to fetch Hive workspaces."))
                }
                let (ws, candidates) = AIAgentManager.resolveWorkspace(query: input.workspace_name, from: workspaces)
                guard let workspace = ws else {
                    if candidates.count > 1 {
                        return .value(.string("Multiple workspaces match '\(input.workspace_name)': \(candidates.joined(separator: ", ")). Please be more specific."))
                    }
                    return .value(.string("No workspace found matching '\(input.workspace_name)'. Available: \(workspaces.map { $0.name }.joined(separator: ", "))."))
                }

                print("[AIAgent] create_feature: \(workspace.name)/\(input.title)")

                var params: [String: Any] = ["title": input.title]
                if let desc = input.description { params["description"] = desc }

                let result: JSON? = await withCheckedContinuation { continuation in
                    API.sharedInstance.createFeatureWithAuth(
                        workspaceId: workspace.id,
                        params: params as NSDictionary,
                        callback: { continuation.resume(returning: $0) },
                        errorCallback: { continuation.resume(returning: nil) }
                    )
                }

                guard let json = result else {
                    return .value(.string("Failed to create feature '\(input.title)' in workspace '\(workspace.name)'."))
                }
                let id    = json["id"].string ?? json["data"]["id"].string ?? "?"
                let title = json["title"].string ?? json["data"]["title"].string ?? input.title
                return .value(.string("Feature '\(title)' created successfully in '\(workspace.name)' (id: \(id))."))
            }
        )
    }

    // MARK: - Tool 10: update_feature

    func buildUpdateFeatureTool() -> TypedTool<HiveUpdateFeatureInput, JSONValue> {
        tool(
            description: "Update an existing feature in a Hive workspace. IMPORTANT: Before invoking this tool, describe the action to the user and ask for explicit confirmation. Only invoke after the user confirms.",
            execute: { (input: HiveUpdateFeatureInput, _: ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> in
                guard let workspaces = await AIAgentManager.fetchWorkspacesAsync() else {
                    return .value(.string("Failed to fetch Hive workspaces."))
                }
                let (ws, wsCandidates) = AIAgentManager.resolveWorkspace(query: input.workspace_name, from: workspaces)
                guard let workspace = ws else {
                    if wsCandidates.count > 1 {
                        return .value(.string("Multiple workspaces match '\(input.workspace_name)': \(wsCandidates.joined(separator: ", ")). Please be more specific."))
                    }
                    return .value(.string("No workspace found matching '\(input.workspace_name)'. Available: \(workspaces.map { $0.name }.joined(separator: ", "))."))
                }

                let featuresJson: JSON? = await withCheckedContinuation { continuation in
                    API.sharedInstance.fetchFeaturesWithAuth(
                        workspaceId: workspace.id,
                        callback: { continuation.resume(returning: $0) },
                        errorCallback: { continuation.resume(returning: nil) }
                    )
                }
                guard let json = featuresJson else {
                    return .value(.string("Failed to fetch features for workspace '\(workspace.name)'."))
                }

                let featureItems = json["data"].array ?? json.array ?? []
                let (feature, featureCandidates) = AIAgentManager.resolveHiveItem(
                    query: input.feature_name,
                    items: featureItems,
                    name: { $0["title"].string ?? "" }
                )
                guard let featureJson = feature, let featureId = featureJson["id"].string else {
                    if featureCandidates.count > 1 {
                        return .value(.string("Multiple features match '\(input.feature_name)': \(featureCandidates.joined(separator: ", ")). Please be more specific."))
                    }
                    return .value(.string("No feature found matching '\(input.feature_name)'. Available: \(featureCandidates.joined(separator: ", "))."))
                }

                print("[AIAgent] update_feature: \(workspace.name)/\(input.feature_name)")

                var params: [String: Any] = [:]
                if let title = input.title             { params["title"] = title }
                if let desc = input.description         { params["description"] = desc }

                let result: JSON? = await withCheckedContinuation { continuation in
                    API.sharedInstance.updateFeatureWithAuth(
                        featureId: featureId,
                        params: params as NSDictionary,
                        callback: { continuation.resume(returning: $0) },
                        errorCallback: { continuation.resume(returning: nil) }
                    )
                }

                guard result != nil else {
                    return .value(.string("Failed to update feature '\(input.feature_name)' in workspace '\(workspace.name)'."))
                }
                return .value(.string("Feature '\(input.feature_name)' updated successfully in '\(workspace.name)'."))
            }
        )
    }

    // MARK: - Tool 11: trigger_task_generation

    func buildTriggerTaskGenerationTool() -> TypedTool<HiveTriggerTaskGenInput, JSONValue> {
        tool(
            description: "Trigger automatic task generation for a Hive feature. IMPORTANT: Before invoking this tool, describe the action to the user and ask for explicit confirmation. Only invoke after the user confirms.",
            execute: { (input: HiveTriggerTaskGenInput, _: ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> in
                guard let workspaces = await AIAgentManager.fetchWorkspacesAsync() else {
                    return .value(.string("Failed to fetch Hive workspaces."))
                }
                let (ws, wsCandidates) = AIAgentManager.resolveWorkspace(query: input.workspace_name, from: workspaces)
                guard let workspace = ws else {
                    if wsCandidates.count > 1 {
                        return .value(.string("Multiple workspaces match '\(input.workspace_name)': \(wsCandidates.joined(separator: ", ")). Please be more specific."))
                    }
                    return .value(.string("No workspace found matching '\(input.workspace_name)'. Available: \(workspaces.map { $0.name }.joined(separator: ", "))."))
                }

                let featuresJson: JSON? = await withCheckedContinuation { continuation in
                    API.sharedInstance.fetchFeaturesWithAuth(
                        workspaceId: workspace.id,
                        callback: { continuation.resume(returning: $0) },
                        errorCallback: { continuation.resume(returning: nil) }
                    )
                }
                guard let json = featuresJson else {
                    return .value(.string("Failed to fetch features for workspace '\(workspace.name)'."))
                }

                let featureItems = json["data"].array ?? json.array ?? []
                let (feature, featureCandidates) = AIAgentManager.resolveHiveItem(
                    query: input.feature_name,
                    items: featureItems,
                    name: { $0["title"].string ?? "" }
                )
                guard let featureJson = feature, let featureId = featureJson["id"].string else {
                    if featureCandidates.count > 1 {
                        return .value(.string("Multiple features match '\(input.feature_name)': \(featureCandidates.joined(separator: ", ")). Please be more specific."))
                    }
                    return .value(.string("No feature found matching '\(input.feature_name)'. Available: \(featureCandidates.joined(separator: ", "))."))
                }

                print("[AIAgent] trigger_task_generation: \(workspace.name)/\(input.feature_name)")

                let result: JSON? = await withCheckedContinuation { continuation in
                    API.sharedInstance.triggerTaskGenerationWithAuth(
                        featureId: featureId,
                        callback: { continuation.resume(returning: $0) },
                        errorCallback: { continuation.resume(returning: nil) }
                    )
                }

                guard result != nil else {
                    return .value(.string("Failed to trigger task generation for feature '\(input.feature_name)'."))
                }
                return .value(.string("Task generation triggered for feature '\(input.feature_name)' in '\(workspace.name)'. Tasks will be created shortly."))
            }
        )
    }

    // MARK: - Tool 12: update_task_status

    func buildUpdateTaskStatusTool() -> TypedTool<HiveUpdateTaskStatusInput, JSONValue> {
        tool(
            description: "Update the status of a Hive task. Valid statuses: TODO, IN_PROGRESS, DONE, CANCELLED, BLOCKED. IMPORTANT: Before invoking this tool, describe the action to the user and ask for explicit confirmation. Only invoke after the user confirms.",
            execute: { (input: HiveUpdateTaskStatusInput, _: ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> in
                guard let workspaces = await AIAgentManager.fetchWorkspacesAsync() else {
                    return .value(.string("Failed to fetch Hive workspaces."))
                }
                let (ws, wsCandidates) = AIAgentManager.resolveWorkspace(query: input.workspace_name, from: workspaces)
                guard let workspace = ws else {
                    if wsCandidates.count > 1 {
                        return .value(.string("Multiple workspaces match '\(input.workspace_name)': \(wsCandidates.joined(separator: ", ")). Please be more specific."))
                    }
                    return .value(.string("No workspace found matching '\(input.workspace_name)'. Available: \(workspaces.map { $0.name }.joined(separator: ", "))."))
                }

                let tasks: [WorkspaceTask]? = await withCheckedContinuation { continuation in
                    API.sharedInstance.fetchTasksWithAuth(
                        workspaceId: workspace.id,
                        includeArchived: false,
                        callback: { continuation.resume(returning: $0) },
                        errorCallback: { continuation.resume(returning: nil) }
                    )
                }
                guard let tasks = tasks else {
                    return .value(.string("Failed to fetch tasks for workspace '\(workspace.name)'."))
                }

                let (task, taskCandidates) = AIAgentManager.resolveHiveItem(
                    query: input.task_name,
                    items: tasks,
                    name: { $0.title }
                )
                guard let resolvedTask = task else {
                    if taskCandidates.count > 1 {
                        return .value(.string("Multiple tasks match '\(input.task_name)': \(taskCandidates.joined(separator: ", ")). Please be more specific."))
                    }
                    return .value(.string("No task found matching '\(input.task_name)'. Available: \(taskCandidates.joined(separator: ", "))."))
                }

                print("[AIAgent] update_task_status: \(workspace.name)/\(input.task_name) → \(input.status)")

                let result: JSON? = await withCheckedContinuation { continuation in
                    API.sharedInstance.updateTaskStatusWithAuth(
                        taskId: resolvedTask.id,
                        status: input.status.uppercased(),
                        callback: { continuation.resume(returning: $0) },
                        errorCallback: { continuation.resume(returning: nil) }
                    )
                }

                guard result != nil else {
                    return .value(.string("Failed to update status of task '\(input.task_name)'."))
                }
                return .value(.string("Task '\(resolvedTask.title)' status updated to '\(input.status.uppercased())' in '\(workspace.name)'."))
            }
        )
    }

    // MARK: - Tool 13: start_task

    func buildStartTaskTool() -> TypedTool<HiveStartTaskInput, JSONValue> {
        tool(
            description: "Start (assign and begin) a Hive task. IMPORTANT: Before invoking this tool, describe the action to the user and ask for explicit confirmation. Only invoke after the user confirms.",
            execute: { (input: HiveStartTaskInput, _: ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> in
                guard let workspaces = await AIAgentManager.fetchWorkspacesAsync() else {
                    return .value(.string("Failed to fetch Hive workspaces."))
                }
                let (ws, wsCandidates) = AIAgentManager.resolveWorkspace(query: input.workspace_name, from: workspaces)
                guard let workspace = ws else {
                    if wsCandidates.count > 1 {
                        return .value(.string("Multiple workspaces match '\(input.workspace_name)': \(wsCandidates.joined(separator: ", ")). Please be more specific."))
                    }
                    return .value(.string("No workspace found matching '\(input.workspace_name)'. Available: \(workspaces.map { $0.name }.joined(separator: ", "))."))
                }

                let tasks: [WorkspaceTask]? = await withCheckedContinuation { continuation in
                    API.sharedInstance.fetchTasksWithAuth(
                        workspaceId: workspace.id,
                        includeArchived: false,
                        callback: { continuation.resume(returning: $0) },
                        errorCallback: { continuation.resume(returning: nil) }
                    )
                }
                guard let tasks = tasks else {
                    return .value(.string("Failed to fetch tasks for workspace '\(workspace.name)'."))
                }

                let (task, taskCandidates) = AIAgentManager.resolveHiveItem(
                    query: input.task_name,
                    items: tasks,
                    name: { $0.title }
                )
                guard let resolvedTask = task else {
                    if taskCandidates.count > 1 {
                        return .value(.string("Multiple tasks match '\(input.task_name)': \(taskCandidates.joined(separator: ", ")). Please be more specific."))
                    }
                    return .value(.string("No task found matching '\(input.task_name)'. Available: \(taskCandidates.joined(separator: ", "))."))
                }

                print("[AIAgent] start_task: \(workspace.name)/\(input.task_name)")

                let result: JSON? = await withCheckedContinuation { continuation in
                    API.sharedInstance.startTaskWithAuth(
                        taskId: resolvedTask.id,
                        callback: { continuation.resume(returning: $0) },
                        errorCallback: { continuation.resume(returning: nil) }
                    )
                }

                guard result != nil else {
                    return .value(.string("Failed to start task '\(input.task_name)'."))
                }
                return .value(.string("Task '\(resolvedTask.title)' started in '\(workspace.name)'."))
            }
        )
    }

    // MARK: - Tool 14: retry_task_workflow

    func buildRetryTaskWorkflowTool() -> TypedTool<HiveRetryTaskInput, JSONValue> {
        tool(
            description: "Retry the workflow for a failed or stalled Hive task. IMPORTANT: Before invoking this tool, describe the action to the user and ask for explicit confirmation. Only invoke after the user confirms.",
            execute: { (input: HiveRetryTaskInput, _: ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> in
                guard let workspaces = await AIAgentManager.fetchWorkspacesAsync() else {
                    return .value(.string("Failed to fetch Hive workspaces."))
                }
                let (ws, wsCandidates) = AIAgentManager.resolveWorkspace(query: input.workspace_name, from: workspaces)
                guard let workspace = ws else {
                    if wsCandidates.count > 1 {
                        return .value(.string("Multiple workspaces match '\(input.workspace_name)': \(wsCandidates.joined(separator: ", ")). Please be more specific."))
                    }
                    return .value(.string("No workspace found matching '\(input.workspace_name)'. Available: \(workspaces.map { $0.name }.joined(separator: ", "))."))
                }

                let tasks: [WorkspaceTask]? = await withCheckedContinuation { continuation in
                    API.sharedInstance.fetchTasksWithAuth(
                        workspaceId: workspace.id,
                        includeArchived: true,
                        callback: { continuation.resume(returning: $0) },
                        errorCallback: { continuation.resume(returning: nil) }
                    )
                }
                guard let tasks = tasks else {
                    return .value(.string("Failed to fetch tasks for workspace '\(workspace.name)'."))
                }

                let (task, taskCandidates) = AIAgentManager.resolveHiveItem(
                    query: input.task_name,
                    items: tasks,
                    name: { $0.title }
                )
                guard let resolvedTask = task else {
                    if taskCandidates.count > 1 {
                        return .value(.string("Multiple tasks match '\(input.task_name)': \(taskCandidates.joined(separator: ", ")). Please be more specific."))
                    }
                    return .value(.string("No task found matching '\(input.task_name)'. Available: \(taskCandidates.joined(separator: ", "))."))
                }

                print("[AIAgent] retry_task_workflow: \(workspace.name)/\(input.task_name)")

                let result: JSON? = await withCheckedContinuation { continuation in
                    API.sharedInstance.retryTaskWorkflowWithAuth(
                        taskId: resolvedTask.id,
                        callback: { continuation.resume(returning: $0) },
                        errorCallback: { continuation.resume(returning: nil) }
                    )
                }

                guard result != nil else {
                    return .value(.string("Failed to retry workflow for task '\(input.task_name)'."))
                }
                return .value(.string("Workflow retry triggered for task '\(resolvedTask.title)' in '\(workspace.name)'."))
            }
        )
    }

    // MARK: - Tool 15: archive_task

    func buildArchiveTaskTool() -> TypedTool<HiveArchiveTaskInput, JSONValue> {
        tool(
            description: "Archive a Hive task. IMPORTANT: Before invoking this tool, describe the action to the user and ask for explicit confirmation. Only invoke after the user confirms.",
            execute: { (input: HiveArchiveTaskInput, _: ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> in
                guard let workspaces = await AIAgentManager.fetchWorkspacesAsync() else {
                    return .value(.string("Failed to fetch Hive workspaces."))
                }
                let (ws, wsCandidates) = AIAgentManager.resolveWorkspace(query: input.workspace_name, from: workspaces)
                guard let workspace = ws else {
                    if wsCandidates.count > 1 {
                        return .value(.string("Multiple workspaces match '\(input.workspace_name)': \(wsCandidates.joined(separator: ", ")). Please be more specific."))
                    }
                    return .value(.string("No workspace found matching '\(input.workspace_name)'. Available: \(workspaces.map { $0.name }.joined(separator: ", "))."))
                }

                let tasks: [WorkspaceTask]? = await withCheckedContinuation { continuation in
                    API.sharedInstance.fetchTasksWithAuth(
                        workspaceId: workspace.id,
                        includeArchived: false,
                        callback: { continuation.resume(returning: $0) },
                        errorCallback: { continuation.resume(returning: nil) }
                    )
                }
                guard let tasks = tasks else {
                    return .value(.string("Failed to fetch tasks for workspace '\(workspace.name)'."))
                }

                let (task, taskCandidates) = AIAgentManager.resolveHiveItem(
                    query: input.task_name,
                    items: tasks,
                    name: { $0.title }
                )
                guard let resolvedTask = task else {
                    if taskCandidates.count > 1 {
                        return .value(.string("Multiple tasks match '\(input.task_name)': \(taskCandidates.joined(separator: ", ")). Please be more specific."))
                    }
                    return .value(.string("No task found matching '\(input.task_name)'. Available: \(taskCandidates.joined(separator: ", "))."))
                }

                print("[AIAgent] archive_task: \(workspace.name)/\(input.task_name)")

                let result: JSON? = await withCheckedContinuation { continuation in
                    API.sharedInstance.archiveTaskWithAuth(
                        taskId: resolvedTask.id,
                        callback: { continuation.resume(returning: $0) },
                        errorCallback: { continuation.resume(returning: nil) }
                    )
                }

                guard result != nil else {
                    return .value(.string("Failed to archive task '\(input.task_name)'."))
                }
                return .value(.string("Task '\(resolvedTask.title)' archived in '\(workspace.name)'."))
            }
        )
    }

    // MARK: - Org Cache Helpers

    /// Fetches org info from GET /api/orgs and caches hiveOrgId + hiveGithubLogin.
    static func fetchAndCacheHiveOrg() async {
        let org: HiveOrg? = await withCheckedContinuation { continuation in
            API.sharedInstance.fetchOrgsWithAuth(
                callback: { continuation.resume(returning: $0) },
                errorCallback: { continuation.resume(returning: nil) }
            )
        }
        guard let org = org else {
            print("[AIAgent] fetchAndCacheHiveOrg: failed to fetch org")
            return
        }
        UserDefaults.Keys.hiveOrgId.set(org.id)
        UserDefaults.Keys.hiveGithubLogin.set(org.githubLogin)
        print("[AIAgent] fetchAndCacheHiveOrg: cached org '\(org.name)' id=\(org.id) login=\(org.githubLogin)")
    }

    /// Fetches workspace slugs for the cached org and stores them with a timestamp.
    /// Clears conversationId cache if slugs changed.
    static func fetchAndCacheOrgSlugs() async {
        // Ensure we have githubLogin
        if UserDefaults.Keys.hiveGithubLogin.get() == nil {
            await fetchAndCacheHiveOrg()
        }
        guard let githubLogin: String = UserDefaults.Keys.hiveGithubLogin.get(), !githubLogin.isEmpty else {
            print("[AIAgent] fetchAndCacheOrgSlugs: no githubLogin available")
            return
        }

        let slugs: [String]? = await withCheckedContinuation { continuation in
            API.sharedInstance.fetchOrgWorkspacesWithAuth(
                githubLogin: githubLogin,
                callback: { continuation.resume(returning: $0) },
                errorCallback: { continuation.resume(returning: nil) }
            )
        }
        guard let slugs = slugs else {
            print("[AIAgent] fetchAndCacheOrgSlugs: failed to fetch slugs")
            return
        }

        // Check if slugs changed — if so, clear conversationId cache
        if let existingData: Data = UserDefaults.Keys.hiveOrgSlugs.get(),
           let existingSlugs = try? JSONDecoder().decode([String].self, from: existingData) {
            let oldSet = Set(existingSlugs)
            let newSet = Set(slugs)
            if oldSet != newSet {
                print("[AIAgent] fetchAndCacheOrgSlugs: slug set changed, clearing conversationId cache")
                UserDefaults.Keys.hiveConversationIdByOrg.set(nil)
            }
        }

        if let encoded = try? JSONEncoder().encode(slugs) {
            UserDefaults.Keys.hiveOrgSlugs.set(encoded)
        }
        UserDefaults.Keys.hiveOrgSlugsCacheDate.set(Date().timeIntervalSince1970)
        print("[AIAgent] fetchAndCacheOrgSlugs: cached \(slugs.count) slug(s)")
    }

    /// Returns cached org slugs if the cache is less than 24 hours old, else nil.
    static func cachedOrgSlugs() -> [String]? {
        guard let cacheDate: Double = UserDefaults.Keys.hiveOrgSlugsCacheDate.get() else { return nil }
        let age = Date().timeIntervalSince1970 - cacheDate
        guard age < 86400 else { return nil }
        guard let data: Data = UserDefaults.Keys.hiveOrgSlugs.get(),
              let slugs = try? JSONDecoder().decode([String].self, from: data) else { return nil }
        return slugs
    }
}
