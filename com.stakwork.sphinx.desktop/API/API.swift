//
//  API.swift
//  com.stakwork.sphinx.desktop
//
//  Created by Tomas Timinskas on 11/05/2020.
//  Copyright © 2020 Sphinx. All rights reserved.
//

import Foundation
import Alamofire
import SwiftyJSON

typealias EmptyCallback = (() -> ())
typealias UploadProgressCallback = ((Int) -> ())
typealias UploadCallback = ((Bool, String?) -> ())
typealias SuccessCallback = ((Bool) -> ())
typealias CreateGroupCallback = ((JSON) -> ())
typealias TemplatesCallback = (([ImageTemplate]) -> ())
typealias PinMessageCallback = ((String) -> ())
typealias ErrorCallback = ((String) -> ())

//Attachments
typealias askAuthenticationCallback = ((String?, String?) -> ())
typealias signChallengeCallback = ((String?) -> ())
typealias verifyAuthenticationCallback = ((String?) -> ())
typealias UploadAttachmentCallback = ((Bool, NSDictionary?) -> ())
typealias GiphySearchCallback = (([GiphyObject]) -> ())
typealias GiphySearchErrorCallback = (() -> ())
typealias MediaInfoCallback = ((Int, String?, Int?) -> ())

//Feed
typealias SyncActionsCallback = ((Bool) -> ())
typealias ContentFeedCallback = ((JSON) -> ())
typealias AllContentFeedStatusCallback = (([ContentFeedStatus]) -> ())
typealias ContentFeedStatusCallback = ((ContentFeedStatus) -> ())

//Crypter
typealias HardwarePublicKeyCallback = ((String) -> ())
typealias HardwareSeedCallback = ((Bool) -> ())

//TribeMembers
typealias ChatContactsCallback = (([JSON]) -> ())

extension API {
    enum RequestError: Swift.Error {
        case failedToCreateRequestURL
        case failedToCreateRequest(urlPath: String)
        case missingResponseData
        case decodingError(DecodingError)
        case unknownError(Swift.Error)
        case unexpectedResponseData
        case failedToFetchContentFeed
        case networkError(AFError)
        case nodeInvoiceGenerationFailure(message: String)
        case karmaReceiptValidationFailure(message: String)
    }
}

class API {
    
    class var sharedInstance : API {
        struct Static {
            static let instance = API()
        }
        return Static.instance
    }
    
    let interceptor = SphinxInterceptor()
    var uploadRequest: UploadRequest?
    var giphyRequest: DataRequest?
    var giphyRequestType: GiphyHelper.SearchType = GiphyHelper.SearchType.Gifs
    
    let messageBubbleHelper = NewMessageBubbleHelper()
    
    public static let kTestV2TribesServer = "34.229.52.200:8801"
    
    public static var kTribesServer : String {
        get {
            if let tribesServerUrl = UserDefaults.Keys.tribesServerURL.get(defaultValue: ""), tribesServerUrl != "" {
                return tribesServerUrl
            }
            return kTestV2TribesServer
        }
        set {
            UserDefaults.Keys.tribesServerURL.set(newValue)
        }
    }
    
    public static var kAttachmentsServerUrl : String {
        get {
            if let fileServerURL = UserDefaults.Keys.fileServerURL.get(defaultValue: ""), fileServerURL != "" {
                return fileServerURL
            }
            return "https://memes.sphinx.chat"
        }
        set {
            UserDefaults.Keys.fileServerURL.set(newValue)
        }
    }
    
    public static var kVideoCallServer : String {
        get {
            if let meetingServerURL = UserDefaults.Keys.meetingServerURL.get(defaultValue: ""), meetingServerURL != "" {
                return meetingServerURL
            }
            return "https://jitsi.sphinx.chat"
        }
        set {
            UserDefaults.Keys.meetingServerURL.set(newValue)
        }
    }
    
    public static var kHUBServerUrl : String {
        get {
            if let inviteServerURL = UserDefaults.Keys.inviteServerURL.get(defaultValue: ""), inviteServerURL != "" {
                return inviteServerURL
            }
            return "https://hub.sphinx.chat"
        }
        set {
            UserDefaults.Keys.inviteServerURL.set(newValue)
        }
    }

    
    class func getUrl(route: String) -> String {
        if let url = URL(string: route), let _ = url.scheme {
            return url.absoluteString
        }
        return "https://\(route)"
        
    }
    
    func session() -> Alamofire.Session? {
        return Alamofire.Session.default
    }
    
    var errorCounter = 0
    let successStatusCode = 200
    let unauthorizedStatusCode = 401
    let notFoundStatusCode = 404
    let badGatewayStatusCode = 502
    let connectionLostError = "The network connection was lost"
    
    public enum ConnectionStatus: Int {
        case Connecting
        case Connected
        case NotConnected
        case Unauthorize
        case NoNetwork
    }
    
    var connectionStatus = ConnectionStatus.Connecting
    
    func sphinxRequest(
        _ urlRequest: URLRequest,
        completionHandler: @escaping (AFDataResponse<Any>) -> Void
    ) {
        unauthorizedHandledRequest(urlRequest, completionHandler: completionHandler)
    }
    
    func unauthorizedHandledRequest(
        _ urlRequest: URLRequest,
        completionHandler: @escaping (AFDataResponse<Any>) -> Void
    ) {
        session()?.request(
            urlRequest,
            interceptor: interceptor
        ).responseJSON { (response) in
            
            let statusCode = (response.response?.statusCode ?? -1)
            
            switch statusCode {
            case self.successStatusCode:
                self.connectionStatus = .Connected
            case self.unauthorizedStatusCode:
                self.connectionStatus = .Unauthorize
            default:
                if response.response == nil ||
                    statusCode == self.notFoundStatusCode  ||
                    statusCode == self.badGatewayStatusCode {
                    
                    self.connectionStatus = response.response == nil ?
                        self.connectionStatus :
                        .NotConnected

                    if self.errorCounter < 5 {
                        self.errorCounter = self.errorCounter + 1
                    } else if response.response != nil {
                        return
                    }
                    completionHandler(response)
                    return
                } else {
                    self.connectionStatus = .NotConnected
                }
            }

            self.errorCounter = 0

            if let _ = response.response {
                completionHandler(response)
            }
        }
    }
    
    func networksConnectionLost() {
        DispatchQueue.main.async {
            self.connectionStatus = .NoNetwork
            self.messageBubbleHelper.showGenericMessageView(text: "network.connection.lost".localized, delay: 3)
        }
    }
    
    func createRequest(
        _ url:String,
        params:NSDictionary?,
        method:String,
        contentType: String = "application/json",
        token: String? = nil
    ) -> URLRequest? {
        
        if !ConnectivityHelper.isConnectedToInternet {
            networksConnectionLost()
            return nil
        }
        
        if let nsURL = URL(string: url) {
            var request = URLRequest(url: nsURL)
            request.httpMethod = method
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            
            if let token = token {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            
            if let p = params {
                do {
                    try request.httpBody = JSONSerialization.data(withJSONObject: p, options: [])
                } catch let error as NSError {
                    print("Error: " + error.localizedDescription)
                }
            }
            
            return request
        } else {
            return nil
        }
    }
}

class SphinxInterceptor : RequestInterceptor {
    public func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping (Result<URLRequest, Error>) -> Void) {
        completion(.success(urlRequest))
    }

    public func retry(_ request: Request,
                      for session: Session,
                      dueTo error: Error,
                      completion: @escaping (RetryResult) -> Void) {
        completion(.doNotRetry)
    }
}
