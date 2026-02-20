//
//  CoreDataManager.swift
//  com.stakwork.sphinx.desktop
//
//  Created by Tomas Timinskas on 11/05/2020.
//  Copyright © 2020 Sphinx. All rights reserved.
//

import Foundation
import CoreData

class CoreDataManager {
    
    static let sharedManager = CoreDataManager()
    
    private init() {}
    
    lazy var persistentContainer: NSPersistentContainer = {
        
        let container = NSPersistentContainer(name: "com_stakwork_sphinx_desktop")
        
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                print("Unresolved error \(error), \(error.userInfo)")
            }
        })
        
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.shouldDeleteInaccessibleFaults = true
        
        // 🔑 Ensures that the `mainContext` is aware of any changes that were made
        // to the persistent container.
        //
        // For example, when we save a background context,
        // the persistent container is automatically informed of the changes that
        // were made. And since the `mainContext` is considered to be a child of
        // the persistent container, it will receive those updates -- merging
        // any changes, as the name suggests, automatically.
        container.viewContext.automaticallyMergesChangesFromParent = true
        
        return container
    }()
    
    func saveContext() {
        CoreDataManager.sharedManager.persistentContainer.viewContext.saveContext()
    }
    
    func getBackgroundContext() -> NSManagedObjectContext {
        let backgroundContext = CoreDataManager.sharedManager.persistentContainer.newBackgroundContext()
        backgroundContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        backgroundContext.shouldDeleteInaccessibleFaults = true
        backgroundContext.automaticallyMergesChangesFromParent = true
        
        return backgroundContext
    }
    
    func clearCoreDataStore() {
        let context = CoreDataManager.sharedManager.persistentContainer.viewContext
        context.performAndWait {
            context.deleteAllObjects()
            do {
                try context.save()
            } catch {
                print("Error on deleting CoreData entities")
            }
        }
    }
    
    func resetContext() {
        let context = CoreDataManager.sharedManager.persistentContainer.viewContext
        context.reset()
    }
    
    func deleteExpiredInvites() {
        for contact in UserContact.getPendingContacts() {
            if let invite = contact.invite, !contact.isOwner, !contact.isConfirmed() && invite.isExpired() {
                invite.removeFromPaymentProcessed()
                deleteContactObjectsFor(contact)
            }
        }

        saveContext()
    }
    
    func deleteContactObjectsFor(_ contact: UserContact) {
        if let chat = contact.getConversation() {
            for message in chat.getAllMessages(limit: nil, forceAllMsgs: true) {
                MediaLoader.clearMessageMediaCache(message: message)
                deleteObject(object: message)
            }
            chat.deleteColor()
            deleteObject(object: chat)
        }

        if let subscription = contact.getCurrentSubscription() {
            deleteObject(object: subscription)
        }

        if let invite = contact.invite {
            invite.removeFromPaymentProcessed()
        }
        
        contact.deleteColor()
        deleteObject(object: contact)
        saveContext()
    }
    
    func deleteChatObjectsFor(_ chat: Chat) {
        let managedContext = persistentContainer.viewContext
        managedContext.performAndWait {
            do {
                // Check if chat is valid and belongs to this context
                guard !chat.isDeleted, chat.managedObjectContext == managedContext else {
                    return
                }

                if let messagesSet = chat.messages, let groupMessages = Array<Any>(messagesSet) as? [TransactionMessage] {
                    for m in groupMessages {
                        if !m.isDeleted {
                            MediaLoader.clearMessageMediaCache(message: m)
                            managedContext.delete(m)
                        }
                    }
                }
                managedContext.delete(chat)
            } catch {
                print("Error deleting chat objects: \(error)")
            }
        }
        saveContext()
    }
    
    func getObjectWith<T>(objectId: NSManagedObjectID) -> T? {
        let managedContext = persistentContainer.viewContext
        return managedContext.object(with:objectId) as? T
    }
    
    func getAllOfType<T>(
        entityName: String,
        sortDescriptors: [NSSortDescriptor]? = nil,
        context: NSManagedObjectContext? = nil
    ) -> [T] {
        let managedContext = context ?? persistentContainer.viewContext
        var objects:[T] = [T]()
        
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName:"\(entityName)")
        fetchRequest.sortDescriptors = sortDescriptors ?? [NSSortDescriptor(key: "id", ascending: false)]
        
        managedContext.performAndWait {
            do {
                try objects = managedContext.fetch(fetchRequest) as! [T]
            } catch let error as NSError {
                print("Error: " + error.localizedDescription)
            }
        }
        
        return objects
    }
    
    func getObjectOfTypeWith<T>(id: Int, entityName: String) -> T? {
        let managedContext = persistentContainer.viewContext
        var objects:[T] = [T]()
        
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName:"\(entityName)")
        let predicate = NSPredicate(format: "id == %d", id)
        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "id", ascending: false)]
        fetchRequest.fetchLimit = 1
        
        managedContext.performAndWait {
            do {
                try objects = managedContext.fetch(fetchRequest) as! [T]
            } catch let error as NSError {
                print("Error: " + error.localizedDescription)
            }
        }
        
        if objects.count > 0 {
            return objects[0]
        }
        return nil
    }
    
    func getObjectsOfTypeWith<T>(
        predicate: NSPredicate?,
        sortDescriptors: [NSSortDescriptor],
        entityName: String,
        fetchLimit: Int? = nil,
        managedContext: NSManagedObjectContext? = nil
    ) -> [T] {
        let managedContext = managedContext ?? persistentContainer.viewContext
        var objects:[T] = [T]()
        
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName:"\(entityName)")
        
        if let predicate = predicate {
            fetchRequest.predicate = predicate
        }
        
        fetchRequest.sortDescriptors = sortDescriptors
        
        if let fetchLimit = fetchLimit {
            fetchRequest.fetchLimit = fetchLimit
        }
        
        managedContext.performAndWait {
            do {
                try objects = managedContext.fetch(fetchRequest) as! [T]
            } catch let error as NSError {
                print("Error: " + error.localizedDescription)
            }
        }
        
        return objects
    }
    
    func getObjectsCountOfTypeWith(
        predicate: NSPredicate? = nil,
        entityName: String,
        context: NSManagedObjectContext? = nil
    ) -> Int {
        let managedContext = context ?? persistentContainer.viewContext
        var count:Int = 0
        
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName:"\(entityName)")
        if let predicate = predicate {
            fetchRequest.predicate = predicate
        }
        
        managedContext.performAndWait {
            do {
                try count = managedContext.count(for: fetchRequest)
            } catch let error as NSError {
                print("Error: " + error.localizedDescription)
            }
        }
        
        return count
    }
    
    func getObjectOfTypeWith<T>(
        predicate: NSPredicate,
        sortDescriptors: [NSSortDescriptor],
        entityName: String,
        managedContext: NSManagedObjectContext? = nil
    ) -> T? {
        let managedContext = managedContext ?? persistentContainer.viewContext
        var objects:[T] = [T]()
        
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName:"\(entityName)")
        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = sortDescriptors
        fetchRequest.fetchLimit = 1
        
        managedContext.performAndWait {
            do {
                try objects = managedContext.fetch(fetchRequest) as! [T]
            } catch let error as NSError {
                print("Error: " + error.localizedDescription)
            }
        }
        
        if objects.count > 0 {
            return objects[0]
        }
        return nil
    }
    
    func deleteObject(object: NSManagedObject) {
        let managedContext = persistentContainer.viewContext
        managedContext.performAndWait {
            // Check if object is valid and not already deleted
            guard !object.isDeleted else {
                return
            }

            // If object belongs to a different context, get it in this context
            if object.managedObjectContext != managedContext {
                if let objectInContext = try? managedContext.existingObject(with: object.objectID) {
                    managedContext.delete(objectInContext)
                }
            } else {
                managedContext.delete(object)
            }
        }
        saveContext()
    }

    func deleteObject(object: NSManagedObject, context: NSManagedObjectContext? = nil) {
        let managedContext = context ?? persistentContainer.viewContext
        managedContext.performAndWait {
            // Check if object is valid and not already deleted
            guard !object.isDeleted else {
                return
            }

            // If object belongs to a different context, get it in this context
            if object.managedObjectContext != managedContext {
                if let objectInContext = try? managedContext.existingObject(with: object.objectID) {
                    managedContext.delete(objectInContext)
                }
            } else {
                managedContext.delete(object)
            }
        }
    }
}

