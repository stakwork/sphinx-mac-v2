//
//  LSat+CoreDataClass.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 19/07/2024.
//  Copyright © 2024 Tomas Timinskas. All rights reserved.
//

import Foundation
import CoreData
import SwiftyJSON

@objc(LSat)
public class LSat: NSManagedObject {
    
    public static func getAllLSat(context: NSManagedObjectContext) -> [LSat] {
        let fetchRequest = NSFetchRequest<LSat>(entityName: "LSat")
        
        do {
            let LSats = try context.fetch(fetchRequest)
            return LSats
        } catch let error as NSError {
            print("Error fetching servers: \(error.localizedDescription)")
            return []
        }
    }
    
}
