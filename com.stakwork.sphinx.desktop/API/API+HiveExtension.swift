//
//  API+HiveExtension.swift
//  Sphinx
//
//  Created on 2025-02-19.
//  Copyright © 2025 Sphinx. All rights reserved.
//

import Foundation
import Alamofire
import SwiftyJSON

typealias HiveAuthTokenCallback = ((String?) -> ())
typealias HiveWorkspacesCallback = (([Workspace]) -> ())
typealias HiveTasksCallback = (([WorkspaceTask]) -> ())
typealias HiveWorkspaceImageCallback = ((String?) -> ())
typealias HiveCallLinkCallback = ((String) -> ())

extension API {

    static let kHiveBaseUrl = "https://hive.sphinx.chat/api"

    func authenticateWithHive(
        callback: @escaping HiveAuthTokenCallback,
        errorCallback: @escaping EmptyCallback
    ) {
        print("[Hive] authenticateWithHive: attempting...")
        guard let signedToken = SphinxOnionManager.sharedInstance.getSignedToken(),
              let pubkey = UserData.sharedInstance.getUserPubKey() else {
            print("[Hive] authenticateWithHive: failed — could not get signed token or pubkey")
            errorCallback()
            return
        }

        let timestamp = Int(Date().timeIntervalSince1970)

        let params: [String: AnyObject] = [
            "token": signedToken as AnyObject,
            "pubkey": pubkey as AnyObject,
            "timestamp": timestamp as AnyObject
        ]

        guard let request = createRequest(
            "\(API.kHiveBaseUrl)/auth/sphinx/token",
            params: params as NSDictionary,
            method: "POST"
        ) else {
            errorCallback()
            return
        }

        AF.request(request).validate().responseData { response in
            switch response.result {
            case .success(let data):
                let json = JSON(data)
                if let token = json["token"].string {
                    print("[Hive] authenticateWithHive: success — token obtained")
                    callback(token)
                } else {
                    print("[Hive] authenticateWithHive: failed — status: \(response.response?.statusCode ?? -1)")
                    errorCallback()
                }
            case .failure(let error):
                print("[Hive] authenticateWithHive: failed — status: \(response.response?.statusCode ?? -1)")
                errorCallback()
            }
        }
    }

    func fetchWorkspaces(
        authToken: String,
        callback: @escaping HiveWorkspacesCallback,
        errorCallback: @escaping EmptyCallback
    ) {
        guard let request = createRequest(
            "\(API.kHiveBaseUrl)/workspaces",
            params: nil,
            method: "GET",
            token: authToken
        ) else {
            errorCallback()
            return
        }

        AF.request(request).responseData { response in
            if let statusCode = response.response?.statusCode, statusCode == 401 {
                errorCallback()
                return
            }
            
            switch response.result {
            case .success(let data):
                let json = JSON(data)
                var workspaces: [Workspace] = []

                if let workspacesArray = json["workspaces"].array {
                    for workspaceJson in workspacesArray {
                        if let workspace = Workspace(json: workspaceJson) {
                            workspaces.append(workspace)
                        }
                    }
                }

                print("[Hive] fetchWorkspaces: \(workspaces.count) workspace(s) returned")
                callback(workspaces)
            case .failure(let error):
                print("[Hive] fetchWorkspaces failed — status: \(response.response?.statusCode ?? -1), error: \(error.localizedDescription)")
                errorCallback()
            }
        }
    }

    func resolveHiveToken(
        callback: @escaping (String) -> Void,
        errorCallback: @escaping EmptyCallback
    ) {
        if let storedToken: String = UserDefaults.Keys.hiveToken.get() {
            callback(storedToken)
        } else {
            authenticateWithHive(
                callback: { token in
                    guard let token = token else { errorCallback(); return }
                    UserDefaults.Keys.hiveToken.set(token)
                    callback(token)
                },
                errorCallback: errorCallback
            )
        }
    }

    func fetchWorkspacesWithAuth(
        callback: @escaping HiveWorkspacesCallback,
        errorCallback: @escaping EmptyCallback
    ) {
        // Check if we have a stored token
        if let storedToken: String = UserDefaults.Keys.hiveToken.get() {
            // Try using the stored token first
            fetchWorkspaces(
                authToken: storedToken,
                callback: callback,
                errorCallback: { [weak self] in
                    // Token might be expired, get a new one and retry
                    self?.authenticateAndFetchWorkspaces(
                        callback: callback,
                        errorCallback: errorCallback
                    )
                }
            )
        } else {
            // No stored token, authenticate first
            authenticateAndFetchWorkspaces(
                callback: callback,
                errorCallback: errorCallback
            )
        }
    }

