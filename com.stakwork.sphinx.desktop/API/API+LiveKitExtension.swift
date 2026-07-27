//
//  API+LiveKitExtension.swift
//  sphinx
//
//  Created by Tomas Timinskas on 05/11/2024.
//  Copyright © 2024 sphinx. All rights reserved.
//

import Foundation
import Alamofire
import SwiftyJSON

extension API {
    func getLiveKitToken(
        room: String,
        alias: String,
        profilePicture: String?,
        hiveCallKey: String? = nil,
        isHost: Bool = false,
        callback: @escaping LiveKitTokenCallback,
        errorCallback: @escaping ErrorCallback
    ) {
        var url = "\(self.kVideoCallServer)/api/connection-details?roomName=\(room)&participantName=\(alias.urlEncode() ?? alias)"
        
        if let profilePicture = profilePicture {
            let metaData = "{\"profilePictureUrl\":\"\(profilePicture)\"}"
            url = url + "&metadata=\(metaData.urlEncode() ?? metaData)"
        }
        
        if let hiveCallKey = hiveCallKey {
            url = url + "&callKey=\(hiveCallKey.urlEncode() ?? hiveCallKey)"
        }
        
        if isHost {
            url = url + "&isHost=true"
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
                let json = JSON(data)
                if let serverUrl = json["serverUrl"].string,
                   let token = json["participantToken"].string {
                    callback(serverUrl, token)
                } else {
                    errorCallback("Error getting response data")
                }
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
    
    func getCallParticipants(
        roomName: String,
        callback: @escaping ([BubbleMessageLayoutState.CallParticipantInfo]) -> Void,
        errorCallback: ((String) -> Void)? = nil
    ) {
        let url = "\(self.kVideoCallServer)/api/participants?roomName=\(roomName.urlEncode() ?? roomName)"
        let request: URLRequest? = createRequest(url, params: nil, method: "GET")
        guard let request = request else {
            errorCallback?("Error creating request")
            callback([])
            return
        }
        sphinxRequest(request) { response in
            switch response.result {
            case .success(let data):
                let json = JSON(data)
                var participants: [BubbleMessageLayoutState.CallParticipantInfo] = []
                for (_, item) in json {
                    let name = item["nickname"].stringValue
                    guard !name.isEmpty else { continue }
                    participants.append(BubbleMessageLayoutState.CallParticipantInfo(
                        identity: name,
                        name: name,
                        profilePictureUrl: item["avatarUrl"].string,
                        isActive: true
                    ))
                }
                callback(participants)
            case .failure(let error):
                errorCallback?(error.localizedDescription)
                callback([])
            }
        }
    }

    func removeParticipant(
        room: String,
        participantIdentity: String,
        adminToken: String,
        callback: @escaping (Bool) -> Void
    ) {
        guard let url = URL(string: "\(self.kVideoCallServer)/api/remove-participant") else {
            callback(false); return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(adminToken)", forHTTPHeaderField: "Authorization")
        let body = ["roomName": room, "participantIdentity": participantIdentity]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request) { _, response, error in
            guard error == nil,
                  let http = response as? HTTPURLResponse,
                  http.statusCode == 200 else { callback(false); return }
            callback(true)
        }.resume()
    }
}
