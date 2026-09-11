//
//  StrutProcessController.swift
//  com.stakwork.sphinx.desktop
//
//  Launch-scoped owner of the bundled Strut child process. Spawns a genuine
//  arm64 Node runtime, waits for a valid ready line, health-checks, then
//  writes host/port/key into StrutConnection's in-memory overlay. Never
//  writes the ready-line key through the apiKey setter. Does not restart
//  a child that dies after ready.
//

import Foundation
import MachO

// MARK: - Process abstraction

protocol StrutProcessRunning: AnyObject, Sendable {
    var isRunning: Bool { get }
    var terminationStatus: Int32 { get }
    var terminationHandler: (@Sendable () -> Void)? { get set }

    func run() throws
    func terminate()
    func killProcess()
    func waitUntilExit(timeout: TimeInterval) -> Bool
    func stdoutLines() -> AsyncStream<String>
}

protocol StrutProcessSpawning: Sendable {
    func spawn(
        executable: URL,
        arguments: [String],
        currentDirectory: URL,
        environment: [String: String]
    ) throws -> any StrutProcessRunning
}

/// Production wrapper around `Foundation.Process` + dedicated stdout/stderr
/// pipes. `@unchecked Sendable` because pipe handlers and `Process` mutate
/// from Foundation callback threads; buffer/continuation access is locked.
final class FoundationStrutProcess: StrutProcessRunning, @unchecked Sendable {
    private let process: Process
    private let stdoutPipe: Pipe
    private let stderrPipe: Pipe
    private let lock = NSLock()
    private var stdoutBuffer = Data()
    private var didFinishStdout = false
    private let stream: AsyncStream<String>
    private let continuation: AsyncStream<String>.Continuation
    private var forwardedTerminationHandler: (@Sendable () -> Void)?

    var terminationHandler: (@Sendable () -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return forwardedTerminationHandler
        }
        set {
            lock.lock()
            forwardedTerminationHandler = newValue
            lock.unlock()
        }
    }

    var isRunning: Bool { process.isRunning }
    var terminationStatus: Int32 { process.terminationStatus }

    init(
        executable: URL,
        arguments: [String],
        currentDirectory: URL,
        environment: [String: String]
    ) {
        process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.environment = environment
        process.standardInput = FileHandle.nullDevice

        stdoutPipe = Pipe()
        stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var captured: AsyncStream<String>.Continuation!
        stream = AsyncStream { captured = $0 }
        continuation = captured

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            self?.consumeStdout(data, eof: data.isEmpty)
        }

        // Drain stderr so a noisy child cannot fill the pipe and deadlock.
        // Log a boundary only — never the raw bytes (may contain secrets).
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            AppLogger.shared.log(
                level: .info,
                message: "[StrutProcess] child stderr (\(data.count) bytes)"
            )
        }

        process.terminationHandler = { [weak self] _ in
            self?.consumeStdout(Data(), eof: true)
            let handler = self?.terminationHandler
            handler?()
        }
    }

    func stdoutLines() -> AsyncStream<String> { stream }

    func run() throws {
        try process.run()
    }

    func terminate() {
        if process.isRunning {
            process.terminate()
        }
    }

    func killProcess() {
        let pid = process.processIdentifier
        if pid > 0, process.isRunning {
            kill(pid, SIGKILL)
        }
    }

    func waitUntilExit(timeout: TimeInterval) -> Bool {
        if !process.isRunning { return true }
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async { [process] in
            process.waitUntilExit()
            group.leave()
        }
        return group.wait(timeout: .now() + timeout) == .success
    }

    private func consumeStdout(_ data: Data, eof: Bool) {
        var lines: [String] = []
        var finish = false
        lock.lock()
        if !didFinishStdout {
            if !data.isEmpty {
                stdoutBuffer.append(data)
            }
            let newline = Data([0x0a])
            while let range = stdoutBuffer.range(of: newline) {
                let lineData = stdoutBuffer.subdata(in: 0..<range.lowerBound)
                stdoutBuffer.removeSubrange(0..<range.upperBound)
                if let line = String(data: lineData, encoding: .utf8) {
                    lines.append(line.trimmingCharacters(in: CharacterSet(charactersIn: "\r")))
                }
            }
            if eof {
                if !stdoutBuffer.isEmpty, let line = String(data: stdoutBuffer, encoding: .utf8) {
                    lines.append(line)
                    stdoutBuffer.removeAll()
                }
                didFinishStdout = true
                finish = true
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
            }
        }
        lock.unlock()
        for line in lines {
            continuation.yield(line)
        }
        if finish {
            continuation.finish()
        }
    }
}

