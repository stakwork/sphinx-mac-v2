//
//  StrutProcessControllerTests.swift
//  com.stakwork.sphinx.desktopTests
//
//  Fake-runner tests for StrutProcessController. Never touches Bundle.main,
//  Foundation.Process, or the production keychain.
//

import XCTest
@testable import com_stakwork_sphinx_desktop

final class FakeStrutProcess: StrutProcessRunning, @unchecked Sendable {
    var isRunning = false
    var terminationStatus: Int32 = 0
    var terminationHandler: (@Sendable () -> Void)?
    var stdoutLinesToEmit: [String] = []
    var finishStdout = true
    var stayAliveAfterTerminate = false
    var waitUntilExitResult = true
    var runError: Error?
    var terminateCount = 0
    var killCount = 0
    var runCount = 0
    var waitTimeouts: [TimeInterval] = []

    func run() throws {
        if let runError { throw runError }
        runCount += 1
        isRunning = true
    }

    func terminate() {
        terminateCount += 1
        if !stayAliveAfterTerminate {
            isRunning = false
            terminationStatus = 15
            terminationHandler?()
        }
    }

    func killProcess() {
        killCount += 1
        isRunning = false
        terminationStatus = 9
        terminationHandler?()
    }

    func waitUntilExit(timeout: TimeInterval) -> Bool {
        waitTimeouts.append(timeout)
        if stayAliveAfterTerminate && isRunning {
            return waitUntilExitResult
        }
        return !isRunning || waitUntilExitResult
    }

    func stdoutLines() -> AsyncStream<String> {
        let lines = stdoutLinesToEmit
        let finish = finishStdout
        return AsyncStream { continuation in
            for line in lines {
                continuation.yield(line)
            }
            if finish {
                continuation.finish()
            }
        }
    }

    func fireTerminationHandler() {
        isRunning = false
        terminationStatus = 1
        terminationHandler?()
    }
}

final class FakeStrutProcessFactory: StrutProcessSpawning, @unchecked Sendable {
    var prepared: [FakeStrutProcess] = []
    var spawned: [FakeStrutProcess] = []
    var spawnError: Error?
    var lastExecutable: URL?
    var lastArguments: [String] = []
    var lastDirectory: URL?
    var lastEnvironment: [String: String] = [:]

    func spawn(
        executable: URL,
        arguments: [String],
        currentDirectory: URL,
        environment: [String: String]
    ) throws -> any StrutProcessRunning {
        lastExecutable = executable
        lastArguments = arguments
        lastDirectory = currentDirectory
        lastEnvironment = environment
        if let spawnError { throw spawnError }
        let process: FakeStrutProcess
        if prepared.isEmpty {
            process = FakeStrutProcess()
        } else {
            process = prepared.removeFirst()
        }
        spawned.append(process)
        return process
    }
}

