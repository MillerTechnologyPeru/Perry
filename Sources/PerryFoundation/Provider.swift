import CPerryFoundation
import Glibc
import PerryInterface
import PerryObjCInterop

// libPerryFoundation: the provider for Foundation.framework and
// CoreFoundation.framework.

private let libobjc = "/usr/lib/libobjc.A.dylib"

nonisolated(unsafe) private var programName = "perry"

@c
public func perry_provider_startup(_ info: UnsafePointer<perry_startup_info>?) {
    guard let info, info.pointee.version >= 2, let lookup = info.pointee.lookup_symbol else { return }
    if let name = info.pointee.progname {
        programName = String(decoding: UnsafeRawBufferPointer(start: name, count: strlen(name)), as: UTF8.self)
    }
    let loaded = ObjC.load { name in
        libobjc.withCString { library in name.withCString { lookup(library, $0) } }
    }
    guard loaded, let nsObject = "NSObject".withCString({ ObjC.getClass($0) }) else {
        foundationFatal("Foundation needs libPerryobjc, which is missing or incomplete")
    }

    _ = ClassDefinition(extending: nsObject, FoundationObject.register, DelayedPerforms.register)
    Strings.install(superclass: nsObject)
    MutableStrings.install(superclass: Strings.stringClass)
    Errors.install(superclass: nsObject)
    Arrays.install(superclass: nsObject)
    Dictionaries.install(superclass: nsObject)
    Sets.install(superclass: nsObject)
    Numbers.install(superclass: nsObject)
    Dates.install(superclass: nsObject)
    RunLoops.install(superclass: nsObject)
    Timers.install(superclass: nsObject)
    Notifications.install(superclass: nsObject)
    Nulls.install(superclass: nsObject)
    DataObjects.install(superclass: nsObject)
    URLs.install(superclass: nsObject)
    UUIDs.install(superclass: nsObject)
    JSON.install(superclass: nsObject)
}

/// Foundation's additions to NSObject. libobjc's -description returns nil.
@ObjCClass("NSObject")
struct FoundationObject {}

@ObjCImplementation
extension FoundationObject {
    @ObjCMethod("description")
    func description() -> String { "<\(ObjC.className(objcObject)): \(objcObject)>" }
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
    var line = "\(String(decoding: date.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)).\(padded) \(programName)[\(getpid()):\(perry_foundation_thread_id())] \(message)"
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
