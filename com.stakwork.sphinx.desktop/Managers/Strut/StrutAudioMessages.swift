//
//  StrutAudioMessages.swift
//  com.stakwork.sphinx.desktop
//
//  JSON encode/decode helpers for the `/audio/stream` text protocol.
//  Optional fields (model, partialModel, hotwords, session, endpoint) are omitted.
//

import Foundation

enum StrutServerMessage: Equatable, Sendable {
    case ready
    case partial(text: String)
    case final(text: String, index: Int)
    case error(message: String)
}

enum StrutAudioMessages {

    /// Encodes `{"type":"start","sampleRate":<Int>}`.
    /// Caller must pass `Int(format.sampleRate.rounded())` — never a raw `Double`.
    static func encodeStart(sampleRate: Int) -> Data {
        let payload: [String: Any] = [
            "type": "start",
            "sampleRate": sampleRate
        ]
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    }

    /// Encodes `{"type":"end"}`.
    static func encodeEnd() -> Data {
        let payload: [String: Any] = ["type": "end"]
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    }

    /// Decode a server text frame by `type`. Unknown or malformed payloads return `nil`.
    static func decodeServerMessage(_ data: Data) -> StrutServerMessage? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = object["type"] as? String
        else {
            return nil
        }

        switch type {
        case "ready":
            return .ready
        case "partial":
            guard let text = object["text"] as? String else { return nil }
            return .partial(text: text)
        case "final":
            guard let text = object["text"] as? String else { return nil }
            let index = intValue(object["index"]) ?? 0
            return .final(text: text, index: index)
        case "error":
            let message = (object["message"] as? String)
                ?? (object["error"] as? String)
                ?? ""
            return .error(message: message)
        default:
            return nil
        }
    }

    private static func intValue(_ raw: Any?) -> Int? {
        if let value = raw as? Int { return value }
        if let number = raw as? NSNumber { return number.intValue }
        return nil
    }
}
