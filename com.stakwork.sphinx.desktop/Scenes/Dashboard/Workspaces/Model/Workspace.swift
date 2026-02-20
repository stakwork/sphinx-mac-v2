//
//  Workspace.swift
//  Sphinx
//
//  Created on 2025-02-19.
//  Copyright © 2025 Sphinx. All rights reserved.
//

import Foundation
import SwiftyJSON

struct Workspace: Codable, Hashable {
    let id: String
    let name: String
    let slug: String?
    let description: String?
    let userRole: String?
    let memberCount: Int
    let ownerId: String?
    let logoUrl: String?
    let logoKey: String?
    let createdAt: String?
    let updatedAt: String?
    let lastAccessedAt: String?

    init(
        id: String,
        name: String,
        slug: String? = nil,
        description: String? = nil,
        userRole: String? = nil,
        memberCount: Int = 0,
        ownerId: String? = nil,
        logoUrl: String? = nil,
        logoKey: String? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil,
        lastAccessedAt: String? = nil
    ) {
        self.id = id
        self.name = name
        self.slug = slug
        self.description = description
        self.userRole = userRole
        self.memberCount = memberCount
        self.ownerId = ownerId
        self.logoUrl = logoUrl
        self.logoKey = logoKey
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastAccessedAt = lastAccessedAt
    }

    init?(json: JSON) {
        guard let id = json["id"].string,
              let name = json["name"].string else {
            return nil
        }

        self.id = id
        self.name = name
        self.slug = json["slug"].string
        self.description = json["description"].string
        self.userRole = json["userRole"].string
        self.memberCount = json["memberCount"].int ?? 0
        self.ownerId = json["ownerId"].string
        self.logoUrl = json["logoUrl"].string
        self.logoKey = json["logoKey"].string
        self.createdAt = json["createdAt"].string
        self.updatedAt = json["updatedAt"].string
        self.lastAccessedAt = json["lastAccessedAt"].string
    }

    var formattedRole: String {
        guard let role = userRole else { return "" }
        return role.capitalized.replacingOccurrences(of: "_", with: " ")
    }

    var membersText: String {
        return "Members: \(memberCount)"
    }
}
