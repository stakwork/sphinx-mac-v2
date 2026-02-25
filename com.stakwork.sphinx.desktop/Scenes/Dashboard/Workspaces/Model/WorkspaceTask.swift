//
//  WorkspaceTask.swift
//  Sphinx
//
//  Created on 2025-02-25.
//  Copyright © 2025 Sphinx. All rights reserved.
//

import Foundation
import SwiftyJSON

struct WorkspaceTask: Codable, Hashable {
    let id: String
    let title: String
    let description: String?
    let status: String        // "TODO|IN_PROGRESS|DONE|CANCELLED|BLOCKED"
    let priority: String      // "LOW|MEDIUM|HIGH|CRITICAL"
    let workflowStatus: String?
    let sourceType: String?
    let mode: String?
    let podId: String?
    let createdAt: String?
    let updatedAt: String?
    let featureId: String?
    let featureTitle: String?
    let assigneeId: String?
    let assigneeName: String?
    let assigneeEmail: String?
    let assigneeImage: String?
    let repositoryId: String?
    let repositoryName: String?
    let repositoryUrl: String?
    let createdById: String?
    let createdByName: String?
    let createdByImage: String?
    let chatMessageCount: Int

    init?(json: JSON) {
        guard let id = json["id"].string,
              let title = json["title"].string,
              let status = json["status"].string,
              let priority = json["priority"].string else { return nil }
        
        self.id = id
        self.title = title
        self.status = status
        self.priority = priority
        self.description = json["description"].string
        self.workflowStatus = json["workflowStatus"].string
        self.sourceType = json["sourceType"].string
        self.mode = json["mode"].string
        self.podId = json["podId"].string
        self.createdAt = json["createdAt"].string
        self.updatedAt = json["updatedAt"].string
        self.featureId = json["feature"]["id"].string
        self.featureTitle = json["feature"]["title"].string
        self.assigneeId = json["assignee"]["id"].string
        self.assigneeName = json["assignee"]["name"].string
        self.assigneeEmail = json["assignee"]["email"].string
        self.assigneeImage = json["assignee"]["image"].string
        self.repositoryId = json["repository"]["id"].string
        self.repositoryName = json["repository"]["name"].string
        self.repositoryUrl = json["repository"]["url"].string
        self.createdById = json["createdBy"]["id"].string
        self.createdByName = json["createdBy"]["name"].string
        self.createdByImage = json["createdBy"]["image"].string
        self.chatMessageCount = json["chatMessageCount"].int ?? 0
    }
}
