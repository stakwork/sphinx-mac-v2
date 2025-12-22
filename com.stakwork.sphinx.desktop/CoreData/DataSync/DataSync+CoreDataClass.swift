//
//  DataSync+CoreDataClass.swift
//  sphinx
//
//  Created by Tomas Timinskas on 18/12/2025.
//  Copyright © 2025 Tomas Timinskas. All rights reserved.
//
import Foundation
import CoreData
import SwiftyJSON

@objc(DataSync)
public class DataSync: NSManagedObject {
    
    public static func getAllDataSync(
        context: NSManagedObjectContext? = nil
    ) -> [DataSync] {
        let managedContext = context ?? CoreDataManager.sharedManager.persistentContainer.viewContext
        let fetchRequest = NSFetchRequest<DataSync>(entityName: "DataSync")
        
        do {
            let dataSyncItems = try managedContext.fetch(fetchRequest)
            return dataSyncItems
        } catch let error as NSError {
            print("Error fetching servers: \(error.localizedDescription)")
            return []
        }
    }
    
    static func getContentItemWith(
        key: String,
        identifier: String,
        context: NSManagedObjectContext? = nil
    ) -> DataSync? {
        let predicate = NSPredicate(format: "key == %@ AND identifier == %@", key, identifier)
        
        let dataSync: DataSync? = CoreDataManager.sharedManager.getObjectOfTypeWith(
            predicate: predicate,
            sortDescriptors: [],
            entityName: "DataSync",
            managedContext: context
        )
        
        return dataSync
    }
    
    static func saveObjectWith(
        key: String,
        identifier: String,
        value: String,
        context: NSManagedObjectContext? = nil
    ) -> DataSync? {
        let managedContext = context ?? CoreDataManager.sharedManager.persistentContainer.viewContext
        
        let date = Date()
        
        let dataSync = DataSync(context: managedContext) as DataSync
        dataSync.key = key
        dataSync.identifier = identifier
        dataSync.date = date
        dataSync.value = value

        managedContext.saveContext()
        
        return dataSync
    }
}
