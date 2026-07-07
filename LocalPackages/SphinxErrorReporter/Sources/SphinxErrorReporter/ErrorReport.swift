// ErrorReport.swift
// SphinxErrorReporter
//
// Codable model matching the Hive /api/webhook/errors contract exactly.
// Required: exceptionType, message
// Optional: stackTrace, frames, environment, release, commitSha, repository,
//           requestContext, metadata, fingerprint
// frames is omitted (not sent as empty array) when nil/empty.
// fingerprint is omitted by default.

import Foundation

/// A single structured stack frame.
public struct Frame: Codable, Sendable {
    public let filename: String
    public let function: String?
    public let lineno: Int?
    public let inApp: Bool?

    public init(
        filename: String,
        function: String? = nil,
        lineno: Int? = nil,
        inApp: Bool? = nil
    ) {
        self.filename = filename
        self.function = function
        self.lineno = lineno
        self.inApp = inApp
    }

    // Explicit CodingKeys to ensure exact 4-key JSON shape (omits nil fields)
    enum CodingKeys: String, CodingKey {
        case filename, function, lineno, inApp
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(filename, forKey: .filename)
        try container.encodeIfPresent(function, forKey: .function)
        try container.encodeIfPresent(lineno, forKey: .lineno)
        try container.encodeIfPresent(inApp, forKey: .inApp)
    }
}

/// Full error report payload matching the Hive webhook contract.
public struct ErrorReport: Codable, Sendable {
    // MARK: Required
    public let exceptionType: String
    public let message: String

    // MARK: Optional
    public let stackTrace: String?
    public let frames: [Frame]?          // omit when nil/empty
    public let environment: String?
    public let release: String?
    public let commitSha: String?
    public let repository: String?
    public let requestContext: [String: AnyCodable]?
    public let metadata: [String: AnyCodable]?
    public let fingerprint: String?      // omit by default

    public init(
        exceptionType: String,
        message: String,
        stackTrace: String? = nil,
        frames: [Frame]? = nil,
        environment: String? = nil,
        release: String? = nil,
        commitSha: String? = nil,
        repository: String? = nil,
        requestContext: [String: Any]? = nil,
        metadata: [String: Any]? = nil,
        fingerprint: String? = nil
    ) {
        self.exceptionType = exceptionType
        self.message = message
        self.stackTrace = stackTrace
        self.frames = (frames?.isEmpty == true) ? nil : frames
        self.environment = environment
        self.release = release
        self.commitSha = commitSha
        self.repository = repository
        self.requestContext = requestContext?.mapValues { AnyCodable($0) }
        self.metadata = metadata?.mapValues { AnyCodable($0) }
        self.fingerprint = fingerprint
    }

    enum CodingKeys: String, CodingKey {
        case exceptionType, message, stackTrace, frames,
             environment, release, commitSha, repository,
             requestContext, metadata, fingerprint
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(exceptionType, forKey: .exceptionType)
        try container.encode(message, forKey: .message)
        try container.encodeIfPresent(stackTrace, forKey: .stackTrace)
        if let frames = frames, !frames.isEmpty {
            try container.encode(frames, forKey: .frames)
        }
        try container.encodeIfPresent(environment, forKey: .environment)
        try container.encodeIfPresent(release, forKey: .release)
        try container.encodeIfPresent(commitSha, forKey: .commitSha)
        try container.encodeIfPresent(repository, forKey: .repository)
        try container.encodeIfPresent(requestContext, forKey: .requestContext)
        try container.encodeIfPresent(metadata, forKey: .metadata)
        try container.encodeIfPresent(fingerprint, forKey: .fingerprint)
    }
}

// MARK: - AnyCodable helper (type-erased JSON value)

/// Type-erased Codable wrapper for heterogeneous JSON dictionaries.
public struct AnyCodable: Codable, Sendable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            let wrapped = array.map { AnyCodable($0) }
            try container.encode(wrapped)
        case let dict as [String: Any]:
            let wrapped = dict.mapValues { AnyCodable($0) }
            try container.encode(wrapped)
        default:
            try container.encodeNil()
        }
    }
}
