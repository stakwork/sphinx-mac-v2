// FrameBuilder.swift
// SphinxErrorReporter
//
// Parses Thread.callStackSymbols into [Frame].
// Classifies frames as in-app vs system.
// Produces repo-relative filenames for in-app frames.

import Foundation

/// Parses symbolicated call stack lines and builds structured Frame objects.
public enum FrameBuilder {

    // MARK: - Public API

    /// Build frames from a raw callStackSymbols array.
    /// Returns nil when no frames could be resolved.
    public static func build(
        from symbols: [String],
        mainImageName: String? = nil
    ) -> [Frame]? {
        let appImageName = mainImageName ?? resolvedMainImageName()
        let frames = symbols.compactMap { line -> Frame? in
            parseSymbol(line, appImageName: appImageName)
        }
        return frames.isEmpty ? nil : frames
    }

    // MARK: - Main image detection

    /// Returns the executable name for the running process, used to classify in-app frames.
    static func resolvedMainImageName() -> String {
        // Use the process info executable name (e.g. "Sphinx" on macOS, "sphinx" on iOS)
        let execURL = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
        return execURL.lastPathComponent
    }

    // MARK: - Symbol parsing

    // Example symbolicated line:
    // "0   Sphinx                             0x000000010000abcd functionName + 123"
    // "0   AppName                            0x000000010000abcd -[ClassName method:] + 16"
    // "0   Sphinx                             0x000000010000abcd $s6Sphinx10MyClass4funcyyF + 44"
    //
    // Stripped/unsymbolicated line:
    // "0   Sphinx                             0x000000010000abcd 0x100000000 + 44012"
    private static func parseSymbol(_ line: String, appImageName: String) -> Frame? {
        // Tokenize: split on whitespace runs
        let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        // Minimum shape: frameIndex, imageName, address, symbolOrAddress [+, offset]
        guard parts.count >= 4 else { return nil }

        let imageName = parts[1]
        let symbolPart = parts[3]

        // Detect if this is an unresolved address (starts with 0x)
        let isStripped = symbolPart.hasPrefix("0x")

        if isStripped {
            // Preserve raw address info but mark no function
            let isApp = isAppFrame(imageName: imageName, appImageName: appImageName)
            return Frame(
                filename: imageName,
                function: nil,
                lineno: nil,
                inApp: isApp
            )
        }

        let isApp = isAppFrame(imageName: imageName, appImageName: appImageName)

        // Function name: everything from parts[3] up to (but not including) " + offset"
        // e.g. "functionName + 123" → function = "functionName"
        var functionName = symbolPart
        if parts.count >= 6 && parts[parts.count - 2] == "+" {
            // Last two tokens are "+ offset"; function is everything between index 3 and n-2
            functionName = parts[3...(parts.count - 3)].joined(separator: " ")
        } else if parts.count == 5 && parts[4].hasPrefix("+") {
            functionName = symbolPart
        }

        // Demangle Swift mangled names if possible
        functionName = demangle(functionName)

        // For in-app frames, produce a repo-relative filename placeholder.
        // In symbolicated debug builds, filename info comes from DWARF; at runtime
        // it's not available in callStackSymbols. We use the image name as the module.
        let filename = isApp ? repoRelativeFilename(for: imageName) : imageName

        return Frame(
            filename: filename,
            function: functionName.isEmpty ? nil : functionName,
            lineno: nil,       // line numbers not available from callStackSymbols
            inApp: isApp
        )
    }

    // MARK: - In-App classification

    static func isAppFrame(imageName: String, appImageName: String) -> Bool {
        // Match against the main executable name (case-insensitive for robustness)
        guard !appImageName.isEmpty else { return false }
        return imageName.lowercased() == appImageName.lowercased()
    }

    // MARK: - Repo-relative filename

    static func repoRelativeFilename(for imageName: String) -> String {
        // Without DWARF info at runtime we can only produce a module-level path.
        // This keeps the contract: in-app frames get a distinct, non-system path
        // that Hive can use to link to the right repo.
        return "\(imageName)/Sources"
    }

    // MARK: - Swift demangling

    static func demangle(_ symbol: String) -> String {
        // Swift mangled names start with "$s" or "_T"
        guard symbol.hasPrefix("$s") || symbol.hasPrefix("$S") || symbol.hasPrefix("_T") else {
            return symbol
        }
        // Use swift_demangle if available (dynamic lookup — Foundation only, no import needed)
        // Falls back to the raw mangled name on failure.
        if let demangled = _tryDemangle(symbol) {
            return demangled
        }
        return symbol
    }

    private static func _tryDemangle(_ mangled: String) -> String? {
        // Use the C swift_demangle function via dlsym — safe on all Apple platforms
        typealias DemangleFn = @convention(c) (
            UnsafePointer<CChar>?, Int,
            UnsafeMutablePointer<CChar>?, UnsafeMutablePointer<Int>?, UInt32
        ) -> UnsafeMutablePointer<CChar>?

        guard let handle = dlopen(nil, RTLD_LAZY),
              let sym = dlsym(handle, "swift_demangle") else {
            return nil
        }
        let fn = unsafeBitCast(sym, to: DemangleFn.self)
        guard let cResult = fn(mangled, mangled.utf8.count, nil, nil, 0) else {
            return nil
        }
        let result = String(cString: cResult)
        free(cResult)
        return result.isEmpty ? nil : result
    }
}
