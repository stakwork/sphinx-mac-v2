//
//  StrutAudioCapturer.swift
//  com.stakwork.sphinx.desktop
//
//  First AVAudioEngine input-tap usage on macOS in this app.
//  Starts the engine before reading format (stopped engines can report
//  sampleRate == 0). Converts on the audio thread, accumulates ~100ms of
//  PCM16LE, then enqueues Data onto a serial send queue.
//

import AVFoundation
import Foundation

enum StrutAudioCaptureError: Error, Equatable, Sendable {
    case invalidSampleRate
    case engineFailed(String)
}

/// Accumulates converted PCM16LE until ~100ms at the declared integer rate
/// (`declaredRate / 10` frames × 2 bytes). Shared by the production capturer
/// and test doubles so chunking is identical.
struct StrutPCMFrameAccumulator {
    let bytesPerChunk: Int
    private var buffer = Data()

    init(declaredRate: Int) {
        let frames = max(1, declaredRate / 10)
        self.bytesPerChunk = frames * MemoryLayout<Int16>.size
    }

    mutating func append(_ pcm: Data) -> [Data] {
        guard !pcm.isEmpty else { return [] }
        buffer.append(pcm)
        var chunks: [Data] = []
        while buffer.count >= bytesPerChunk {
            chunks.append(Data(buffer.prefix(bytesPerChunk)))
            buffer.removeSubrange(0..<bytesPerChunk)
        }
        return chunks
    }

    mutating func reset() {
        buffer.removeAll(keepingCapacity: false)
    }
}

protocol StrutAudioCapturer: AnyObject, Sendable {
    /// `prepare()` + `engine.start()`, then read `inputNode.outputFormat(forBus: 0)`.
    /// Does not install the tap — caller sends the `start` frame first.
    func prepare() throws -> Int

    func startTap(
        onPCM: @escaping @Sendable (Data) -> Void,
        onConfigurationChange: @escaping @Sendable () -> Void,
        onSampleRateMismatch: @escaping @Sendable (Int) -> Void
    ) throws

    func stop()
}

/// `@unchecked Sendable` because AVAudioEngine and the input tap are not
/// Sendable; tap callbacks run on the realtime audio thread and mutable
/// state is serialized by `NSLock`.
final class AVAudioEngineStrutCapturer: StrutAudioCapturer, @unchecked Sendable {

    /// Requested tap size only — hardware delivers 512/1024 typically.
    /// Never `sampleRate / 10`.
    private static let tapBufferSize: AVAudioFrameCount = 1024

    /// Keeps retired `AVAudioEngine` instances alive until AVFAudio's async
    /// IOUnit property listener has drained. Mirrors
    /// `CallParticipantsSocketManager.disconnecting`. The delayed release
    /// captures only the engine identity, never `self`.
    private static let drainLock = NSLock()
    nonisolated(unsafe) private static var draining: [AVAudioEngine] = []

    private var engine = AVAudioEngine()
    private let sendQueue = DispatchQueue(label: "com.sphinx.strut.dictation.send")
    private let lock = NSLock()

    private var declaredRate: Int = 0
    private var accumulator = StrutPCMFrameAccumulator(declaredRate: 1)
    private var tapInstalled = false
    /// Set when an ObjC exception is caught from AVFAudio. Teardown must not
    /// call `isRunning` / `removeTap` / `stop()` on a half-built graph.
    private var isEngineUnusable = false
    private var configObserver: NSObjectProtocol?

    private var onPCM: (@Sendable (Data) -> Void)?
    private var onConfigurationChange: (@Sendable () -> Void)?
    private var onSampleRateMismatch: (@Sendable (Int) -> Void)?

    deinit {
        // Must return immediately: an unstructured delayed Task capturing `self`
        // here would use a destroyed object. Retire the engine without `self`.
        teardownCurrentEngine(replaceWithFresh: false)
    }

