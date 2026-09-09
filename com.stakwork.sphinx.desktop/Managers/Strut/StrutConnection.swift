//
//  StrutConnection.swift
//  com.stakwork.sphinx.desktop
//
//  Process-wide owner of live strut connection config (base URL + API key)
//  and an unauthenticated GET /health reachability probe.
//  Does not spawn, bundle, or manage a strut process.
//

import Foundation

protocol StrutSecretStore: Sendable {
    func get() -> String?
    func set(_ value: String)
    func delete()
}

/// Production adapter: machine-local strut API key in the existing sphinx-app keychain.
/// Uses the raw composed key (`mac.strut_api_key`) — not accountUUID-prefixed, not PIN-wrapped.
struct KeychainStrutSecretStore: StrutSecretStore {
    func get() -> String? {
        KeychainManager.sharedInstance.getValueFor(
            composedKey: KeychainManager.KeychainKeys.strutApiKey.rawValue
        )
    }

    func set(_ value: String) {
        let _ = KeychainManager.sharedInstance.save(
            value: value,
            forComposedKey: KeychainManager.KeychainKeys.strutApiKey.rawValue
        )
    }

    func delete() {
        let _ = KeychainManager.sharedInstance.deleteValueFor(
            composedKey: KeychainManager.KeychainKeys.strutApiKey.rawValue
        )
    }
}

enum StrutHealthResult: Equatable, Sendable {
    case reachable
    case unreachable(Reason)

    enum Reason: Equatable, Sendable {
        case invalidURL
        case connectionRefused
        case timeout
        case httpStatus(Int)
    }
}

struct StrutReadyConnection: Equatable, Sendable {
    let baseURL: URL
    let authorizationHeaderValue: String
}

enum StrutNotReady: Error, Equatable, Sendable {
    case unreachable(StrutHealthResult.Reason)
    case missingAPIKey
}

/// `@unchecked Sendable` because this is a process-wide singleton whose mutable
/// state lives in UserDefaults, Keychain, and URLSession rather than in-memory
/// stored properties — the same pattern as `API` and `KeychainManager`.
class StrutConnection: @unchecked Sendable {

    static let defaultBaseURLString = "http://127.0.0.1:51234"

    private static let baseURLDefaultsKey = "strutBaseURL"
    private static let healthTimeout: TimeInterval = 3

    nonisolated(unsafe) static let shared = StrutConnection()

    private let userDefaults: UserDefaults
    private let secretStore: any StrutSecretStore
    private let urlSession: URLSession

    init(
        userDefaults: UserDefaults = .standard,
        secretStore: any StrutSecretStore = KeychainStrutSecretStore(),
        urlSession: URLSession = StrutConnection.makeEphemeralSession()
    ) {
        self.userDefaults = userDefaults
        self.secretStore = secretStore
        self.urlSession = urlSession
    }

    static func makeEphemeralSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = healthTimeout
        configuration.timeoutIntervalForResource = healthTimeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    // MARK: - Live config (recomputed on every access)

    var baseURLString: String {
        get {
            let stored = (userDefaults.string(forKey: Self.baseURLDefaultsKey) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return stored.isEmpty ? Self.defaultBaseURLString : stored
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                userDefaults.removeObject(forKey: Self.baseURLDefaultsKey)
            } else {
                userDefaults.set(trimmed, forKey: Self.baseURLDefaultsKey)
            }
        }
    }

