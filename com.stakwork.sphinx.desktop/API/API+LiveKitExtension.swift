//
//  API+LiveKitExtension.swift
//  sphinx
//
//  Created by Tomas Timinskas on 05/11/2024.
//  Copyright © 2024 sphinx. All rights reserved.
//

import Foundation
import SwiftyJSON

extension API {
    func getLiveKitToken(
        room: String,
        alias: String,
        profilePicture: String?,
        callback: @escaping LiveKitTokenCallback,
        errorCallback: @escaping ErrorCallback
    ) {
        var url = "\(self.kVideoCallServer)/api/connection-details?roomName=\(room)&participantName=\(alias)"
        
        if let profilePicture = profilePicture {
            url = url + "&metadata={\"profilePictureUrl\":\"\(profilePicture)\"}"
        }
        
        let request : URLRequest? = createRequest(
            url,
            params: nil,
            method: "GET"
        )
        
        guard let request = request else {
            errorCallback("")
            return
        }
        
        //NEEDS TO BE CHANGED
        sphinxRequest(request) { response in
            switch response.result {
            case .success(let data):
                if let dictionary = data as? NSDictionary {
                    if let serverUrl = dictionary["serverUrl"] as? String,
                       let token = dictionary["participantToken"] as? String
                    {
                        callback(serverUrl, token)
                        return
                    }
                }
                errorCallback("")
            case .failure(_):
                errorCallback("")
            }
        }
    }
}
