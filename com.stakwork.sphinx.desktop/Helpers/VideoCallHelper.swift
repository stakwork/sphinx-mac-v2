//
//  VideoCallHelper.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 10/07/2020.
//  Copyright © 2020 Sphinx. All rights reserved.
//

import Cocoa

class VideoCallHelper {
    
    public enum CallMode: Int {
        case Audio
        case All
    }
    
    public static func getCallMode(link: String) -> CallMode {
        var mode = CallMode.All
        
        if link.contains("startAudioOnly") {
            mode = CallMode.Audio
        }
        
        return mode
    }
    
    public static func createCallMessage(
        mode: CallMode,
        secondBrainUrl: String? = nil,
        appUrl: String? = nil
    ) -> String {
        let time = Date.timeIntervalSinceReferenceDate
        var graphUrl: String? = nil
        
        if let secondBrainUrl = secondBrainUrl, !secondBrainUrl.isEmpty {
            if let url = URL(string: secondBrainUrl), let host = url.host {
                graphUrl = host
            } else {
                graphUrl = secondBrainUrl
            }
        } else if let appUrl = appUrl, !appUrl.isEmpty {
            if let url = URL(string: appUrl), let host = url.host {
                graphUrl = host
            } else {
                graphUrl = appUrl
            }
        }
        
        var room = "\(API.sharedInstance.kVideoCallServer)/rooms\(TransactionMessage.kCallRoomName).\(time)"
        
        if let graphUrl = graphUrl {
            room = "\(API.sharedInstance.kVideoCallServer)/rooms\(TransactionMessage.kCallRoomName).-\(graphUrl)-.\(time)"
        }
        
        if mode == .Audio {
            return room + "?startAudioOnly=true"
        }
        return room
    }
    
}
