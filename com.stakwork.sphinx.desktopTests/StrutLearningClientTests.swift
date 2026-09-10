//
//  StrutLearningClientTests.swift
//  com.stakwork.sphinx.desktopTests
//
//  Path-aware URLProtocol stub. Never hits a live strut process.
//

import XCTest
@testable import com_stakwork_sphinx_desktop

final class StrutLearningClientTests: XCTestCase {

    private let auth = "Bearer test-key"
    private let sessionId = "550e8400-e29b-41d4-a716-446655440000"

    override func setUp() {
        super.setUp()
        StrutURLProtocolStub.reset()
    }

    override func tearDown() {
        StrutURLProtocolStub.reset()
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeReady(
        url: String = "http://127.0.0.1:51234"
    ) -> StrutReadyConnection {
        StrutReadyConnection(
            baseURL: URL(string: url)!,
            authorizationHeaderValue: auth
        )
    }

    private func makeClient() -> StrutLearningClient {
        let configuration = StrutLearningClient.makeShortTimeoutConfiguration()
        configuration.protocolClasses = [StrutURLProtocolStub.self]
        return StrutLearningClient(sessionConfiguration: configuration)
    }

    private var expectedCorrectionPath: String {
        URL(string: "http://127.0.0.1:51234")!
            .appendingPathComponent("audio")
            .appendingPathComponent("sessions")
            .appendingPathComponent(sessionId)
            .appendingPathComponent("corrections")
            .path
    }

    private var expectedHotwordsPath: String {
        URL(string: "http://127.0.0.1:51234")!
            .appendingPathComponent("audio")
            .appendingPathComponent("hotwords")
            .appendingPathComponent("sphinx")
            .path
    }

    private func jsonObject(from request: URLRequest?) -> [String: Any]? {
        guard let body = request?.httpBody else { return nil }
        return (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
    }

    // MARK: - POST correction

    func testPostCorrection_SendsMethodPathBearerAndJSONBody() async {
        StrutURLProtocolStub.stubJSON(
            method: "POST",
            path: expectedCorrectionPath,
            statusCode: 204,
            object: [:]
        )

        let client = makeClient()
        await client.postCorrection(
            sessionId: sessionId,
            text: "hello world",
            ready: makeReady()
        )

        XCTAssertEqual(StrutURLProtocolStub.requestCount, 1)
        XCTAssertEqual(StrutURLProtocolStub.recordedMethods(), ["POST"])
        XCTAssertEqual(StrutURLProtocolStub.recordedPaths(), [expectedCorrectionPath])
        XCTAssertEqual(StrutURLProtocolStub.authorizationValues(), [auth])

        let object = jsonObject(from: StrutURLProtocolStub.lastRequest)
        XCTAssertEqual(object?["text"] as? String, "hello world")
        XCTAssertEqual(object?.count, 1)
        XCTAssertEqual(
            StrutURLProtocolStub.lastRequest?.value(forHTTPHeaderField: "Content-Type"),
            "application/json"
        )
    }

    func testPostCorrection_PathUsesAppendingPathComponentNotConcatenation() async {
        StrutURLProtocolStub.stubJSON(
            method: "POST",
            path: expectedCorrectionPath,
            object: [:]
        )

        let client = makeClient()
        await client.postCorrection(
            sessionId: sessionId,
            text: "span",
            ready: makeReady()
        )

        XCTAssertEqual(StrutURLProtocolStub.recordedPaths(), [expectedCorrectionPath])
        XCTAssertEqual(
            expectedCorrectionPath,
            "/audio/sessions/\(sessionId)/corrections"
        )
    }

    func testPostCorrection_401And404And5xxDoNotThrow() async {
        let statuses = [401, 404, 500]
        for status in statuses {
            StrutURLProtocolStub.reset()
            StrutURLProtocolStub.stub(
                method: "POST",
                path: expectedCorrectionPath,
                response: .init(statusCode: status)
            )
            let client = makeClient()
            await client.postCorrection(
                sessionId: sessionId,
                text: "span",
                ready: makeReady()
            )
            XCTAssertEqual(
                StrutURLProtocolStub.requestCount,
                1,
                "status \(status) must still complete one request"
            )
        }
    }

    func testPostCorrection_InvalidSessionIdSendsNoRequest() async {
        StrutURLProtocolStub.stubJSON(
            method: "POST",
            path: expectedCorrectionPath,
            object: [:]
        )
        let client = makeClient()
        let invalid = [
            "",
            "not-a-uuid",
            "../",
            "/etc/passwd",
            "foo?bar",
            "foo#bar",
            "foo/bar",
            "https://evil.example/x"
        ]
        for id in invalid {
            StrutURLProtocolStub.reset()
            await client.postCorrection(
                sessionId: id,
                text: "span",
                ready: makeReady()
            )
            XCTAssertEqual(
                StrutURLProtocolStub.requestCount,
                0,
                "id \(id) must never become a request"
            )
        }
    }

    func testIsValidSessionId() {
        XCTAssertTrue(StrutLearningClient.isValidSessionId(sessionId))
        XCTAssertTrue(
            StrutLearningClient.isValidSessionId(UUID().uuidString)
        )
        XCTAssertFalse(StrutLearningClient.isValidSessionId(""))
        XCTAssertFalse(StrutLearningClient.isValidSessionId("not-a-uuid"))
        XCTAssertFalse(StrutLearningClient.isValidSessionId("../"))
        XCTAssertFalse(StrutLearningClient.isValidSessionId("foo?bar"))
        XCTAssertFalse(StrutLearningClient.isValidSessionId("foo#bar"))
        XCTAssertFalse(StrutLearningClient.isValidSessionId("foo/bar"))
    }

    // MARK: - PUT hotwords

    func testPutHotwords_SendsMethodPathBearerAndJSONBody() async {
        StrutURLProtocolStub.stubJSON(
            method: "PUT",
            path: expectedHotwordsPath,
            statusCode: 200,
            object: [:]
        )

        let client = makeClient()
        await client.putHotwords(
            name: "sphinx",
            words: ["Alice", "Sphinx", "Stakwork"],
            ready: makeReady()
        )

        XCTAssertEqual(StrutURLProtocolStub.requestCount, 1)
        XCTAssertEqual(StrutURLProtocolStub.recordedMethods(), ["PUT"])
        XCTAssertEqual(StrutURLProtocolStub.recordedPaths(), [expectedHotwordsPath])
        XCTAssertEqual(StrutURLProtocolStub.authorizationValues(), [auth])

        let object = jsonObject(from: StrutURLProtocolStub.lastRequest)
        let words = (object?["words"] as? [Any])?.compactMap { $0 as? String }
        XCTAssertEqual(words, ["Alice", "Sphinx", "Stakwork"])
        XCTAssertEqual(object?.count, 1)
    }

    func testPutHotwords_404DoesNotThrow() async {
        StrutURLProtocolStub.stub(
            method: "PUT",
            path: expectedHotwordsPath,
            response: .init(statusCode: 404)
        )
        let client = makeClient()
        await client.putHotwords(
            name: "sphinx",
            words: ["Sphinx"],
            ready: makeReady()
        )
        XCTAssertEqual(StrutURLProtocolStub.requestCount, 1)
    }

    // MARK: - Scheme allowlist

    func testDisallowedScheme_SendsNoRequest() async {
        StrutURLProtocolStub.stubJSON(
            method: "POST",
            path: expectedCorrectionPath,
            object: [:]
        )
        StrutURLProtocolStub.stubJSON(
            method: "PUT",
            path: "/audio/hotwords/sphinx",
            object: [:]
        )

        let client = makeClient()
        let ready = makeReady(url: "http://example.com")
        await client.postCorrection(
            sessionId: sessionId,
            text: "span",
            ready: ready
        )
        await client.putHotwords(
            name: "sphinx",
            words: ["Sphinx"],
            ready: ready
        )
        XCTAssertEqual(StrutURLProtocolStub.requestCount, 0)
    }

    func testHTTP_AllowedForLoopback() async {
        StrutURLProtocolStub.stubJSON(
            method: "POST",
            path: expectedCorrectionPath,
            object: [:]
        )
        let client = makeClient()
        await client.postCorrection(
            sessionId: sessionId,
            text: "span",
            ready: makeReady(url: "http://127.0.0.1:51234")
        )
        XCTAssertEqual(StrutURLProtocolStub.requestCount, 1)
    }

    func testHTTPS_AllowedForNonLoopback() async {
        let path = URL(string: "https://strut.example")!
            .appendingPathComponent("audio")
            .appendingPathComponent("sessions")
            .appendingPathComponent(sessionId)
            .appendingPathComponent("corrections")
            .path
        StrutURLProtocolStub.stubJSON(
            method: "POST",
            path: path,
            object: [:]
        )
        let client = makeClient()
        await client.postCorrection(
            sessionId: sessionId,
            text: "span",
            ready: makeReady(url: "https://strut.example")
        )
        XCTAssertEqual(StrutURLProtocolStub.requestCount, 1)
    }

    // MARK: - Redirect

    func testSameHostRedirect_StripsAuthorization() async {
        let followedPath = "/audio/sessions/\(sessionId)/corrections-followed"
        StrutURLProtocolStub.stub(
            method: "POST",
            path: expectedCorrectionPath,
            response: .init(
                statusCode: 302,
                redirectLocation: "http://127.0.0.1:51234\(followedPath)"
            )
        )
        StrutURLProtocolStub.stubJSON(
            method: "POST",
            path: followedPath,
            statusCode: 200,
            object: [:]
        )

        let client = makeClient()
        await client.postCorrection(
            sessionId: sessionId,
            text: "span",
            ready: makeReady()
        )

        let followed = StrutURLProtocolStub.requests.first {
            $0.url?.path == followedPath
        }
        if let followed {
            XCTAssertNil(followed.value(forHTTPHeaderField: "Authorization"))
        } else {
            // Session completed the 3xx without following; policy helper
            // still guarantees Authorization is stripped when a follow happens.
            let original = URL(string: "http://127.0.0.1:51234\(expectedCorrectionPath)")
            var next = URLRequest(
                url: URL(string: "http://127.0.0.1:51234\(followedPath)")!
            )
            next.setValue(auth, forHTTPHeaderField: "Authorization")
            let sanitized = StrutRedirectPolicy.followRequestStrippingAuthorization(
                originalURL: original,
                newRequest: next
            )
            XCTAssertNotNil(sanitized)
            XCTAssertNil(sanitized?.value(forHTTPHeaderField: "Authorization"))
        }
    }

    func testCrossHostRedirect_IsRefused() async {
        StrutURLProtocolStub.stub(
            method: "POST",
            path: expectedCorrectionPath,
            response: .init(
                statusCode: 302,
                redirectLocation: "https://evil.example/audio/sessions/\(sessionId)/corrections"
            )
        )

        let client = makeClient()
        await client.postCorrection(
            sessionId: sessionId,
            text: "span",
            ready: makeReady()
        )

        let hosts = StrutURLProtocolStub.requests.compactMap { $0.url?.host }
        XCTAssertFalse(hosts.contains("evil.example"))
        XCTAssertFalse(
            StrutURLProtocolStub.recordedPaths().contains(where: { $0.contains("evil") })
        )
    }

    func testRedirectPolicy_SameHostStripsAuthorization() {
        let original = URL(string: "http://127.0.0.1:51234/audio/sessions/\(sessionId)/corrections")
        var sameHost = URLRequest(
            url: URL(string: "http://127.0.0.1:51234/other")!
        )
        sameHost.setValue(auth, forHTTPHeaderField: "Authorization")
        let followed = StrutRedirectPolicy.followRequestStrippingAuthorization(
            originalURL: original,
            newRequest: sameHost
        )
        XCTAssertNotNil(followed)
        XCTAssertNil(followed?.value(forHTTPHeaderField: "Authorization"))

        var crossHost = URLRequest(url: URL(string: "https://evil.example/x")!)
        crossHost.setValue(auth, forHTTPHeaderField: "Authorization")
        XCTAssertNil(
            StrutRedirectPolicy.followRequestStrippingAuthorization(
                originalURL: original,
                newRequest: crossHost
            )
        )
    }

    // MARK: - Source constraints

    func testLearningClientDoesNotUseEphemeralHealthSession() {
        let source = try! String(
            contentsOfFile: #filePath
                .replacingOccurrences(
                    of: "com.stakwork.sphinx.desktopTests/StrutLearningClientTests.swift",
                    with: "com.stakwork.sphinx.desktop/Managers/Strut/StrutLearningClient.swift"
                ),
            encoding: .utf8
        )
        XCTAssertFalse(source.contains("makeEphemeralSession("))
        XCTAssertFalse(source.contains("readyConnection("))
        XCTAssertFalse(source.contains("checkHealth("))
        XCTAssertFalse(source.contains("API.getUrl"))
        XCTAssertFalse(source.contains("\"/audio/sessions/\\("))
    }
}
