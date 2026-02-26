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

extension API {

    static let kHiveBaseUrl = "https://hive.sphinx.chat/api"

    func authenticateWithHive(
        callback: @escaping HiveAuthTokenCallback,
        errorCallback: @escaping EmptyCallback
    ) {
        guard let signedToken = SphinxOnionManager.sharedInstance.getSignedToken(),
              let pubkey = UserData.sharedInstance.getUserPubKey() else {
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

        AF.request(request).responseData { response in
            switch response.result {
            case .success(let data):
                let json = JSON(data)
                if let token = json["token"].string {
                    callback(token)
                } else {
                    errorCallback()
                }
            case .failure:
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

                callback(workspaces)
            case .failure:
                errorCallback()
            }
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
            switch response.result {
            case .success(let data):
                let json = JSON(data)
                var tasks: [WorkspaceTask] = []
                if let tasksArray = json["tasks"].array {
                    for taskJson in tasksArray {
                        if let task = WorkspaceTask(json: taskJson) {
                            tasks.append(task)
                        }
                    }
                }
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

// MARK: - Workspace Image Cache

class WorkspaceImageCache {
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
