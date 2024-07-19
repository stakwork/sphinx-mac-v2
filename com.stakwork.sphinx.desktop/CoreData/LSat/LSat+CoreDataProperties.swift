//
//  LSat+CoreDataProperties.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 19/07/2024.
//  Copyright © 2024 Tomas Timinskas. All rights reserved.
//

import Foundation
import CoreData

extension LSat {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<LSat> {
        return NSFetchRequest<LSat>(entityName: "LSat")
    }

    @NSManaged public var identifier: String
    @NSManaged public var macarron: String
    @NSManaged public var paymentRequest: String
    @NSManaged public var preimage: String?
    @NSManaged public var issuer: String?
    @NSManaged public var paths: String?
    @NSManaged public var metadata: String?
    @NSManaged public var status: Int
    @NSManaged public var createdAt: Date?

}