struct FoundationStrutProcessFactory: StrutProcessSpawning {
    func spawn(
        executable: URL,
        arguments: [String],
        currentDirectory: URL,
        environment: [String: String]
    ) throws -> any StrutProcessRunning {
        FoundationStrutProcess(
            executable: executable,
            arguments: arguments,
            currentDirectory: currentDirectory,
            environment: environment
        )
    }
}

// MARK: - Mach-O arm64 check

enum StrutMachO {
    static let cpuTypeARM64: UInt32 = UInt32(bitPattern: CPU_TYPE_ARM64)
    static let cpuTypeX86_64: UInt32 = UInt32(bitPattern: CPU_TYPE_X86_64)

    static func containsARM64(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            return false
        }
        return containsARM64(in: data)
    }

    static func containsARM64(in data: Data) -> Bool {
        guard data.count >= 8 else { return false }
        let magic = readUInt32(data, offset: 0, swap: false)
        switch magic {
        case MH_MAGIC_64:
            return readUInt32(data, offset: 4, swap: false) == cpuTypeARM64
        case MH_CIGAM_64:
            return readUInt32(data, offset: 4, swap: true) == cpuTypeARM64
        case FAT_MAGIC, FAT_MAGIC_64:
            return fatContainsARM64(data, swap: false, is64: magic == FAT_MAGIC_64)
        case FAT_CIGAM, FAT_CIGAM_64:
            return fatContainsARM64(data, swap: true, is64: magic == FAT_CIGAM_64)
        default:
            return false
        }
    }

    private static func fatContainsARM64(_ data: Data, swap: Bool, is64: Bool) -> Bool {
        guard data.count >= 8 else { return false }
        let nfat = Int(readUInt32(data, offset: 4, swap: swap))
        guard nfat > 0, nfat < 64 else { return false }
        let archSize = is64 ? 32 : 20
        for index in 0..<nfat {
            let offset = 8 + index * archSize
            guard data.count >= offset + 4 else { return false }
            let cpuType = readUInt32(data, offset: offset, swap: swap)
            if cpuType == cpuTypeARM64 { return true }
        }
        return false
    }

    private static func readUInt32(_ data: Data, offset: Int, swap: Bool) -> UInt32 {
        let slice = data[offset..<(offset + 4)]
        var value: UInt32 = 0
        Swift.withUnsafeMutableBytes(of: &value) { dest in
            slice.withUnsafeBytes { raw in
                dest.copyBytes(from: raw)
            }
        }
        return swap ? value.byteSwapped : value
    }
}

// MARK: - Controller

/// `@unchecked Sendable` because this is a process-wide owner whose mutable
/// state is the child `Process` plus the injected connection. Overlay writes
/// and the termination handler are serialized on `overlayQueue`, matching
/// `StrutConnection`'s occupancyLock justification.
final class StrutProcessController: @unchecked Sendable {

