//
//  API+ContentItemsExtension.swift
//  sphinx
//
//  Created by Tomas Timinskas on 12/11/2025.
//  Copyright © 2025 Tomas Timinskas. All rights reserved.
//

extension API {
    func checkItemNodeExists(url: String) async throws -> CheckNodeResponse {
        let apiUrl = "\(API.kGraphMindsetUrl)/add_node?sig=&msg="
        
        var params = [String: AnyObject]()
        params["url"] = url as AnyObject
        
        guard let request = createRequest(
            apiUrl,
            params: params as NSDictionary,
            method: "POST"
        ) else {
            throw NodeError.invalidRequest
        }
        
        let response = try await performSphinxRequest(request)
        
        guard let dictionary = response as? NSDictionary,
              let dataDic = dictionary["data"] as? NSDictionary else {
            throw NodeError.invalidResponse
        }
        
        if let success = dictionary["success"] as? Bool, success {
            guard let projectId = dataDic["project_id"] as? Int,
                  let refId = dataDic["ref_id"] as? String else {
                throw NodeError.missingData
            }
            
            return CheckNodeResponse(
                success: true,
                refId: refId,
                projectId: projectId
            )
        } else {
            guard let nodeKey = dataDic["node_key"] as? String,
                  let refId = dataDic["ref_id"] as? String else {
                throw NodeError.missingData
            }
            
            return CheckNodeResponse(
                success: false,
                refId: refId,
                nodeKey: nodeKey
            )
        }
    }

    // Helper to convert sphinxRequest to async
    private func performSphinxRequest(_ request: URLRequest) async throws -> Any {
        return try await withCheckedThrowingContinuation { continuation in
            sphinxRequest(request) { response in
                switch response.result {
                case .success(let data):
                    continuation.resume(returning: data)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // Custom errors
    enum NodeError: Error, LocalizedError {
        case invalidRequest
        case invalidResponse
        case missingData
        
        var errorDescription: String? {
            switch self {
            case .invalidRequest:
                return "Error creating request"
            case .invalidResponse:
                return "Error getting response data"
            case .missingData:
                return "Missing required data in response"
            }
        }
    }
    
    func checkItemNodeStatus(refId: String) async throws -> NodeStatusResponse {
        let url = "\(API.kGraphMindsetUrl)/node/\(refId)"
        
        guard let request = createRequest(
            url,
            params: nil,
            method: "GET"
        ) else {
            throw NodeError.invalidRequest
        }
        
        // Convert sphinxRequest to async
        let response = try await performSphinxRequest(request)
        
        guard let dictionary = response as? NSDictionary,
              let properties = dictionary["properties"] as? NSDictionary else {
            throw NodeError.invalidResponse
        }
        
        // Parse status
        let status = properties["status"] as? String ?? ""
        let projectIdString = properties["projectId"] as? String
        let projectId = projectIdString.flatMap { Int($0) }
        
        switch status.lowercased() {
        case "completed", "success":
            return NodeStatusResponse(
                completed: true,
                processing: false,
                projectId: projectId
            )
            
        case "processing":
            return NodeStatusResponse(
                completed: false,
                processing: true,
                projectId: projectId
            )
            
        default:
            return NodeStatusResponse(
                completed: false,
                processing: false,
                projectId: projectId
            )
        }
    }
}