    private func authenticateAndFetchWorkspaces(
        callback: @escaping HiveWorkspacesCallback,
        errorCallback: @escaping EmptyCallback
    ) {
        authenticateWithHive(
            callback: { [weak self] token in
                guard let token = token else {
                    errorCallback()
                    return
                }

                // Store the new token
                UserDefaults.Keys.hiveToken.set(token)

                self?.fetchWorkspaces(
                    authToken: token,
                    callback: callback,
                    errorCallback: errorCallback
                )
            },
            errorCallback: errorCallback
        )
    }

    func fetchTasks(
        workspaceId: String,
        includeArchived: Bool,
        authToken: String,
        callback: @escaping HiveTasksCallback,
        errorCallback: @escaping EmptyCallback
    ) {
        let urlString = "\(API.kHiveBaseUrl)/tasks?workspaceId=\(workspaceId)&limit=100&includeArchived=\(includeArchived)"
        guard let request = createRequest(urlString, params: nil, method: "GET", token: authToken) else {
            errorCallback()
            return
        }
        
        AF.request(request).responseData { response in
            if let statusCode = response.response?.statusCode, statusCode == 401 {
                print("[HiveAPI] Tasks fetch unauthorized (401) - token may be expired")
                errorCallback()
                return
            }
            
            switch response.result {
            case .success(let data):
                let json = JSON(data)

                // Check if the response contains an error
                if let error = json["error"].string {
                    print("[HiveAPI] Tasks fetch error: \(error)")
                    errorCallback()
                    return
                }

                let tasks: [WorkspaceTask] = (json["data"].array ?? []).compactMap { WorkspaceTask(json: $0) }
                callback(tasks)
            case .failure:
                errorCallback()
            }
        }
    }

    func fetchTasksWithAuth(
        workspaceId: String,
        includeArchived: Bool,
        callback: @escaping HiveTasksCallback,
        errorCallback: @escaping EmptyCallback
    ) {
        if let storedToken: String = UserDefaults.Keys.hiveToken.get() {
            fetchTasks(
                workspaceId: workspaceId,
                includeArchived: includeArchived,
                authToken: storedToken,
                callback: callback,
                errorCallback: { [weak self] in
                    self?.authenticateAndFetchTasks(
                        workspaceId: workspaceId,
                        includeArchived: includeArchived,
                        callback: callback,
                        errorCallback: errorCallback
                    )
                }
            )
        } else {
            authenticateAndFetchTasks(
                workspaceId: workspaceId,
                includeArchived: includeArchived,
                callback: callback,
                errorCallback: errorCallback
            )
        }
    }

    private func authenticateAndFetchTasks(
        workspaceId: String,
        includeArchived: Bool,
        callback: @escaping HiveTasksCallback,
        errorCallback: @escaping EmptyCallback
    ) {
        authenticateWithHive(
            callback: { [weak self] token in
                guard let token = token else { errorCallback(); return }
                UserDefaults.Keys.hiveToken.set(token)
                self?.fetchTasks(
                    workspaceId: workspaceId,
                    includeArchived: includeArchived,
                    authToken: token,
                    callback: callback,
                    errorCallback: errorCallback
                )
            },
            errorCallback: errorCallback
        )
    }

    // MARK: - Tribe Call Link

