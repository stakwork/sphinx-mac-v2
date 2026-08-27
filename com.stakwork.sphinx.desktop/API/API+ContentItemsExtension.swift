//
//  API+ContentItemsExtension.swift
//  sphinx
//
//  Created by Tomas Timinskas on 12/11/2025.
//  Copyright © 2025 Tomas Timinskas. All rights reserved.
//

extension API {
    ///Submits a piece of content to the personal graph.
    ///
    ///Replaces the removed POST /add_node. The v2 contract differs in every part:
    ///  - flat body ({content_type, source_link}) instead of nested node_type/node_data
    ///  - response is {status, nodes[], status_messages[]} instead of {success, data{}}
    ///  - rejections come back as {errorCode, message}
    ///
    ///NOTE ON AUTH: the v2/content route requires an identity — a Sphinx signature, a
    ///Stakwork admin token, or a valid L402 macaroon — and returns 401 without one.
    ///`free=true` only skips boltwall's *payment* determination (and needs TESTING_FREE=true
    ///set on the boltwall container); it does not satisfy the route's identity check,
    ///so the signed sig/msg pair below is what actually authenticates this client.
    func checkItemNodeExists(url: String, contentType: String) async throws -> CheckNodeResponse {
        guard let baseUrl = UserData.sharedInstance.getPersonalGraphBoltwallUrl() else {
            throw NodeError.missingUrl
        }

        guard let signatureQuery = API.graphSignatureQuery() else {
            throw NodeError.missingToken
        }

        let apiUrl = "\(baseUrl)/v2/content?free=true&\(signatureQuery)"

        var params = [String: AnyObject]()
        params["content_type"] = contentType as AnyObject
        params["source_link"] = url.fixedYoutubeUrl as AnyObject

        ///Required by /v2/content for every non-radar content_type — omitting it is a
        ///400 MISSING_WEBHOOK_URL. It is where Stakwork posts back when the run finishes;
        ///this client doesn't receive it (it polls via checkItemNodeStatus), so it points
        ///at the swarm's own boltwall, matching the RADAR_*_WEBHOOK values the swarm sets.
        ///TODO: confirm the intended callback path with the backend team.
        params["webhook_url"] = "\(baseUrl)/v2/content" as AnyObject

        guard let request = createRequest(
            apiUrl,
            params: params as NSDictionary,
            method: "POST"
        ) else {
            throw NodeError.invalidRequest
        }

        let response = try await performSphinxRequest(request, label: "addContent(v2/content)")

        guard let dictionary = response as? NSDictionary else {
            API.graphLog("   ✗ v2/content: expected a dictionary, got \(type(of: response)): \(response)")
            throw NodeError.invalidResponse
        }

        ///Structured rejection: {"errorCode": "...", "message": "..."}
        if let errorCode = dictionary["errorCode"] as? String {
            let message = dictionary["message"] as? String ?? errorCode

            ///"Already in the graph" is not a failure — under the old /add_node it came
            ///back as a plain success:false + node_key result. v2 reports it as a
            ///"Warning" that jarvis then flattens into {errorCode, message}, dropping
            ///the data.ref_id it carried, so only the node_key survives. Surface it as
            ///its own case so the caller can stop instead of retrying a duplicate.
            let alreadyExists = "Node already exists in the graph"
            if errorCode == alreadyExists || message.contains(alreadyExists) {
                let nodeKey = dictionary["node_key"] as? String
                    ?? message.components(separatedBy: "node_key: ").last
                API.graphLog("   • v2/content: already in the graph (node_key: \(nodeKey ?? "unknown"))")
                throw NodeError.alreadyExists(nodeKey: nodeKey)
            }

            API.graphLog("   ✗ v2/content rejected: \(errorCode) — \(message)")
            throw NodeError.rejected(code: errorCode, message: message)
        }

        guard let status = dictionary["status"] as? String, status == "Success" else {
            API.graphLog("   ✗ v2/content: expected status \"Success\", got \(dictionary)")
            throw NodeError.invalidResponse
        }

        ///nodes[0] carries the same payload the old response nested under "data".
        guard let nodes = dictionary["nodes"] as? [NSDictionary],
              let node = nodes.first,
              let refId = node["ref_id"] as? String else {
            let messages = dictionary["status_messages"] ?? "none"
            API.graphLog("   ✗ v2/content: no node with a ref_id in \(dictionary["nodes"] ?? "nil"), status_messages: \(messages)")
            throw NodeError.missingData
        }

        return CheckNodeResponse(
            success: true,
            refId: refId,
            nodeKey: node["node_key"] as? String,
            projectId: node["project_id"] as? Int
        )
    }

    ///Set to false to silence the personal-graph request/response logging below.
    nonisolated(unsafe) static var logContentItemRequests = true

    static func graphLog(_ message: String) {
        guard API.logContentItemRequests else { return }
        print("[PersonalGraph] \(message)")
    }

    ///Truncates a raw body so a huge HTML error page doesn't flood the console.
    private func previewBody(_ data: Data?) -> String {
        guard let data = data, !data.isEmpty else { return "<empty body>" }

        guard let text = String(data: data, encoding: .utf8) else {
            return "<\(data.count) bytes of non-UTF8 data>"
        }

        let limit = 2000
        return text.count > limit ? String(text.prefix(limit)) + "… (\(text.count) chars total)" : text
    }

