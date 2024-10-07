//
//  APIGroupsExtension.swift
//  com.stakwork.sphinx.desktop
//
//  Created by Tomas Timinskas on 11/05/2020.
//  Copyright © 2020 Sphinx. All rights reserved.
//

import Foundation
import SwiftyJSON
import Alamofire

extension API {

    func getTribeInfo(
        host: String,
        uuid: String,
        callback: @escaping CreateGroupCallback,
        errorCallback: @escaping EmptyCallback
    ) {
        let hostProtocol = SphinxOnionManager.sharedInstance.isProductionEnv ? "https" : "http"
        let finalHost = SphinxOnionManager.sharedInstance.isProductionEnv ? host : SphinxOnionManager.sharedInstance.kTestV2TribesServer
        let url = API.getUrl(route: "\(hostProtocol)://\(finalHost)/tribes/\(uuid)")
        let tribeRequest : URLRequest? = createRequest(url, params: nil, method: "GET")
        
        guard let request = tribeRequest else {
            errorCallback()
            return
        }
        
        sphinxRequest(request) { response in
            switch response.result {
            case .success(let data):
                if let json = data as? NSDictionary {
                    callback(JSON(json))
                } else {
                    errorCallback()
                }
            case .failure(_):
                errorCallback()
            }
        }
    }
}
