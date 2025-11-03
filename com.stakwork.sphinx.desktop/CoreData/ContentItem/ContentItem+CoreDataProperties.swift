//
//  ContentItem+CoreDataProperties.swift
//  sphinx
//
//  Created by Tomas Timinskas on 30/10/2025.
//  Copyright © 2025 Tomas Timinskas. All rights reserved.
//
import Foundation
import CoreData

extension ContentItem {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<ContentItem> {
        return NSFetchRequest<ContentItem>(entityName: "ContentItem")
    }

    @NSManaged public var uuid: UUID?
    @NSManaged public var type: String
    @NSManaged public var value: String
    @NSManaged public var date: Date
    @NSManaged public var status: Int16
    @NSManaged public var projectId: String?
    @NSManaged public var order: Int

}
