//
//  AIAgentManager+HivePlannerFormat.swift
//  Sphinx
//
//  Pure formatting / resolution helpers for the Hive planner tools.
//  NOTE: FORM / PLAN artifact shapes are UNCONFIRMED; summariseArtifact only
//  emits the artifact type plus a truncated raw-content excerpt.
//  Copyright © 2026 Sphinx. All rights reserved.
//

import Foundation
import SwiftyJSON

extension AIAgentManager {

    static let plannerBusyMessage = "Planner is already running — try again shortly"

    // MARK: - Unwrap

    /// Returns nil when the response signals failure (`error` field or `success == false`).
    /// Returns `json["data"]` when it is a dictionary, otherwise the JSON itself.
    static func hiveUnwrap(_ json: JSON) -> JSON? {
        if json.type == .null || json.type == .unknown { return nil }
        let errorField = json["error"]
        if errorField.exists() && errorField.type != .null { return nil }
        if json["success"].bool == false { return nil }
        if json["data"].type == .dictionary { return json["data"] }
        return json
    }

    static func excerpt(_ text: String, limit: Int = 200) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        if flat.count <= limit { return flat }
        return String(flat.prefix(limit)) + "…"
    }

    // MARK: - Feature detail

    static func formatFeatureDetail(json: JSON?, featureId: String, fallbackTitle: String) -> String {
        guard let json = json, let detail = hiveUnwrap(json) else {
            return "Failed to fetch detail for feature '\(fallbackTitle)'."
        }
        var lines: [String] = []
        lines.append("Feature: \(detail["title"].string ?? fallbackTitle)")
        lines.append("ID: \(featureId)")
        if let status = detail["status"].string { lines.append("Status: \(status)") }
        if let priority = detail["priority"].string { lines.append("Priority: \(priority)") }
        if let desc = detail["description"].string, !desc.isEmpty { lines.append("Description: \(desc)") }
        lines.append("Workflow Status: \(nonEmpty(detail["workflowStatus"].string) ?? "none")")
        lines.append("Deployment Status: \(nonEmpty(detail["deploymentStatus"].string) ?? "none")")
        if let url = nonEmpty(detail["deploymentUrl"].string) { lines.append("Deployment URL: \(url)") }
        if let created = detail["createdAt"].string { lines.append("Created: \(created)") }
        if let updated = detail["updatedAt"].string { lines.append("Updated: \(updated)") }
        if let tc = detail["taskCount"].int ?? detail["tasks"].array?.count { lines.append("Tasks: \(tc)") }
        return lines.joined(separator: "\n")
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s = s, !s.isEmpty else { return nil }
        return s
    }

    // MARK: - Plan

    static func formatPlan(json: JSON?, fallbackTitle: String) -> String {
        guard let json = json, let detail = hiveUnwrap(json) else {
            return "Failed to fetch plan for feature '\(fallbackTitle)'."
        }
        func section(_ title: String, _ body: String?) -> String {
            let trimmed = body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return "\(title):\n" + (trimmed.isEmpty ? "(not written yet)" : trimmed)
        }
        let stories: [String] = (detail["userStories"].array ?? []).compactMap { item in
            if let s = item.string { return s.isEmpty ? nil : s }
            if let t = item["title"].string { return t.isEmpty ? nil : t }
            return nil
        }
        let storiesBody = stories.isEmpty ? nil : stories.map { "- \($0)" }.joined(separator: "\n")

        var parts: [String] = []
        parts.append("Plan for feature: \(detail["title"].string ?? fallbackTitle)")
        parts.append(section("Brief", detail["brief"].string))
        parts.append(section("User Stories", storiesBody))
        parts.append(section("Requirements", detail["requirements"].string))
        parts.append(section("Architecture", detail["architecture"].string))
        parts.append("Workflow Status: \(nonEmpty(detail["workflowStatus"].string) ?? "none")")
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Chat

    /// Type + truncated raw content excerpt only. Shapes of FORM/PLAN artifacts are unconfirmed.
    static func summariseArtifact(_ artifact: JSON) -> String {
        let type = artifact["type"].string ?? "UNKNOWN"
        let content = artifact["content"]
        var raw = ""
        if content.exists() && content.type != .null {
            raw = content.string ?? content.rawString(options: []) ?? ""
        }
        if raw.isEmpty { return "[artifact \(type)]" }
        return "[artifact \(type)] \(excerpt(raw))"
    }

    static func formatChat(messages: [JSON]) -> String {
        if messages.isEmpty { return "No planner messages yet" }
        var lines: [String] = []
        for msg in messages.suffix(30) {
            let role = (msg["role"].string ?? "unknown").lowercased()
            let text = msg["message"].string ?? msg["content"].string ?? ""
            if !text.isEmpty { lines.append("[\(role)] \(text)") }
            for artifact in msg["artifacts"].array ?? [] {
                lines.append("[\(role)] \(summariseArtifact(artifact))")
            }
            if text.isEmpty && (msg["artifacts"].array ?? []).isEmpty {
                lines.append("[\(role)] ")
            }
        }
        return lines.joined(separator: "\n")
    }

    static func hiveChatMessages(_ json: JSON) -> [JSON] {
        if let arr = json.array { return arr }
        if let arr = json["data"].array { return arr }
        if let arr = json["data"]["messages"].array { return arr }
        return json["messages"].array ?? []
    }

    // MARK: - Async fetch

    static func fetchFeatureDetailAsync(featureId: String) async -> JSON? {
        await withCheckedContinuation { continuation in
            API.sharedInstance.fetchFeatureDetailWithAuth(
                featureId: featureId,
                callback: { continuation.resume(returning: $0) },
                errorCallback: { continuation.resume(returning: nil) }
            )
        }
    }

    static func fetchFeatureChatAsync(featureId: String) async -> JSON? {
        await withCheckedContinuation { continuation in
            API.sharedInstance.fetchFeatureChatWithAuth(
                featureId: featureId,
                callback: { continuation.resume(returning: $0) },
                errorCallback: { continuation.resume(returning: nil) }
            )
        }
    }

    // MARK: - Feature resolution

    enum FeatureResolution: Equatable {
        case found(id: String, title: String)
        case message(String)
    }

    /// Pages through a workspace's own feature list (IDs never come from the model).
    static func resolveFeature(
        featureName: String,
        cap: Int = 10,
        fetchPage: (Int) async -> JSON?
    ) async -> FeatureResolution {
        var pagesFetched = 0
        var page = 1
        while page <= cap {
            guard let json = await fetchPage(page) else {
                if pagesFetched == 0 { return .message("Failed to fetch features.") }
                break
            }
            pagesFetched += 1
            let items = json["data"].array ?? json.array ?? []
            let (match, candidates) = resolveHiveItem(
                query: featureName,
                items: items,
                name: { $0["title"].string ?? "" }
            )
            if let m = match, let id = m["id"].string {
                return .found(id: id, title: m["title"].string ?? featureName)
            }
            // resolveHiveItem returns every item name when nothing matched; a strict subset means ambiguity.
            if candidates.count > 1 && candidates.count < items.count {
                return .message("Multiple features match '\(featureName)': \(candidates.joined(separator: ", ")). Please be more specific.")
            }
            if json["hasMore"].bool != true { break }
            page += 1
        }
        return .message("No feature found matching '\(featureName)' (not found in \(pagesFetched) page(s)).")
    }

    static func resolveFeature(workspaceName: String, featureName: String) async -> FeatureResolution {
        guard let workspaces = await fetchWorkspacesAsync() else {
            return .message("Failed to fetch Hive workspaces.")
        }
        let (ws, wsCandidates) = resolveWorkspace(query: workspaceName, from: workspaces)
        guard let workspace = ws else {
            if wsCandidates.count > 1 {
                return .message("Multiple workspaces match '\(workspaceName)': \(wsCandidates.joined(separator: ", ")). Please be more specific.")
            }
            return .message("No workspace found matching '\(workspaceName)'. Available: \(workspaces.map { $0.name }.joined(separator: ", ")).")
        }
        return await resolveFeature(featureName: featureName) { page in
            await withCheckedContinuation { (continuation: CheckedContinuation<JSON?, Never>) in
                API.sharedInstance.fetchFeaturesWithAuth(
                    workspaceId: workspace.id,
                    page: page,
                    callback: { continuation.resume(returning: $0) },
                    errorCallback: { continuation.resume(returning: nil) }
                )
            }
        }
    }
}
