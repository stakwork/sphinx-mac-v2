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
        var url = "\(self.kVideoCallServer)/api/connection-details?roomName=\(room)&participantName=\(alias.urlEncode() ?? alias)"
        
        if let profilePicture = profilePicture {
            let metaData = "{\"profilePictureUrl\":\"\(profilePicture)\"}"
            url = url + "&metadata=\(metaData.urlEncode() ?? metaData)"
        }
        
        let request : URLRequest? = createRequest(
            url,
            params: nil,
            method: "GET"
        )
        
        guard let request = request else {
            errorCallback("Error creating request")
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
                errorCallback("Error getting response data")
            case .failure(let error):
                errorCallback(error.localizedDescription)
            }
        }
    }
    
    func toggleLiveKitRecording(
        room: String,
        now: String? = nil,
        action: String,
        callback: @escaping LiveKitRecordingCallback
    ) {
        var url = "\(self.kVideoCallServer)/api/record/\(action)?roomName=\(room)"
        
        if let now = now {
            url = "\(url)&now=\(now)"
        }
        
        guard let url = URL(string: url) else {
            callback(false)
            return
        }
        
        // Create the request
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            // Handle the response
            if let _ = error {
                callback(false)
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                callback(false)
                return
            }
            
            if httpResponse.statusCode == 200 {
                callback(true)
                return
            }
            
            guard let data = data, !data.isEmpty else {
                callback(false)
                return
            }
            
            // Handle response data
            if let _ = String(data: data, encoding: .utf8) {
                callback(false)
            } else {
                callback(false)
            }
        }
        
        // Start the request
        task.resume()
    }
}