    /// Frozen argv entry for the bundled helper (`Contents/Strut/desktop.js`).
    ///
    /// Packaging spike (T3 / cmtwz42og0005l1041ujkorf3): strut's desktop
    /// launcher is `desktop.js` (`stakwork/strut` v0.1.1,
    /// `plans/native-dictation-client.md` §0). A host spawns
    /// `node <Strut>/desktop.js` with `currentDirectoryURL` = that folder.
    /// `sherpa-onnx-node`'s addon loader is patched upstream
    /// (`scripts/package-desktop.mjs`'s `relocateNative`) to `require` its
    /// native addon from `<Strut>/native/sherpa-onnx.node` directly, rather
    /// than resolving a `sherpa-onnx-<platform>` optional dependency via
    /// `os.arch()`. Do not pass the `strut` shell wrapper; do not invent a
    /// `strut.js` filename.
    ///
    /// `node` itself ships outside the strut tarball (fetched separately
    /// from nodejs.org) and is placed in the same `native/` directory, so
    /// every Mach-O the host code-signs lives in one binaries-only folder.
    ///
    /// The helper is embedded at `Contents/Strut`, deliberately NOT
    /// `Contents/Helpers/Strut`: `Contents/Helpers/` is a reserved bundle
    /// location (like Frameworks/PlugIns/XPCServices) where codesign
    /// requires everything to be independently-signed nested code and
    /// rejects any plain resource file outright — confirmed with a minimal
    /// repro (a lone resource file under `Contents/Helpers/x/`, no Mach-O
    /// involved, already fails to seal; the identical tree under
    /// `Contents/Strut/` signs fine). Do not move this back under Helpers/.
    ///
    /// Helper entitlements (`StrutNode.entitlements`): sandbox inherit +
    /// `cs.allow-jit`. No `cs.disable-library-validation`. Do not add
    /// `cs.allow-unsigned-executable-memory` unless a signed Apple Silicon
    /// build dies in V8 isolate setup.
    static let defaultEntryFileName = "desktop.js"
    static let defaultNodeBinaryName = "node"
    static let defaultNativeDirName = "native"
    /// 10s is enough for Node 22 + sherpa-onnx-node cold start on Apple
    /// Silicon (typically 1–3s; recognizer ready is ~1s after listen).
    /// Bump only if a signed spike measures a longer ready-line delay.
    static let defaultReadyLineTimeout: TimeInterval = 10
    static let defaultStopWaitTimeout: TimeInterval = 2

    nonisolated(unsafe) static let shared = StrutProcessController()

    private let connection: StrutConnection
    private let processFactory: any StrutProcessSpawning
    private let helperFolderURL: @Sendable () -> URL
    private let writableDirectoryURL: @Sendable () -> URL
    private let entryFileName: String
    private let nodeBinaryName: String
    private let nativeDirName: String
    private let readyLineTimeout: TimeInterval
    private let stopWaitTimeout: TimeInterval
    private let fileManager: FileManager

    private let overlayQueue = DispatchQueue(label: "com.sphinx.strutprocess.overlay")
    private let stateLock = StrutAsyncLock()
    nonisolated(unsafe) private var currentProcess: (any StrutProcessRunning)?
    nonisolated(unsafe) private var startGeneration: UInt64 = 0

    init(
        connection: StrutConnection = .shared,
        processFactory: any StrutProcessSpawning = FoundationStrutProcessFactory(),
        helperFolderURL: @escaping @Sendable () -> URL = {
            Bundle.main.bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Strut", isDirectory: true)
        },
        writableDirectoryURL: @escaping @Sendable () -> URL = {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
            return appSupport
                .appendingPathComponent("Sphinx", isDirectory: true)
                .appendingPathComponent("Strut", isDirectory: true)
        },
        entryFileName: String = StrutProcessController.defaultEntryFileName,
        nodeBinaryName: String = StrutProcessController.defaultNodeBinaryName,
        nativeDirName: String = StrutProcessController.defaultNativeDirName,
        readyLineTimeout: TimeInterval = StrutProcessController.defaultReadyLineTimeout,
        stopWaitTimeout: TimeInterval = StrutProcessController.defaultStopWaitTimeout,
        fileManager: FileManager = .default
    ) {
        self.connection = connection
        self.processFactory = processFactory
        self.helperFolderURL = helperFolderURL
        self.writableDirectoryURL = writableDirectoryURL
        self.entryFileName = entryFileName
        self.nodeBinaryName = nodeBinaryName
        self.nativeDirName = nativeDirName
        self.readyLineTimeout = readyLineTimeout
        self.stopWaitTimeout = stopWaitTimeout
        self.fileManager = fileManager
    }

    // MARK: - Start

    func start() async {
        await Task.detached(priority: .userInitiated) { [self] in
            await self.performStart()
        }.value
    }

