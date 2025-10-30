//
//  ContentItemsManager.swift
//  sphinx
//
//  Created by Tomas Timinskas on 30/10/2025.
//  Copyright © 2025 Tomas Timinskas. All rights reserved.
//
import CoreData

class ContentItemsManager {
    static let shared = ContentItemsManager()
    
    let context = CoreDataManager.sharedManager.persistentContainer.viewContext
    
    private init() {}
    
    func add(value: String) {
        ContentItem.saveObjectFrom(value: value)
    }
    
    func addMultiple(_ values: [String]) {
        for value in values {
            ContentItem.saveObjectFrom(value: value)
        }
    }
    
    // MARK: - Load
    
    func load() -> [ContentItem] {
        return ContentItem.getAllContentItems(context: context)
    }
    
    // MARK: - Delete
    
    func remove(with value: String) {
        if let contenItem = ContentItem.getContentItemWith(value: value) {
            CoreDataManager.sharedManager.deleteObject(object: contenItem, context: context)
        }
        context.saveContext()
    }
    
    func remove(with uuid: UUID) {
        if let contenItem = ContentItem.getContentItemWith(uuid: uuid) {
            CoreDataManager.sharedManager.deleteObject(object: contenItem, context: context)
        }
        context.saveContext()
    }
    
    func removeAll() {
        for item in ContentItem.getAllContentItems(context: context) {
            CoreDataManager.sharedManager.deleteObject(object: item, context: context)
        }
        context.saveContext()
    }
    
    func getByType(_ type: ContentItem.ContentType) {
        for item in ContentItem.getContentItesmWith(type: type.rawValue, managedContext: context) {
            CoreDataManager.sharedManager.deleteObject(object: item, context: context)
        }
        context.saveContext()
    }
    
    func set(value: String, forUUID uuid: UUID) {
        if let contenItem = ContentItem.getContentItemWith(uuid: uuid) {
            contenItem.value = value
            contenItem.managedObjectContext?.saveContext()
        }
    }
}
