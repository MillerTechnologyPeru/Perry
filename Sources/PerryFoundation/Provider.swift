import CPerryFoundation
import Glibc
import PerryInterface
import PerryObjCInterop

// libPerryFoundation: the provider for Foundation.framework and
// CoreFoundation.framework. PerryProviderPlugin generates its
// perry_provider_startup and perry_provider_symbol from the module's
// Objective-C declarations; this file adds the provider's own steps.

private let libobjc = "/usr/lib/libobjc.A.dylib"

/// Before the generated startup defines Foundation's classes: records the
/// program's arguments and paths, and binds libobjc's C API, which
/// Foundation calls rather than linking a second copy of the runtime.
func providerWillStart(_ info: perry_startup_info) -> Bool {
    guard info.version >= 2, let lookup = info.lookup_symbol else { return false }
    Process.start(info)
    Threads.mainThread = pthread_self()
    RunLoops.mainThread = pthread_self()
    let loaded = ObjC.load { name in
        libobjc.withCString { library in name.withCString { lookup(library, $0) } }
    }
    guard loaded, "NSObject".withCString({ ObjC.getClass($0) }) != nil else {
        foundationFatal("Foundation needs libPerryobjc, which is missing or incomplete")
    }
    let libSystem = { (name: String) in
        "/usr/lib/libSystem.B.dylib".withCString { library in name.withCString { lookup(library, $0) } }
    }
    MainDispatchQueue.load(libSystem)
    Dispatch.load(libSystem)
    return true
}

// MARK: - NSLog

/// Writes one NSLog line to stderr in Foundation's format:
/// "2026-11-01 21:30:00.123 App[pid:tid] message".
private func log(_ message: String) {
    var now = timespec()
    clock_gettime(CLOCK_REALTIME, &now)
    var seconds = now.tv_sec
    var local = tm()
    localtime_r(&seconds, &local)
    var date = [CChar](repeating: 0, count: 32)
    strftime(&date, date.count, "%Y-%m-%d %H:%M:%S", &local)
    let milliseconds = String(now.tv_nsec / 1_000_000)
    let padded = String(repeating: "0", count: 3 - milliseconds.count) + milliseconds
    var line = "\(String(decoding: date.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)).\(padded) \(Process.name)[\(getpid()):\(perry_foundation_thread_id())] \(message)"
    if !line.hasSuffix("\n") { line += "\n" }
    line.withCString { _ = write(2, $0, strlen($0)) }
}

/// NSLog's body, from the variadic entry point in variadic.S.
@c
public func perry_foundation_log(_ format: id?, _ arguments: UnsafeRawPointer?) {
    guard let arguments else { return }
    var darwin = DarwinArguments(arguments)
    log(Format.string(Strings.value(of: format) ?? "", &darwin))
}

/// void NSLogv(NSString *format, va_list args): a Darwin va_list is a
/// pointer to the argument slots.
@c(_NSLogv)
public func NSLogv(_ format: id?, _ arguments: UnsafeRawPointer?) {
    perry_foundation_log(format, arguments)
}