    private func performStart() async {
        if isChildRunning() {
            stop()
        }

        stateLock.lock()
        startGeneration += 1
        let generation = startGeneration
        stateLock.unlock()

        // Activate a cleared overlay and delete any persisted strut key so a
        // stale secret cannot leak through. Do not health-check yet: an empty
        // base URL still falls back to the default local port.
        clearOverlay()
        connection.apiKey = ""

        guard let spawnPlan = resolveSpawnPlan() else { return }

        log("[StrutProcess] spawn start")

        let child: any StrutProcessRunning
        do {
            child = try processFactory.spawn(
                executable: spawnPlan.nodeURL,
                arguments: [spawnPlan.entryURL.path],
                currentDirectory: spawnPlan.helperFolder,
                environment: spawnPlan.environment
            )
        } catch {
            failStart(reason: "spawn failure", child: nil)
            return
        }

        installTerminationHandler(child, generation: generation)
        setCurrentProcess(child)

        do {
            try child.run()
        } catch {
            failStart(reason: "spawn failure", child: child)
            return
        }

        let waitResult = await waitForReadyLine(on: child)
        switch waitResult {
        case .timeout:
            failStart(reason: "ready timeout", child: child)
        case .exited:
            failStart(reason: "child exited", child: child)
        case .invalidReady:
            failStart(reason: "invalid ready line", child: child)
        case .ready(let line):
            await publishAfterHealth(line: line, child: child, generation: generation)
        }
    }

    // MARK: - Stop

    func stop() {
        let child = takeCurrentProcess()
        if let child, child.isRunning {
            terminateChild(child, reason: nil)
        }
        clearOverlay()
    }

    // MARK: - Spawn plan

    private struct SpawnPlan {
        let helperFolder: URL
        let nodeURL: URL
        let entryURL: URL
        let environment: [String: String]
    }

    private func resolveSpawnPlan() -> SpawnPlan? {
        let helperFolder = helperFolderURL()
        var isDirectory: ObjCBool = false
        let helperExists = fileManager.fileExists(
            atPath: helperFolder.path,
            isDirectory: &isDirectory
        )
        let nodeURL = helperFolder
            .appendingPathComponent(nativeDirName, isDirectory: true)
            .appendingPathComponent(nodeBinaryName)
        let entryURL = helperFolder.appendingPathComponent(entryFileName)

        guard helperExists, isDirectory.boolValue,
              fileManager.fileExists(atPath: nodeURL.path) else {
            failStart(reason: "missing binary", child: nil)
            return nil
        }

        guard StrutMachO.containsARM64(at: nodeURL) else {
            log("[StrutProcess] arm64 reject")
            failStart(reason: "non-arm64", child: nil)
            return nil
        }

        let writable = writableDirectoryURL()
        do {
            try fileManager.createDirectory(
                at: writable,
                withIntermediateDirectories: true
            )
        } catch {
            failStart(reason: "spawn failure", child: nil)
            return nil
        }

        var environment = ProcessInfo.processInfo.environment
        for key in environment.keys where key.hasPrefix("DYLD_") {
            environment.removeValue(forKey: key)
        }
        environment["HOME"] = writable.path
        environment["TMPDIR"] = writable.path

        return SpawnPlan(
            helperFolder: helperFolder,
            nodeURL: nodeURL,
            entryURL: entryURL,
            environment: environment
        )
    }

    // MARK: - Ready wait / health

    private enum ReadyWaitResult {
        case ready(StrutReadyLine)
        case timeout
        case exited
        case invalidReady
    }

