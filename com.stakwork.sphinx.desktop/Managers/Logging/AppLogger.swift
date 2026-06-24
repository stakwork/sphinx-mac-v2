// AppLogger.swift
// com.stakwork.sphinx.desktop

import Foundation

private let kLogRetentionHours: Double = 72
private let kMaxLogFileBytes: Int = 5 * 1024 * 1024  // 5 MB hard cap

final class AppLogger: @unchecked Sendable {

    // MARK: - Public types

    enum LogLevel: String {
        case debug   = "DEBUG"
        case info    = "INFO"
        case warning = "WARNING"
        case error   = "ERROR"
    }

    struct LogEntry {
        let id: UUID
        let timestamp: Date
        let level: LogLevel
        let message: String

        init(level: LogLevel = .info, message: String, timestamp: Date = Date()) {
            self.id = UUID()
            self.timestamp = timestamp
            self.level = level
            self.message = message
        }

        /// Formatted as `[2025-01-15T14:32:01Z] [INFO] message`
        var formatted: String {
            "[\(AppLogger.isoFormatter.string(from: timestamp))] [\(level.rawValue)] \(message)"
        }
    }

    // MARK: - Singleton

    nonisolated(unsafe) static let shared = AppLogger()
    private init() {}

    // MARK: - State

    private(set) var entries: [LogEntry] = []
    private var entryObservers: [UUID: (LogEntry) -> Void] = [:]

    private let queue = DispatchQueue(label: "com.sphinx.applogger", qos: .utility)
    private var pipe: Pipe?
    private var originalStdout: Int32 = -1
    private var originalStderr: Int32 = -1
    private var appendHandle: FileHandle?

    // MARK: - Formatters (static so signal handler helpers can use them)

    nonisolated(unsafe) static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // MARK: - Log file URL

