//
//  GraphJournalEntry+CoreDataClass.swift
//  sphinx
//
//  Append-only journal row of the personal knowledge graph (source of truth).
//  Rows are never updated or deleted by the graph code; deletes are tombstone rows.
//
import Foundation
import CoreData

@objc(GraphJournalEntry)
public class GraphJournalEntry: NSManagedObject {

    var operationType: GraphOpType? {
        return GraphOpType(rawValue: opType)
    }
}
