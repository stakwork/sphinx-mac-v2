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
        case onQueue = 0
        case uploaded = 1
        case processing = 2
        case success = 3
        case error = 4
        
        public init(fromRawValue: Int){
            self = ContentItemStatus(rawValue: fromRawValue) ?? .onQueue
        }
        
        var sfSymbol: String {
            switch self {
            case .onQueue:
                return "clock"
            case .uploaded:
                return "arrow.up.circle"
            case .processing:
                return "gearshape.2"
            case .success:
                return "checkmark.circle"
            case .error:
                return "xmark.circle"
            }
        }
        
        var color: NSColor {
            switch self {
            case .onQueue:
                return NSColor.Sphinx.SecondaryText
            case .uploaded:
                return NSColor.Sphinx.PrimaryBlue
            case .processing:
                return NSColor.Sphinx.SphinxOrange
            case .success:
                return NSColor.Sphinx.PrimaryGreen
            case .error:
                return NSColor.Sphinx.PrimaryRed
            }
        }
        
        var statusString : String {
            get {
                switch(self) {
                case .onQueue:
                    return "Uploaded"
                case .processing:
                    return "Processing"
                case .success:
                    return "Succeded"
                case .error:
                    return "Failed"
                default:
                    return "On Queue"
                }
            }
        }
    }
    
    enum ContentType: String {
        case image = "image"
        case video = "video"
        case fileURL = "fileURL"
        case externalURL = "externalURL"
        case text = "text"
    }
    
    func shouldBeUploaded() -> Bool {
        return type == ContentType.image.rawValue || type == ContentType.video.rawValue || type == ContentType.fileURL.rawValue || type == ContentType.text.rawValue
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
        } catch _ as NSError {
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
            sortDescriptors: [NSSortDescriptor(key: "order", ascending: true)],
            entityName: "ContentItem",
            managedContext: managedContext
        )
        
        return contentItems
    }
    
    static func getContentItemsWith(
        status: Int,
        managedContext: NSManagedObjectContext? = nil
    ) -> [ContentItem] {
        let predicate = NSPredicate(format: "status == %d", status)
        
        let contentItems: [ContentItem] = CoreDataManager.sharedManager.getObjectsOfTypeWith(
            predicate: predicate,
            sortDescriptors: [NSSortDescriptor(key: "order", ascending: true)],
            entityName: "ContentItem",
            managedContext: managedContext
        )
        
        return contentItems
    }
    
    static func getContentItesmWith(
        statuses: [Int],
        managedContext: NSManagedObjectContext? = nil
    ) -> [ContentItem] {
        let predicate = NSPredicate(format: "status IN %@", statuses)
        
        let contentItems: [ContentItem] = CoreDataManager.sharedManager.getObjectsOfTypeWith(
            predicate: predicate,
            sortDescriptors: [NSSortDescriptor(key: "order", ascending: true)],
            entityName: "ContentItem",
            managedContext: managedContext
        )
        
        return contentItems
    }
    
    static func saveObjectFrom(
        value: String,
        context: NSManagedObjectContext? = nil
    ) -> ContentItem? {
        let managedContext = context ?? CoreDataManager.sharedManager.persistentContainer.viewContext
        
        let date = Date()
        
        let contentItem = ContentItem(context: managedContext) as ContentItem
        contentItem.uuid = UUID()
        contentItem.date = Date()
        contentItem.value = value
        contentItem.status = Int16(ContentItemStatus.onQueue.rawValue)
        contentItem.projectId = nil
        contentItem.referenceId = nil
        contentItem.errorMessage = nil
        contentItem.lastProcessedAt = nil
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
        
        return contentItem
    }
}
