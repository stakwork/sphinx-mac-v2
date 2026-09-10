//
//  StrutDictationClientTests.swift
//  com.stakwork.sphinx.desktopTests
//
//  Fake transport/capturer only. No live strut process, no E2E.
//

import XCTest
@testable import com_stakwork_sphinx_desktop

// MARK: - Fakes

final class FakeStrutStreamTransport: StrutStreamTransport, @unchecked Sendable {

    enum Frame: Equatable {
        case text(String)
        case data(Data)
    }

    private let lock = NSLock()
    private var onMessage: (@Sendable (Int, StrutServerMessage) -> Void)?
    private var onClose: (@Sendable (Int, Int) -> Void)?
    private var onFailure: (@Sendable (Int, StrutStreamTransportError) -> Void)?

    private(set) var frames: [Frame] = []
    private(set) var openCount = 0
    private(set) var closeCount = 0
    private(set) var lastOpenGeneration = 0
    var failWith: StrutStreamTransportError?

    func setHandlers(
        onMessage: @escaping @Sendable (Int, StrutServerMessage) -> Void,
        onClose: @escaping @Sendable (Int, Int) -> Void,
        onFailure: @escaping @Sendable (Int, StrutStreamTransportError) -> Void
    ) {
        lock.lock()
        self.onMessage = onMessage
        self.onClose = onClose
        self.onFailure = onFailure
        lock.unlock()
    }

    func open(
        ready: StrutReadyConnection,
        generation: Int
    ) async -> Result<Void, StrutStreamTransportError> {
        lock.lock()
        openCount += 1
        lastOpenGeneration = generation
        let fail = failWith
        lock.unlock()

        if let fail {
            return .failure(fail)
        }
        return .success(())
    }

    func send(text: String) {
        lock.lock()
        frames.append(.text(text))
        lock.unlock()
    }

    func send(data: Data) {
        lock.lock()
        frames.append(.data(data))
        lock.unlock()
    }

    func close(code: Int) async {
        lock.lock()
        closeCount += 1
        lock.unlock()
    }

    func deliver(_ message: StrutServerMessage, generation: Int? = nil) {
        lock.lock()
        let gen = generation ?? lastOpenGeneration
        let handler = onMessage
        lock.unlock()
        handler?(gen, message)
    }

    func deliverClose(_ code: Int, generation: Int? = nil) {
        lock.lock()
        let gen = generation ?? lastOpenGeneration
        let handler = onClose
        lock.unlock()
        handler?(gen, code)
    }

    var texts: [String] {
        lock.lock()
        defer { lock.unlock() }
        return frames.compactMap {
            if case .text(let value) = $0 { return value }
            return nil
        }
    }

    var datas: [Data] {
        lock.lock()
        defer { lock.unlock() }
        return frames.compactMap {
            if case .data(let value) = $0 { return value }
            return nil
        }
    }

    var snapshot: [Frame] {
        lock.lock()
        defer { lock.unlock() }
        return frames
    }
}

final class FakeStrutAudioCapturer: StrutAudioCapturer, @unchecked Sendable {

    private let lock = NSLock()
    private var onPCM: (@Sendable (Data) -> Void)?
    private var onConfigurationChange: (@Sendable () -> Void)?
    private var onSampleRateMismatch: (@Sendable (Int) -> Void)?
    private var accumulator = StrutPCMFrameAccumulator(declaredRate: 48_000)

    var declaredRate: Int = 48_000
    private(set) var prepareCount = 0
    private(set) var startTapCount = 0
    private(set) var stopCount = 0
    var prepareError: StrutAudioCaptureError?

    func prepare() throws -> Int {
        lock.lock()
        defer { lock.unlock() }
        if let prepareError { throw prepareError }
        prepareCount += 1
        accumulator = StrutPCMFrameAccumulator(declaredRate: declaredRate)
        return declaredRate
    }

