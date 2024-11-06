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

import Combine
import KeychainAccess
import LiveKit
import SwiftUI

struct Preferences: Codable, Equatable {
    var url = ""
    var token = ""
    var e2eeKey = ""
    var isE2eeEnabled = false

    // Connect options
    var autoSubscribe = true

    // Room options
    var simulcast = true
    var adaptiveStream = true
    var dynacast = true
    var reportStats = true

    // Settings
    var videoViewVisible = true
    var showInformationOverlay = false
    var preferSampleBufferRendering = false
    var videoViewMode: VideoView.LayoutMode = .fit
    var videoViewMirrored = false

    var connectionHistory = Set<ConnectionHistory>()
}

let encoder = JSONEncoder()
let decoder = JSONDecoder()

class ValueStore<T: Codable & Equatable>: ObservableObject {
    private let store: Keychain
    private let key: String
    private let message = ""
    private weak var timer: Timer?

    public var value: T {
        didSet {
            guard oldValue != value else { return }
            lazySync()
        }
    }

    private var storeWithOptions: Keychain {
        store
            .accessibility(.whenUnlocked)
            .synchronizable(true)
    }

    public init(store: Keychain, key: String, default: T) {
        self.store = store
        self.key = key
        
        value = `default`

        if let data = try? storeWithOptions.getData(key) {
            if let result = try? decoder.decode(T.self, from: data) {
                value = result
            }
        }
    }

    deinit {
        timer?.invalidate()
    }

    public func lazySync() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1,
                                     repeats: false,
                                     block: { _ in self.sync() })
    }

    public func sync() {
        do {
            let data = try encoder.encode(value)
            try storeWithOptions.set(data, key: key)
        } catch {
            print("Failed to write in Keychain, error: \(error)")
        }
    }
}

struct ConnectionHistory: Codable {
    let updated: Date
    let url: String
    let token: String
    let e2ee: Bool
    let e2eeKey: String
    let roomSid: Room.Sid?
    let roomName: String?
    let participantSid: Participant.Sid?
    let participantIdentity: Participant.Identity?
    let participantName: String?
}

extension ConnectionHistory: CustomStringConvertible {
    var description: String {
        var segments: [String] = []
        if let roomName {
            segments.append(String(describing: roomName))
        }
        if let participantIdentity {
            segments.append(String(describing: participantIdentity))
        }
        segments.append(url)
        return segments.joined(separator: " ")
    }
}

extension ConnectionHistory: Identifiable {
    var id: Int {
        hashValue
    }
}

extension ConnectionHistory: Hashable, Equatable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
        hasher.combine(token)
    }

    static func == (lhs: ConnectionHistory, rhs: ConnectionHistory) -> Bool {
        lhs.url == rhs.url && lhs.token == rhs.token
    }
}

extension Sequence<ConnectionHistory> {
    var sortedByUpdated: [ConnectionHistory] {
        Array(self).sorted { $0.updated > $1.updated }
    }
}

extension Set<ConnectionHistory> {
    mutating func update(room: Room, e2ee: Bool, e2eeKey: String) {
        guard let url = room.url,
              let token = room.token else { return }

        let element = ConnectionHistory(
            updated: Date(),
            url: url,
            token: token,
            e2ee: e2ee,
            e2eeKey: e2eeKey,
            roomSid: room.sid,
            roomName: room.name,
            participantSid: room.localParticipant.sid,
            participantIdentity: room.localParticipant.identity,
            participantName: room.localParticipant.name
        )

        update(with: element)
    }
}
