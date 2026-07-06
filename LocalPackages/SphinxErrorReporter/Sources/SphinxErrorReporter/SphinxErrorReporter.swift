// SphinxErrorReporter.swift
// SphinxErrorReporter
//
// Public API entry point.
// SphinxErrorReporter.start(_:) — installs crash handler, starts network monitor, flushes pending queue.
// SphinxErrorReporter.capture(_:repository:metadata:requestContext:) — reports caught errors.

import Foundation

/// Drop-in SDK for capturing and reporting crashes and errors to Hive.
///
/// Usage:
/// ```swift
/// let config = Config(
///     hiveBaseURL: URL(string: "https://hive.sphinx.chat/api")!,
///     ingestKey: "hive_...",
///     mainRepo: "stakwork/sphinx-mac-v2"
/// )
/// SphinxErrorReporter.start(config)
/// ```
public enum SphinxErrorReporter {

    // MARK: - Internal state (package-internal, visible to CrashHandler)

    static var currentConfig: Config?
    static var reportStore: ReportStore?
    private static var transport: Transport?

    // MARK: - Public API

    /// Start the SDK. Install crash/signal handlers, flush any pending reports.
    /// Call once at app launch, after any other crash-reporting SDK (so handlers chain).
    public static func start(_ config: Config) {
        currentConfig = config

        let store = ReportStore()
        let trans = Transport(config: config)
        store.configure(transport: trans, config: config)

        reportStore = store
        transport = trans

        // Install crash/signal handlers (chains any prior handlers, e.g. Bugsnag)
        CrashHandler.install()

        // Flush any reports that were persisted during a prior crash
        store.flush()

        SDKLogger.log("start() — SDK initialized, mainRepo=\(config.mainRepo)", config: config)
    }

    /// Capture a caught/recoverable error.
    /// - Parameters:
    ///   - error: The error to report.
    ///   - repository: Optional per-error repository override (uses Config.mainRepo if nil).
    ///   - metadata: Optional key-value metadata dictionary.
    ///   - requestContext: Optional HTTP request context dictionary.
    public static func capture(
        _ error: Error,
        repository: String? = nil,
        metadata: [String: Any]? = nil,
        requestContext: [String: Any]? = nil
    ) {
        guard let config = currentConfig, let store = reportStore else {
            // Not started — silently drop
            return
        }

        SDKLogger.log("capture() — received error: \(type(of: error))", config: config)

        let symbols = Thread.callStackSymbols
        let frames = FrameBuilder.build(from: symbols)

        let report = ErrorReport(
            exceptionType: String(describing: type(of: error)),
            message: error.localizedDescription,
            stackTrace: symbols.joined(separator: "\n"),
            frames: frames,
            environment: config.environment,
            release: config.release,
            commitSha: config.commitSha,
            repository: repository ?? config.mainRepo,
            requestContext: requestContext,
            metadata: metadata
        )

        store.enqueue(report)
        SDKLogger.log("capture() — enqueued report", config: config)
    }

    /// Capture a caught error described by a string message.
    /// - Parameters:
    ///   - exceptionType: Identifier for the error type.
    ///   - message: Human-readable error description.
    ///   - repository: Optional per-error repository override.
    ///   - metadata: Optional metadata dictionary.
    public static func captureMessage(
        _ message: String,
        exceptionType: String = "ManualCapture",
        repository: String? = nil,
        metadata: [String: Any]? = nil
    ) {
        guard let config = currentConfig, let store = reportStore else { return }

        SDKLogger.log("captureMessage() — \(exceptionType)", config: config)

        let symbols = Thread.callStackSymbols
        let frames = FrameBuilder.build(from: symbols)

        let report = ErrorReport(
            exceptionType: exceptionType,
            message: message,
            stackTrace: symbols.joined(separator: "\n"),
            frames: frames,
            environment: config.environment,
            release: config.release,
            commitSha: config.commitSha,
            repository: repository ?? config.mainRepo,
            metadata: metadata
        )

        store.enqueue(report)
    }
}
