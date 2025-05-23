/*
 * Copyright 2024 LiveKit
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import LiveKit
import SwiftyJSON
import SwiftUI

public extension Participant {
    var mainVideoPublication: TrackPublication? {
        firstScreenSharePublication ?? firstCameraPublication
    }

    var mainVideoTrack: VideoTrack? {
        firstScreenShareVideoTrack ?? firstCameraVideoTrack
    }

    var subVideoTrack: VideoTrack? {
        firstScreenShareVideoTrack != nil ? firstCameraVideoTrack : nil
    }
    
    var profilePictureUrl: String? {
        get {
            if let data = metadata?.data(using: .utf8) {
                let json = JSON(data)
                
                if let profilePictureUrl = json["profilePictureUrl"].string, profilePictureUrl.isNotEmpty {
                    return profilePictureUrl
                }
            }
            return nil
        }
    }    
}