    func prepare() throws -> Int {
        // Never reuse a draining instance — retire the current engine (if any)
        // then allocate a fresh one so this start cannot touch the drain list.
        teardownCurrentEngine(replaceWithFresh: false)
        engine = AVAudioEngine()

        // On macOS the engine's I/O nodes are created lazily on first access.
        // Touching `inputNode` before `prepare()` / `start()` builds the node
        // graph; skipping it makes `-[AVAudioEngine prepare]` raise the
        // uncatchable `required condition is false: inputNode != nullptr ||
        // outputNode != nullptr` exception.
        let inputNode = try runAVFAudioSafely(op: "inputNode") { () -> AVAudioInputNode in
            let inputNode = engine.inputNode
            let inputFormat = inputNode.inputFormat(forBus: 0)
            guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0 else {
                // No usable input device / mic access — surface as a catchable error
                // instead of letting the engine assert.
                throw StrutAudioCaptureError.engineFailed("no audio input device available")
            }
            return inputNode
        }

        try runAVFAudioSafely(op: "prepare") {
            engine.prepare()
        }

        try runAVFAudioSafely(op: "start") {
            do {
                try engine.start()
            } catch {
                throw StrutAudioCaptureError.engineFailed(error.localizedDescription)
            }
        }

        let sampleRate = try runAVFAudioSafely(op: "outputFormat") { () -> Double in
            let format = inputNode.outputFormat(forBus: 0)
            let sampleRate = format.sampleRate
            guard sampleRate > 0 else {
                // Leave the engine running so `stop()` can drain it; do not
                // `engine.stop()` here (that would skip the drain list).
                throw StrutAudioCaptureError.invalidSampleRate
            }
            return sampleRate
        }

        let declared = Int(sampleRate.rounded())
        lock.lock()
        declaredRate = declared
        accumulator = StrutPCMFrameAccumulator(declaredRate: declared)
        lock.unlock()

        observeConfigurationChanges()
        return declared
    }

    func startTap(
        onPCM: @escaping @Sendable (Data) -> Void,
        onConfigurationChange: @escaping @Sendable () -> Void,
        onSampleRateMismatch: @escaping @Sendable (Int) -> Void
    ) throws {
        lock.lock()
        self.onPCM = onPCM
        self.onConfigurationChange = onConfigurationChange
        self.onSampleRateMismatch = onSampleRateMismatch
        lock.unlock()

        try runAVFAudioSafely(op: "startTap", markUnusableOnException: false) {
            let format = engine.inputNode.outputFormat(forBus: 0)
            engine.inputNode.installTap(
                onBus: 0,
                bufferSize: Self.tapBufferSize,
                format: format
            ) { [weak self] buffer, _ in
                self?.handleTap(buffer)
            }
        }

        lock.lock()
        tapInstalled = true
        lock.unlock()
    }

    func stop() {
        teardownCurrentEngine(replaceWithFresh: true)
    }

    /// Converts AVFAudio Objective-C `NSException`s into `StrutAudioCaptureError`
    /// so Swift `do/catch` can fail the session instead of terminating.
    ///
    /// Uses the same mechanics as `CoreDataManager.performSafely`
    /// (`withoutActuallyEscaping` + `autoreleasepool` + `NSExceptionCatcher`)
    /// so the ObjC block wrapper does not SIGTRAP. Unlike `performSafely`,
    /// inner Swift errors are rethrown rather than swallowed.
    private func runAVFAudioSafely<T>(
        op: String,
        markUnusableOnException: Bool = true,
        _ body: () throws -> T
    ) throws -> T {
        var result: T?
        var swiftError: NSError?
        var exceptionReason: NSString?
        var caughtException = false

        // withoutActuallyEscaping is safe here because NSExceptionCatcher.tryExecute
        // calls the block synchronously and never stores it beyond the call.
        // The autoreleasepool forces the ObjC block wrapper to be released before
        // withoutActuallyEscaping checks the refcount — without it, ObjC ARC
        // autoreleases the block parameter, leaving a dangling retain that causes
        // "non-escaping closure has escaped" SIGTRAP.
        withoutActuallyEscaping(body) { escapableBlock in
            let succeeded = autoreleasepool {
                NSExceptionCatcher.tryExecute({
                    do {
                        result = try escapableBlock()
                    } catch {
                        swiftError = error as NSError
                    }
                }, exceptionReason: &exceptionReason)
            }
            if !succeeded {
                caughtException = true
            }
        }

        if let error = swiftError {
            throw error
        }
        if caughtException {
            let reason = (exceptionReason as String?) ?? "unknown"
            if markUnusableOnException {
                isEngineUnusable = true
            }
            AppLogger.shared.log(
                level: .error,
                message: "[StrutDictation] engine \(op) exception reason=\(reason)"
            )
            throw StrutAudioCaptureError.engineFailed(reason)
        }
        guard let result else {
            throw StrutAudioCaptureError.engineFailed("\(op) returned no result")
        }
        return result
    }

