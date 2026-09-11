//
//  StrutReadyLine.swift
//  com.stakwork.sphinx.desktop
//
//  Pure parser for the single JSON ready line emitted on Strut stdout.
//  Never invents fields; invalid input decodes to nil.
//

import Foundation

struct StrutReadyLine: Equatable, Sendable {
    let host: String
    let port: Int
    let key: String

    /// Decode one stdout line into a validated ready payload.
    /// Returns `nil` for malformed JSON, wrong event, missing fields,
    /// non-loopback host, out-of-range port, or empty key.
    static func parse(_ line: String) -> StrutReadyLine? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            return nil
        }
        guard let raw = try? JSONDecoder().decode(Raw.self, from: data) else {
            return nil
        }
        guard raw.event == "ready" else { return nil }

        let host = raw.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard StrutURLSchemePolicy.isLoopbackHost(host) else { return nil }
        guard (1...65535).contains(raw.port) else { return nil }

        let key = raw.key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }

        return StrutReadyLine(host: host, port: raw.port, key: key)
    }

    /// Scan multi-line stdout and return the first valid ready line.
    /// Garbage / extra lines are ignored.
    static func firstValidLine(in text: String) -> StrutReadyLine? {
        for line in text.split(whereSeparator: \.isNewline) {
            if let parsed = parse(String(line)) {
                return parsed
            }
        }
        return nil
    }

    private struct Raw: Decodable {
        let event: String
        let port: Int
        let host: String
        let key: String
    }
}
