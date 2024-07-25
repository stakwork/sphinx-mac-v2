//
//  LSat+FetchUtils.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 19/07/2024.
//  Copyright © 2024 Tomas Timinskas. All rights reserved.
//

import Foundation
import CoreData


extension LSat {

    public enum Predicates {
        
        public static func matching(identifier: String) -> NSPredicate {
            let keyword = "=="
            let formatSpecifier = "%@"

            return NSPredicate(
                format: "%K \(keyword) \(formatSpecifier)",
                "identifier",
                identifier
            )
        }
        
        public static func all() -> NSPredicate? {
            return nil
        }
    }
}


extension LSat {

    public enum FetchRequests {

        public static func baseFetchRequest<LSat>() -> NSFetchRequest<LSat> {
            NSFetchRequest<LSat>(entityName: "LSat")
        }


        public static func `default`() -> NSFetchRequest<LSat> {
            let request: NSFetchRequest<LSat> = baseFetchRequest()

            request.predicate = nil

            return request
        }
        
        public static func all() -> NSFetchRequest<LSat> {
            let request: NSFetchRequest<LSat> = baseFetchRequest()

            request.predicate = Predicates.all()

            return request
        }
     
        
        public static func matching(identifier: String) -> NSFetchRequest<LSat> {
            let request: NSFetchRequest<LSat> = baseFetchRequest()
            
            request.predicate = Predicates.matching(identifier: identifier)
            request.sortDescriptors = []

            return request
        }
    }
}
