//
//  C.swift
//  sphinx
//
//  Created by Tomas Timinskas on 30/10/2025.
//  Copyright © 2025 Tomas Timinskas. All rights reserved.
//
import Foundation
import CoreData


extension ContentItem {

    public enum Predicates {
        public static func all() -> NSPredicate? {
            return nil
        }
    }
}


extension ContentItem {

    public enum FetchRequests {

        public static func baseFetchRequest<ContentItem>() -> NSFetchRequest<ContentItem> {
            NSFetchRequest<ContentItem>(entityName: "ContentItem")
        }


        public static func `default`() -> NSFetchRequest<ContentItem> {
            let request: NSFetchRequest<ContentItem> = baseFetchRequest()

            request.predicate = nil

            return request
        }
        
        public static func all() -> NSFetchRequest<ContentItem> {
            let request: NSFetchRequest<ContentItem> = baseFetchRequest()

            request.predicate = Predicates.all()
            request.sortDescriptors = [NSSortDescriptor(key: "order", ascending: false)]

            return request
        }
     
        
//        public static func matching(identifier: String) -> NSFetchRequest<LSat> {
//            let request: NSFetchRequest<LSat> = baseFetchRequest()
//            
//            request.predicate = Predicates.matching(identifier: identifier)
//            request.sortDescriptors = []
//
//            return request
//        }
    }
}
