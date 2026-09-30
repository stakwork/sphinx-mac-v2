//
//  API+HivePlanner.swift
//  Sphinx
//
//  Hive feature planner chat API (read + send) and write-result classification.
//  Copyright © 2026 Sphinx. All rights reserved.
//

import Foundation
import Alamofire
import SwiftyJSON

// MARK: - HiveWriteResult

enum HiveWriteResult: Equatable {
    case success(JSON)
    case conflict(String)
    case forbidden
    case notFound
    case unauthorized
    /// The request may or may not have been processed (transport failure, no HTTP status).
    case unknownOutcome
    case failed(String?)

    /// Pure classification of an HTTP outcome. Never inspects `response.result`.
    static func from(statusCode: Int?, json: JSON?, transportError: Error?) -> HiveWriteResult {
        guard let status = statusCode else {
            // No HTTP response at all: we can't know whether the server processed the request.
            return .unknownOutcome
        }

        switch status {
        case 200..<300:
            guard let json = json else { return .failed("Empty response") }
            let errorField = json["error"]
            if errorField.exists() && errorField.type != .null {
                return .failed(errorField.string ?? "Request failed")
            }
            if json["success"].bool != true {
                return .failed(json["message"].string ?? "Request was not successful")
            }
            return .success(json)
        case 401:
            return .unauthorized
        case 403:
            return .forbidden
        case 404:
            return .notFound
        case 409:
            let message = json?["error"].string ?? json?["message"].string ?? ""
            return .conflict(message)
        default:
            return .failed("HTTP \(status)")
        }
    }
}

// MARK: - Write pipeline

typealias HiveWriteRequestFn = (URLRequest, @escaping (Int?, Data?, Error?) -> Void) -> Void

extension API {

    /// Default sender: Alamofire. Uses the HTTP status code only (never `response.result`).
    // Immutable closure capturing nothing; safe to share.
    nonisolated(unsafe) static let defaultHiveWriteSend: HiveWriteRequestFn = { request, done in
        AF.request(request).responseData { response in
            done(response.response?.statusCode, response.data, response.error)
        }
    }

    /// Sends once; on 401 re-authenticates and retries exactly once. A second 401 is `.unauthorized`.
    /// Every other outcome (including transport errors) is returned without retry, because
    /// the write may already have been applied.
    static func performHiveWrite(
        token: String,
        build: @escaping (String) -> URLRequest?,
        reauth: @escaping (@escaping (String?) -> Void) -> Void,
        send: @escaping HiveWriteRequestFn,
        completion: @escaping (HiveWriteResult) -> Void
    ) {
        func classify(_ status: Int?, _ data: Data?, _ error: Error?) -> HiveWriteResult {
            let json: JSON? = data.map { JSON($0) }
            return HiveWriteResult.from(statusCode: status, json: json, transportError: error)
        }

        guard let firstRequest = build(token) else {
            completion(.failed("Could not build request"))
            return
        }

        send(firstRequest) { status, data, error in
            guard status == 401 else {
                completion(classify(status, data, error))
                return
            }
            reauth { newToken in
                guard let newToken = newToken, let retryRequest = build(newToken) else {
                    completion(.unauthorized)
                    return
                }
                send(retryRequest) { status2, data2, error2 in
                    completion(classify(status2, data2, error2))
                }
            }
        }
    }
}

// MARK: - Feature chat

extension API {

    /// Percent-encodes a feature id for use as a single path segment ('/' is encoded too).
    static func hivePathSegment(_ id: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return id.addingPercentEncoding(withAllowedCharacters: allowed) ?? id
    }

    /// Static so it can be unit-tested without touching `API.sharedInstance`.
    /// Mirrors `createRequest(_:params:method:token:)` (JSON body, Bearer token).
    static func buildFeatureChatSendRequest(
        featureId: String,
        message: String,
        replyId: String?,
        token: String
    ) -> URLRequest? {
        let params: NSDictionary = [
            "message": message,
            "contextTags": [Any](),
            "replyId": replyId ?? NSNull(),
            "sourceWebsocketID": NSNull(),
            "selectedRepositoryIds": [Any]()
        ]
        guard let url = URL(string: "\(API.kHiveBaseUrl)/features/\(API.hivePathSegment(featureId))/chat"),
              let body = try? JSONSerialization.data(withJSONObject: params, options: []) else {
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        return request
    }

    func sendFeatureChatMessageWithAuth(
        featureId: String,
        message: String,
        replyId: String?,
        request send: @escaping HiveWriteRequestFn = API.defaultHiveWriteSend,
        completion: @escaping (HiveWriteResult) -> Void
    ) {
        let build: (String) -> URLRequest? = { token in
            API.buildFeatureChatSendRequest(featureId: featureId, message: message, replyId: replyId, token: token)
        }
        let reauth: (@escaping (String?) -> Void) -> Void = { [weak self] done in
            guard let self = self else { done(nil); return }
            self.authenticateWithHive(
                callback: { token in
                    if let token = token { UserDefaults.Keys.hiveToken.set(token) }
                    done(token)
                },
                errorCallback: { done(nil) }
            )
        }
        let finish: (HiveWriteResult) -> Void = { result in
            if case .success = result {} else {
                print("[HiveAPI] feature chat send \(featureId): \(result)")
            }
            completion(result)
        }

        if let stored: String = UserDefaults.Keys.hiveToken.get() {
            API.performHiveWrite(token: stored, build: build, reauth: reauth, send: send, completion: finish)
        } else {
            reauth { token in
                guard let token = token else { finish(.unauthorized); return }
                API.performHiveWrite(token: token, build: build, reauth: reauth, send: send, completion: finish)
            }
        }
    }

    func fetchFeatureChat(
        featureId: String,
        authToken: String,
        callback: @escaping (JSON) -> Void,
        errorCallback: @escaping EmptyCallback
    ) {
        guard let request = createRequest(
            "\(API.kHiveBaseUrl)/features/\(API.hivePathSegment(featureId))/chat",
            params: nil, method: "GET", token: authToken
        ) else { errorCallback(); return }
        AF.request(request).responseData { response in
            let sc = response.response?.statusCode
            if sc == 401 { errorCallback(); return }
            if let sc = sc, !(200..<300).contains(sc) {
                print("[HiveAPI] feature chat fetch \(featureId): HTTP \(sc)")
                errorCallback()
                return
            }
            switch response.result {
            case .success(let data): callback(JSON(data))
            case .failure:
                print("[HiveAPI] feature chat fetch \(featureId): transport failure")
                errorCallback()
            }
        }
    }

    func fetchFeatureChatWithAuth(
        featureId: String,
        callback: @escaping (JSON) -> Void,
        errorCallback: @escaping EmptyCallback
    ) {
        let reauthAndFetch: EmptyCallback = { [weak self] in
            self?.authenticateWithHive(
                callback: { token in
                    guard let token = token else { errorCallback(); return }
                    UserDefaults.Keys.hiveToken.set(token)
                    self?.fetchFeatureChat(featureId: featureId, authToken: token, callback: callback, errorCallback: errorCallback)
                },
                errorCallback: errorCallback
            )
        }
        if let stored: String = UserDefaults.Keys.hiveToken.get() {
            fetchFeatureChat(featureId: featureId, authToken: stored, callback: callback, errorCallback: reauthAndFetch)
        } else {
            reauthAndFetch()
        }
    }
}