    var apiKey: String {
        get {
            secretStore.get() ?? ""
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                secretStore.delete()
            } else {
                secretStore.set(trimmed)
            }
        }
    }

    var authorizationHeaderValue: String? {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return "Bearer \(trimmed)"
    }

    var healthURL: URL? {
        resolvedBaseURL?.appendingPathComponent("health")
    }

    /// Parsed, scheme-normalized base URL (no trailing slash, no `/health` path).
    var resolvedBaseURL: URL? {
        parseBaseURL(from: baseURLString)
    }

    /// 1. Trim. 2. Parse; if there is no usable scheme/host, prepend `http://`.
    /// 3. Require a non-empty host. 4. Strip a trailing slash.
    /// Do not string-concat `{base}/health` and do not use `API.getUrl(route:)`.
    private func parseBaseURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Foundation treats `127.0.0.1:51234` as scheme `127.0.0.1` with no host.
        // A scheme is only "present" when the first parse already has a host.
        let candidate: String
        if let url = URL(string: trimmed),
           let scheme = url.scheme, !scheme.isEmpty,
           let host = url.host, !host.isEmpty {
            candidate = trimmed
        } else {
            candidate = "http://\(trimmed)"
        }

        guard let parsed = URL(string: candidate),
              let host = parsed.host, !host.isEmpty else {
            return nil
        }

        var absolute = parsed.absoluteString
        if absolute.hasSuffix("/") {
            absolute.removeLast()
            guard let stripped = URL(string: absolute),
                  let strippedHost = stripped.host, !strippedHost.isEmpty else {
                return nil
            }
            return stripped
        }
        return parsed
    }

    // MARK: - Health check

    func checkHealth() async -> StrutHealthResult {
        AppLogger.shared.log(level: .info, message: "[StrutConnection] Health check started")

        // Capture the resolved health URL at the start so a setter mid-flight
        // cannot retarget this probe's success onto a different base.
        guard let capturedHealthURL = healthURL else {
            AppLogger.shared.log(
                level: .error,
                message: "[StrutConnection] Health check failed: invalid URL"
            )
            return .unreachable(.invalidURL)
        }

        var request = URLRequest(
            url: capturedHealthURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: Self.healthTimeout
        )
        request.httpMethod = "GET"

        do {
            let (_, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                AppLogger.shared.log(
                    level: .error,
                    message: "[StrutConnection] Health check failed: connection refused"
                )
                return .unreachable(.connectionRefused)
            }

            if (200...299).contains(http.statusCode) {
                AppLogger.shared.log(
                    level: .info,
                    message: "[StrutConnection] Health check succeeded with HTTP status \(http.statusCode)"
                )
                return .reachable
            }

            AppLogger.shared.log(
                level: .error,
                message: "[StrutConnection] Health check failed: HTTP status \(http.statusCode)"
            )
            return .unreachable(.httpStatus(http.statusCode))
        } catch {
            let reason = mapHealthFailure(error)
            AppLogger.shared.log(
                level: .error,
                message: "[StrutConnection] Health check failed: \(healthFailureLogDescription(reason))"
            )
            return .unreachable(reason)
        }
    }

    // MARK: - Ready-connection gate

    func readyConnection() async -> Result<StrutReadyConnection, StrutNotReady> {
        switch await checkHealth() {
        case .unreachable(let reason):
            return .failure(.unreachable(reason))
        case .reachable:
            guard let authorizationHeaderValue else {
                return .failure(.missingAPIKey)
            }
            guard let baseURL = resolvedBaseURL else {
                return .failure(.unreachable(.invalidURL))
            }
            return .success(
                StrutReadyConnection(
                    baseURL: baseURL,
                    authorizationHeaderValue: authorizationHeaderValue
                )
            )
        }
    }

    // MARK: - Mapping / logging helpers

    private func mapHealthFailure(_ error: Error) -> StrutHealthResult.Reason {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return .timeout
            case .cannotConnectToHost:
                return .connectionRefused
            default:
                // URLError.Code.connectionRefused is not a Foundation case;
                // POSIX ECONNREFUSED is handled below.
                break
            }
        }

        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == Int(ECONNREFUSED) {
            return .connectionRefused
        }
        if nsError.domain == NSURLErrorDomain {
            if nsError.code == NSURLErrorTimedOut {
                return .timeout
            }
            if nsError.code == NSURLErrorCannotConnectToHost {
                return .connectionRefused
            }
        }
        // No HTTP status available — fold remaining transport failures into
        // connection refused rather than inventing a new reason case.
        return .connectionRefused
    }

    private func healthFailureLogDescription(_ reason: StrutHealthResult.Reason) -> String {
        switch reason {
        case .invalidURL:
            return "invalid URL"
        case .connectionRefused:
            return "connection refused"
        case .timeout:
            return "timeout"
        case .httpStatus(let status):
            return "HTTP status \(status)"
        }
    }
}
