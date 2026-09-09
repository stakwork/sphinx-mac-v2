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
    )

    func stop()
}

/// `@unchecked Sendable` because AVAudioEngine and the input tap are not
/// Sendable; tap callbacks run on the realtime audio thread and mutable
/// state is serialized by `NSLock`.
final class AVAudioEngineStrutCapturer: StrutAudioCapturer, @unchecked Sendable {

    /// Requested tap size only — hardware delivers 512/1024 typically.
    /// Never `sampleRate / 10`.
    private static let tapBufferSize: AVAudioFrameCount = 1024

    private let engine = AVAudioEngine()
    private let sendQueue = DispatchQueue(label: "com.sphinx.strut.dictation.send")
    private let lock = NSLock()

    private var declaredRate: Int = 0
    private var accumulator = StrutPCMFrameAccumulator(declaredRate: 1)
    private var tapInstalled = false
    private var configObserver: NSObjectProtocol?

    private var onPCM: (@Sendable (Data) -> Void)?
    private var onConfigurationChange: (@Sendable () -> Void)?
    private var onSampleRateMismatch: (@Sendable (Int) -> Void)?

    func prepare() throws -> Int {
        engine.prepare()
        do {
            try engine.start()
        } catch {
            throw StrutAudioCaptureError.engineFailed(error.localizedDescription)
        }

        let format = engine.inputNode.outputFormat(forBus: 0)
        let sampleRate = format.sampleRate
        guard sampleRate > 0 else {
            engine.stop()
            throw StrutAudioCaptureError.invalidSampleRate
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
    ) {
        lock.lock()
        self.onPCM = onPCM
        self.onConfigurationChange = onConfigurationChange
        self.onSampleRateMismatch = onSampleRateMismatch
        let format = engine.inputNode.outputFormat(forBus: 0)
        tapInstalled = true
        lock.unlock()

        engine.inputNode.installTap(
            onBus: 0,
            bufferSize: Self.tapBufferSize,
            format: format
        ) { [weak self] buffer, _ in
            self?.handleTap(buffer)
        }
    }

    func stop() {
        lock.lock()
        let wasInstalled = tapInstalled
        tapInstalled = false
        onPCM = nil
        onConfigurationChange = nil
        onSampleRateMismatch = nil
        accumulator.reset()
        lock.unlock()

        if wasInstalled {
            engine.inputNode.removeTap(onBus: 0)
        }
        if engine.isRunning {
            engine.stop()
        }
        if let observer = configObserver {
            NotificationCenter.default.removeObserver(observer)
            configObserver = nil
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