    func startTap(
        onPCM: @escaping @Sendable (Data) -> Void,
        onConfigurationChange: @escaping @Sendable () -> Void,
        onSampleRateMismatch: @escaping @Sendable (Int) -> Void
    ) {
        lock.lock()
        startTapCount += 1
        self.onPCM = onPCM
        self.onConfigurationChange = onConfigurationChange
        self.onSampleRateMismatch = onSampleRateMismatch
        lock.unlock()
    }

    func stop() {
        lock.lock()
        stopCount += 1
        onPCM = nil
        onConfigurationChange = nil
        onSampleRateMismatch = nil
        accumulator.reset()
        lock.unlock()
    }

    /// Feed already-converted PCM16LE through the 100ms accumulator.
    func feedPCM(_ pcm: Data) {
        lock.lock()
        let chunks = accumulator.append(pcm)
        let callback = onPCM
        lock.unlock()
        for chunk in chunks {
            callback?(chunk)
        }
    }

    func feedHardwareBuffers(count: Int, framesPerBuffer: Int = 1024) {
        let pcm = Data(count: framesPerBuffer * MemoryLayout<Int16>.size)
        for _ in 0..<count {
            feedPCM(pcm)
        }
    }

    func triggerConfigurationChange() {
        lock.lock()
        let callback = onConfigurationChange
        lock.unlock()
        callback?()
    }

    func triggerSampleRateMismatch(_ rate: Int) {
        lock.lock()
        let callback = onSampleRateMismatch
        lock.unlock()
        callback?(rate)
    }
}

struct FakeMicGate: StrutDictationMicGate {
    var busy: Bool = false
    var granted: Bool = true

    func isBusy() async -> Bool { busy }
    func requestPermission() async -> Bool { granted }
}

// MARK: - Tests

private final class CallbackLog: @unchecked Sendable {
    private let lock = NSLock()
    private var errors: [String] = []
    private var partials: [String] = []
    private var finals: [String] = []

    func addError(_ value: String) {
        lock.lock(); errors.append(value); lock.unlock()
    }
    func addPartial(_ value: String) {
        lock.lock(); partials.append(value); lock.unlock()
    }
    func addFinal(_ value: String) {
        lock.lock(); finals.append(value); lock.unlock()
    }
    var errorValues: [String] {
        lock.lock(); defer { lock.unlock() }; return errors
    }
    var partialValues: [String] {
        lock.lock(); defer { lock.unlock() }; return partials
    }
    var finalValues: [String] {
        lock.lock(); defer { lock.unlock() }; return finals
    }
}

final class StrutDictationClientTests: XCTestCase {

    private func makeReady() -> StrutReadyConnection {
        StrutReadyConnection(
            baseURL: URL(string: "http://127.0.0.1:51234")!,
            authorizationHeaderValue: "Bearer test-key"
        )
    }

    private func makeClient(
        transport: FakeStrutStreamTransport,
        capturer: FakeStrutAudioCapturer,
        micBusy: Bool = false,
        stopTimeout: TimeInterval = 2.0,
        restartBackoff: TimeInterval = 0.05,
        session: String? = nil,
        hotwords: [String] = []
    ) -> StrutDictationClient {
        StrutDictationClient(
            ready: makeReady(),
            transport: transport,
            capturer: capturer,
            micGate: FakeMicGate(busy: micBusy, granted: true),
            stopTimeout: stopTimeout,
            restartBackoff: restartBackoff,
            session: session,
            hotwords: hotwords
        )
    }

    private func waitUntil(
        _ timeout: TimeInterval = 1.0,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ predicate: @escaping () -> Bool
    ) {
        let exp = expectation(description: "condition")
        let timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { timer in
            if predicate() {
                timer.invalidate()
                exp.fulfill()
            }
        }
        let result = XCTWaiter.wait(for: [exp], timeout: timeout)
        timer.invalidate()
        if result != .completed {
            XCTFail("condition not met within \(timeout)s", file: file, line: line)
        }
    }

