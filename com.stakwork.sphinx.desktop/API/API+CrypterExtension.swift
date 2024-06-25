//
//  API+CrypterExtension.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 22/08/2023.
//  Copyright © 2023 Tomas Timinskas. All rights reserved.
//

import Foundation
import SwiftyJSON
import Alamofire

extension API {
    func getHardwarePublicKey(
        callback: @escaping HardwarePublicKeyCallback,
        errorCallback: @escaping EmptyCallback
    ) {
        let ip = "http://192.168.71.1"
//        let ip = "http://192.168.0.25:8000"
        
        let url = "\(ip)/ecdh"
        
        let tribeRequest : URLRequest? = createRequest(url, params: nil, method: "GET")
        
        guard let request = tribeRequest else {
            errorCallback()
            return
        }
        
        sphinxRequest(request) { response in
            switch response.result {
            case .success(let data):
                if let response = data as? NSDictionary {
                    if let publicKey = response["pubkey"] as? String {
                        callback(publicKey)
                        return
                    }
                } else {
                    errorCallback()
                }
            case .failure(_):
                errorCallback()
            }
        }
    }
    
    func sendSeedToHardware(
        hardwarePostDto: CrypterManager.HardwarePostDto,
        callback: @escaping HardwareSeedCallback
    ) {
        
        let ip = "http://192.168.71.1"
//        let ip = "http://192.168.0.25:8000"
        
        guard let encryptedSeed = hardwarePostDto.encryptedSeed,
              let networkName = hardwarePostDto.networkName,
              let networkPassword = hardwarePostDto.networkPassword,
              let lightnigUrl = hardwarePostDto.lightningNodeUrl,
              let bitcoinNetwork = hardwarePostDto.bitcoinNetwork,
              let publicKey = hardwarePostDto.publicKey else {
            
            callback(false)
            return
        }
        
        let params = "{\"seed\":\"\(encryptedSeed)\",\"ssid\":\"\(networkName)\",\"pass\":\"\(networkPassword)\",\"broker\":\"\(lightnigUrl)\",\"pubkey\":\"\(publicKey)\",\"network\":\"\(bitcoinNetwork)\"}"
        
        let url = "\(ip)/config?config=\(params.urlEncode()!)"
        let request : URLRequest? = createRequest(url, params: nil, method: "POST")
        
        guard let request = request else {
            callback(false)
            return
        }
        
        sphinxRequest(request) { response in
            switch response.result {
            case .success(let data):
                if let _ = data as? NSDictionary {
                    callback(true)
                } else {
                    callback(false)
                }
            case .failure(_):
                callback(false)
            }
        }
    }
    
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
                       let default_lsp = dictionary["default_lsp"] as? String,
                       let router_url = dictionary["ROUTER_URL"] as? String
                    {
                        SphinxOnionManager.sharedInstance.saveConfigFrom(
                            lspHost: default_lsp,
                            tribeServerHost: tribe_host,
                            defaultTribePubkey: tribe,
                            router_url: router_url
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
}
