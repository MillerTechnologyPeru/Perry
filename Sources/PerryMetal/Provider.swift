import Glibc
import PerryInterface
import PerryObjCInterop

// libPerryMetal: the provider for Metal.framework, on Vulkan through
// metal2vulkan, a separate library opened when an app first asks for a
// device. Each Metal object is a peer holding metal2vulkan's handle for it.
// PerryProviderPlugin generates the entry points from the module's
// Objective-C declarations; this file binds libobjc and libdispatch first.

private let libobjc = "/usr/lib/libobjc.A.dylib"
private let libdispatch = "/usr/lib/system/libdispatch.dylib"

func providerWillStart(_ info: perry_startup_info) -> Bool {
    guard info.version >= 2, let lookup = info.lookup_symbol else { return false }
    func symbol(_ library: String, _ name: String) -> UnsafeMutableRawPointer? {
        library.withCString { library in name.withCString { lookup(library, $0) } }
    }
    guard ObjCRuntime.load({ symbol(libobjc, $0) }) else {
        metalFatal("Metal needs libPerryobjc, which is missing or incomplete")
    }
    DispatchData.createMap = symbol(libdispatch, "_dispatch_data_create_map")
        .map { unsafeBitCast($0, to: DispatchData.CreateMap.self) }
    return true
}

func metalFatal(_ message: String) -> Never {
    let line = "perry: Metal: *** \(message)\n"
    line.withCString { _ = write(2, $0, strlen($0)) }
    abort()
}

func metalWarning(_ message: String) {
    let line = "perry: Metal: \(message)\n"
    line.withCString { _ = write(2, $0, strlen($0)) }
}

/// PERRY_METAL_TRACE: the device's answers and the first calls of each kind.
enum Trace {
    nonisolated(unsafe) static let enabled = getenv("PERRY_METAL_TRACE") != nil
    /// PERRY_METAL_DEBUG_CLEAR: passes clear drawables to magenta and other
    /// targets to green, to see which draws land.
    nonisolated(unsafe) static let debugClear = getenv("PERRY_METAL_DEBUG_CLEAR") != nil
    /// PERRY_METAL_DEBUG_NO_CULL and _NO_SCISSOR: ignore those calls.
    nonisolated(unsafe) static let debugNoCull = getenv("PERRY_METAL_DEBUG_NO_CULL") != nil
    nonisolated(unsafe) static let debugNoScissor = getenv("PERRY_METAL_DEBUG_NO_SCISSOR") != nil
    /// PERRY_METAL_TRACE_ALL: kinds, comma-separated, logged every time.
    nonisolated(unsafe) static let all = Set((getenv("PERRY_METAL_TRACE_ALL").map { String(cString: $0) } ?? "").split(separator: ",").map(String.init))
    /// PERRY_METAL_DUMP_UPLOADS=<directory>: small RGBA8 uploads, as PPMs.
    nonisolated(unsafe) static let uploadDirectory = getenv("PERRY_METAL_DUMP_UPLOADS").map { String(cString: $0) }
    nonisolated(unsafe) static var uploads = 0
    /// PERRY_METAL_DEBUG_NO_MIPS: samplers read only the base level.
    nonisolated(unsafe) static let debugNoMips = getenv("PERRY_METAL_DEBUG_NO_MIPS") != nil
    nonisolated(unsafe) static let debugBarriers = getenv("PERRY_METAL_DEBUG_BARRIERS") != nil
    nonisolated(unsafe) private static var counts: [String: Int] = [:]

    /// The first floats of some bytes, for a log.
    static func floats(_ bytes: UnsafeRawPointer?, _ length: UInt) -> String {
        guard let bytes else { return "nil" }
        return (0..<min(Int(length) / 4, 12)).map { "\(bytes.loadUnaligned(fromByteOffset: $0 * 4, as: Float.self))" }.joined(separator: " ")
    }

    /// Logs the first three of each kind, then every 300th.
    static func log(_ kind: String, _ message: @autoclosure () -> String = "") {
        guard enabled else { return }
        let count = (counts[kind] ?? 0) + 1
        counts[kind] = count
        guard count <= 3 || count % 300 == 0 || all.contains(kind) else { return }
        let line = "perry: Metal: \(kind) #\(count) \(message())\n"
        line.withCString { _ = write(2, $0, strlen($0)) }
    }
}
