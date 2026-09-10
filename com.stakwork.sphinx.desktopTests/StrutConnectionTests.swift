//
//  StrutConnectionTests.swift
//  com.stakwork.sphinx.desktopTests
//
//  Host-backed unit tests for StrutConnection. Injects UserDefaults(suiteName:)
//  and an in-memory StrutSecretStore — never UserDefaults.standard or the
//  real sphinx-app keychain.
//

import XCTest
@testable import com_stakwork_sphinx_desktop

/// In-memory stand-in for KeychainStrutSecretStore. `@unchecked Sendable`
/// because tests mutate a single-thread dictionary, never the system keychain.
final class InMemoryStrutSecretStore: StrutSecretStore, @unchecked Sendable {
    private var value: String?

    func get() -> String? { value }

    func set(_ value: String) {
        self.value = value
    }

    func delete() {
        value = nil
    }
}

final class StrutConnectionTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var secretStore: InMemoryStrutSecretStore!

    override func setUp() {
        super.setUp()
        suiteName = "StrutConnectionTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        secretStore = InMemoryStrutSecretStore()
        StrutURLProtocolStub.reset()
        StrutConnection.releaseDictationOccupancy()
        StrutConnection.resetHotwordsSeeded()
    }

    override func tearDown() {
        StrutConnection.releaseDictationOccupancy()
        StrutConnection.resetHotwordsSeeded()
        if let suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        secretStore = nil
        suiteName = nil
        StrutURLProtocolStub.reset()
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StrutURLProtocolStub.self]
        configuration.timeoutIntervalForRequest = 3
        configuration.timeoutIntervalForResource = 3
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    private func makeConnection() -> StrutConnection {
        StrutConnection(
            userDefaults: defaults,
            secretStore: secretStore,
            urlSession: makeSession()
        )
    }

    // MARK: - Dictation occupancy

    func testDictationOccupancy_SecondAcquireFailsUntilRelease() {
        StrutConnection.releaseDictationOccupancy()
        defer { StrutConnection.releaseDictationOccupancy() }

        XCTAssertTrue(StrutConnection.tryAcquireDictationOccupancy())
        XCTAssertFalse(
            StrutConnection.tryAcquireDictationOccupancy(),
            "A second VM must not occupy dictation while the first holds it"
        )
        StrutConnection.releaseDictationOccupancy()
        XCTAssertTrue(
            StrutConnection.tryAcquireDictationOccupancy(),
            "Occupancy must be reusable after release"
        )
    }

    func testDictationOccupancy_ReleaseWithoutAcquireIsSafe() {
        StrutConnection.releaseDictationOccupancy()
        StrutConnection.releaseDictationOccupancy()
        XCTAssertTrue(StrutConnection.tryAcquireDictationOccupancy())
        StrutConnection.releaseDictationOccupancy()
    }

    func testTryMarkHotwordsSeeded_ReturnsTrueExactlyOnce() {
        StrutConnection.resetHotwordsSeeded()
        defer { StrutConnection.resetHotwordsSeeded() }

        XCTAssertTrue(StrutConnection.tryMarkHotwordsSeeded())
        XCTAssertFalse(
            StrutConnection.tryMarkHotwordsSeeded(),
            "Hotword seed must be process-once"
        )
        XCTAssertFalse(StrutConnection.tryMarkHotwordsSeeded())
    }

    // MARK: - 1. Default / persisted base URL

    func testBaseURL_DefaultsWhenUnset() {
        let connection = makeConnection()
        XCTAssertEqual(connection.baseURLString, StrutConnection.defaultBaseURLString)
        XCTAssertEqual(connection.baseURLString, "http://127.0.0.1:51234")
    }

    func testBaseURL_DefaultsWhenEmpty() {
        let connection = makeConnection()
        connection.baseURLString = "http://10.0.0.1:9"
        connection.baseURLString = ""
        XCTAssertEqual(connection.baseURLString, StrutConnection.defaultBaseURLString)
        XCTAssertNil(defaults.string(forKey: "strutBaseURL"))
    }

    func testBaseURL_DefaultsWhenWhitespaceOnly() {
        let connection = makeConnection()
        connection.baseURLString = "   \n\t  "
        XCTAssertEqual(connection.baseURLString, StrutConnection.defaultBaseURLString)
        XCTAssertNil(defaults.string(forKey: "strutBaseURL"))
    }

    func testBaseURL_PersistedRoundTrip() {
        let connection = makeConnection()
        connection.baseURLString = "  http://10.0.0.2:51234  "
        XCTAssertEqual(connection.baseURLString, "http://10.0.0.2:51234")
        XCTAssertEqual(defaults.string(forKey: "strutBaseURL"), "http://10.0.0.2:51234")

        let reread = makeConnection()
        XCTAssertEqual(reread.baseURLString, "http://10.0.0.2:51234")
    }

    // MARK: - 2. API key / Authorization header

    func testAPIKey_RoundTripViaInMemoryStore() {
        let connection = makeConnection()
        XCTAssertEqual(connection.apiKey, "")
        XCTAssertNil(connection.authorizationHeaderValue)

        connection.apiKey = "  secret-key  "
        XCTAssertEqual(connection.apiKey, "secret-key")
        XCTAssertEqual(connection.authorizationHeaderValue, "Bearer secret-key")
        XCTAssertEqual(secretStore.get(), "secret-key")
    }

    func testAPIKey_EmptyOrWhitespaceClearsAuthorizationHeader() {
        let connection = makeConnection()
        connection.apiKey = "present"
        XCTAssertEqual(connection.authorizationHeaderValue, "Bearer present")

        connection.apiKey = "   "
        XCTAssertEqual(connection.apiKey, "")
        XCTAssertNil(connection.authorizationHeaderValue)
        XCTAssertNil(secretStore.get())

        connection.apiKey = "present-again"
        connection.apiKey = ""
        XCTAssertNil(connection.authorizationHeaderValue)
        XCTAssertNil(secretStore.get())
    }

    func testAuthorizationHeaderValue_NeverEmitsBareBearer() {
        let connection = makeConnection()
        connection.apiKey = ""
        XCTAssertNil(connection.authorizationHeaderValue)
        connection.apiKey = "\t"
        XCTAssertNotEqual(connection.authorizationHeaderValue, "Bearer ")
        XCTAssertNil(connection.authorizationHeaderValue)
    }

    // MARK: - 3. URL construction

    func testHealthURL_SchemeLessHostPortIsNormalizedToHTTP() {
        let connection = makeConnection()
        connection.baseURLString = "127.0.0.1:51234"
        XCTAssertEqual(
            connection.healthURL?.absoluteString,
            "http://127.0.0.1:51234/health"
        )
        XCTAssertEqual(
            connection.resolvedBaseURL?.absoluteString,
            "http://127.0.0.1:51234"
        )
    }

    func testHealthURL_PathOnlyIsInvalid() async {
        let connection = makeConnection()
        connection.baseURLString = "/health"
        XCTAssertNil(connection.healthURL)

        let result = await connection.checkHealth()
        XCTAssertEqual(result, .unreachable(.invalidURL))
        XCTAssertEqual(StrutURLProtocolStub.requestCount, 0)
    }

    func testHealthURL_UnparseableIsInvalidWithNoNetworkCall() async {
        let connection = makeConnection()
        connection.baseURLString = "not a url"
        XCTAssertNil(connection.healthURL)

        let result = await connection.checkHealth()
        XCTAssertEqual(result, .unreachable(.invalidURL))
        XCTAssertEqual(StrutURLProtocolStub.requestCount, 0)
    }

    func testHealthURL_StripsTrailingSlashOnBase() {
        let connection = makeConnection()
        connection.baseURLString = "http://127.0.0.1:51234/"
        XCTAssertEqual(
            connection.healthURL?.absoluteString,
            "http://127.0.0.1:51234/health"
        )
    }

    // MARK: - 4. Health request assembly

    func testCheckHealth_GETHasNoAuthorizationAndTargetsHealthPath() async {
        StrutURLProtocolStub.response = .init(statusCode: 200)
        let connection = makeConnection()
        connection.baseURLString = "http://127.0.0.1:51234"
        connection.apiKey = "must-not-be-sent-on-health"

        let result = await connection.checkHealth()
        XCTAssertEqual(result, .reachable)

        let request = StrutURLProtocolStub.lastRequest
        XCTAssertEqual(request?.httpMethod, "GET")
        XCTAssertEqual(request?.url?.absoluteString, "http://127.0.0.1:51234/health")
        XCTAssertNil(request?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(request?.cachePolicy, .reloadIgnoringLocalCacheData)
    }

    // MARK: - 5. checkHealth() mapping

    func testCheckHealth_2xxIsReachable() async {
        StrutURLProtocolStub.response = .init(statusCode: 204)
        let connection = makeConnection()
        let result = await connection.checkHealth()
        XCTAssertEqual(result, .reachable)
    }

    func testCheckHealth_ConnectionRefused() async {
        StrutURLProtocolStub.response = .init(
            error: URLError(.cannotConnectToHost)
        )
        let connection = makeConnection()
        let result = await connection.checkHealth()
        XCTAssertEqual(result, .unreachable(.connectionRefused))
    }

    func testCheckHealth_Timeout() async {
        StrutURLProtocolStub.response = .init(error: URLError(.timedOut))
        let connection = makeConnection()
        let result = await connection.checkHealth()
        XCTAssertEqual(result, .unreachable(.timeout))
    }

    func testCheckHealth_5xxMapsToHTTPStatus() async {
        StrutURLProtocolStub.response = .init(statusCode: 503)
        let connection = makeConnection()
        let result = await connection.checkHealth()
        XCTAssertEqual(result, .unreachable(.httpStatus(503)))
    }

    // MARK: - 6. readyConnection()

    func testReadyConnection_ReachableEmptyKeyIsMissingAPIKey() async {
        StrutURLProtocolStub.response = .init(statusCode: 200)
        let connection = makeConnection()
        connection.apiKey = ""

        let result = await connection.readyConnection()
        XCTAssertEqual(result, .failure(.missingAPIKey))
    }

    func testReadyConnection_ReachableWithKeySucceedsWithBearer() async {
        StrutURLProtocolStub.response = .init(statusCode: 200)
        let connection = makeConnection()
        connection.apiKey = "dictation-key"

        let result = await connection.readyConnection()
        switch result {
        case .success(let ready):
            XCTAssertEqual(ready.authorizationHeaderValue, "Bearer dictation-key")
            XCTAssertFalse(ready.authorizationHeaderValue.hasSuffix("Bearer "))
            XCTAssertEqual(ready.baseURL.absoluteString, "http://127.0.0.1:51234")
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
    }

    func testReadyConnection_UnreachablePropagatesReason() async {
        StrutURLProtocolStub.response = .init(statusCode: 500)
        let connection = makeConnection()
        connection.apiKey = "present"

        let result = await connection.readyConnection()
        XCTAssertEqual(result, .failure(.unreachable(.httpStatus(500))))
    }
}
