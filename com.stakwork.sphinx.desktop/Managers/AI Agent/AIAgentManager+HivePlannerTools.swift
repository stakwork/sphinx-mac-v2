//
//  AIAgentManager+HivePlannerTools.swift
//  Sphinx
//
//  Hive planner tools: get_feature_plan, get_feature_plan_chat, send_to_planner.
//  Feature ids come only from the caller's own workspace/feature list via resolveFeature.
//  answer_planner_form is intentionally NOT implemented (Hive FORM contract unverified).
//  Copyright © 2026 Sphinx. All rights reserved.
//

import Foundation
import SwiftAISDK
import SwiftyJSON

extension AIAgentManager {

    struct HiveSendToPlannerInput: Codable, Sendable {
        let workspace_name: String
        let feature_name: String
        let message: String
        let reply_to_message_id: String?
    }

    // MARK: - get_feature_plan

    func buildGetFeaturePlanTool() -> TypedTool<HiveFeatureNameInput, JSONValue> {
        tool(
            description: "Get the plan for a Hive feature (brief, user stories, requirements, architecture, workflow status) by workspace and feature name.",
            execute: { (input: HiveFeatureNameInput, _: ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> in
                let resolution = await AIAgentManager.resolveFeature(
                    workspaceName: input.workspace_name,
                    featureName: input.feature_name
                )
                switch resolution {
                case .message(let text):
                    return .value(.string(text))
                case .found(let id, let title):
                    let detail = await AIAgentManager.fetchFeatureDetailAsync(featureId: id)
                    return .value(.string(AIAgentManager.formatPlan(json: detail, fallbackTitle: title)))
                }
            }
        )
    }

    // MARK: - get_feature_plan_chat

    func buildGetFeaturePlanChatTool() -> TypedTool<HiveFeatureNameInput, JSONValue> {
        tool(
            description: "Get the recent planner chat messages (last 30, with artifact summaries) for a Hive feature, to catch up on planning.",
            execute: { (input: HiveFeatureNameInput, _: ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> in
                let resolution = await AIAgentManager.resolveFeature(
                    workspaceName: input.workspace_name,
                    featureName: input.feature_name
                )
                switch resolution {
                case .message(let text):
                    return .value(.string(text))
                case .found(let id, let title):
                    guard let json = await AIAgentManager.fetchFeatureChatAsync(featureId: id),
                          AIAgentManager.hiveUnwrap(json) != nil else {
                        return .value(.string("Failed to fetch planner chat for feature '\(title)'."))
                    }
                    let messages = AIAgentManager.hiveChatMessages(json)
                    let header = "Planner chat for feature '\(title)':\n"
                    return .value(.string(header + AIAgentManager.formatChat(messages: messages)))
                }
            }
        )
    }

    // MARK: - send_to_planner

    func buildSendToPlannerTool() -> TypedTool<HiveSendToPlannerInput, JSONValue> {
        tool(
            description: "Send a message to a Hive feature's planner. Never call this twice for the same user request, and never retry after a 'planner is already running' (busy) or 'may or may not have reached' (unknown) result. IMPORTANT: Before invoking this tool, describe the action to the user and ask for explicit confirmation. Only invoke after the user confirms.",
            execute: { (input: HiveSendToPlannerInput, _: ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> in
                let resolution = await AIAgentManager.resolveFeature(
                    workspaceName: input.workspace_name,
                    featureName: input.feature_name
                )
                switch resolution {
                case .message(let text):
                    return .value(.string(text))
                case .found(let id, _):
                    let result = await AIAgentManager.sendToPlanner(
                        featureId: id,
                        message: input.message,
                        replyId: input.reply_to_message_id,
                        fetchDetail: { await AIAgentManager.fetchFeatureDetailAsync(featureId: $0) },
                        send: { featureId, message, replyId in
                            await withCheckedContinuation { (continuation: CheckedContinuation<HiveWriteResult, Never>) in
                                API.sharedInstance.sendFeatureChatMessageWithAuth(
                                    featureId: featureId,
                                    message: message,
                                    replyId: replyId,
                                    completion: { continuation.resume(returning: $0) }
                                )
                            }
                        }
                    )
                    return .value(.string(result))
                }
            }
        )
    }

    /// Testable core. FAILS CLOSED: the feature must be loadable (proving the caller can access it)
    /// before anything is sent. Sends at most once; never retries. Logs feature id + outcome only.
    static func sendToPlanner(
        featureId: String,
        message: String,
        replyId: String?,
        fetchDetail: (String) async -> JSON?,
        send: (String, String, String?) async -> HiveWriteResult
    ) async -> String {
        guard let detailJson = await fetchDetail(featureId),
              detailJson["data"].type == .dictionary,
              let detail = hiveUnwrap(detailJson) else {
            print("[AIAgent] send_to_planner: feature \(featureId) access check failed, not sent")
            return "You don't have access to this feature, or it could not be loaded. Nothing was sent."
        }

        if detail["workflowStatus"].string?.uppercased() == "IN_PROGRESS" {
            print("[AIAgent] send_to_planner: feature \(featureId) planner busy, not sent")
            return plannerBusyMessage
        }

        let result = await send(featureId, message, replyId)
        let outcome: String
        let reply: String
        switch result {
        case .success:
            outcome = "sent"
            reply = "Message sent to the planner."
        case .conflict:
            outcome = "conflict"
            reply = plannerBusyMessage
        case .forbidden:
            outcome = "forbidden"
            reply = "You don't have access to this feature."
        case .unauthorized:
            outcome = "unauthorized"
            reply = "Your Hive session has expired — please sign in again."
        case .notFound:
            outcome = "not found"
            reply = "Feature not found."
        case .unknownOutcome:
            outcome = "unknown outcome"
            reply = "The send may or may not have reached the planner — do NOT resend; check get_feature_plan_chat first."
        case .failed:
            outcome = "failed"
            reply = "Failed to send the message to the planner."
        }
        print("[AIAgent] send_to_planner: feature \(featureId) \(outcome)")
        return reply
    }
}
