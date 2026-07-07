// CrashHandler.swift
// SphinxErrorReporter
//
// Installs NSSetUncaughtExceptionHandler and POSIX signal handlers.
// Chains any previously-installed handler (coexists with Bugsnag etc.).
// On crash: builds ErrorReport, persists synchronously to disk, then re-raises.

import Foundation

/// Installs crash/signal handlers and chains prior handlers.
enum CrashHandler {

    // MARK: - Prior handler storage (global, signal-safe)

    private static var priorExceptionHandler: NSUncaughtExceptionHandler?

    // Store prior signal handlers (one per signal)
    private static var priorSIGABRT = sigaction()
    private static var priorSIGILL  = sigaction()
    private static var priorSIGSEGV = sigaction()
    private static var priorSIGFPE  = sigaction()
    private static var priorSIGBUS  = sigaction()
    private static var priorSIGTRAP = sigaction()

    // MARK: - Install

    /// Install handlers. Call once at app startup (after other crash SDKs).
    static func install() {
        // Capture prior exception handler for chaining
        priorExceptionHandler = NSGetUncaughtExceptionHandler()
        NSSetUncaughtExceptionHandler { exception in
            CrashHandler.handleException(exception)
        }

        // Install signal handlers
        installSignalHandler(SIGABRT, &priorSIGABRT)
        installSignalHandler(SIGILL,  &priorSIGILL)
        installSignalHandler(SIGSEGV, &priorSIGSEGV)
        installSignalHandler(SIGFPE,  &priorSIGFPE)
        installSignalHandler(SIGBUS,  &priorSIGBUS)
        installSignalHandler(SIGTRAP, &priorSIGTRAP)
    }

    // MARK: - Exception handler

    private static func handleException(_ exception: NSException) {
        // Build report from exception
        let symbols = exception.callStackSymbols
        let frames = FrameBuilder.build(from: symbols)

        var meta: [String: Any] = [:]
        if let userInfo = exception.userInfo, !userInfo.isEmpty {
            meta["exceptionUserInfo"] = userInfo.description
        }

        // Capture raw context for symbolication
        let rawCtx = RawCrashContext.capture(from: symbols)
        let rawMeta = rawCtx.toMetadata()
        for (k, v) in rawMeta { meta[k] = v }

        let report = ErrorReport(
            exceptionType: exception.name.rawValue,
            message: exception.reason ?? "(no reason)",
            stackTrace: symbols.joined(separator: "\n"),
            frames: frames,
            environment: SphinxErrorReporter.currentConfig?.environment,
            release: SphinxErrorReporter.currentConfig?.release,
            commitSha: SphinxErrorReporter.currentConfig?.commitSha,
            repository: SphinxErrorReporter.currentConfig?.mainRepo,
            metadata: meta.isEmpty ? nil : meta
        )

        // Persist synchronously to disk (no async — we're about to die)
        SphinxErrorReporter.reportStore?.persistSync(report)

        // Chain to prior handler
        priorExceptionHandler?(exception)
    }

    // MARK: - Signal handler

    private static func installSignalHandler(_ sig: Int32, _ prior: inout sigaction) {
        var action = sigaction()
        action.__sigaction_u.__sa_handler = { sig in CrashHandler.handleSignal(sig) }
        sigemptyset(&action.sa_mask)
        action.sa_flags = 0
        sigaction(sig, &action, &prior)
    }

    private static func handleSignal(_ sig: Int32) {
        let sigName = signalName(sig)
        let symbols = Thread.callStackSymbols
        let frames = FrameBuilder.build(from: symbols)

        let rawCtx = RawCrashContext.capture(from: symbols)
        var meta = rawCtx.toMetadata()
        meta["signal"] = sig

        let report = ErrorReport(
            exceptionType: "Signal\(sigName)",
            message: "Fatal signal \(sigName) (\(sig)) received",
            stackTrace: symbols.joined(separator: "\n"),
            frames: frames,
            environment: SphinxErrorReporter.currentConfig?.environment,
            release: SphinxErrorReporter.currentConfig?.release,
            commitSha: SphinxErrorReporter.currentConfig?.commitSha,
            repository: SphinxErrorReporter.currentConfig?.mainRepo,
            metadata: meta
        )

        SphinxErrorReporter.reportStore?.persistSync(report)

        // Re-raise to chain to prior handler (Bugsnag, default crash reporter, etc.)
        // Reset to default handler first to avoid infinite loop
        var defAction = sigaction()
        defAction.__sigaction_u.__sa_handler = SIG_DFL
        sigemptyset(&defAction.sa_mask)
        defAction.sa_flags = 0
        sigaction(sig, &defAction, nil)
        kill(getpid(), sig)
    }

    // MARK: - Helpers

    private static func signalName(_ sig: Int32) -> String {
        switch sig {
        case SIGABRT: return "SIGABRT"
        case SIGILL:  return "SIGILL"
        case SIGSEGV: return "SIGSEGV"
        case SIGFPE:  return "SIGFPE"
        case SIGBUS:  return "SIGBUS"
        case SIGTRAP: return "SIGTRAP"
        default:      return "SIG\(sig)"
        }
    }
}
