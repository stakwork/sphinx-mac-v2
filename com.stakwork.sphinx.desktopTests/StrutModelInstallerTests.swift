//
//  StrutModelInstallerTests.swift
//  com.stakwork.sphinx.desktopTests
//
//  Path-aware URLProtocol stub. Never hits a live strut process.
//

import XCTest
@testable import com_stakwork_sphinx_desktop

final class StrutModelInstallerTests: XCTestCase {

    private let auth = "Bearer test-key"

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

    private func makeInstaller(
        ready: StrutReadyConnection? = nil
    ) -> StrutModelInstaller {
        let configuration = StrutModelInstaller.makeLongTimeoutConfiguration()
        configuration.protocolClasses = [StrutURLProtocolStub.self]
        return StrutModelInstaller(
            ready: ready ?? makeReady(),
            sessionConfiguration: configuration
        )
    }

    private func defaultModelsJSON(
        available: Bool = true,
        primaryId: String = "primary-id",
        partialId: String = "partial-id",
        primaryInstalled: Bool = false,
        partialInstalled: Bool = false
    ) -> [String: Any] {
        [
            "available": available,
            "models": [
                [
                    "id": primaryId,
                    "role": "model",
                    "default": true,
                    "installed": primaryInstalled
                ],
                [
                    "id": partialId,
                    "role": "partialModel",
                    "default": true,
                    "installed": partialInstalled
                ]
            ]
        ]
    }

    private func stubModels(_ object: [String: Any], status: Int = 200) {
        StrutURLProtocolStub.stubJSON(
            method: "GET",
            path: "/audio/models",
            statusCode: status,
            object: object
        )
    }

    private func stubDownloadDone(id: String) {
        StrutURLProtocolStub.stubSSE(
            method: "POST",
            path: "/audio/models/\(id)/download",
            chunks: [
                StrutSSEFixture.progress(received: 10, total: 100, phase: "download"),
                StrutSSEFixture.done()
            ]
        )
    }

    private func assertExactAuthorization() {
        let values = StrutURLProtocolStub.authorizationValues()
        XCTAssertFalse(values.isEmpty)
        for value in values {
            XCTAssertEqual(value, auth)
            XCTAssertFalse(value.hasPrefix("Bearer Bearer"))
        }
    }

    // MARK: - Authorization

    func testAuthorizationHeader_IsUsedAsIsOnEveryRequest() async {
        stubModels(defaultModelsJSON())
        stubDownloadDone(id: "primary-id")
        stubDownloadDone(id: "partial-id")

        let result = await makeInstaller().install()
        XCTAssertEqual(result, .success(()))
        XCTAssertEqual(StrutURLProtocolStub.requestCount, 3)
        assertExactAuthorization()
    }

    // MARK: - 401 / available:false / already installed

    func test401OnModelsGET_AbortsBeforeAnyDownload() async {
        StrutURLProtocolStub.stub(
            method: "GET",
            path: "/audio/models",
            response: .init(
                statusCode: 401,
                body: Data("event: progress\ndata: {\"received\":1}\n\n".utf8)
            )
        )
        stubDownloadDone(id: "primary-id")

        let result = await makeInstaller().install()
        XCTAssertEqual(result, .failure(.httpStatus(401)))
        XCTAssertEqual(StrutURLProtocolStub.recordedMethods(), ["GET"])
        XCTAssertEqual(StrutURLProtocolStub.recordedPaths(), ["/audio/models"])
        assertExactAuthorization()
    }

    func testAvailableFalse_FailsWithoutDownloadPOST() async {
        stubModels(defaultModelsJSON(available: false))
        stubDownloadDone(id: "primary-id")
        stubDownloadDone(id: "partial-id")

        let result = await makeInstaller().install()
        XCTAssertEqual(result, .failure(.sttUnavailable))
        XCTAssertEqual(StrutURLProtocolStub.recordedMethods(), ["GET"])
        XCTAssertFalse(StrutURLProtocolStub.recordedMethods().contains("POST"))
    }

