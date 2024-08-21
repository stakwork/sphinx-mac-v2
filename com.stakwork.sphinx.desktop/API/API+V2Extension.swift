//
//  API+V2Extension.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 03/07/2024.
//  Copyright © 2024 Tomas Timinskas. All rights reserved.
//

import Foundation
import SwiftyJSON

extension API {
    func getServerConfig(
        callback: @escaping SuccessCallback
    ) {
        let url = "https://config.config.sphinx.chat/api/config/bitcoin"
        let request : URLRequest? = createRequest(url, params: nil, method: "GET")
        
        guard let request = request else {
            callback(false)
            return
        }
        
        //NEEDS TO BE CHANGED
        sphinxRequest(request) { response in
            switch response.result {
            case .success(let data):
                if let dictionary = data as? NSDictionary {
                    if let tribe = dictionary["tribe"] as? String,
                       let tribe_host = dictionary["tribe_host"] as? String,
                       let default_lsp = dictionary["default_lsp"] as? String
                    {
                        SphinxOnionManager.sharedInstance.saveConfigFrom(
                            lspHost: default_lsp,
                            tribeServerHost: tribe_host,
                            defaultTribePubkey: tribe,
                            routerUrl: dictionary["router"] as? String
                        )
                        
                        callback(true)
                        return
                    }
                }
                callback(false)
            case .failure(_):
                callback(false)
            }
        }
    }
    
    func updateDefaultTribe() {
        let url = "https://config.config.sphinx.chat/api/config/bitcoin"
        let request : URLRequest? = createRequest(url, params: nil, method: "GET")
        
        guard let request = request else {
            return
        }
        
        //NEEDS TO BE CHANGED
        sphinxRequest(request) { response in
            switch response.result {
            case .success(let data):
                if let dictionary = data as? NSDictionary {
                    if let tribe = dictionary["tribe"] as? String {
                        UserDefaults.Keys.defaultTribePublicKey.set(tribe)
                    }
                }
            case .failure(_):
                break
            }
        }
    }
    
    func fetchRoutingInfo(
        callback: @escaping UpdateRoutingInfoCallback
    ) {
        let hostProtocol = UserDefaults.Keys.isProductionEnv.get(defaultValue: false) ? "https" : "http"
        let url = "\(hostProtocol)://\(SphinxOnionManager.sharedInstance.routerUrl)/api/node"
        let request : URLRequest? = createRequest(url, params: nil, method: "GET")
        
        guard let request = request else {
            callback(nil, nil)
            return
        }
        
        sphinxRequest(request) { response in
            switch response.result {
            case .success(let data):
                if let data = data as? NSDictionary {
                    let json = JSON(data)
                    let resultString = json.rawString()
                    
                    callback(
                        resultString,
                        json["pubkey"].string
                    )
                } else {
                    callback(nil, nil)
                }
            case .failure(_):
                callback(nil, nil)
            }
        }
    }
    
    func fetchRoutingInfoFor(
        pubkey: String,
        amtMsat: Int,
        callback: @escaping FetchRoutingInfoCallback
    ) {
        let hostProtocol = UserDefaults.Keys.isProductionEnv.get(defaultValue: false) ? "https" : "http"
        let url = "\(hostProtocol)://\(SphinxOnionManager.sharedInstance.routerUrl)/api/route?pubkey=\(pubkey)&msat=\(amtMsat)"
        let request : URLRequest? = createRequest(url, params: nil, method: "GET")
        
        guard let request = request else {
            callback(nil)
            return
        }
        
        sphinxRequest(request) { response in
            switch response.result {
            case .success(let data):
                if let _ = data as? [NSDictionary] {
                    let json = JSON(data)
                    let resultString = json.rawString()
                    callback(resultString)
                } else {
                    callback(nil)
                }
            case .failure(_):
                callback(nil)
            }
        }
    }
}
