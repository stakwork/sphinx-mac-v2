//
//  HiveNotificationConstants.swift
//  Sphinx
//
//  Created on 2026-07-01.
//  Copyright © 2026 Sphinx. All rights reserved.
//

import Foundation

/// Shared notification-preference metadata used by both the API layer and the UI.
enum HiveNotificationConstants {

    static let notificationKeys: [(key: String, label: String)] = [
        ("TASK_ASSIGNED",                "Task Assigned"),
        ("FEATURE_ASSIGNED",             "Feature Assigned"),
        ("PLAN_AWAITING_CLARIFICATION",  "Plan Awaiting Clarification"),
        ("PLAN_AWAITING_APPROVAL",       "Plan Awaiting Approval"),
        ("PLAN_TASKS_GENERATED",         "Plan Tasks Generated"),
        ("WORKFLOW_HALTED",              "Workflow Halted"),
        ("FEATURE_COMPLETED",            "Feature Completed"),
        ("FEATURE_DEPLOYED_PRODUCTION",  "Feature Deployed to Production"),
        ("TASK_PR_MERGED",               "Task PR Merged"),
        ("GRAPH_CHAT_RESPONSE",          "Graph Chat Response"),
        ("WORKSPACE_ACCESS_REQUEST",     "Workspace Access Request")
    ]

    static let defaultPreferences: [String: Bool] = [
        "TASK_ASSIGNED":                true,
        "FEATURE_ASSIGNED":             true,
        "PLAN_AWAITING_CLARIFICATION":  true,
        "PLAN_AWAITING_APPROVAL":       true,
        "PLAN_TASKS_GENERATED":         true,
        "WORKFLOW_HALTED":              true,
        "FEATURE_COMPLETED":            true,
        "FEATURE_DEPLOYED_PRODUCTION":  true,
        "TASK_PR_MERGED":               true,
        "GRAPH_CHAT_RESPONSE":          false,
        "WORKSPACE_ACCESS_REQUEST":     true
    ]

    /// Merges server-fetched values over defaults.
    /// All 11 known keys are always present; unknown server keys are preserved.
    static func merged(fetched: [String: Bool]) -> [String: Bool] {
        var result = defaultPreferences
        for (key, value) in fetched {
            result[key] = value
        }
        return result
    }
}