final class StrutProcessControllerTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var secretStore: InMemoryStrutSecretStore!
    private var factory: FakeStrutProcessFactory!
    private var helperFolder: URL!
    private var writableFolder: URL!

    override func setUp() {
        super.setUp()
        suiteName = "StrutProcessControllerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        secretStore = InMemoryStrutSecretStore()
        factory = FakeStrutProcessFactory()
        StrutURLProtocolStub.reset()

        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("StrutProcessTests-\(UUID().uuidString)", isDirectory: true)
        helperFolder = temp.appendingPathComponent("Strut", isDirectory: true)
        writableFolder = temp.appendingPathComponent("Writable", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: helperFolder,
            withIntermediateDirectories: true
        )
        try? FileManager.default.createDirectory(
            at: writableFolder,
            withIntermediateDirectories: true
        )
    }

    override func tearDown() {
        if let helperFolder {
            try? FileManager.default.removeItem(
                at: helperFolder.deletingLastPathComponent()
            )
        }
        if let suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        secretStore = nil
        factory = nil
        suiteName = nil
        StrutURLProtocolStub.reset()
        super.tearDown()
    }

    // MARK: - Fixtures

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

    /// `node` lives in `native/`, isolated from every plain resource
    /// (matches the packaged layout — see `StrutProcessController`'s
    /// `defaultNativeDirName` doc comment).
    private func writeNodeBinary(arm64: Bool, fat: Bool = false) {
        let nativeFolder = helperFolder.appendingPathComponent("native", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: nativeFolder,
            withIntermediateDirectories: true
        )
        let url = nativeFolder.appendingPathComponent("node")
        let data: Data
        if fat {
            data = arm64 ? Self.fatARM64MachO : Self.fatX86MachO
        } else {
            data = arm64 ? Self.thinARM64MachO : Self.thinX86MachO
        }
        FileManager.default.createFile(atPath: url.path, contents: data)
        FileManager.default.createFile(
            atPath: helperFolder.appendingPathComponent("desktop.js").path,
            contents: Data()
        )
    }

    private func readyJSON(
        host: String = "127.0.0.1",
        port: Int = 51235,
        key: String = "launch-key"
    ) -> String {
        #"{"event":"ready","host":"\#(host)","port":\#(port),"key":"\#(key)"}"#
    }

    private func makeController(
        connection: StrutConnection,
        readyTimeout: TimeInterval = 2,
        stopTimeout: TimeInterval = 0.05
    ) -> StrutProcessController {
        StrutProcessController(
            connection: connection,
            processFactory: factory,
            helperFolderURL: { [helperFolder] in helperFolder! },
            writableDirectoryURL: { [writableFolder] in writableFolder! },
            readyLineTimeout: readyTimeout,
            stopWaitTimeout: stopTimeout
        )
    }

    private func preparedRunningProcess(
        stdout: [String],
        finishStdout: Bool = true,
        stayAliveAfterTerminate: Bool = false
    ) -> FakeStrutProcess {
        let process = FakeStrutProcess()
        process.stdoutLinesToEmit = stdout
        process.finishStdout = finishStdout
        process.stayAliveAfterTerminate = stayAliveAfterTerminate
        return process
    }

    // MARK: - Mach-O bytes (little-endian thin; big-endian fat)

    private static let thinARM64MachO = Data([
        0xcf, 0xfa, 0xed, 0xfe,
        0x0c, 0x00, 0x00, 0x01
    ])

    private static let thinX86MachO = Data([
        0xcf, 0xfa, 0xed, 0xfe,
        0x07, 0x00, 0x00, 0x01
    ])

    private static let fatARM64MachO = Data([
        0xca, 0xfe, 0xba, 0xbe,
        0x00, 0x00, 0x00, 0x01,
        0x01, 0x00, 0x00, 0x0c,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00
    ])

    private static let fatX86MachO = Data([
        0xca, 0xfe, 0xba, 0xbe,
        0x00, 0x00, 0x00, 0x01,
        0x01, 0x00, 0x00, 0x07,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00
    ])

    // MARK: - Tests

    func testStart_ValidReadyAndHealthyPublishesHostPortKey() async {
        writeNodeBinary(arm64: true)
        StrutURLProtocolStub.response = .init(statusCode: 200)
        secretStore.set("stale-secret")

        let process = preparedRunningProcess(stdout: ["noise", readyJSON()])
        factory.prepared = [process]
        let connection = makeConnection()
        let controller = makeController(connection: connection)

        await controller.start()

        XCTAssertEqual(connection.baseURLString, "http://127.0.0.1:51235")
        XCTAssertEqual(connection.apiKey, "launch-key")
        XCTAssertNil(secretStore.get(), "Ready-line key must not be persisted")
        XCTAssertEqual(factory.spawned.count, 1)
        XCTAssertEqual(
            factory.lastExecutable,
            helperFolder.appendingPathComponent("native").appendingPathComponent("node")
        )
        XCTAssertEqual(
            factory.lastArguments,
            [helperFolder.appendingPathComponent("desktop.js").path]
        )
        XCTAssertEqual(factory.lastDirectory, helperFolder)
        XCTAssertEqual(factory.lastEnvironment["HOME"], writableFolder.path)
        XCTAssertEqual(factory.lastEnvironment["TMPDIR"], writableFolder.path)
        XCTAssertNil(factory.lastEnvironment["DYLD_LIBRARY_PATH"])
        XCTAssertEqual(process.runCount, 1)
        XCTAssertEqual(
            StrutURLProtocolStub.lastRequest?.url?.absoluteString,
            "http://127.0.0.1:51235/health"
        )
    }

    func testStart_FatARM64BinaryIsAccepted() async {
        writeNodeBinary(arm64: true, fat: true)
        StrutURLProtocolStub.response = .init(statusCode: 200)
        factory.prepared = [
            preparedRunningProcess(stdout: [readyJSON(key: "fat-key")])
        ]
        let connection = makeConnection()
        await makeController(connection: connection).start()
        XCTAssertEqual(connection.apiKey, "fat-key")
        XCTAssertEqual(factory.spawned.count, 1)
    }

    func testStart_HealthFailureClearsAndSIGTERMsWithoutRespawn() async {
        writeNodeBinary(arm64: true)
        StrutURLProtocolStub.response = .init(error: URLError(.cannotConnectToHost))
        secretStore.set("stale-secret")

        let process = preparedRunningProcess(
            stdout: [readyJSON()],
            stayAliveAfterTerminate: false
        )
        factory.prepared = [process]
        let connection = makeConnection()
        await makeController(connection: connection).start()

        XCTAssertEqual(connection.apiKey, "")
        XCTAssertNil(connection.authorizationHeaderValue)
        XCTAssertEqual(connection.baseURLString, StrutConnection.defaultBaseURLString)
        XCTAssertEqual(process.terminateCount, 1)
        XCTAssertEqual(factory.spawned.count, 1, "Must not respawn after health failure")
        XCTAssertNil(secretStore.get())
    }

    func testStart_ChildExitBeforeReadyNeverAppliesKey() async {
        writeNodeBinary(arm64: true)
        let process = preparedRunningProcess(stdout: [], finishStdout: true)
        factory.prepared = [process]
        let connection = makeConnection()
        connection.apiKey = "stale-secret"

        await makeController(connection: connection).start()

        XCTAssertEqual(connection.apiKey, "")
        XCTAssertEqual(connection.baseURLString, StrutConnection.defaultBaseURLString)
        XCTAssertEqual(factory.spawned.count, 1)
        XCTAssertEqual(StrutURLProtocolStub.requestCount, 0)
    }

    func testStart_TimeoutBeforeReadyClearsAndSIGTERMs() async {
        writeNodeBinary(arm64: true)
        let process = preparedRunningProcess(
            stdout: ["still starting"],
            finishStdout: false
        )
        factory.prepared = [process]
        let connection = makeConnection()
        await makeController(connection: connection, readyTimeout: 0.15).start()

        XCTAssertEqual(connection.apiKey, "")
        XCTAssertEqual(process.terminateCount, 1)
        XCTAssertEqual(factory.spawned.count, 1)
        XCTAssertEqual(StrutURLProtocolStub.requestCount, 0)
    }

    func testStart_InvalidReadyLineNeverWritesKey() async {
        writeNodeBinary(arm64: true)
        let process = preparedRunningProcess(
            stdout: [#"{"event":"started","host":"127.0.0.1","port":1,"key":"x"}"#]
        )
        factory.prepared = [process]
        let connection = makeConnection()
        await makeController(connection: connection).start()

        XCTAssertEqual(connection.apiKey, "")
        XCTAssertEqual(process.terminateCount, 1)
        XCTAssertEqual(StrutURLProtocolStub.requestCount, 0)
    }

    func testStart_NonARM64AbortsBeforeSpawn() async {
        writeNodeBinary(arm64: false)
        let connection = makeConnection()
        connection.apiKey = "stale-secret"
        await makeController(connection: connection).start()

        XCTAssertEqual(factory.spawned.count, 0)
        XCTAssertEqual(connection.apiKey, "")
        XCTAssertEqual(connection.baseURLString, StrutConnection.defaultBaseURLString)
    }

    func testStart_FatX86AbortsBeforeSpawn() async {
        writeNodeBinary(arm64: false, fat: true)
        let connection = makeConnection()
        await makeController(connection: connection).start()
        XCTAssertEqual(factory.spawned.count, 0)
        XCTAssertEqual(connection.apiKey, "")
    }

    func testStart_MissingBinaryAbortsBeforeSpawn() async {
        let connection = makeConnection()
        connection.apiKey = "stale-secret"
        await makeController(connection: connection).start()
        XCTAssertEqual(factory.spawned.count, 0)
        XCTAssertEqual(connection.apiKey, "")
        XCTAssertNil(secretStore.get())
    }

    func testStart_OverlayEmptyKeyWinsOverPreSeededSecret() async {
        writeNodeBinary(arm64: false)
        secretStore.set("stale-secret")
        let connection = makeConnection()
        XCTAssertEqual(connection.apiKey, "stale-secret")

        await makeController(connection: connection).start()

        secretStore.set("stale-secret")
        XCTAssertEqual(connection.apiKey, "")
        XCTAssertNil(connection.authorizationHeaderValue)
        XCTAssertEqual(secretStore.get(), "stale-secret")
    }

    func testTerminationHandler_ClearsSessionAndDoesNotRestart() async {
        writeNodeBinary(arm64: true)
        StrutURLProtocolStub.response = .init(statusCode: 200)
        let process = preparedRunningProcess(stdout: [readyJSON()])
        factory.prepared = [process]
        let connection = makeConnection()
        let controller = makeController(connection: connection)

        await controller.start()
        XCTAssertEqual(connection.apiKey, "launch-key")
        XCTAssertEqual(factory.spawned.count, 1)

        process.fireTerminationHandler()

        XCTAssertEqual(connection.apiKey, "")
        XCTAssertEqual(factory.spawned.count, 1, "Must not restart after post-ready death")
    }

    func testStop_SIGTERMThenSIGKILLAfterWaitCap() async {
        writeNodeBinary(arm64: true)
        StrutURLProtocolStub.response = .init(statusCode: 200)
        let process = preparedRunningProcess(
            stdout: [readyJSON()],
            stayAliveAfterTerminate: true
        )
        process.waitUntilExitResult = false
        factory.prepared = [process]
        let connection = makeConnection()
        let controller = makeController(connection: connection, stopTimeout: 0.05)

        await controller.start()
        XCTAssertEqual(connection.apiKey, "launch-key")

        controller.stop()

        XCTAssertEqual(process.terminateCount, 1)
        XCTAssertEqual(process.killCount, 1)
        XCTAssertEqual(connection.apiKey, "")
        XCTAssertFalse(process.waitTimeouts.isEmpty)
    }

    func testStop_NoChildIsIdempotentNoOp() {
        let connection = makeConnection()
        let controller = makeController(connection: connection)
        controller.stop()
        controller.stop()
        XCTAssertEqual(factory.spawned.count, 0)
        XCTAssertEqual(connection.apiKey, "")
    }

    func testStart_WhileChildRunningStopsOldFirst() async {
        writeNodeBinary(arm64: true)
        StrutURLProtocolStub.response = .init(statusCode: 200)

        let first = preparedRunningProcess(
            stdout: [readyJSON(port: 51235, key: "first-key")],
            stayAliveAfterTerminate: true
        )
        first.waitUntilExitResult = true
        let second = preparedRunningProcess(
            stdout: [readyJSON(port: 51236, key: "second-key")]
        )
        factory.prepared = [first, second]

        let connection = makeConnection()
        let controller = makeController(connection: connection)

        await controller.start()
        XCTAssertEqual(connection.apiKey, "first-key")
        XCTAssertEqual(factory.spawned.count, 1)

        first.stayAliveAfterTerminate = false
        await controller.start()

        XCTAssertEqual(first.terminateCount, 1)
        XCTAssertEqual(factory.spawned.count, 2)
        XCTAssertEqual(connection.apiKey, "second-key")
        XCTAssertEqual(connection.baseURLString, "http://127.0.0.1:51236")
    }

    func testStart_SpawnFailureClearsWithoutApplyingKey() async {
        writeNodeBinary(arm64: true)
        factory.spawnError = NSError(
            domain: "StrutProcessControllerTests",
            code: 1
        )
        let connection = makeConnection()
        connection.apiKey = "stale-secret"
        await makeController(connection: connection).start()

        XCTAssertEqual(connection.apiKey, "")
        XCTAssertEqual(factory.spawned.count, 0)
    }
}