    /// Synchronous teardown. Observer is removed first so a configuration-change
    /// posted during stop cannot reach a stopping engine. The retired engine is
    /// then moved onto the static drain list and replaced so `prepare()` cannot
    /// touch it.
    private func teardownCurrentEngine(replaceWithFresh: Bool) {
        if let observer = configObserver {
            NotificationCenter.default.removeObserver(observer)
            configObserver = nil
        }

        lock.lock()
        let wasInstalled = tapInstalled
        tapInstalled = false
        onPCM = nil
        onConfigurationChange = nil
        onSampleRateMismatch = nil
        accumulator.reset()
        lock.unlock()

        // A graph that raised an ObjC exception never ran real I/O — skip
        // `isRunning` / `removeTap` / `stop()` and do not drain it.
        if isEngineUnusable {
            isEngineUnusable = false
            if replaceWithFresh {
                engine = AVAudioEngine()
            }
            return
        }

        let wasRunning = engine.isRunning
        if wasInstalled {
            engine.inputNode.removeTap(onBus: 0)
        }
        if wasRunning {
            engine.stop()
        }

        // Only drain engines that actually ran I/O — unused placeholders have
        // no IOUnit listener and can deallocate immediately.
        if wasInstalled || wasRunning {
            let retired = engine
            Self.drainLock.lock()
            let alreadyDraining = Self.draining.contains(where: { $0 === retired })
            if !alreadyDraining {
                Self.draining.append(retired)
            }
            Self.drainLock.unlock()

            if !alreadyDraining {
                AppLogger.shared.log(
                    level: .info,
                    message: "[StrutDictation] engine retained for drain"
                )
                // Identity only — the static list retains `retired`. Never capture `self`.
                let retiredID = ObjectIdentifier(retired)
                DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(500)) {
                    Self.drainLock.lock()
                    Self.draining.removeAll { ObjectIdentifier($0) == retiredID }
                    Self.drainLock.unlock()
                    AppLogger.shared.log(
                        level: .info,
                        message: "[StrutDictation] engine released"
                    )
                }
            }
        }

        if replaceWithFresh {
            engine = AVAudioEngine()
        }
    }

    // MARK: - Audio thread

    /// Convert + accumulate on the audio thread. No MainActor work here.
    private func handleTap(_ buffer: AVAudioPCMBuffer) {
        let bufferRate = Int(buffer.format.sampleRate.rounded())

        lock.lock()
        guard tapInstalled else {
            lock.unlock()
            return
        }
        let declared = declaredRate
        if bufferRate != declared {
            let mismatch = onSampleRateMismatch
            lock.unlock()
            sendQueue.async {
                mismatch?(bufferRate)
            }
            return
        }
        let pcm = StrutPCM.pcm16LE(from: buffer)
        let chunks = accumulator.append(pcm)
        let callback = onPCM
        lock.unlock()

        guard !chunks.isEmpty else { return }
        sendQueue.async {
            for chunk in chunks {
                callback?(chunk)
            }
        }
    }

    private func observeConfigurationChanges() {
        if let observer = configObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.lock.lock()
            let callback = self.onConfigurationChange
            self.lock.unlock()
            self.sendQueue.async {
                callback?()
            }
        }
    }
}
