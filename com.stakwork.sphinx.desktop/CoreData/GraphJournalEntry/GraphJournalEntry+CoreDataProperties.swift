//
//  GraphJournalEntry+CoreDataProperties.swift
//  sphinx
//
import Foundation
import CoreData

extension GraphJournalEntry {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<GraphJournalEntry> {
        return NSFetchRequest<GraphJournalEntry>(entityName: "GraphJournalEntry")
    }

    @NSManaged public var clientId: String
    @NSManaged public var seq: Int64
    @NSManaged public var timestamp: Date
    @NSManaged public var opType: Int16
    @NSManaged public var entityId: UUID
    @NSManaged public var payload: Data
    @NSManaged public var schemaVersion: Int16
}