    private func waitForReadyLine(on child: any StrutProcessRunning) async -> ReadyWaitResult {
        await withTaskGroup(of: ReadyWaitResult.self) { group in
            group.addTask {
                var sawLine = false
                for await line in child.stdoutLines() {
                    sawLine = true
                    if let parsed = StrutReadyLine.parse(line) {
                        return .ready(parsed)
                    }
                }
                return sawLine ? .invalidReady : .exited
            }
            group.addTask { [readyLineTimeout] in
                let nanoseconds = UInt64(max(readyLineTimeout, 0) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                return .timeout
            }
            let first = await group.next() ?? .timeout
            group.cancelAll()
            return first
        }
    }

    private func publishAfterHealth(
        line: StrutReadyLine,
        child: any StrutProcessRunning,
        generation: UInt64
    ) async {
        let baseURLString = Self.baseURLString(host: line.host, port: line.port)

        // Host/port only — empty key so readyConnection() stays .missingAPIKey
        // until health succeeds.
        let publishedHostPort = applyOverlayIfCurrent(
            child: child,
            generation: generation,
            baseURLString: baseURLString,
            apiKey: ""
        )
        guard publishedHostPort else {
            failStart(reason: "child exited", child: child)
            return
        }
        log("[StrutProcess] ready applied host=\(line.host) port=\(line.port)")

        let health = await connection.checkHealth()
        switch health {
        case .reachable:
            log("[StrutProcess] health reachable")
            applyOverlayIfCurrent(
                child: child,
                generation: generation,
                baseURLString: baseURLString,
                apiKey: line.key
            )
        case .unreachable:
            log("[StrutProcess] health unreachable")
            failStart(reason: "health unreachable", child: child)
        }
    }

    private static func baseURLString(host: String, port: Int) -> String {
        if host.contains(":") && !host.hasPrefix("[") {
            return "http://[\(host)]:\(port)"
        }
        return "http://\(host):\(port)"
    }

    // MARK: - Overlay + child state

    private func installTerminationHandler(
        _ child: any StrutProcessRunning,
        generation: UInt64
    ) {
        child.terminationHandler = { [weak self] in
            guard let self else { return }
            self.overlayQueue.async {
                self.log("[StrutProcess] child exit code \(child.terminationStatus)")
                self.stateLock.lock()
                let matchesGeneration = self.startGeneration == generation
                if self.currentProcess === child {
                    self.currentProcess = nil
                }
                self.stateLock.unlock()
                if matchesGeneration {
                    self.connection.clearLaunchSession()
                    self.log("[StrutProcess] clear-on-failure: child exited")
                }
            }
        }
    }

    @discardableResult
    private func applyOverlayIfCurrent(
        child: any StrutProcessRunning,
        generation: UInt64,
        baseURLString: String,
        apiKey: String
    ) -> Bool {
        overlayQueue.sync {
            guard isSameChildRunning(child, generation: generation) else { return false }
            connection.applyLaunchSession(baseURLString: baseURLString, apiKey: apiKey)
            return true
        }
    }

    private func isSameChildRunning(
        _ child: any StrutProcessRunning,
        generation: UInt64
    ) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return startGeneration == generation
            && currentProcess === child
            && child.isRunning
    }

    private func clearOverlay() {
        overlayQueue.sync {
            connection.clearLaunchSession()
        }
    }

    private func failStart(reason: String, child: (any StrutProcessRunning)?) {
        log("[StrutProcess] clear-on-failure: \(reason)")
        if let child {
            terminateChild(child, reason: reason)
            stateLock.lock()
            if currentProcess === child {
                currentProcess = nil
            }
            stateLock.unlock()
        }
        clearOverlay()
    }

    private func terminateChild(_ child: any StrutProcessRunning, reason: String?) {
        guard child.isRunning else { return }
        log("[StrutProcess] SIGTERM")
        child.terminate()
        let exited = child.waitUntilExit(timeout: stopWaitTimeout)
        if !exited && child.isRunning {
            log("[StrutProcess] SIGKILL fallback")
            child.killProcess()
            _ = child.waitUntilExit(timeout: 1)
        }
    }

    private func isChildRunning() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return currentProcess?.isRunning == true
    }

    private func setCurrentProcess(_ child: any StrutProcessRunning) {
        stateLock.lock()
        currentProcess = child
        stateLock.unlock()
    }

    private func takeCurrentProcess() -> (any StrutProcessRunning)? {
        stateLock.lock()
        defer { stateLock.unlock() }
        let child = currentProcess
        currentProcess = nil
        return child
    }

    private func log(_ message: String) {
        AppLogger.shared.log(level: .info, message: message)
    }
}