    func testAlreadyInstalled_NeverPOSTs() async {
        stubModels(
            defaultModelsJSON(primaryInstalled: true, partialInstalled: true)
        )
        stubDownloadDone(id: "primary-id")
        stubDownloadDone(id: "partial-id")

        let result = await makeInstaller().install()
        XCTAssertEqual(result, .success(()))
        XCTAssertEqual(StrutURLProtocolStub.recordedMethods(), ["GET"])
        XCTAssertFalse(StrutURLProtocolStub.recordedMethods().contains("POST"))
    }

    func testOneInstalled_OnlyDownloadsTheOther() async {
        stubModels(
            defaultModelsJSON(primaryInstalled: true, partialInstalled: false)
        )
        stubDownloadDone(id: "partial-id")
        stubDownloadDone(id: "primary-id")

        let result = await makeInstaller().install()
        XCTAssertEqual(result, .success(()))
        XCTAssertEqual(StrutURLProtocolStub.recordedMethods(), ["GET", "POST"])
        XCTAssertEqual(
            StrutURLProtocolStub.recordedPaths(),
            ["/audio/models", "/audio/models/partial-id/download"]
        )
    }

    // MARK: - Malicious ids

    func testRejectedIds_NeverBecomeRequests() async {
        let malicious = ["../", "/etc/passwd", "https://evil.example/x"]
        for id in malicious {
            StrutURLProtocolStub.reset()
            stubModels(defaultModelsJSON(primaryId: id))
            stubDownloadDone(id: id)

            let result = await makeInstaller().install()
            XCTAssertEqual(result, .failure(.invalidModelId(id)), "id \(id)")
            XCTAssertFalse(
                StrutURLProtocolStub.recordedMethods().contains("POST"),
                "id \(id) must never POST"
            )
            XCTAssertEqual(StrutURLProtocolStub.recordedPaths(), ["/audio/models"])
        }
    }

    func testIsValidModelId() {
        XCTAssertTrue(StrutModelInstaller.isValidModelId("primary-id"))
        XCTAssertFalse(StrutModelInstaller.isValidModelId(""))
        XCTAssertFalse(StrutModelInstaller.isValidModelId("../"))
        XCTAssertFalse(StrutModelInstaller.isValidModelId("/etc/passwd"))
        XCTAssertFalse(StrutModelInstaller.isValidModelId("https://evil.example/x"))
        XCTAssertFalse(StrutModelInstaller.isValidModelId("foo?bar"))
        XCTAssertFalse(StrutModelInstaller.isValidModelId("foo#bar"))
        XCTAssertFalse(StrutModelInstaller.isValidModelId("foo\\bar"))
        XCTAssertFalse(StrutModelInstaller.isValidModelId("..hidden"))
    }

    // MARK: - Scheme allowlist

    func testHTTP_AllowedForLoopback() async {
        stubModels(defaultModelsJSON())
        stubDownloadDone(id: "primary-id")
        stubDownloadDone(id: "partial-id")

        let localhost = await makeInstaller(
            ready: makeReady(url: "http://localhost:51234")
        ).install()
        XCTAssertEqual(localhost, .success(()))

        StrutURLProtocolStub.reset()
        stubModels(defaultModelsJSON())
        stubDownloadDone(id: "primary-id")
        stubDownloadDone(id: "partial-id")
        let loopback = await makeInstaller(
            ready: makeReady(url: "http://127.0.0.1:51234")
        ).install()
        XCTAssertEqual(loopback, .success(()))
    }

    func testHTTP_RejectedForNonLoopback() async {
        stubModels(defaultModelsJSON())
        let result = await makeInstaller(
            ready: makeReady(url: "http://example.com")
        ).install()
        XCTAssertEqual(
            result,
            .failure(.disallowedScheme(scheme: "http", host: "example.com"))
        )
        XCTAssertEqual(StrutURLProtocolStub.requestCount, 0)
    }

    func testHTTPS_AllowedForNonLoopback() async {
        stubModels(defaultModelsJSON())
        stubDownloadDone(id: "primary-id")
        stubDownloadDone(id: "partial-id")
        let result = await makeInstaller(
            ready: makeReady(url: "https://strut.example")
        ).install()
        XCTAssertEqual(result, .success(()))
    }

