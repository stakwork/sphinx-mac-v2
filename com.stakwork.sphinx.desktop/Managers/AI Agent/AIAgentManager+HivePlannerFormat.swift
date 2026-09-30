//
//  AIAgentManager+HivePlannerFormat.swift
//  Sphinx
//
//  Pure formatting / resolution helpers for the Hive planner tools.
//  Confirmed Hive contract: userStories are objects {id,title,order,completed,...};
//  clarifying questions are PLAN artifacts whose content is
//  {tool_use:"ask_clarifying_questions", content:[{question,type,options?}]}; a question
//  message is answered once a later message has replyId == its id.
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

    /// Stories sorted by `order` ascending (stable; missing order sorts last), rendered as
    /// `- [x] title` / `- [ ] title`. Plain strings are tolerated as `- [ ] text`.
    static func formatUserStories(_ items: [JSON]) -> String? {
        var entries: [(order: Double, index: Int, line: String)] = []
        for (index, item) in items.enumerated() {
            if let text = item.string {
                if text.isEmpty { continue }
                entries.append((Double.greatestFiniteMagnitude, index, "- [ ] \(text)"))
                continue
            }
            guard let title = item["title"].string, !title.isEmpty else { continue }
            let done = item["completed"].bool == true
            let order = item["order"].double ?? Double.greatestFiniteMagnitude
            entries.append((order, index, "- [\(done ? "x" : " ")] \(title)"))
        }
        if entries.isEmpty { return nil }
        let sorted = entries.sorted { $0.order != $1.order ? $0.order < $1.order : $0.index < $1.index }
        return sorted.map { $0.line }.joined(separator: "\n")
    }

    static func formatPlan(json: JSON?, fallbackTitle: String) -> String {
        guard let json = json, let detail = hiveUnwrap(json) else {
            return "Failed to fetch plan for feature '\(fallbackTitle)'."
        }
        func section(_ title: String, _ body: String?) -> String {
            let trimmed = body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return "\(title):\n" + (trimmed.isEmpty ? "(not written yet)" : trimmed)
        }
        let storiesBody = formatUserStories(detail["userStories"].array ?? [])

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

    // MARK: Clarifying questions

    static let clarifyingQuestionsTool = "ask_clarifying_questions"

    /// Returns the question objects when the artifact is a PLAN clarifying-questions artifact, else nil.
    static func clarifyingQuestions(_ artifact: JSON) -> [JSON]? {
        guard artifact["type"].string == "PLAN" else { return nil }
        let content = artifact["content"]
        guard content["tool_use"].string == clarifyingQuestionsTool else { return nil }
        return content["content"].array ?? content["questions"].array ?? []
    }

    /// Message ids that are answered: a LATER message has `replyId` equal to that id.
    static func answeredMessageIds(_ messages: [JSON]) -> Set<String> {
        var answered = Set<String>()
        var laterReplyIds = Set<String>()
        for msg in messages.reversed() {
            if let id = msg["id"].string, laterReplyIds.contains(id) { answered.insert(id) }
            if let reply = msg["replyId"].string, !reply.isEmpty { laterReplyIds.insert(reply) }
        }
        return answered
    }

    /// Pure. `messageId` / `answered` describe the owning planner message (used for clarifying questions).
    static func summariseArtifact(_ artifact: JSON, messageId: String? = nil, answered: Bool = false) -> String {
        let type = artifact["type"].string ?? "UNKNOWN"
        if let questions = clarifyingQuestions(artifact) {
            var lines = ["[artifact PLAN: clarifying questions] message id: \(messageId ?? "unknown") — \(answered ? "Answered" : "Open")"]
            for (i, q) in questions.enumerated() {
                let text = q["question"].string ?? q.string ?? ""
                var line = "\(i + 1). \(text)"
                if let kind = q["type"].string, !kind.isEmpty { line += " (\(kind))" }
                lines.append(line)
                let options = (q["options"].array ?? []).compactMap { $0.string ?? $0["label"].string }
                if !options.isEmpty { lines.append("   Options: \(options.joined(separator: ", "))") }
            }
            return lines.joined(separator: "\n")
        }
        let content = artifact["content"]
        var raw = ""
        if content.exists() && content.type != .null {
            raw = content.string ?? content.rawString(options: []) ?? ""
        }
        if raw.isEmpty { return "[artifact \(type)]" }
        return "[artifact \(type)] \(excerpt(raw))"
    }

    /// Shows the last 30 messages as `[role] text`, plus every OPEN clarifying-question message
    /// from the FULL history (even if older than the window) listed first with its message id.
    static func formatChat(messages: [JSON]) -> String {
        if messages.isEmpty { return "No planner messages yet" }
        let answeredIds = answeredMessageIds(messages)

        var openBlocks: [String] = []
        for msg in messages {
            guard let id = msg["id"].string, !answeredIds.contains(id) else { continue }
            for artifact in msg["artifacts"].array ?? [] where clarifyingQuestions(artifact) != nil {
                openBlocks.append(summariseArtifact(artifact, messageId: id, answered: false))
            }
        }

        var lines: [String] = []
        if !openBlocks.isEmpty {
            lines.append("Open clarifying questions (reply with send_to_planner using reply_to_message_id = the message id):")
            lines.append(contentsOf: openBlocks)
            lines.append("Recent messages:")
        }
        for msg in messages.suffix(30) {
            let role = (msg["role"].string ?? "unknown").lowercased()
            let text = msg["message"].string ?? msg["content"].string ?? ""
            let id = msg["id"].string
            if !text.isEmpty { lines.append("[\(role)] \(text)") }
            for artifact in msg["artifacts"].array ?? [] {
                let isAnswered = id.map { answeredIds.contains($0) } ?? false
                lines.append("[\(role)] \(summariseArtifact(artifact, messageId: id, answered: isAnswered))")
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
