//
//  StrutDictationClient.swift
//  com.stakwork.sphinx.desktop
//
//  Orchestrates mic capture + `/audio/stream`. Caller supplies a captured
//  StrutReadyConnection — this type never calls readyConnection(),
//  checkHealth(), or makeEphemeralSession().
//

import Foundation

protocol StrutDictationMicGate: Sendable {
    func isBusy() async -> Bool
    func requestPermission() async -> Bool
}

struct ProductionStrutDictationMicGate: StrutDictationMicGate {
    func isBusy() async -> Bool {
        if AudioRecorderHelper.shared.state == .Record {
            return true
        }
        return await MainActor.run {
            WindowsManager.sharedInstance.getLiveKitCallWindow() != nil
        }
    }

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                AudioRecorderHelper.requestMicrophonePermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }
}

/// `@unchecked Sendable` because this is a process-wide-style manager whose
/// mutable session state is serialized by `NSLock` — the same pattern as
/// `StrutConnection` / `GraphChatSSEManager`.
final class StrutDictationClient: @unchecked Sendable {

    var onReady: (@Sendable () -> Void)?
    var onPartial: (@Sendable (String) -> Void)?
    var onFinal: (@Sendable (String, Int) -> Void)?
    var onError: (@Sendable (String) -> Void)?

    private let ready: StrutReadyConnection?
    private let transport: any StrutStreamTransport
    private let capturer: any StrutAudioCapturer
    private let micGate: any StrutDictationMicGate
    private let stopTimeout: TimeInterval
    private let restartBackoff: TimeInterval
    /// Minted by the view model after occupancy; reused on device-change restart.
    private let session: String?
    /// Start-frame hotwords; reused on device-change restart, never regenerated.
    private let hotwords: [String]

    private let lock = NSLock()
    private var generation: Int = 0
    private var phase: Phase = .idle
    private var transcript = StrutTranscriptState()
    private var declaredRate: Int = 0
    private var isReconfiguring = false
    private var pendingReconfiguration = false
    private var receivedTrailingFinal = false
    private var receivedClose1000 = false

    /// Keeps the client alive through teardown so an in-flight write cannot
    /// race a released transport (mirrors `CallParticipantsSocketManager.disconnecting`).
    private static let teardownLock = NSLock()
    private static var disconnecting: [StrutDictationClient] = []

    private enum Phase: Equatable {
        case idle
        case starting
        case streaming
        case stopping
        case restarting
    }

    init(
        ready: StrutReadyConnection?,
        transport: (any StrutStreamTransport)? = nil,
        capturer: (any StrutAudioCapturer)? = nil,
        micGate: any StrutDictationMicGate = ProductionStrutDictationMicGate(),
        stopTimeout: TimeInterval = 2.0,
        restartBackoff: TimeInterval = 0.3,
        session: String? = nil,
        hotwords: [String] = []
    ) {
        self.ready = ready
        self.transport = transport ?? URLSessionStrutStreamTransport()
        self.capturer = capturer ?? AVAudioEngineStrutCapturer()
        self.micGate = micGate
        self.stopTimeout = stopTimeout
        self.restartBackoff = restartBackoff
        self.session = session
        self.hotwords = hotwords

        self.transport.setHandlers(
            onMessage: { [weak self] generation, message in
                self?.handleMessage(message, generation: generation)
            },
            onClose: { [weak self] generation, code in
                self?.handleClose(code, generation: generation)
            },
            onFailure: { [weak self] generation, error in
                self?.handleTransportFailure(error, generation: generation)
            }
        )
    }

    // MARK: - Public API

    func start() {
        lock.lock()
        guard phase == .idle else {
            lock.unlock()
            emitError("dictation already in progress")
            return
        }
        phase = .starting
        generation += 1
        let gen = generation
        transcript = StrutTranscriptState()
        receivedTrailingFinal = false
        receivedClose1000 = false
        lock.unlock()

        Task {
            await self.runStart(generation: gen, isRestart: false)
        }
    }

    func stop() {
        Task {
            await self.stopAndWait()
        }
    }

