//
//  API+ContentItemsExtension.swift
//  sphinx
//
//  Created by Tomas Timinskas on 12/11/2025.
//  Copyright © 2025 Tomas Timinskas. All rights reserved.
//

extension API {
    func checkItemNodeExists(url: String) async throws -> CheckNodeResponse {
        guard let baseUrl = UserData.sharedInstance.getPersonalGraphBoltwallUrl() else {
            throw NodeError.missingUrl
        }
        let apiUrl = "\(baseUrl)/add_node?sig=&msg="
        
        var nodeDataParams = [String: AnyObject]()
        nodeDataParams["source_link"] = url.fixedYoutubeUrl as AnyObject
        
        var params = [String: AnyObject]()
        params["node_type"] = "Multimedia" as AnyObject
        params["node_data"] = nodeDataParams as AnyObject
        
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
        case missingUrl
        case missingToken
        case invalidRequest
        case invalidResponse
        case missingData
        
        var errorDescription: String? {
            switch self {
            case .missingUrl:
                return "Missing Graph URL"
            case .missingToken:
                return "Missing Token"
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
        guard let baseUrl = UserData.sharedInstance.getPersonalGraphBoltwallUrl() else {
            throw NodeError.missingUrl
        }
        let url = "\(baseUrl)/node/\(refId)"
        
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
    
    func checkProjectStatus(projectId: String) async throws -> ProjectStatusResponse {
        guard let baseUrl = UserData.sharedInstance.getPersonalGraphStakworklUrl() else {
            throw NodeError.missingUrl
        }
        
        guard let token = UserData.sharedInstance.getPersonalGraphValue(
            with: KeychainManager.KeychainKeys.personalGraphToken
        ) else {
            throw NodeError.missingToken
        }
        
        let apiUrl = "\(baseUrl)/api/v1/projects/\(projectId)/status"

        guard let request = createRequest(
            apiUrl,
            params: nil,
            method: "GET",
            token: token
        ) else {
            throw NodeError.invalidRequest
        }
        
        let data = try await performSphinxRequest(request)
        
        guard let dictionary = data as? NSDictionary,
              let responseData = dictionary["data"] as? NSDictionary,
              let success = dictionary["success"] as? Bool, success else
        {
            throw NodeError.invalidResponse
        }
        
        let status = responseData["status"] as? String
        var errorMessage: String? = nil
        
        switch status {
        case "new":
            break
        case "in_progress":
            break
        case "halted":
            errorMessage = "Run halted"
            break
        case "completed":
            break
        case "error":
            errorMessage = "Run failed"
            break
        case "stopped":
            errorMessage = "Run stopped"
            break
        case "stopping":
            errorMessage = "Run stopped"
            break
        case "enqueued":
            break
        case "stuck":
            errorMessage = "Run stuck"
            break
        case "refunded":
            errorMessage = "Run refunded"
            break
        default:
            break
        }
        
        return ProjectStatusResponse(
            completed: status == "completed",
            processing: status == "in_progress" || status == "enqueued",
            failed: status == "error" || status == "halted" || status == "stopped" || status == "stopping" || status == "stuck" || status == "refunded",
            errorMessage: errorMessage
        )
    }
    func createGraphMindsetRunForItem(
        url: String,
        refId: String
    ) async throws -> CreateRunResponse {
        guard let baseUrl = UserData.sharedInstance.getPersonalGraphStakworklUrl() else {
            throw NodeError.missingUrl
        }
        
        guard let token = UserData.sharedInstance.getPersonalGraphValue(
            with: KeychainManager.KeychainKeys.personalGraphToken
        ) else {
            throw NodeError.missingToken
        }
        
        // Build API URL
        let apiUrl = "\(baseUrl)/api/v1/projects"
        
        // Build parameters
        var varsParams = [String: AnyObject]()
        varsParams["media_url"] = url as AnyObject
        varsParams["ref_id"] = refId as AnyObject
        
        var attributesParams = [String: AnyObject]()
        attributesParams["vars"] = varsParams as AnyObject
        
        var setVarsParams = [String: AnyObject]()
        setVarsParams["attributes"] = attributesParams as AnyObject
        
        var workflowParams = [String: AnyObject]()
        workflowParams["set_var"] = setVarsParams as AnyObject
        
        var params = [String: AnyObject]()
        params["name"] = url as AnyObject
        params["workflow_id"] = 53 as AnyObject
        params["workflow_params"] = workflowParams as AnyObject
        
        // Create request
        guard let request = createRequest(
            apiUrl,
            params: params as NSDictionary,
            method: "POST",
            token: token
        ) else {
            throw NodeError.invalidRequest
        }
        
        // Perform request
        let data = try await performSphinxRequest(request)
        
        // Parse response
        guard let dictionary = data as? NSDictionary,
              let responseData = dictionary["data"] as? NSDictionary,
              let success = dictionary["success"] as? Bool,
              success else {
            throw NodeError.invalidResponse
        }
        
        let projectId = responseData["project_id"] as? Int
        
        return CreateRunResponse(
            success: true,
            projectId: projectId,
            refId: refId
        )
    }
}
