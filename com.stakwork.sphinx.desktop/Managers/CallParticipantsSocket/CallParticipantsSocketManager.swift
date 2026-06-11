//
//  CallParticipantsSocketManager.swift
//  Sphinx
//
//  Created by Sphinx on 08/06/2026.
//  Copyright © 2026 sphinx. All rights reserved.
//

import Foundation
import Starscream

class CallParticipantsSocketManager: NSObject, WebSocketDelegate, @unchecked Sendable {

    var socket: WebSocketClient?
    var subscribedRooms: Set<String> = []
    weak var delegate: CallParticipantsSocketDelegate?

    // MARK: - Connection

    private func buildSocketURL() -> URL? {
        var server = API.sharedInstance.kVideoCallServer
        if server.hasPrefix("https://") {
            server = "wss://" + server.dropFirst("https://".count)
        } else if server.hasPrefix("http://") {
            server = "ws://" + server.dropFirst("http://".count)
        }
        server = server + "/ws"
        return URL(string: server)
    }

    private func connect() {
        guard socket == nil else { return }
        guard let url = buildSocketURL() else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        let ws = WebSocket(request: request)
        ws.delegate = self
        socket = ws
        ws.connect()
    }

    private func disconnect() {
        socket?.disconnect()
        socket = nil
    }

    // MARK: - Public API

    func subscribe(roomName: String) {
        subscribedRooms.insert(roomName)
        if socket == nil {
            connect()
        } else {
            sendSubscribe(roomName: roomName)
        }
    }
    
    func sendSubscribeTo(roomName: String) {
        sendSubscribe(roomName: roomName)
    }

    func unsubscribe(roomName: String) {
        sendUnsubscribe(roomName: roomName)
        subscribedRooms.remove(roomName)
        if subscribedRooms.isEmpty {
            disconnect()
        }
    }

    // MARK: - Private helpers

    private func sendSubscribe(roomName: String) {
        let payload: [String: Any] = ["action": "subscribe", "roomName": roomName]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return }
        socket?.write(string: text)
    }

    private func sendUnsubscribe(roomName: String) {
        let payload: [String: Any] = ["action": "unsubscribe", "roomName": roomName]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return }
        socket?.write(string: text)
    }

    // MARK: - WebSocketDelegate

    func websocketDidConnect(socket: WebSocketClient) {
        // Re-subscribe all rooms on reconnect
        for roomName in subscribedRooms {
            sendSubscribe(roomName: roomName)
        }
    }

    func websocketDidDisconnect(socket: WebSocketClient, error: Error?) {
        // No auto-reconnect; reconnect happens on next subscribe call
        self.socket = nil
    }

    func websocketDidReceiveMessage(socket: WebSocketClient, text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String,
              let roomName = json["roomName"] as? String else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            switch type {
            case "current_participants":
                let participants = self.parseParticipants(from: json)
                self.delegate?.didReceiveCurrentParticipants(roomName: roomName, participants: participants)

            case "participant_joined":
                if let participant = self.parseParticipant(from: json) {
                    self.delegate?.participantJoined(roomName: roomName, participant: participant)
                }

            case "participant_left":
                let identity = (json["identity"] as? String) ?? ""
                self.delegate?.participantLeft(roomName: roomName, identity: identity)

            case "room_finished":
                self.delegate?.roomFinished(roomName: roomName)

            default:
                break
            }
        }
    }

    func websocketDidReceiveData(socket: WebSocketClient, data: Data) {
        // Not used
    }

    // MARK: - Parsing helpers

    private func parseParticipants(from json: [String: Any]) -> [BubbleMessageLayoutState.CallParticipantInfo] {
        guard let list = json["participants"] as? [[String: Any]] else { return [] }
        return list.compactMap { parseParticipantDict($0) }
    }

    private func parseParticipant(from json: [String: Any]) -> BubbleMessageLayoutState.CallParticipantInfo? {
        guard let participant = json["participant"] as? [String: Any] else {
            // participant fields may be at top level
            return parseParticipantDict(json)
        }
        return parseParticipantDict(participant)
    }

    private func parseParticipantDict(_ dict: [String: Any]) -> BubbleMessageLayoutState.CallParticipantInfo? {
        guard let nickname = dict["nickname"] as? String else { return nil }
        let identity = dict["identity"] as? String
        let avatarUrl = dict["avatarUrl"] as? String
        return BubbleMessageLayoutState.CallParticipantInfo(
            identity: identity ?? nickname,
            name: nickname,
            profilePictureUrl: avatarUrl,
            isActive: true
        )
    }
}