    private var logFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Sphinx", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sphinx_logs.txt")
    }

    // MARK: - Start

    func start() {
        // Load previous logs asynchronously — never block launch
        queue.async { [weak self] in
            self?.loadAndPruneExistingLog()
            self?.openAppendHandle()
        }
        redirectStdoutStderr()
        registerSignalHandlers()
    }

    // MARK: - Private – stdout/stderr redirect

    private func redirectStdoutStderr() {
        let p = Pipe()
        self.pipe = p

        // Save originals so we can still write to the terminal
        originalStdout = dup(STDOUT_FILENO)
        originalStderr = dup(STDERR_FILENO)

        // Redirect both stdout and stderr into the pipe
        dup2(p.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        dup2(p.fileHandleForWriting.fileDescriptor, STDERR_FILENO)

        p.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }

            // Echo to original stdout so Xcode console still works
            if let origFD = self?.originalStdout, origFD != -1 {
                _ = data.withUnsafeBytes { write(origFD, $0.baseAddress!, $0.count) }
            }

            // Split into individual lines and store
            let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
            for line in lines {
                self?.ingest(message: line, level: .info)
            }
        }
    }

    private func ingest(message: String, level: LogLevel) {
        let entry = LogEntry(level: level, message: message)
        queue.async { [weak self] in
            guard let self else { return }
            self.entries.append(entry)
            self.writeEntryToFile(entry)
            let observers = self.entryObservers
            DispatchQueue.main.async {
                observers.values.forEach { $0(entry) }
            }
        }
    }

    // MARK: - Private – file I/O

    private func openAppendHandle() {
        let url = logFileURL
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        appendHandle = try? FileHandle(forWritingTo: url)
        appendHandle?.seekToEndOfFile()
    }

    private func writeEntryToFile(_ entry: LogEntry) {
        guard let data = (entry.formatted + "\n").data(using: .utf8) else { return }
        if let handle = appendHandle {
            handle.write(data)
        } else {
            // Handle not ready yet (still loading on startup); create file and write
            let url = logFileURL
            if FileManager.default.fileExists(atPath: url.path) {
                if let h = try? FileHandle(forWritingTo: url) {
                    h.seekToEndOfFile(); h.write(data); try? h.close()
                }
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private func loadAndPruneExistingLog() {
        let url = logFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        // If the file exceeds the hard cap, keep only the tail before parsing
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let rawContent: String
        if fileSize > kMaxLogFileBytes {
            // Read the last 5 MB and drop the first (likely partial) line
            guard let handle = try? FileHandle(forReadingFrom: url) else { return }
            let offset = UInt64(max(0, fileSize - kMaxLogFileBytes))
            try? handle.seek(toOffset: offset)
            let data = handle.readDataToEndOfFile()
            try? handle.close()
            guard var tail = String(data: data, encoding: .utf8) else { return }
            // Drop the potentially-truncated first line
            if let nl = tail.range(of: "\n") { tail = String(tail[nl.upperBound...]) }
            rawContent = tail
        } else {
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
            rawContent = content
        }

        let cutoff = Date().addingTimeInterval(-kLogRetentionHours * 3600)
        var kept: [LogEntry] = []
        for line in rawContent.components(separatedBy: .newlines) where !line.isEmpty {
            if let entry = parseLogLine(line), entry.timestamp >= cutoff {
                kept.append(entry)
            }
        }
        entries = kept

        // Rewrite pruned content
        let pruned = kept.map { $0.formatted }.joined(separator: "\n")
        try? pruned.write(to: url, atomically: true, encoding: .utf8)
    }

    private func parseLogLine(_ line: String) -> LogEntry? {
        // Expected format: [2025-01-15T14:32:01Z] [INFO] message
        guard line.hasPrefix("[") else { return nil }
        let parts = line.components(separatedBy: "] ")
        guard parts.count >= 3 else { return nil }
        let tsRaw = String(parts[0].dropFirst())  // strip leading "["
        guard let date = AppLogger.isoFormatter.date(from: tsRaw) else { return nil }
        let levelRaw = String(parts[1].dropFirst())  // strip "["
        let level = LogLevel(rawValue: levelRaw) ?? .info
        let message = parts[2...].joined(separator: "] ")
        return LogEntry(level: level, message: message, timestamp: date)
    }

    // MARK: - Public API

    /// Register a callback invoked on the main thread for every new log entry.
    /// Returns a token that must be passed to `removeObserver` to unsubscribe.
    func addObserver(_ handler: @escaping (LogEntry) -> Void) -> UUID {
        let id = UUID()
        queue.async { [weak self] in
            self?.entryObservers[id] = handler
        }
        return id
    }

    func removeObserver(_ id: UUID) {
        queue.async { [weak self] in
            self?.entryObservers.removeValue(forKey: id)
        }
    }

    /// Flush in-memory entries to disk (call on app terminate / background)
    func flush() {
        queue.sync {
            try? appendHandle?.synchronizeFile()
        }
    }

    /// Write current buffer to a timestamped temp file and return the URL
    func exportedFileURL() -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let stamp = formatter.string(from: Date())
        let fileName = "sphinx_logs_\(stamp).txt"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        let content = entries.map { $0.formatted }.joined(separator: "\n")
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    /// Clear in-memory buffer and delete on-disk log file
    func clear() {
        queue.async { [weak self] in
            guard let self else { return }
            self.entries.removeAll()
            try? self.appendHandle?.close()
            self.appendHandle = nil
            try? FileManager.default.removeItem(at: self.logFileURL)
        }
    }

    // MARK: - Signal handlers

    private func registerSignalHandlers() {
        AppLoggerSignalBridge.install(logFilePath: logFileURL.path)
    }
}

// MARK: - C-compatible signal bridge

/// Thin wrapper that stores the log-file path in a C-accessible global and registers
/// async-signal-safe signal handlers for the common crash signals.
enum AppLoggerSignalBridge {

    static func install(logFilePath: String) {
        // Store path in a C global (max 1023 chars)
        logFilePath.withCString { ptr in
            strncpy(&gSignalLogPath.0, ptr, MemoryLayout.size(ofValue: gSignalLogPath) - 1)
        }

        for sig in [SIGSEGV, SIGABRT, SIGILL, SIGBUS, SIGFPE] {
            signal(sig) { signum in
                // Only async-signal-safe POSIX syscalls here — no Swift heap
                // allocation, no ObjC, no Foundation. String(cString:) and
                // FileHandle are not signal-safe and will crash if the runtime
                // heap is corrupted at the point the signal fires.
                withUnsafePointer(to: gSignalLogPath) { ptr in
                    let pathPtr = UnsafeRawPointer(ptr).assumingMemoryBound(to: CChar.self)
                    guard pathPtr.pointee != 0 else { return }
                    let fd = open(pathPtr, O_WRONLY | O_CREAT | O_APPEND, 0o644)
                    guard fd >= 0 else { return }
                    let marker: StaticString = "CRASH — signal received\n"
                    marker.withUTF8Buffer { buf in
                        _ = Darwin.write(fd, buf.baseAddress!, buf.count)
                    }
                    _ = Darwin.close(fd)
                }
                signal(signum, SIG_DFL)
                raise(signum)
            }
        }
    }
}

/// C-accessible global buffer for the log file path (1 KB is more than enough).
nonisolated(unsafe) private var gSignalLogPath: (
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar
) = (
    0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
)
