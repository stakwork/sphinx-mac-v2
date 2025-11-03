//
//  ContentItem+CoreDataClass.swift
//  sphinx
//
//  Created by Tomas Timinskas on 30/10/2025.
//  Copyright © 2025 Tomas Timinskas. All rights reserved.
//
import Foundation
import CoreData
import SwiftyJSON

@objc(ContentItem)
public class ContentItem: NSManagedObject {
    
    enum ContentItemStatus: Int {
        case pending = 0
        case sent = 1
        case processing = 2
        case success = 3
        case error = 4
        
        public init(fromRawValue: Int){
            self = ContentItemStatus(rawValue: fromRawValue) ?? .pending
        }
    }
    
    enum ContentType: String {
        case image = "image"
        case video = "video"
        case fileURL = "fileURL"
        case externalURL = "externalURL"
        case text = "text"
    }
    
    public static func getAllContentItems(context: NSManagedObjectContext) -> [ContentItem] {
        let fetchRequest = NSFetchRequest<ContentItem>(entityName: "ContentItem")
        
        do {
            let contentItems = try context.fetch(fetchRequest)
            return contentItems
        } catch let error as NSError {
            print("Error fetching servers: \(error.localizedDescription)")
            return []
        }
    }
    
    static func getContentItemWith(
        uuid: UUID,
        managedContext: NSManagedObjectContext? = nil
    ) -> ContentItem? {
        let predicate = NSPredicate(format: "uuid == %@", uuid.uuidString)
        
        let contentItem: ContentItem? = CoreDataManager.sharedManager.getObjectOfTypeWith(
            predicate: predicate,
            sortDescriptors: [],
            entityName: "ContentItem",
            managedContext: managedContext
        )
        
        return contentItem
    }
    
    static func getContentItemWith(
        value: String,
        managedContext: NSManagedObjectContext? = nil
    ) -> ContentItem? {
        let predicate = NSPredicate(format: "value == %@", value)
        
        let contentItem: ContentItem? = CoreDataManager.sharedManager.getObjectOfTypeWith(
            predicate: predicate,
            sortDescriptors: [],
            entityName: "ContentItem",
            managedContext: managedContext
        )
        
        return contentItem
    }
    
    static func getLowestItemOrder(
        managedContext: NSManagedObjectContext? = nil
    ) -> ContentItem? {
        let fetchRequest = NSFetchRequest<ContentItem>(entityName: "ContentItem")
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "order", ascending: true)]
        fetchRequest.fetchLimit = 1
        
        let managedContext = managedContext ?? CoreDataManager.sharedManager.persistentContainer.viewContext
        
        do {
            let results = try managedContext.fetch(fetchRequest)
            return results.first
        } catch let error as NSError {
            return nil
        }
    }
    
    static func getContentItesmWith(
        type: String,
        managedContext: NSManagedObjectContext? = nil
    ) -> [ContentItem] {
        let predicate = NSPredicate(format: "type == %@", type)
        
        let contentItems: [ContentItem] = CoreDataManager.sharedManager.getObjectsOfTypeWith(
            predicate: predicate,
            sortDescriptors: [],
            entityName: "ContentItem",
            managedContext: managedContext
        )
        
        return contentItems
    }
    
    static func saveObjectFrom(
        value: String
    ) {
        let managedContext = CoreDataManager.sharedManager.persistentContainer.viewContext
        
        let date = Date()
        
        let contentItem = ContentItem(context: managedContext) as ContentItem
        contentItem.uuid = UUID()
        contentItem.date = Date()
        contentItem.value = value
        contentItem.status = Int16(ContentItemStatus.pending.rawValue)
        contentItem.projectId = nil
        contentItem.order = Int(date.timeIntervalSince1970)
        
        let result = FileAnalyzer.analyze(value)
        
        switch result {
        case .localImageFile(_):
            contentItem.type = ContentType.image.rawValue
        case .localVideoFile(_):
            contentItem.type = ContentType.video.rawValue
        case .localFile(_, _):
            contentItem.type = ContentType.fileURL.rawValue
        case .urlString(_):
            contentItem.type = ContentType.externalURL.rawValue
        case .plainText(_):
            contentItem.type = ContentType.text.rawValue
        }

        managedContext.saveContext()
    }
}
