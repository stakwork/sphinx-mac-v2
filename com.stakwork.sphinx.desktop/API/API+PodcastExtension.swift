//
//  APIPodcastExtension.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 14/10/2020.
//  Copyright © 2020 Sphinx. All rights reserved.
//

import Foundation
import Alamofire
import SwiftyJSON
import ObjectMapper

extension API {
    typealias PodcastFeedCallback = ((JSON) -> ())
    typealias PodcastInfoCallback = ((JSON) -> ())
    
    func getPodcastFeed(
        url: String,
        callback: @escaping PodcastFeedCallback,
        errorCallback: @escaping EmptyCallback
    ){
        guard let request = createRequest(url, params: nil, method: "GET") else {
            errorCallback()
            return
        }
        
        sphinxRequest(request) { response in
            switch response.result {
            case .success(let data):
                if let json = data as? NSDictionary {
                    callback(JSON(json))
                    return
                }
                errorCallback()
            case .failure(_):
                errorCallback()
            }
        }
    }
    
    func getContentFeed(
        url: String,
        callback: @escaping ContentFeedCallback,
        errorCallback: @escaping EmptyCallback
    ) {
        guard let request = createRequest(url, params: nil, method: "GET") else {
            errorCallback()
            return
        }
        
        sphinxRequest(request) { response in
            if let data = response.data {
                callback(JSON(data))
            } else {
                errorCallback()
            }
        }
    }
    
    func getPodcastInfo(
        podcastId: Int,
        callback: @escaping PodcastInfoCallback,
        errorCallback: @escaping EmptyCallback
    ) {
        let url = "https://tribes.sphinx.chat/podcast?id=\(podcastId)"
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