    func generateTribeCallLink(
        swarmName: String,
        authToken: String,
        callback: @escaping HiveCallLinkCallback,
        errorCallback: @escaping EmptyCallback
    ) {
        guard let encodedSwarmName = swarmName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            errorCallback()
            return
        }
        let urlString = "\(API.kHiveBaseUrl)/workspaces/_/calls/generate-link?swarmName=\(encodedSwarmName)"
        guard let request = createRequest(urlString, params: nil, method: "POST", token: authToken) else {
            errorCallback()
            return
        }
        AF.request(request).responseData { response in
            if let statusCode = response.response?.statusCode, statusCode == 401 {
                errorCallback()
                return
            }
            switch response.result {
            case .success(let data):
                let json = JSON(data)
                if let url = json["url"].string {
                    callback(url)
                } else {
                    errorCallback()
                }
            case .failure:
                errorCallback()
            }
        }
    }

    func generateTribeCallLinkWithAuth(
        swarmName: String,
        callback: @escaping HiveCallLinkCallback,
        errorCallback: @escaping EmptyCallback
    ) {
        if let storedToken: String = UserDefaults.Keys.hiveToken.get() {
            generateTribeCallLink(swarmName: swarmName, authToken: storedToken, callback: callback,
                errorCallback: { [weak self] in
                    self?.authenticateAndGenerateTribeCallLink(swarmName: swarmName, callback: callback, errorCallback: errorCallback)
                })
        } else {
            authenticateAndGenerateTribeCallLink(swarmName: swarmName, callback: callback, errorCallback: errorCallback)
        }
    }

    private func authenticateAndGenerateTribeCallLink(
        swarmName: String,
        callback: @escaping HiveCallLinkCallback,
        errorCallback: @escaping EmptyCallback
    ) {
        authenticateWithHive(callback: { [weak self] token in
            guard let token = token else { errorCallback(); return }
            UserDefaults.Keys.hiveToken.set(token)
            self?.generateTribeCallLink(swarmName: swarmName, authToken: token, callback: callback, errorCallback: errorCallback)
        }, errorCallback: errorCallback)
    }

    // MARK: - Workspace Image

    func fetchWorkspaceImage(
        slug: String,
        authToken: String,
        callback: @escaping HiveWorkspaceImageCallback,
        errorCallback: @escaping EmptyCallback
    ) {
        guard let encodedSlug = slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            errorCallback()
            return
        }
        let urlString = "\(API.kHiveBaseUrl)/workspaces/\(encodedSlug)/image"
        guard let request = createRequest(urlString, params: nil, method: "GET", token: authToken) else {
            errorCallback()
            return
        }
        AF.request(request).responseData { response in
            if let statusCode = response.response?.statusCode, statusCode == 401 {
                errorCallback()
                return
            }
            switch response.result {
            case .success(let data):
                let json = JSON(data)
                if let presignedUrl = json["presignedUrl"].string,
                   let expiresIn = json["expiresIn"].int {
                    let expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
                    WorkspaceImageCache.shared.setImage(url: presignedUrl, forSlug: slug, expiresAt: expiresAt)
                    callback(presignedUrl)
                } else {
                    callback(nil)
                }
            case .failure:
                errorCallback()
            }
        }
    }

    func fetchWorkspaceImageWithAuth(
        slug: String,
        callback: @escaping HiveWorkspaceImageCallback,
        errorCallback: @escaping EmptyCallback
    ) {
        if let cachedUrl = WorkspaceImageCache.shared.getImageUrl(forSlug: slug) {
            callback(cachedUrl)
            return
        }
        if let storedToken: String = UserDefaults.Keys.hiveToken.get() {
            fetchWorkspaceImage(slug: slug, authToken: storedToken, callback: callback,
                errorCallback: { [weak self] in
                    self?.authenticateAndFetchWorkspaceImage(slug: slug, callback: callback, errorCallback: errorCallback)
                })
        } else {
            authenticateAndFetchWorkspaceImage(slug: slug, callback: callback, errorCallback: errorCallback)
        }
    }

    private func authenticateAndFetchWorkspaceImage(
        slug: String,
        callback: @escaping HiveWorkspaceImageCallback,
        errorCallback: @escaping EmptyCallback
    ) {
        authenticateWithHive(callback: { [weak self] token in
            guard let token = token else { errorCallback(); return }
            UserDefaults.Keys.hiveToken.set(token)
            self?.fetchWorkspaceImage(slug: slug, authToken: token, callback: callback, errorCallback: errorCallback)
        }, errorCallback: errorCallback)
    }
}

    // MARK: - Workspace Detail

    func fetchWorkspaceDetail(
        slug: String,
        authToken: String,
        callback: @escaping (JSON) -> Void,
        errorCallback: @escaping EmptyCallback
    ) {
        guard let encodedSlug = slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let request = createRequest("\(API.kHiveBaseUrl)/workspaces/\(encodedSlug)", params: nil, method: "GET", token: authToken) else {
            errorCallback(); return
        }
        AF.request(request).responseData { response in
            if let sc = response.response?.statusCode, sc == 401 { errorCallback(); return }
            switch response.result {
            case .success(let data): callback(JSON(data))
            case .failure: errorCallback()
            }
        }
    }

    func fetchWorkspaceDetailWithAuth(
        slug: String,
        callback: @escaping (JSON) -> Void,
        errorCallback: @escaping EmptyCallback
    ) {
        if let token: String = UserDefaults.Keys.hiveToken.get() {
            fetchWorkspaceDetail(slug: slug, authToken: token, callback: callback,
                errorCallback: { [weak self] in self?.authenticateAndFetchWorkspaceDetail(slug: slug, callback: callback, errorCallback: errorCallback) })
        } else {
            authenticateAndFetchWorkspaceDetail(slug: slug, callback: callback, errorCallback: errorCallback)
        }
    }

    private func authenticateAndFetchWorkspaceDetail(
        slug: String,
        callback: @escaping (JSON) -> Void,
        errorCallback: @escaping EmptyCallback
    ) {
        authenticateWithHive(callback: { [weak self] token in
            guard let token = token else { errorCallback(); return }
            UserDefaults.Keys.hiveToken.set(token)
            self?.fetchWorkspaceDetail(slug: slug, authToken: token, callback: callback, errorCallback: errorCallback)
        }, errorCallback: errorCallback)
    }

    // MARK: - Workspace Members

    func fetchWorkspaceMembers(
        slug: String,
        authToken: String,
        callback: @escaping (JSON) -> Void,
        errorCallback: @escaping EmptyCallback
    ) {
        guard let encodedSlug = slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let request = createRequest("\(API.kHiveBaseUrl)/workspaces/\(encodedSlug)/members", params: nil, method: "GET", token: authToken) else {
            errorCallback(); return
        }
        AF.request(request).responseData { response in
            if let sc = response.response?.statusCode, sc == 401 { errorCallback(); return }
            switch response.result {
            case .success(let data): callback(JSON(data))
            case .failure: errorCallback()
        }
        }
    }

    func fetchWorkspaceMembersWithAuth(
        slug: String,
        callback: @escaping (JSON) -> Void,
        errorCallback: @escaping EmptyCallback
    ) {
        if let token: String = UserDefaults.Keys.hiveToken.get() {
            fetchWorkspaceMembers(slug: slug, authToken: token, callback: callback,
                errorCallback: { [weak self] in self?.authenticateAndFetchWorkspaceMembers(slug: slug, callback: callback, errorCallback: errorCallback) })
        } else {
            authenticateAndFetchWorkspaceMembers(slug: slug, callback: callback, errorCallback: errorCallback)
        }
    }

    private func authenticateAndFetchWorkspaceMembers(
        slug: String,
        callback: @escaping (JSON) -> Void,
        errorCallback: @escaping EmptyCallback
    ) {
        authenticateWithHive(callback: { [weak self] token in
            guard let token = token else { errorCallback(); return }
            UserDefaults.Keys.hiveToken.set(token)
            self?.fetchWorkspaceMembers(slug: slug, authToken: token, callback: callback, errorCallback: errorCallback)
        }, errorCallback: errorCallback)
    }

    // MARK: - Search Workspace

    func searchWorkspace(
        slug: String,
        query: String,
        authToken: String,
        callback: @escaping (JSON) -> Void,
        errorCallback: @escaping EmptyCallback
    ) {
        guard let encodedSlug = slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let request = createRequest("\(API.kHiveBaseUrl)/workspaces/\(encodedSlug)/search?query=\(encodedQuery)", params: nil, method: "GET", token: authToken) else {
            errorCallback(); return
        }
        AF.request(request).responseData { response in
            if let sc = response.response?.statusCode, sc == 401 { errorCallback(); return }
            switch response.result {
            case .success(let data): callback(JSON(data))
            case .failure: errorCallback()
            }
        }
    }

    func searchWorkspaceWithAuth(
        slug: String,
        query: String,
        callback: @escaping (JSON) -> Void,
        errorCallback: @escaping EmptyCallback
    ) {
        if let token: String = UserDefaults.Keys.hiveToken.get() {
            searchWorkspace(slug: slug, query: query, authToken: token, callback: callback,
                errorCallback: { [weak self] in self?.authenticateAndSearchWorkspace(slug: slug, query: query, callback: callback, errorCallback: errorCallback) })
        } else {
            authenticateAndSearchWorkspace(slug: slug, query: query, callback: callback, errorCallback: errorCallback)
        }
    }

    private func authenticateAndSearchWorkspace(
        slug: String,
        query: String,
        callback: @escaping (JSON) -> Void,
        errorCallback: @escaping EmptyCallback
    ) {
        authenticateWithHive(callback: { [weak self] token in
            guard let token = token else { errorCallback(); return }
            UserDefaults.Keys.hiveToken.set(token)
            self?.searchWorkspace(slug: slug, query: query, authToken: token, callback: callback, errorCallback: errorCallback)
        }, errorCallback: errorCallback)
    }

    // MARK: - Features

    func fetchFeatures(
        workspaceId: String,
        authToken: String,
        callback: @escaping (JSON) -> Void,
        errorCallback: @escaping EmptyCallback
    ) {
        guard let request = createRequest("\(API.kHiveBaseUrl)/features?workspaceId=\(workspaceId)", params: nil, method: "GET", token: authToken) else {
            errorCallback(); return
        }
        AF.request(request).responseData { response in
            if let sc = response.response?.statusCode, sc == 401 { errorCallback(); return }
            switch response.result {
            case .success(let data): callback(JSON(data))
            case .failure: errorCallback()
            }
        }
    }

    func fetchFeaturesWithAuth(
        workspaceId: String,
        callback: @escaping (JSON) -> Void,
        errorCallback: @escaping EmptyCallback
    ) {
        if let token: String = UserDefaults.Keys.hiveToken.get() {
            fetchFeatures(workspaceId: workspaceId, authToken: token, callback: callback,
                errorCallback: { [weak self] in self?.authenticateAndFetchFeatures(workspaceId: workspaceId, callback: callback, errorCallback: errorCallback) })
        } else {
            authenticateAndFetchFeatures(workspaceId: workspaceId, callback: callback, errorCallback: errorCallback)
        }
    }

    private func authenticateAndFetchFeatures(
        workspaceId: String,
        callback: @escaping (JSON) -> Void,
        errorCallback: @escaping EmptyCallback
    ) {
        authenticateWithHive(callback: { [weak self] token in
            guard let token = token else { errorCallback(); return }
            UserDefaults.Keys.hiveToken.set(token)
            self?.fetchFeatures(workspaceId: workspaceId, authToken: token, callback: callback, errorCallback: errorCallback)
        }, errorCallback: errorCallback)
    }

    func fetchFeatureDetail(
        featureId: String,
        authToken: String,
        callback: @escaping (JSON) -> Void,
        errorCallback: @escaping EmptyCallback
    ) {
        guard let request = createRequest("\(API.kHiveBaseUrl)/features/\(featureId)", params: nil, method: "GET", token: authToken) else {
            errorCallback(); return
        }
        AF.request(request).responseData { response in
            if let sc = response.response?.statusCode, sc == 401 { errorCallback(); return }
            switch response.result {
            case .success(let data): callback(JSON(data))
            case .failure: errorCallback()
            }
        }
    }

    func fetchFeatureDetailWithAuth(
        featureId: String,
        callback: @escaping (JSON) -> Void,
        errorCallback: @escaping EmptyCallback
    ) {
        if let token: String = UserDefaults.Keys.hiveToken.get() {
            fetchFeatureDetail(featureId: featureId, authToken: token, callback: callback,
                errorCallback: { [weak self] in self?.authenticateAndFetchFeatureDetail(featureId: featureId, callback: callback, errorCallback: errorCallback) })
        } else {
            authenticateAndFetchFeatureDetail(featureId: featureId, callback: callback, errorCallback: errorCallback)
        }
    }

    private func authenticateAndFetchFeatureDetail(
        featureId: String,
        callback: @escaping (JSON) -> Void,
        errorCallback: @escaping EmptyCallback
    ) {
        authenticateWithHive(callback: { [weak self] token in
            guard let token = token else { errorCallback(); return }
            UserDefaults.Keys.hiveToken.set(token)
            self?.fetchFeatureDetail(featureId: featureId, authToken: token, callback: callback, errorCallback: errorCallback)
        }, errorCallback: errorCallback)
    }

    func createFeature(
        workspaceId: String,
        params: NSDictionary,
        authToken: String,
        callback: @escaping (JSON) -> Void,
        errorCallback: @escaping EmptyCallback
    ) {
        guard let request = createRequest("\(API.kHiveBaseUrl)/features?workspaceId=\(workspaceId)", params: params, method: "POST", token: authToken) else {
            errorCallback(); return
        }
        AF.request(request).responseData { response in
            if let sc = response.response?.statusCode, sc == 401 { errorCallback(); return }
            switch response.result {
            case .success(let data): callback(JSON(data))
            case .failure: errorCallback()
            }
        }
    }

    func createFeatureWithAuth(
        workspaceId: String,
        params: NSDictionary,
        callback: @escaping (JSON) -> Void,
        errorCallback: @escaping EmptyCallback
    ) {
        if let token: String = UserDefaults.Keys.hiveToken.get() {
            createFeature(workspaceId: workspaceId, params: params, authToken: token, callback: callback,
                errorCallback: { [weak self] in self?.authenticateAndCreateFeature(workspaceId: workspaceId, params: params, callback: callback, errorCallback: errorCallback) })
        } else {
            authenticateAndCreateFeature(workspaceId: workspaceId, params: params, callback: callback, errorCallback: errorCallback)
        }
    }

    private func authenticateAndCreateFeature(
        workspaceId: String,
        params: NSDictionary,
        callback: @escaping (JSON) -> Void,
        errorCallback: @escaping EmptyCallback
    ) {
        authenticateWithHive(callback: { [weak self] token in
            guard let token = token else { errorCallback(); return }
            UserDefaults.Keys.hiveToken.set(token)
            self?.createFeature(workspaceId: workspaceId, params: params, authToken: token, callback: callback, errorCallback: errorCallback)
        }, errorCallback: errorCallback)
    }

    func updateFeature(
        featureId: String,
        params: NSDictionary,
        authToken: String,
        callback: @escaping (JSON) -> Void,
        errorCallback: @escaping EmptyCallback
    ) {
        guard let request = createRequest("\(API.kHiveBaseUrl)/features/\(featureId)", params: params, method: "PUT", token: authToken) else {
            errorCallback(); return
        }
        AF.request(request).responseData { response in
            if let sc = response.response?.statusCode, sc == 401 { errorCallback(); return }
            switch response.result {
            case .success(let data): callback(JSON(data))
            case .failure: errorCallback()
            }
        }
    }

    func updateFeatureWithAuth(
        featureId: String,
        params: NSDictionary,
        callback: @escaping (JSON) -> Void,
        errorCallback: @escaping EmptyCallback
    ) {
        if let token: String = UserDefaults.Keys.hiveToken.get() {
            updateFeature(featureId: featureId, params: params, authToken: token, callback: callback,
                errorCallback: { [weak self] in self?.authenticateAndUpdateFeature(featureId: featureId, params: params, callback: callback, errorCallback: errorCallback) })
        } else {
            authenticateAndUpdateFeature(featureId: featureId, params: params, callback: callback, errorCallback: errorCallback)
        }
    }

    private func authenticateAndUpdateFeature(
        featureId: String,
        params: NSDictionary,
        callback: @escaping (JSON) -> Void,
        errorCallback: @escaping EmptyCallback
    ) {
        authenticateWithHive(callback: { [weak self] token in
            guard let token = token else { errorCallback(); return }
            UserDefaults.Keys.hiveToken.set(token)
            self?.updateFeature(featureId: featureId, params: params, authToken: token, callback: callback, errorCallback: errorCallback)
        }, errorCallback: errorCallback)
    }

    // MARK: - Task Detail & Messages

    func fetchTaskDetail(
        taskId: String,
        authToken: String,
        callback: @escaping (JSON) -> Void,
        errorCallback: @escaping EmptyCallback
    ) {
        guard let request = createRequest("\(API.kHiveBaseUrl)/tasks/\(taskId)", params: nil, method: "GET", token: authToken) else {
            errorCallback(); return
        }
        AF.request(request).responseData { response in
            if let sc = response.response?.statusCode, sc == 401 { errorCallback(); return }
            switch response.result {
            case .success(let data): callback(JSON(data))
            case .failure: errorCallback()
            }
        }
    }

    func fetchTaskDetailWithAuth(
        taskId: String,
        callback: @escaping (JSON) -> Void,
        errorCallback: @escaping EmptyCallback
    ) {
        if let token: String = UserDefaults.Keys.hiveToken.get() {
            fetchTaskDetail(taskId: taskId, authToken: token, callback: callback,
                errorCallback: { [weak self] in self?.authenticateAndFetchTaskDetail(taskId: taskId, callback: callback, errorCallback: errorCallback) })
        } else {
            authenticateAndFetchTaskDetail(taskId: taskId, callback: callback, errorCallback: errorCallback)
        }
    }

    private func authenticateAndFetchTaskDetail(
        taskId: String,
        callback: @escaping (JSON) -> Void,
        errorCallback: @escaping EmptyCallback
    ) {
        authenticateWithHive(callback: { [weak self] token in
            guard let token = token else { errorCallback(); return }
            UserDefaults.Keys.hiveToken.set(token)
            self?.fetchTaskDetail(taskId: taskId, authToken: token, callback: callback, errorCallback: errorCallback)
        }, errorCallback: errorCallback)
    }

    func fetchTaskMessages(
        taskId: String,
        authToken: String,
        callback: @escaping (JSON) -> Void,
        errorCallback: @escaping EmptyCallback
    ) {
        guard let request = createRequest("\(API.kHiveBaseUrl)/tasks/\(taskId)/messages", params: nil, method: "GET", token: authToken) else {
            errorCallback(); return
        }
        AF.request(request).responseData { response in
            if let sc = response.response?.statusCode, sc == 401 { errorCallback(); return }
            switch response.result {
            case .success(let data): callback(JSON(data))
            case .failure: errorCallback()
            }
        }
    }

    func fetchTaskMessagesWithAuth(
        taskId: String,
        callback: @escaping (JSON) -> Void,
        errorCallback: @escaping EmptyCallback
    ) {
        if let token: String = UserDefaults.Keys.hiveToken.get() {
            fetchTaskMessages(taskId: taskId, authToken: token, callback: callback,
                errorCallback: { [weak self] in self?.authenticateAndFetchTaskMessages(taskId: taskId, callback: callback, errorCallback: errorCallback) })
        } else {
            authenticateAndFetchTaskMessages(taskId: taskId, callback: callback, errorCallback: errorCallback)
        }
    }

    private func authenticateAndFetchTaskMessages(
        taskId: String,
        callback: @escaping (JSON) -> Void,
        errorCallback: @escaping EmptyCallback
    ) {
        authenticateWithHive(callback: { [weak self] token in
            guard let token = token else { errorCallback(); return }
            UserDefaults.Keys.hiveToken.set(token)
            self?.fetchTaskMessages(taskId: taskId, authToken: token, callback: callback, errorCallback: errorCallback)
        }, errorCallback: errorCallback)
    }

    // MARK: - Task Write Operations

    func triggerTaskGeneration(
        featureId: String,
        authToken: String,
        callback: @escaping (JSON) -> Void,
        errorCallback: @escaping EmptyCallback
    ) {
        guard let request = createRequest("\(API.kHiveBaseUrl)/features/\(featureId)/generate-tasks", params: nil, method: "POST", token: authToken) else {
            errorCallback(); return
        }
        AF.request(request).responseData { response in
            if let sc = response.response?.statusCode, sc == 401 { errorCallback(); return }
            switch response.result {
            case .success(let data): callback(JSON(data))
            case .failure: errorCallback()
            }
        }
    }

    func triggerTaskGenerationWithAuth(
        featureId: String,
        callback: @escaping (JSON) -> Void,
        errorCallback: @escaping EmptyCallback
    ) {
        if let token: String = UserDefaults.Keys.hiveToken.get() {
            triggerTaskGeneration(featureId: featureId, authToken: token, callback: callback,
                errorCallback: { [weak self] in self?.authenticateAndTriggerTaskGeneration(featureId: featureId, callback: callback, errorCallback: errorCallback) })
        } else {
            authenticateAndTriggerTaskGeneration(featureId: featureId, callback: callback, errorCallback: errorCallback)
        }
    }

    private func authenticateAndTriggerTaskGeneration(
        featureId: String,
        callback: @escaping (JSON) -> Void,
        errorCallback: @escaping EmptyCallback
    ) {
        authenticateWithHive(callback: { [weak self] token in
            guard let token = token else { errorCallback(); return }
            UserDefaults.Keys.hiveToken.set(token)
            self?.triggerTaskGeneration(featureId: featureId, authToken: token, callback: callback, errorCallback: errorCallback)
        }, errorCallback: errorCallback)
    }

    func updateTaskStatus(
        taskId: String,
        status: String,
        authToken: String,
        callback: @escaping (JSON) -> Void,
        errorCallback: @escaping EmptyCallback
    ) {
        let params: NSDictionary = ["status": status as AnyObject]
        guard let request = createRequest("\(API.kHiveBaseUrl)/tasks/\(taskId)/status", params: params, method: "PUT", token: authToken) else {
            errorCallback(); return
        }
        AF.request(request).responseData { response in
            if let sc = response.response?.statusCode, sc == 401 { errorCallback(); return }
            switch response.result {
            case .success(let data): callback(JSON(data))
            case .failure: errorCallback()
            }
        }
    }

    func updateTaskStatusWithAuth(
        taskId: String,
        status: String,
        callback: @escaping (JSON) -> Void,
        errorCallback: @escaping EmptyCallback
    ) {
        if let token: String = UserDefaults.Keys.hiveToken.get() {
            updateTaskStatus(taskId: taskId, status: status, authToken: token, callback: callback,
                errorCallback: { [weak self] in self?.authenticateAndUpdateTaskStatus(taskId: taskId, status: status, callback: callback, errorCallback: errorCallback) })
        } else {
            authenticateAndUpdateTaskStatus(taskId: taskId, status: status, callback: callback, errorCallback: errorCallback)
        }
    }

    private func authenticateAndUpdateTaskStatus(
        taskId: String,
        status: String,
        callback: @escaping (JSON) -> Void,
        errorCallback: @escaping EmptyCallback
    ) {
        authenticateWithHive(callback: { [weak self] token in
            guard let token = token else { errorCallback(); return }
            UserDefaults.Keys.hiveToken.set(token)
            self?.updateTaskStatus(taskId: taskId, status: status, authToken: token, callback: callback, errorCallback: errorCallback)
        }, errorCallback: errorCallback)
    }

    func startTask(
        taskId: String,
        authToken: String,
        callback: @escaping (JSON) -> Void,
        errorCallback: @escaping EmptyCallback
    ) {
        guard let request = createRequest("\(API.kHiveBaseUrl)/tasks/\(taskId)/start", params: nil, method: "POST", token: authToken) else {
            errorCallback(); return
        }
        AF.request(request).responseData { response in
            if let sc = response.response?.statusCode, sc == 401 { errorCallback(); return }
            switch response.result {
            case .success(let data): callback(JSON(data))
            case .failure: errorCallback()
            }
        }
    }

    func startTaskWithAuth(
        taskId: String,
        callback: @escaping (JSON) -> Void,
        errorCallback: @escaping EmptyCallback
    ) {
        if let token: String = UserDefaults.Keys.hiveToken.get() {
            startTask(taskId: taskId, authToken: token, callback: callback,
                errorCallback: { [weak self] in self?.authenticateAndStartTask(taskId: taskId, callback: callback, errorCallback: errorCallback) })
        } else {
            authenticateAndStartTask(taskId: taskId, callback: callback, errorCallback: errorCallback)
        }
    }

    private func authenticateAndStartTask(
        taskId: String,
        callback: @escaping (JSON) -> Void,
        errorCallback: @escaping EmptyCallback
    ) {
        authenticateWithHive(callback: { [weak self] token in
            guard let token = token else { errorCallback(); return }
            UserDefaults.Keys.hiveToken.set(token)
            self?.startTask(taskId: taskId, authToken: token, callback: callback, errorCallback: errorCallback)
        }, errorCallback: errorCallback)
    }

    func retryTaskWorkflow(
        taskId: String,
        authToken: String,
        callback: @escaping (JSON) -> Void,
        errorCallback: @escaping EmptyCallback
    ) {
        guard let request = createRequest("\(API.kHiveBaseUrl)/tasks/\(taskId)/retry", params: nil, method: "POST", token: authToken) else {
            errorCallback(); return
        }
        AF.request(request).responseData { response in
            if let sc = response.response?.statusCode, sc == 401 { errorCallback(); return }
            switch response.result {
            case .success(let data): callback(JSON(data))
            case .failure: errorCallback()
            }
        }
    }

    func retryTaskWorkflowWithAuth(
        taskId: String,
        callback: @escaping (JSON) -> Void,
        errorCallback: @escaping EmptyCallback
    ) {
        if let token: String = UserDefaults.Keys.hiveToken.get() {
            retryTaskWorkflow(taskId: taskId, authToken: token, callback: callback,
                errorCallback: { [weak self] in self?.authenticateAndRetryTaskWorkflow(taskId: taskId, callback: callback, errorCallback: errorCallback) })
        } else {
            authenticateAndRetryTaskWorkflow(taskId: taskId, callback: callback, errorCallback: errorCallback)
        }
    }

    private func authenticateAndRetryTaskWorkflow(
        taskId: String,
        callback: @escaping (JSON) -> Void,
        errorCallback: @escaping EmptyCallback
    ) {
        authenticateWithHive(callback: { [weak self] token in
            guard let token = token else { errorCallback(); return }
            UserDefaults.Keys.hiveToken.set(token)
            self?.retryTaskWorkflow(taskId: taskId, authToken: token, callback: callback, errorCallback: errorCallback)
        }, errorCallback: errorCallback)
    }

    func archiveTask(
        taskId: String,
        authToken: String,
        callback: @escaping (JSON) -> Void,
        errorCallback: @escaping EmptyCallback
    ) {
        guard let request = createRequest("\(API.kHiveBaseUrl)/tasks/\(taskId)/archive", params: nil, method: "POST", token: authToken) else {
            errorCallback(); return
        }
        AF.request(request).responseData { response in
            if let sc = response.response?.statusCode, sc == 401 { errorCallback(); return }
            switch response.result {
            case .success(let data): callback(JSON(data))
            case .failure: errorCallback()
            }
        }
    }

    func archiveTaskWithAuth(
        taskId: String,
        callback: @escaping (JSON) -> Void,
        errorCallback: @escaping EmptyCallback
    ) {
        if let token: String = UserDefaults.Keys.hiveToken.get() {
            archiveTask(taskId: taskId, authToken: token, callback: callback,
                errorCallback: { [weak self] in self?.authenticateAndArchiveTask(taskId: taskId, callback: callback, errorCallback: errorCallback) })
        } else {
            authenticateAndArchiveTask(taskId: taskId, callback: callback, errorCallback: errorCallback)
        }
    }

    private func authenticateAndArchiveTask(
        taskId: String,
        callback: @escaping (JSON) -> Void,
        errorCallback: @escaping EmptyCallback
    ) {
        authenticateWithHive(callback: { [weak self] token in
            guard let token = token else { errorCallback(); return }
            UserDefaults.Keys.hiveToken.set(token)
            self?.archiveTask(taskId: taskId, authToken: token, callback: callback, errorCallback: errorCallback)
        }, errorCallback: errorCallback)
    }
}

// MARK: - Workspace Image Cache

class WorkspaceImageCache: @unchecked Sendable {
    static let shared = WorkspaceImageCache()
    private struct CachedImage { let url: String; let expiresAt: Date }
    private var cache: [String: CachedImage] = [:]
    private let queue = DispatchQueue(label: "com.sphinx.workspaceImageCache")
    private init() {}

    func setImage(url: String, forSlug slug: String, expiresAt: Date) {
        queue.async { [weak self] in self?.cache[slug] = CachedImage(url: url, expiresAt: expiresAt) }
    }

    func getImageUrl(forSlug slug: String) -> String? {
        queue.sync {
            guard let cached = cache[slug] else { return nil }
            if cached.expiresAt.timeIntervalSinceNow < 60 { cache.removeValue(forKey: slug); return nil }
            return cached.url
        }
    }

    func clearCache() {
        queue.async { [weak self] in self?.cache.removeAll() }
    }
}
