import Glibc
import PerryObjCInterop

// Libraries for Metal Shading Language source. metal2vulkan reads compiled
// AIR only, and Apple's compiler runs only on macOS, so the source an app
// compiles at run time is compiled ahead of time instead: each source is
// keyed by its UTF-8 bytes (FNV-1a and length), written to the cache
// directory as <key>.metal when it is first seen, and loaded from
// <key>.metallib once Scripts/compile-metal-sources.sh has built that on a
// Mac. The directory is PERRY_METAL_SOURCES, else metal-sources beside the
// app's bundle.

enum SourceCache {
    enum Result {
        case compiled([UInt8])
        /// Where the source was written.
        case missing(String)
    }

    static let directory: String = {
        if let setting = getenv("PERRY_METAL_SOURCES"), setting.pointee != 0 { return String(cString: setting) }
        let bundle = NSBundle.main().bundlePath() ?? "."
        let parent = bundle.split(separator: "/", omittingEmptySubsequences: false).dropLast().joined(separator: "/")
        return (parent.isEmpty ? "." : parent) + "/metal-sources"
    }()

    static func key(_ source: [UInt8]) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in source { hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3 }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex + "-\(source.count)"
    }

    static func library(for source: String) -> Result {
        let bytes = Array(source.utf8)
        let base = directory + "/" + key(bytes)
        if let library = readFile(base + ".metallib") { return .compiled(library) }
        let path = base + ".metal"
        if access(path, F_OK) != 0 {
            mkdir(directory, 0o755)
            if let file = fopen(path, "wb") {
                _ = bytes.withUnsafeBytes { fwrite($0.baseAddress, 1, $0.count, file) }
                fclose(file)
            }
        }
        return .missing(path)
    }
}
