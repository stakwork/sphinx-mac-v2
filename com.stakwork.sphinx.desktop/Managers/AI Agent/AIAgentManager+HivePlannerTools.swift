//
//  AIAgentManager+HivePlannerTools.swift
//  Sphinx
//
//  Hive planner tools: get_feature_plan, get_feature_plan_chat, send_to_planner,
//  answer_planner_form. Feature ids come only from the caller's own workspace/feature
//  list via resolveFeature. Clarifying questions are answered ONLY via answer_planner_form
//  (POST /features/:id/chat with replyId = the target PLAN message id); send_to_planner
//  never sets replyId.
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
    }

    struct HivePlannerFormAnswerInput: Codable, Sendable {
        let workspace_name: String
        let feature_name: String
        let answer: String
        let planner_message_id: String?
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
                        replyId: nil,
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

    // MARK: - answer_planner_form

    func buildAnswerPlannerFormTool() -> TypedTool<HivePlannerFormAnswerInput, JSONValue> {
        tool(
            description: "Answer a Hive feature's open PLAN clarifying questions from the planner chat. Put the answers to ALL questions in that planner message into the single 'answer' string, one block per question in the same order the planner asked them, separated by a blank line — do not add 'Q1:' style prefixes. If planner_message_id is omitted, the latest open clarifying-questions message is answered. Never call this twice for the same user request, and never retry after a 'planner is already running' (busy) or 'may or may not have reached' (unknown) result. IMPORTANT: Before invoking this tool, describe the action to the user and ask for explicit confirmation. Only invoke after the user confirms.",
            execute: { (input: HivePlannerFormAnswerInput, _: ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> in
                let resolution = await AIAgentManager.resolveFeature(
                    workspaceName: input.workspace_name,
                    featureName: input.feature_name
                )
                switch resolution {
                case .message(let text):
                    return .value(.string(text))
                case .found(let id, _):
                    let result = await AIAgentManager.answerPlannerForm(
                        featureId: id,
                        answer: input.answer,
                        plannerMessageId: input.planner_message_id,
                        fetchDetail: { await AIAgentManager.fetchFeatureDetailAsync(featureId: $0) },
                        fetchChat: { await AIAgentManager.fetchFeatureChatAsync(featureId: $0) },
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

    /// Testable core for `answer_planner_form`. Combines the answers into a single message
    /// (bare text, no "Q1:" prefixes — the model is asked to already order/join them), then
    /// posts it as a reply to the resolved PLAN clarifying-questions message. FAILS CLOSED:
    /// the feature must be loadable, a target message must resolve, and it must not already
    /// be answered, before anything is posted. Posts at most once; never retries.
    static func answerPlannerForm(
        featureId: String,
        answer: String,
        plannerMessageId: String?,
        fetchDetail: (String) async -> JSON?,
        fetchChat: (String) async -> JSON?,
        send: (String, String, String?) async -> HiveWriteResult
    ) async -> String {
        func log(_ outcome: String, http: String = "n/a") {
            print("[AIAgent] answer_planner_form: feature=\(featureId) outcome=\(outcome) http=\(http)")
        }

        guard let detailJson = await fetchDetail(featureId),
              detailJson["data"].type == .dictionary,
              let detail = hiveUnwrap(detailJson) else {
            log("not_found")
            return "You don't have access to this feature, or it could not be loaded. Nothing was sent."
        }

        if detail["workflowStatus"].string?.uppercased() == "IN_PROGRESS" {
            log("conflict")
            return plannerBusyMessage
        }

        guard let chatJson = await fetchChat(featureId), hiveUnwrap(chatJson) != nil else {
            log("failed")
            return "Failed to fetch planner chat for this feature. Nothing was sent."
        }
        let messages = hiveChatMessages(chatJson)

        let resolution = resolvePlannerMessage(messages: messages, plannerMessageId: plannerMessageId)
        let targetId: String
        switch resolution {
        case .invalidMessageId:
            log("not_found")
            return "That message isn't an open clarifying-questions message for this feature. Nothing was sent."
        case .noOpenQuestions:
            log("not_found")
            return "No open clarifying questions for this feature."
        case .alreadyAnswered:
            log("already_answered")
            return "Those questions were already answered."
        case .target(let id):
            targetId = id
        }

        let result = await send(featureId, answer, targetId)
        let outcome: String
        let reply: String
        switch result {
        case .success:
            outcome = "sent"
            reply = "Answer submitted to the planner."
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
            outcome = "not_found"
            reply = "Feature not found."
        case .unknownOutcome:
            outcome = "unknown"
            reply = "The answer may or may not have reached the planner — do NOT resend; check get_feature_plan_chat first."
        case .failed:
            outcome = "failed"
            reply = "Failed to submit the answer to the planner."
        }
        log(outcome)
        return reply
    }
}
