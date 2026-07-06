// RawCrashContext.swift
// SphinxErrorReporter
//
// Captures raw address/UUID/image context for stripped (release) crash builds
// where symbols don't resolve. Serialized into metadata + stackTrace.

import Foundation

/// Captures binary image metadata needed for server-side symbolication.
public struct BinaryImageInfo: Codable, Sendable {
    public let uuid: String
    public let loadAddress: String
    public let name: String
    public let arch: String

    public init(uuid: String, loadAddress: String, name: String, arch: String) {
        self.uuid = uuid
        self.loadAddress = loadAddress
        self.name = name
        self.arch = arch
    }
}

/// Raw crash context for builds where symbols are not available (stripped release).
public struct RawCrashContext: Codable, Sendable {
    public let frames: [RawFrame]
    public let binaryImages: [BinaryImageInfo]
    public let arch: String
    public let osVersion: String
    public let rawStackTrace: String

    public struct RawFrame: Codable, Sendable {
        public let index: Int
        public let address: String
        public let imageName: String

        public init(index: Int, address: String, imageName: String) {
            self.index = index
            self.address = address
            self.imageName = imageName
        }
    }

    public init(
        frames: [RawFrame],
        binaryImages: [BinaryImageInfo],
        arch: String,
        osVersion: String,
        rawStackTrace: String
    ) {
        self.frames = frames
        self.binaryImages = binaryImages
        self.arch = arch
        self.osVersion = osVersion
        self.rawStackTrace = rawStackTrace
    }

    // MARK: - Factory

    /// Build a RawCrashContext from Thread.callStackSymbols.
    public static func capture(from symbols: [String]) -> RawCrashContext {
        var rawFrames: [RawFrame] = []

        for (index, line) in symbols.enumerated() {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 3 else { continue }
            let imageName = parts[1]
            let address = parts[2]
            rawFrames.append(RawFrame(index: index, address: address, imageName: imageName))
        }

        let images = captureLoadedImages()
        let arch = cpuArch()
        let osVer = osVersion()
        let rawTrace = symbols.joined(separator: "\n")

        return RawCrashContext(
            frames: rawFrames,
            binaryImages: images,
            arch: arch,
            osVersion: osVer,
            rawStackTrace: rawTrace
        )
    }

    // MARK: - Metadata serialization

    /// Serializes this context into a [String: Any] metadata dictionary.
    public func toMetadata() -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(self),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ["rawCrashContext": rawStackTrace]
        }
        return dict
    }

    // MARK: - Platform helpers

    private static func cpuArch() -> String {
#if arch(arm64)
        return "arm64"
#elseif arch(x86_64)
        return "x86_64"
#else
        return "unknown"
#endif
    }

    private static func osVersion() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    /// Reads loaded binary images using dyld APIs — captures UUID + load address
    /// which are mandatory for server-side symbolication.
    private static func captureLoadedImages() -> [BinaryImageInfo] {
        var images: [BinaryImageInfo] = []
        let count = _dyld_image_count()
        let arch = cpuArch()

        for i in 0..<count {
            guard let header = _dyld_get_image_header(i),
                  let nameC = _dyld_get_image_name(i) else { continue }

            let name = URL(fileURLWithPath: String(cString: nameC)).lastPathComponent
            let slide = _dyld_get_image_vmaddr_slide(i)
            let loadAddr = String(format: "0x%llx", UInt(bitPattern: header) &+ UInt(bitPattern: slide))

            // Extract UUID from LC_UUID load command
            let uuid = extractUUID(from: header) ?? "00000000-0000-0000-0000-000000000000"

            images.append(BinaryImageInfo(
                uuid: uuid,
                loadAddress: loadAddr,
                name: name,
                arch: arch
            ))
        }
        return images
    }

    /// Walks Mach-O load commands to find LC_UUID.
    private static func extractUUID(from header: UnsafePointer<mach_header>) -> String? {
#if arch(arm64) || arch(x86_64)
        let header64 = UnsafeRawPointer(header).assumingMemoryBound(to: mach_header_64.self)
        var offset: UInt = UInt(MemoryLayout<mach_header_64>.size)
        let commandCount = Int(header64.pointee.ncmds)

        for _ in 0..<commandCount {
            let lcPtr = UnsafeRawPointer(header).advanced(by: Int(offset))
            let lc = lcPtr.assumingMemoryBound(to: load_command.self)

            if lc.pointee.cmd == LC_UUID {
                let uuidCmd = lcPtr.assumingMemoryBound(to: uuid_command.self)
                let uuid = uuidCmd.pointee.uuid
                return String(format: "%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X",
                              uuid.0, uuid.1, uuid.2, uuid.3,
                              uuid.4, uuid.5,
                              uuid.6, uuid.7,
                              uuid.8, uuid.9,
                              uuid.10, uuid.11, uuid.12, uuid.13, uuid.14, uuid.15)
            }
            offset += UInt(lc.pointee.cmdsize)
        }
#endif
        return nil
    }
}
