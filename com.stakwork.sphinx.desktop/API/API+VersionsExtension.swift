//
//  APIVersionsExtension.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 11/01/2021.
//  Copyright © 2021 Tomas Timinskas. All rights reserved.
//

import Foundation
import Alamofire
import SwiftyJSON

extension API {
    typealias AppVersionsCallback = ((String) -> ())
    
    func getAppVersions(
        callback: @escaping AppVersionsCallback
    ) {
        let url = "\(API.kHUBServerUrl)/api/v1/app_versions"
        
        guard let request = createRequest(url, params: nil, method: "GET") else {
            print("Error getting app version")
            return
        }
        
        sphinxRequest(request) { response in
            switch response.result {
            case .success(let data):
                if let json = data as? NSDictionary {
                    if let success = json["success"] as? Bool, let response = json["response"] as? NSDictionary, success {
                        if let version = response["mac-v2"] as? String {
                            callback(version)
                            return
                        }
                    }
                }
            case .failure(_):
                print("Error getting app version")
            }
        }
    }
}