    /// Awaits capturer release and the trailing-final window. Safe to call
    /// concurrently: a second waiter joins the in-flight stop.
    func stopAndWait() async {
        lock.lock()
        let currentPhase = phase
        if currentPhase == .idle {
            lock.unlock()
            return
        }
        if currentPhase == .stopping {
            lock.unlock()
            await waitUntilIdle()
            return
        }
        if currentPhase == .starting || currentPhase == .restarting {
            generation += 1
            phase = .idle
            lock.unlock()
            capturer.stop()
            await self.transport.close(code: 1000)
            return
        }
        phase = .stopping
        lock.unlock()

        await self.finishStop(userInitiated: true)
    }

    private func waitUntilIdle() async {
        while true {
            lock.lock()
            let current = phase
            lock.unlock()
            if current == .idle { return }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    // MARK: - Start

    private func runStart(generation gen: Int, isRestart: Bool) async {
        guard isCurrent(gen) else { return }

        guard let ready else {
            failStart("strut connection is not ready", generation: gen)
            return
        }

        if !isRestart {
            if let schemeError = StrutURLSchemePolicy.validate(ready.baseURL) {
                let message: String
                if case .disallowedScheme(let scheme, let host) = schemeError {
                    message = "disallowed scheme \(scheme) for host \(host)"
                } else {
                    message = "disallowed scheme for host \(ready.baseURL.host ?? "")"
                }
                failStart(message, generation: gen)
                return
            }

            if await micGate.isBusy() {
                guard isCurrent(gen) else { return }
                failStart("microphone is in use", generation: gen)
                return
            }

            let granted = await micGate.requestPermission()
            guard isCurrent(gen) else { return }
            if !granted {
                failStart("microphone permission denied", generation: gen)
                return
            }
        }

        let openResult = await transport.open(ready: ready, generation: gen)
        guard isCurrent(gen) else {
            await transport.close(code: 1000)
            return
        }
        switch openResult {
        case .failure(let error):
            failStart(error.userMessage, generation: gen)
            return
        case .success:
            break
        }

        do {
            let rate = try capturer.prepare()
            guard isCurrent(gen) else {
                capturer.stop()
                await transport.close(code: 1000)
                return
            }
            guard rate > 0 else {
                capturer.stop()
                failStart("input sample rate is 0", generation: gen)
                return
            }

            lock.lock()
            declaredRate = rate
            lock.unlock()

            AppLogger.shared.log(
                level: .info,
                message: "[StrutDictation] start sampleRate=\(rate) host=\(logHost) path=/audio/stream"
            )

            sendTextFrame(
                StrutAudioMessages.encodeStart(
                    sampleRate: rate,
                    session: session,
                    hotwords: hotwords
                )
            )

            lock.lock()
            if generation == gen {
                phase = .streaming
            }
            lock.unlock()

            capturer.startTap(
                onPCM: { [weak self] data in
                    self?.handlePCM(data, generation: gen)
                },
                onConfigurationChange: { [weak self] in
                    self?.noteDeviceChange(generation: gen)
                },
                onSampleRateMismatch: { [weak self] _ in
                    self?.noteDeviceChange(generation: gen)
                }
            )
        } catch {
            failStart("failed to start audio capture", generation: gen)
        }
    }

    private func failStart(_ message: String, generation gen: Int) {
        lock.lock()
        let current = generation
        if current == gen {
            phase = .idle
        }
        lock.unlock()
        guard current == gen else { return }
        capturer.stop()
        Task { await self.transport.close(code: 1000) }
        emitError(message)
    }

    // MARK: - Stop

    private func finishStop(userInitiated: Bool) async {
        retainForDisconnect()
        defer { releaseDisconnect() }

        if userInitiated {
            AppLogger.shared.log(
                level: .info,
                message: "[StrutDictation] user end host=\(logHost) path=/audio/stream"
            )
        }

        capturer.stop()
        sendTextFrame(StrutAudioMessages.encodeEnd())

        let deadline = Date().addingTimeInterval(stopTimeout)
        while Date() < deadline {
            lock.lock()
            let done = receivedTrailingFinal || receivedClose1000
            lock.unlock()
            if done { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        lock.lock()
        let gotFinalOrClose = receivedTrailingFinal || receivedClose1000
        generation += 1
        phase = .idle
        lock.unlock()

        await transport.close(code: 1000)

        if userInitiated && !gotFinalOrClose {
            emitError("stopped without a final response")
        }
    }

    // MARK: - Device-change restart

    private func noteDeviceChange(generation gen: Int) {
        lock.lock()
        guard gen == generation, phase == .streaming else {
            lock.unlock()
            return
        }
        if isReconfiguring {
            pendingReconfiguration = true
            lock.unlock()
            return
        }
        isReconfiguring = true
        pendingReconfiguration = false
        lock.unlock()

        Task {
            await self.restartAfterDeviceChange()
        }
    }

    private func restartAfterDeviceChange() async {
        AppLogger.shared.log(
            level: .info,
            message: "[StrutDictation] device-change restart host=\(logHost) path=/audio/stream"
        )

        lock.lock()
        generation += 1
        let gen = generation
        phase = .restarting
        pendingReconfiguration = false
        receivedTrailingFinal = false
        receivedClose1000 = false
        lock.unlock()

        capturer.stop()
        sendTextFrame(StrutAudioMessages.encodeEnd())
        await transport.close(code: 1000)

        let backoffNs = UInt64(max(restartBackoff, 0) * 1_000_000_000)
        if backoffNs > 0 {
            try? await Task.sleep(nanoseconds: backoffNs)
        }

        guard isCurrent(gen) else {
            lock.lock()
            isReconfiguring = false
            pendingReconfiguration = false
            lock.unlock()
            return
        }

        await runStart(generation: gen, isRestart: true)

        lock.lock()
        isReconfiguring = false
        pendingReconfiguration = false
        lock.unlock()
    }

    // MARK: - Transport / PCM

    private func handlePCM(_ data: Data, generation gen: Int) {
        lock.lock()
        let current = generation
        let currentPhase = phase
        lock.unlock()
        guard gen == current, currentPhase == .streaming else { return }
        transport.send(data: data)
    }

    private func handleMessage(_ message: StrutServerMessage, generation gen: Int) {
        lock.lock()
        guard gen == generation else {
            lock.unlock()
            return
        }
        let currentPhase = phase
        switch message {
        case .ready:
            lock.unlock()
            AppLogger.shared.log(
                level: .info,
                message: "[StrutDictation] ready host=\(logHost) path=/audio/stream"
            )
            emitReady()
        case .partial(let text):
            transcript.apply(partial: text)
            let live = transcript.liveText
            lock.unlock()
            emitPartial(live)
        case .final(let text, let index):
            if currentPhase == .stopping {
                receivedTrailingFinal = true
            }
            transcript.apply(final: text)
            lock.unlock()
            emitFinal(text, index: index)
        case .error(let message):
            phase = .idle
            generation += 1
            lock.unlock()
            capturer.stop()
            emitError(message)
            Task { await self.transport.close(code: 1000) }
        }
    }

    private func handleClose(_ code: Int, generation gen: Int) {
        lock.lock()
        guard gen == generation else {
            lock.unlock()
            return
        }
        if code == 1000 {
            receivedClose1000 = true
        }
        lock.unlock()
    }

    private func handleTransportFailure(
        _ error: StrutStreamTransportError,
        generation gen: Int
    ) {
        lock.lock()
        guard gen == generation else {
            lock.unlock()
            return
        }
        let currentPhase = phase
        if currentPhase == .streaming || currentPhase == .starting || currentPhase == .restarting {
            phase = .idle
            generation += 1
        }
        lock.unlock()
        capturer.stop()
        emitError(error.userMessage)
    }

    // MARK: - Helpers

    private func isCurrent(_ gen: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return gen == generation
    }

    private func sendTextFrame(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }
        transport.send(text: text)
    }

    private var logHost: String {
        ready?.baseURL.host ?? ""
    }

    private func emitReady() {
        let handler = onReady
        Task { @MainActor in handler?() }
    }

    private func emitPartial(_ text: String) {
        let handler = onPartial
        Task { @MainActor in handler?(text) }
    }

    private func emitFinal(_ text: String, index: Int) {
        let handler = onFinal
        Task { @MainActor in handler?(text, index) }
    }

    private func emitError(_ message: String) {
        let handler = onError
        Task { @MainActor in handler?(message) }
    }

    private func retainForDisconnect() {
        Self.teardownLock.lock()
        if !Self.disconnecting.contains(where: { $0 === self }) {
            Self.disconnecting.append(self)
        }
        Self.teardownLock.unlock()
    }

    private func releaseDisconnect() {
        Self.teardownLock.lock()
        Self.disconnecting.removeAll { $0 === self }
        Self.teardownLock.unlock()
    }
}
