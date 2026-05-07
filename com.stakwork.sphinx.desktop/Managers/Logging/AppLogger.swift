// AppLogger.swift
// com.stakwork.sphinx.desktop

import Foundation

private let kLogRetentionHours: Double = 24

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
        loadAndPruneExistingLog()
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
            self.appendToFile(entry)
            let observers = self.entryObservers
            DispatchQueue.main.async {
                observers.values.forEach { $0(entry) }
            }
        }
    }

    // MARK: - Private – file I/O

    private func loadAndPruneExistingLog() {
        let url = logFileURL
        guard FileManager.default.fileExists(atPath: url.path),
              let content = try? String(contentsOf: url, encoding: .utf8) else { return }

        let cutoff = Date().addingTimeInterval(-kLogRetentionHours * 3600)
        var kept: [LogEntry] = []

        for line in content.components(separatedBy: .newlines) where !line.isEmpty {
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

    private func appendToFile(_ entry: LogEntry) {
        let line = entry.formatted + "\n"
        guard let data = line.data(using: .utf8) else { return }
        let url = logFileURL
        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            }
        } else {
            try? data.write(to: url, options: .atomic)
        }
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
            let content = entries.map { $0.formatted }.joined(separator: "\n")
            try? content.write(to: logFileURL, atomically: true, encoding: .utf8)
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
            try? FileManager.default.removeItem(at: self.logFileURL)
        }
    }

    // MARK: - Signal handlers

    private func registerSignalHandlers() {
        // Signal handlers must be C-style functions; we use a file-path stored in a
        // C-accessible global so the handler can write without calling Swift code.
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
                // Build sentinel line using only async-signal-safe calls
                let sigName: String
                switch signum {
                case SIGSEGV: sigName = "SIGSEGV"
                case SIGABRT: sigName = "SIGABRT"
                case SIGILL:  sigName = "SIGILL"
                case SIGBUS:  sigName = "SIGBUS"
                case SIGFPE:  sigName = "SIGFPE"
                default:      sigName = "SIG\(signum)"
                }
                let msg = "💥 CRASH — signal \(sigName) at \(Date())\n"
                if let data = msg.data(using: .utf8) {
                    let path = String(cString: &gSignalLogPath.0)
                    if let fd = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) {
                        fd.seekToEndOfFile()
                        fd.write(data)
                        try? fd.close()
                    }
                }
                // Re-raise so the OS can generate the crash report
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
