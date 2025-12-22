//
//  DataSync+CoreDataProperties.swift
//  sphinx
//
//  Created by Tomas Timinskas on 18/12/2025.
//  Copyright © 2025 Tomas Timinskas. All rights reserved.
//
import Foundation
import CoreData

extension DataSync {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<DataSync> {
        return NSFetchRequest<DataSync>(entityName: "DataSync")
    }

    @NSManaged public var key: String
    @NSManaged public var identifier: String
    @NSManaged public var date: Date
    @NSManaged public var value: String
}
