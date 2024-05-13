//
//  APIPeopleExtension.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 05/01/2022.
//  Copyright © 2022 Tomas Timinskas. All rights reserved.
//

import Foundation
import Alamofire
import SwiftyJSON

extension API {
    
    typealias VerifyExternalCallback = ((Bool, NSDictionary?) -> ())
    typealias SignVerifyCallback = ((String?) -> ())
    typealias GetPersonInfoCallback = ((Bool, JSON?) -> ())
    typealias GetExternalRequestByKeyCallback = ((Bool, JSON?) -> ())
    typealias PeopleTorRequestCallback = ((Bool) -> ())
    
    public func authorizeExternal(
        host: String,
        challenge: String,
        token: String,
        params: [String: AnyObject],
        callback: @escaping SuccessCallback
    ) {
        
        let url = "https://\(host)/verify/\(challenge)?token=\(token)"
        
        guard let request = createRequest(url, params: params as NSDictionary, method: "POST") else {
            callback(false)
            return
        }
        
        sphinxRequest(request) { response in
            switch response.result {
            case .success(let data):
                if let _ = data as? NSDictionary {
                    callback(true)
                }
            case .failure( _):
                callback(false)
            }
        }
    }
    
    public func getPersonInfo(
        host: String,
        pubkey: String,
        callback: @escaping GetPersonInfoCallback
    ) {
        
        let url = "https://\(host)/person/\(pubkey)"
        
        guard let request = createRequest(url, params: nil, method: "GET") else {
            callback(false, nil)
            return
        }
        
        sphinxRequest(request) { response in
            switch response.result {
            case .success(let data):
                if let json = data as? NSDictionary {
                    callback(true, JSON(json))
                    return
                }
                callback(false, nil)
            case .failure(_):
                callback(false, nil)
            }
        }
    }
    
    public func getExternalRequestByKey(
        host: String,
        key: String,
        callback: @escaping GetExternalRequestByKeyCallback
    ) {
        let url = "https://\(host)/save/\(key)"
        
        guard let request = createRequest(url, params: nil, method: "GET") else {
            callback(false, nil)
            return
        }
        
        sphinxRequest(request) { response in
            switch response.result {
            case .success(let data):
                if let json = data as? NSDictionary {
                    callback(true, JSON(json))
                    return
                }
                callback(false, nil)
            case .failure(_):
                callback(false, nil)
            }
        }
    }
    
    ///Replace with call to people site
    public func savePeopleProfile(
        params: [String: AnyObject],
        callback: @escaping PeopleTorRequestCallback
    ) {
        
//        guard let request = getURLRequest(route: "/profile", params: params as NSDictionary, method: "POST") else {
//            callback(false)
//            return
//        }
//        
//        sphinxRequest(request) { response in
//            switch response.result {
//            case .success(let data):
//                if let json = data as? NSDictionary {
//                    if let success = json["success"] as? Bool,
//                       let _ = json["response"] as? NSDictionary, success {
//                        callback(true)
//                        return
//                    }
//                }
//                callback(false)
//            case .failure(_):
//                callback(false)
//            }
//        }
    }
    
    ///Replace with call to people site
    public func deletePeopleProfile(
        params: [String: AnyObject],
        callback: @escaping PeopleTorRequestCallback
    ) {
        
//        guard let request = getURLRequest(route: "/profile", params: params as NSDictionary, method: "DELETE") else {
//            callback(false)
//            return
//        }
//        
//        sphinxRequest(request) { response in
//            switch response.result {
//            case .success(let data):
//                if let json = data as? NSDictionary {
//                    if let success = json["success"] as? Bool,
//                       let _ = json["response"] as? NSDictionary, success {
//                        callback(true)
//                        return
//                    }
//                }
//                callback(false)
//            case .failure(_):
//                callback(false)
//            }
//        }
    }
}
