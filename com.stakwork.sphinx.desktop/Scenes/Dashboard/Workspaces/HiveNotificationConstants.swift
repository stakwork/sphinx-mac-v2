//
//  HiveNotificationConstants.swift
//  com.stakwork.sphinx.desktop
//
//  Created on 2026-07-01.
//  Copyright © 2026 Sphinx. All rights reserved.
//

import Foundation

/// Shared constants for Hive notification preference types.
/// Mirrors the 11 entries defined in the iOS HiveConfigurationViewController.
enum HiveNotificationConstants {

    /// Ordered list of (key, display label) pairs for all 11 notification types.
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
        ("WORKSPACE_ACCESS_REQUEST",     "Workspace Access Request"),
    ]

    /// Default on/off state for each notification type.
    /// Used as the base that fetched server preferences are merged over.
    static let defaultPreferences: [String: Bool] = [
        "TASK_ASSIGNED":               true,
        "FEATURE_ASSIGNED":            true,
        "PLAN_AWAITING_CLARIFICATION": true,
        "PLAN_AWAITING_APPROVAL":      true,
        "PLAN_TASKS_GENERATED":        true,
        "WORKFLOW_HALTED":             true,
        "FEATURE_COMPLETED":           true,
        "FEATURE_DEPLOYED_PRODUCTION": true,
        "TASK_PR_MERGED":              true,
        "GRAPH_CHAT_RESPONSE":         false,
        "WORKSPACE_ACCESS_REQUEST":    true,
    ]

    /// Merges server-fetched preferences over defaults.
    /// - All 11 known keys are always present in the result (falling back to default if absent).
    /// - Unknown keys returned by the server are preserved as-is.
    static func merged(fetched: [String: Bool]) -> [String: Bool] {
        var result = defaultPreferences
        for (key, value) in fetched {
            result[key] = value
        }
        return result
    }
}
