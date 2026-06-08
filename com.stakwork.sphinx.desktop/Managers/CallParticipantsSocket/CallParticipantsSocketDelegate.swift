//
//  CallParticipantsSocketDelegate.swift
//  Sphinx
//
//  Created by Sphinx on 08/06/2026.
//  Copyright © 2026 sphinx. All rights reserved.
//

import Foundation

protocol CallParticipantsSocketDelegate: AnyObject {
    func didReceiveCurrentParticipants(roomName: String, participants: [BubbleMessageLayoutState.CallParticipantInfo])
    func participantJoined(roomName: String, participant: BubbleMessageLayoutState.CallParticipantInfo)
    func participantLeft(roomName: String, identity: String)
    func roomFinished(roomName: String)
}