    // MARK: - Redirect

    func testCrossHostRedirect_IsRefused() async {
        StrutURLProtocolStub.stub(
            method: "GET",
            path: "/audio/models",
            response: .init(
                statusCode: 302,
                redirectLocation: "https://evil.example/audio/models"
            )
        )

        let result = await makeInstaller().install()
        switch result {
        case .failure(.redirectRefused), .failure(.httpStatus(302)):
            break
        default:
            XCTFail("Expected redirect refused or unfollowed 302, got \(result)")
        }
        let hosts = StrutURLProtocolStub.requests.compactMap { $0.url?.host }
        XCTAssertFalse(hosts.contains("evil.example"))
        XCTAssertFalse(
            StrutURLProtocolStub.recordedPaths().contains(where: { $0.contains("evil") })
        )
    }

    func testRedirectPolicy_SameHostOnly() {
        let original = URL(string: "http://127.0.0.1:51234/audio/models")
        XCTAssertTrue(
            StrutRedirectPolicy.isSameHost(
                original,
                URL(string: "http://127.0.0.1:51234/other")
            )
        )
        XCTAssertFalse(
            StrutRedirectPolicy.isSameHost(
                original,
                URL(string: "https://evil.example/x")
            )
        )
    }

    // MARK: - SSE

    func testSSE_ProgressDoneDriveCallbacks() async {
        stubModels(defaultModelsJSON(partialInstalled: true))
        StrutURLProtocolStub.stubSSE(
            method: "POST",
            path: "/audio/models/primary-id/download",
            chunks: [
                StrutSSEFixture.progress(received: 5, total: 50, phase: "fetch"),
                StrutSSEFixture.progress(received: 50, total: 50, phase: "write"),
                StrutSSEFixture.done()
            ]
        )

        let recorder = ProgressRecorder()
        let result = await makeInstaller().install { phase, received, total in
            recorder.add(phase, received, total)
        }
        XCTAssertEqual(result, .success(()))
        XCTAssertEqual(recorder.events.count, 2)
        XCTAssertEqual(recorder.events[0].0, "fetch")
        XCTAssertEqual(recorder.events[0].1, 5)
        XCTAssertEqual(recorder.events[0].2, 50)
        XCTAssertEqual(recorder.events[1].0, "write")
        XCTAssertEqual(recorder.events[1].1, 50)
        XCTAssertEqual(recorder.events[1].2, 50)
        XCTAssertEqual(
            StrutURLProtocolStub.recordedPaths(),
            ["/audio/models", "/audio/models/primary-id/download"]
        )
    }

    func testSSE_ErrorDrivesFailure() async {
        stubModels(defaultModelsJSON(partialInstalled: true))
        StrutURLProtocolStub.stubSSE(
            method: "POST",
            path: "/audio/models/primary-id/download",
            chunks: [StrutSSEFixture.error("disk full")]
        )

        let result = await makeInstaller().install()
        XCTAssertEqual(result, .failure(.downloadFailed("disk full")))
    }

    func testInstallerDoesNotUseEphemeralHealthSession() {
        let source = try! String(
            contentsOfFile: #filePath
                .replacingOccurrences(
                    of: "com.stakwork.sphinx.desktopTests/StrutModelInstallerTests.swift",
                    with: "com.stakwork.sphinx.desktop/Managers/Strut/StrutModelInstaller.swift"
                ),
            encoding: .utf8
        )
        XCTAssertFalse(source.contains("readyConnection("))
        XCTAssertFalse(source.contains("checkHealth("))
        XCTAssertFalse(source.contains("makeEphemeralSession("))
    }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [(String?, Int?, Int?)] = []

    func add(_ phase: String?, _ received: Int?, _ total: Int?) {
        lock.lock()
        defer { lock.unlock() }
        _events.append((phase, received, total))
    }

    var events: [(String?, Int?, Int?)] {
        lock.lock()
        defer { lock.unlock() }
        return _events
    }
}
