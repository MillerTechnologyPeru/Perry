import CPerryFoundation
import Glibc
import PerryInterface
import PerryObjCInterop

// libPerryFoundation: the provider for Foundation.framework and
// CoreFoundation.framework.

private let libobjc = "/usr/lib/libobjc.A.dylib"


@c
public func perry_provider_startup(_ info: UnsafePointer<perry_startup_info>?) {
    guard let info, info.pointee.version >= 2, let lookup = info.pointee.lookup_symbol else { return }
    Process.start(info.pointee)
    let loaded = ObjC.load { name in
        libobjc.withCString { library in name.withCString { lookup(library, $0) } }
    }
    guard loaded, let nsObject = "NSObject".withCString({ ObjC.getClass($0) }) else {
        foundationFatal("Foundation needs libPerryobjc, which is missing or incomplete")
    }

    // Foundation's categories on NSObject.
    NSObject.addObjCCategoryFoundation()
    NSObject.addObjCCategoryDelayedPerforms()
    NSObject.addObjCCategoryThreadPerforms()
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
    NSJSONSerialization.defineObjCClass()
    Process.install(superclass: nsObject)
    Bundles.install(superclass: nsObject)
    Threads.install(superclass: nsObject)
    UserDefaults.install()
    FileManagers.install()
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
