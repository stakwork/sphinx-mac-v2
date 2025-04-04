//
//  Chapter+Computed.swift
//  sphinx
//
//  Created by Tomas Timinskas on 03/04/2025.
//  Copyright © 2025 Tomas Timinskas. All rights reserved.
//
import Foundation
import CoreData

public class Chapter {
    
    public var dateAddedToGraph: Date
    public var nodeType: String
    public var isAd: Bool
    public var name: String
    public var sourceLink: String
    public var timestamp: String
    public var referenceId: String
    
    
    init(
        dateAddedToGraph: Date,
        nodeType: String,
        isAd: Bool,
        name: String,
        sourceLink: String,
        timestamp: String,
        referenceId: String
    ) {
        self.dateAddedToGraph = dateAddedToGraph
        self.nodeType = nodeType
        self.isAd = isAd
        self.name = name
        self.sourceLink = sourceLink
        self.timestamp = timestamp
        self.referenceId = referenceId
    }
}

struct Properties: Codable {
    var date_added_to_graph: String?
    var weight: Int?
    var date: TimeInterval?
    var episode_title: String?
    var image_url: String?
    var media_url: String?
    var source_link: String?
    var status: String?
    var is_ad: String?
    var name: String?
    var timestamp: String?
}

struct Node: Codable {
    var date_added_to_graph: TimeInterval
    var node_type: String
    var properties: Properties
    var ref_id: String
}

struct Edge: Codable {
    var edge_type: String
    var properties: Properties
    var ref_id: String
    var source: String
    var target: String
}

struct GraphData: Codable {
    var nodes: [Node]
    var edges: [Edge]
}
