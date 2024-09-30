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
    typealias CheckPeopleProfile = (Int?) -> ()
    typealias CreatePeopleProfile = (Bool) -> ()
    
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
    
    public func checkPeopleProfileWith(
        publicKey: String,
        callback: @escaping CheckPeopleProfile
    ) {
        let url = "\(API.tribesV1Url)/person/\(publicKey)"
        
        guard let request = createRequest(url, params: nil, method: "GET") else {
            callback(nil)
            return
        }
        
        sphinxRequest(request) { response in
            if let data = response.data {
                let jsonProfile = JSON(data)
                if let pubKey = jsonProfile["owner_pubkey"].string, pubKey == publicKey {
                    callback(jsonProfile["id"].int)
                } else {
                    callback(nil)
                }
            } else {
                callback(nil)
            }
        }
    }
    
    public func createPeopleProfileWith(
        token: String,
        userId: Int?,
        alias: String,
        imageUrl: String?,
        publicKey: String,
        routeHint: String,
        callback: @escaping CreatePeopleProfile
    ) {
        let url = "\(API.tribesV1Url)/person?token=\(token)"
        
        let params: [String: AnyObject] = [
            "id": userId as AnyObject,
            "owner_pubkey": publicKey as AnyObject,
            "owner_alias": alias as AnyObject,
            "owner_route_hint": routeHint as AnyObject,
            "img": imageUrl as AnyObject
        ]
        
        guard let request = createRequest(url, params: params as NSDictionary, method: "POST") else {
            callback(false)
            return
        }
        
        sphinxRequest(request) { response in
            if let data = response.data {
                let jsonProfile = JSON(data)
                if let pubKey = jsonProfile["owner_pubkey"].string, pubKey == publicKey {
                    callback(true)
                } else {
                    callback(false)
                }
            } else {
                callback(false)
            }
        }
    }
}