extension NSManagedObjectContext {
    func saveContext() {
        if self.hasChanges {
            do {
                try self.save()
            } catch {
                let nserror = error as NSError
                print("Unresolved error \(nserror)")
            }
        }
    }
    
    /// Fire-and-forget version - schedules the block but returns immediately
    func performSafely(_ block: @escaping () throws -> Void) {
        self.perform {
            do {
                try block()
            } catch let error as NSError {
                Self.logCoreDataError(error)
            }
        }
    }

    /// Async version - waits for the block to complete before returning
    /// Use this when you need to ensure the operation completes before continuing
    func performSafely(_ block: @escaping () throws -> Void) async {
        await self.perform {
            do {
                try block()
            } catch let error as NSError {
                Self.logCoreDataError(error)
            }
        }
    }

    private static func logCoreDataError(_ error: NSError) {
        print("❌ CoreData Error:")
        print("   Domain: \(error.domain)")
        print("   Code: \(error.code)")
        print("   Description: \(error.localizedDescription)")
        print("   UserInfo: \(error.userInfo)")

        // Handle specific errors
        if error.domain == NSCocoaErrorDomain {
            switch error.code {
            case NSValidationMissingMandatoryPropertyError:
                print("⚠️ Missing required property")
            case NSValidationRelationshipLacksMinimumCountError:
                print("⚠️ Relationship count error")
            case NSManagedObjectContextLockingError:
                print("⚠️ Threading violation!")
            default:
                print("⚠️ Other CoreData error")
            }
        }
    }
}