    private func startAndWait(
        _ client: StrutDictationClient,
        transport: FakeStrutStreamTransport,
        capturer: FakeStrutAudioCapturer
    ) {
        client.start()
        waitUntil {
            capturer.startTapCount >= 1 && transport.texts.contains { $0.contains("\"start\"") }
        }
    }

    private func isStartFrame(_ text: String) -> Bool {
        guard
            let data = text.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return false
        }
        return object["type"] as? String == "start"
    }

    private func startPayload(_ text: String) -> [String: Any]? {
        guard
            let data = text.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            object["type"] as? String == "start"
        else {
            return nil
        }
        return object
    }

    private func isEndFrame(_ text: String) -> Bool {
        guard
            let data = text.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return false
        }
        return object["type"] as? String == "end"
    }

    // MARK: - Start before PCM

    func testStartFrameIsSentBeforeAnyPCM() {
        let transport = FakeStrutStreamTransport()
        let capturer = FakeStrutAudioCapturer()
        let client = makeClient(transport: transport, capturer: capturer)

        startAndWait(client, transport: transport, capturer: capturer)
        capturer.feedHardwareBuffers(count: 5)

        let frames = transport.snapshot
        let startIndex = frames.firstIndex {
            if case .text(let text) = $0 { return isStartFrame(text) }
            return false
        }
        let dataIndex = frames.firstIndex {
            if case .data = $0 { return true }
            return false
        }
        XCTAssertNotNil(startIndex)
        XCTAssertNotNil(dataIndex)
        XCTAssertLessThan(startIndex!, dataIndex!)
        XCTAssertEqual(capturer.prepareCount, 1)
        XCTAssertEqual(capturer.startTapCount, 1)
    }

    // MARK: - 100ms accumulation

    func testAccumulatorEmits100msChunksAt48kHz() {
        var accumulator = StrutPCMFrameAccumulator(declaredRate: 48_000)
        XCTAssertEqual(accumulator.bytesPerChunk, 9_600)

        let hardware = Data(count: 1024 * 2)
        XCTAssertTrue(accumulator.append(hardware).isEmpty)
        XCTAssertTrue(accumulator.append(hardware).isEmpty)
        XCTAssertTrue(accumulator.append(hardware).isEmpty)
        XCTAssertTrue(accumulator.append(hardware).isEmpty)
        let chunks = accumulator.append(hardware)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].count, 9_600)
    }

    func testClientForwardsAccumulated100msChunksNotPerHardwareBuffer() {
        let transport = FakeStrutStreamTransport()
        let capturer = FakeStrutAudioCapturer()
        let client = makeClient(transport: transport, capturer: capturer)

        startAndWait(client, transport: transport, capturer: capturer)

        capturer.feedHardwareBuffers(count: 4)
        XCTAssertTrue(transport.datas.isEmpty)

        capturer.feedHardwareBuffers(count: 1)
        XCTAssertEqual(transport.datas.count, 1)
        XCTAssertEqual(transport.datas[0].count, 9_600)
    }

    // MARK: - Stop

    func testStopSendsEndAndCompletesOnTrailingFinal() {
        let transport = FakeStrutStreamTransport()
        let capturer = FakeStrutAudioCapturer()
        let client = makeClient(
            transport: transport,
            capturer: capturer,
            stopTimeout: 0.8
        )

        let log = CallbackLog()
        client.onError = { log.addError($0) }

        startAndWait(client, transport: transport, capturer: capturer)
        client.stop()

        waitUntil { transport.texts.contains { self.isEndFrame($0) } }
        transport.deliver(.final(text: "hello", index: 0))
        waitUntil { transport.closeCount >= 1 }

        XCTAssertFalse(log.errorValues.contains("stopped without a final response"))
        XCTAssertGreaterThanOrEqual(capturer.stopCount, 1)
    }

    func testStopCompletesOnClose1000() {
        let transport = FakeStrutStreamTransport()
        let capturer = FakeStrutAudioCapturer()
        let client = makeClient(
            transport: transport,
            capturer: capturer,
            stopTimeout: 0.8
        )

        let log = CallbackLog()
        client.onError = { log.addError($0) }

        startAndWait(client, transport: transport, capturer: capturer)
        client.stop()
        waitUntil { transport.texts.contains { self.isEndFrame($0) } }
        transport.deliverClose(1000)
        waitUntil { transport.closeCount >= 1 }

        XCTAssertFalse(log.errorValues.contains("stopped without a final response"))
    }

    func testStopTimeoutErrorsWhenSilent() {
        let transport = FakeStrutStreamTransport()
        let capturer = FakeStrutAudioCapturer()
        let client = makeClient(
            transport: transport,
            capturer: capturer,
            stopTimeout: 0.25
        )

        let log = CallbackLog()
        client.onError = { log.addError($0) }

        startAndWait(client, transport: transport, capturer: capturer)
        client.stop()
        waitUntil { transport.texts.contains { self.isEndFrame($0) } }
        waitUntil { log.errorValues.contains("stopped without a final response") }

        XCTAssertEqual(log.errorValues.last, "stopped without a final response")
        XCTAssertGreaterThanOrEqual(transport.closeCount, 1)
        XCTAssertGreaterThanOrEqual(capturer.stopCount, 1)
    }

    // MARK: - Device-change restart

    func testDeviceChangeBurstCoalescesToOneRestart() {
        let transport = FakeStrutStreamTransport()
        let capturer = FakeStrutAudioCapturer()
        let client = makeClient(
            transport: transport,
            capturer: capturer,
            restartBackoff: 0.05
        )

        startAndWait(client, transport: transport, capturer: capturer)
        XCTAssertEqual(transport.openCount, 1)

        capturer.triggerConfigurationChange()
        capturer.triggerConfigurationChange()
        capturer.triggerSampleRateMismatch(44_100)
        capturer.triggerConfigurationChange()

        waitUntil(1.5) {
            transport.openCount == 2
                && capturer.startTapCount == 2
                && transport.texts.filter { self.isStartFrame($0) }.count == 2
                && transport.texts.filter { self.isEndFrame($0) }.count == 1
        }

        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        XCTAssertEqual(transport.openCount, 2)
        XCTAssertEqual(transport.texts.filter { isStartFrame($0) }.count, 2)
        XCTAssertEqual(transport.texts.filter { isEndFrame($0) }.count, 1)
        XCTAssertEqual(capturer.startTapCount, 2)
    }

    func testDeviceChangeRestartReusesSessionAndHotwords() {
        let session = "A1B2C3D4-E5F6-7890-ABCD-EF1234567890"
        let hotwords = ["Alice", "Sphinx", "Stakwork"]
        let transport = FakeStrutStreamTransport()
        let capturer = FakeStrutAudioCapturer()
        let client = makeClient(
            transport: transport,
            capturer: capturer,
            restartBackoff: 0.05,
            session: session,
            hotwords: hotwords
        )

        startAndWait(client, transport: transport, capturer: capturer)
        capturer.triggerConfigurationChange()

        waitUntil(1.5) {
            transport.texts.filter { self.isStartFrame($0) }.count == 2
        }

        let starts = transport.texts.compactMap { startPayload($0) }
        XCTAssertEqual(starts.count, 2)
        for payload in starts {
            XCTAssertEqual(payload["session"] as? String, session)
            let words: [String]?
            if let strings = payload["hotwords"] as? [String] {
                words = strings
            } else {
                words = (payload["hotwords"] as? [Any]) as? [String]
            }
            XCTAssertEqual(words, hotwords)
            XCTAssertEqual(payload["sampleRate"] as? Int, 48_000)
        }
    }

    // MARK: - Stale generation

    func testStaleGenerationPCMAndMessagesAreDropped() {
        let transport = FakeStrutStreamTransport()
        let capturer = FakeStrutAudioCapturer()
        let client = makeClient(
            transport: transport,
            capturer: capturer,
            restartBackoff: 0.05
        )

        let log = CallbackLog()
        client.onPartial = { log.addPartial($0) }
        client.onFinal = { text, _ in log.addFinal(text) }

        startAndWait(client, transport: transport, capturer: capturer)
        let staleGeneration = transport.lastOpenGeneration

        transport.deliver(.partial(text: "live"))
        waitUntil { !log.partialValues.isEmpty }

        capturer.triggerConfigurationChange()
        waitUntil(1.5) { transport.openCount == 2 }

        let stalePartials = log.partialValues.count
        let staleFinals = log.finalValues.count
        transport.deliver(.partial(text: "stale-partial"), generation: staleGeneration)
        transport.deliver(.final(text: "stale-final", index: 1), generation: staleGeneration)
        capturer.feedHardwareBuffers(count: 5)

        RunLoop.current.run(until: Date().addingTimeInterval(0.15))

        XCTAssertEqual(log.partialValues.count, stalePartials)
        XCTAssertEqual(log.finalValues.count, staleFinals)
        XCTAssertFalse(log.partialValues.contains("stale-partial"))
        XCTAssertFalse(log.finalValues.contains("stale-final"))
    }

    // MARK: - Auth / exclusivity

    func testUpgrade401NeverStartsCapturer() {
        let transport = FakeStrutStreamTransport()
        transport.failWith = .rejectedAuth(code: 401)
        let capturer = FakeStrutAudioCapturer()
        let client = makeClient(transport: transport, capturer: capturer)

        let log = CallbackLog()
        client.onError = { log.addError($0) }

        client.start()
        waitUntil { log.errorValues.contains { $0.contains("401") } }

        XCTAssertTrue(log.errorValues.last?.contains("401") == true)
        XCTAssertEqual(capturer.prepareCount, 0)
        XCTAssertEqual(capturer.startTapCount, 0)
        XCTAssertTrue(transport.texts.isEmpty)
        XCTAssertTrue(transport.datas.isEmpty)
    }

    func testMissingReadyConnectionNeverOpensSocket() {
        let transport = FakeStrutStreamTransport()
        let capturer = FakeStrutAudioCapturer()
        let client = StrutDictationClient(
            ready: nil,
            transport: transport,
            capturer: capturer,
            micGate: FakeMicGate()
        )

        let log = CallbackLog()
        client.onError = { log.addError($0) }

        client.start()
        waitUntil { log.errorValues.contains { $0.lowercased().contains("ready") } }

        XCTAssertTrue(log.errorValues.last?.lowercased().contains("ready") == true)
        XCTAssertEqual(transport.openCount, 0)
        XCTAssertEqual(capturer.prepareCount, 0)
        XCTAssertEqual(capturer.startTapCount, 0)
    }

    func testSecondStartWhileActiveDoesNotOpenAnotherSocket() {
        let transport = FakeStrutStreamTransport()
        let capturer = FakeStrutAudioCapturer()
        let client = makeClient(transport: transport, capturer: capturer)

        let log = CallbackLog()
        client.onError = { log.addError($0) }

        startAndWait(client, transport: transport, capturer: capturer)
        client.start()

        waitUntil { log.errorValues.contains("dictation already in progress") }
        XCTAssertEqual(transport.openCount, 1)
        XCTAssertEqual(capturer.startTapCount, 1)
    }

    func testMicExclusivityNeverStartsCapturerOrSocket() {
        let transport = FakeStrutStreamTransport()
        let capturer = FakeStrutAudioCapturer()
        let client = makeClient(
            transport: transport,
            capturer: capturer,
            micBusy: true
        )

        let log = CallbackLog()
        client.onError = { log.addError($0) }

        client.start()
        waitUntil { log.errorValues.contains { $0.lowercased().contains("microphone") } }

        XCTAssertTrue(log.errorValues.last?.lowercased().contains("microphone") == true)
        XCTAssertEqual(capturer.prepareCount, 0)
        XCTAssertEqual(capturer.startTapCount, 0)
        XCTAssertEqual(transport.openCount, 0)
    }
}
