//
//  WorkspaceTasksMockData.swift
//  Sphinx
//
//  Created on 2025-02-26.
//  Copyright © 2025 Sphinx. All rights reserved.
//

import Foundation
import SwiftyJSON

struct WorkspaceTasksMockData {
    
    static let activeTasks: [WorkspaceTask] = [
        // CRITICAL priority, BLOCKED status
        createTask(
            id: "task-001",
            title: "Fix critical production bug in payment gateway",
            status: "BLOCKED",
            priority: "CRITICAL",
            repositoryName: "sphinx-payments",
            updatedAt: "2026-02-26T10:30:00Z"
        ),
        // HIGH priority, IN_PROGRESS status
        createTask(
            id: "task-002",
            title: "Implement real-time workspace notifications",
            status: "IN_PROGRESS",
            priority: "HIGH",
            repositoryName: "sphinx-mac-v2",
            updatedAt: "2026-02-26T09:15:00Z"
        ),
        // MEDIUM priority, TODO status
        createTask(
            id: "task-003",
            title: "Update API documentation for workspace endpoints",
            status: "TODO",
            priority: "MEDIUM",
            repositoryName: "sphinx-api-docs",
            updatedAt: "2026-02-25T16:45:00Z"
        ),
        // LOW priority, TODO status
        createTask(
            id: "task-004",
            title: "Refactor legacy codebase utilities",
            status: "TODO",
            priority: "LOW",
            repositoryName: nil,
            updatedAt: "2026-02-24T14:20:00Z"
        ),
        // DONE status, HIGH priority
        createTask(
            id: "task-005",
            title: "Complete user authentication flow redesign",
            status: "DONE",
            priority: "HIGH",
            repositoryName: "sphinx-auth",
            updatedAt: "2026-02-26T08:00:00Z"
        ),
        // CANCELLED status, MEDIUM priority
        createTask(
            id: "task-006",
            title: "Integrate third-party analytics service",
            status: "CANCELLED",
            priority: "MEDIUM",
            repositoryName: nil,
            updatedAt: "2026-02-23T11:30:00Z"
        ),
        // CRITICAL priority, IN_PROGRESS status
        createTask(
            id: "task-007",
            title: "Database migration for user profiles",
            status: "IN_PROGRESS",
            priority: "CRITICAL",
            repositoryName: "sphinx-backend",
            updatedAt: "2026-02-26T07:45:00Z"
        ),
        // HIGH priority, TODO status, no repository
        createTask(
            id: "task-008",
            title: "Design new onboarding flow mockups",
            status: "TODO",
            priority: "HIGH",
            repositoryName: nil,
            updatedAt: "2026-02-25T13:10:00Z"
        ),
    ]
    
    static let archivedTasks: [WorkspaceTask] = []
    
    private static func createTask(
        id: String,
        title: String,
        status: String,
        priority: String,
        repositoryName: String?,
        updatedAt: String
    ) -> WorkspaceTask {
        let json: [String: Any] = [
            "id": id,
            "title": title,
            "status": status,
            "priority": priority,
            "updatedAt": updatedAt,
            "repository": repositoryName != nil ? ["name": repositoryName!] : [:],
            "chatMessageCount": 0
        ]
        return WorkspaceTask(json: JSON(json))!
    }
}