    // Helper to convert sphinxRequest to async
    private func performSphinxRequest(_ request: URLRequest, label: String) async throws -> Any {
        struct AnyBox: @unchecked Sendable { let value: Any }

        API.graphLog("→ \(label): \(request.httpMethod ?? "?") \(request.url?.absoluteString ?? "?")")

        if let body = request.httpBody, let bodyText = String(data: body, encoding: .utf8) {
            API.graphLog("   request body: \(bodyText)")
        }

        let box = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AnyBox, Error>) in
            sphinxRequest(request) { response in
                let status = response.response?.statusCode
                API.graphLog("← \(label): HTTP \(status.map(String.init) ?? "no status")")
                API.graphLog("   raw body: \(self.previewBody(response.data))")

                switch response.result {
                case .success(let data):
                    continuation.resume(returning: AnyBox(value: data))
                case .failure(let error):
                    API.graphLog("   ✗ transport/decoding failure: \(error)")
                    if let underlying = error.underlyingError {
                        API.graphLog("   ✗ underlying: \(underlying)")
                    }
                    continuation.resume(throwing: error)
                }
            }
        }
        return box.value
    }

    // Custom errors
    enum NodeError: Error, LocalizedError {
        case missingUrl
        case missingToken
        case invalidRequest
        case invalidResponse
        case missingData
        ///The endpoint answered with a structured {errorCode, message} rejection.
        case rejected(code: String, message: String)
        ///The content is already in the graph. Terminal, and not a failure.
        case alreadyExists(nodeKey: String?)

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
            case .rejected(let code, let message):
                return "\(code): \(message)"
            case .alreadyExists:
                return "Already added to the graph"
            }
        }
    }

    ///Builds the `sig`/`msg` query pair boltwall uses to identify the caller.
    ///
    ///Boltwall reads both from the query string (`const { msg, sig } = req.query`),
    ///base64-decodes `msg`, and recovers the pubkey from a Lightning signed message.
    ///It only requires that both are non-empty and that the signature verifies — there
    ///is no replay window — so any freshly signed value works as proof of key ownership.
    ///Returns nil when there's no seed (logged out), leaving the caller to fail loudly.
    static func graphSignatureQuery() -> String? {
        let som = SphinxOnionManager.sharedInstance

        guard let seed = som.getAccountSeed() else {
            API.graphLog("   ✗ cannot sign request: no account seed available")
            return nil
        }

        ///Base64 of the signed value, since boltwall decodes msg as base64.
        let message = Data(som.getTimeWithEntropy().utf8).base64EncodedString()

        do {
            let sig = try Sphinx.signBase64(
                seed: seed,
                idx: 0,
                time: som.getTimeWithEntropy(),
                network: som.network,
                msg: message
            )
            return "sig=\(sig.urlSafe)&msg=\(message.urlSafe)"
        } catch {
            API.graphLog("   ✗ cannot sign request: \(error)")
            return nil
        }
    }

    ///Maps a ContentItem.ContentType to the `content_type` that POST /v2/content expects.
    ///The backend turns content_type into a node type via CONTENT_TYPE_TO_NODE_TYPE;
    ///the "Multimedia" node_type the old /add_node call hardcoded no longer exists.
    static func graphContentType(for itemType: String?) -> String {
        switch itemType {
        case ContentItem.ContentType.video.rawValue:
            return "audio_video"
        case ContentItem.ContentType.externalURL.rawValue:
            return "webpage"
        default:
            // image / fileURL / text all arrive as an uploaded file URL
            return "document"
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
        let response = try await performSphinxRequest(request, label: "checkItemNodeStatus(refId: \(refId))")

        guard let dictionary = response as? NSDictionary,
              let properties = dictionary["properties"] as? NSDictionary else {
            API.graphLog("   ✗ checkItemNodeStatus: expected a dictionary with a \"properties\" key, got \(type(of: response)): \(response)")
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
        
        let data = try await performSphinxRequest(request, label: "checkProjectStatus(projectId: \(projectId))")

        guard let dictionary = data as? NSDictionary,
              let responseData = dictionary["data"] as? NSDictionary,
              let success = dictionary["success"] as? Bool, success else
        {
            API.graphLog("   ✗ checkProjectStatus: expected success=true with a \"data\" key, got \(type(of: data)): \(data)")
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
    ) async throws -> CheckNodeResponse {
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
        params["workflow_id"] = 1 as AnyObject
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
        let data = try await performSphinxRequest(request, label: "createGraphMindsetRunForItem(refId: \(refId))")

        // Parse response
        guard let dictionary = data as? NSDictionary,
              let responseData = dictionary["data"] as? NSDictionary,
              let success = dictionary["success"] as? Bool,
              success else {
            API.graphLog("   ✗ createGraphMindsetRunForItem: expected success=true with a \"data\" key, got \(type(of: data)): \(data)")
            throw NodeError.invalidResponse
        }
        
        let projectId = responseData["project_id"] as? Int
        
        return CheckNodeResponse(
            success: true,
            refId: refId,
            projectId: projectId
        )
    }
}
