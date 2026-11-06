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
    Exceptions.load { name in libobjc.withCString { library in name.withCString { lookup(library, $0) } } }
    let libSystem = { (name: String) in
        "/usr/lib/libSystem.B.dylib".withCString { library in name.withCString { lookup(library, $0) } }
    }
    MainDispatchQueue.load(libSystem)
    Dispatch.load(libSystem)
    BundleLoading.loadLibrary = info.version >= 3 ? info.load_library : nil
    return true
}

/// Foundation's data symbols, which the loader asks for while binding
/// images: the empty array and dictionary @[] and @{} compile to.
func providerSymbol(_ name: String) -> UnsafeMutableRawPointer? { EmptyCollections.slots[name].map(UnsafeMutableRawPointer.init) }

/// Once Foundation's classes are defined: their protocols, and the empty
/// collections.
func providerDidStart(_ info: perry_startup_info) {
    Conformances.adopt()
    EmptyCollections.fill()
}

/// The protocols Foundation's value classes adopt, which casts check: Swift
/// casts its strings, bridged as NSString subclasses, to NSCopying.
enum Conformances {
    /// Each with the protocols it inherits from: secure coding is coding.
    static let protocols: [(name: String, adopting: [String])] = [
        ("NSCopying", []), ("NSMutableCopying", []), ("NSCoding", []), ("NSSecureCoding", ["NSCoding"]), ("NSFastEnumeration", []),
    ]

    static let classes: [(name: String, protocols: [String])] = [
        ("NSString", ["NSCopying", "NSMutableCopying", "NSSecureCoding"]),
        ("NSAttributedString", ["NSCopying", "NSMutableCopying", "NSSecureCoding"]),
        ("NSArray", ["NSCopying", "NSMutableCopying", "NSSecureCoding", "NSFastEnumeration"]),
        ("NSDictionary", ["NSCopying", "NSMutableCopying", "NSSecureCoding", "NSFastEnumeration"]),
        ("NSSet", ["NSCopying", "NSMutableCopying", "NSSecureCoding", "NSFastEnumeration"]),
        ("NSOrderedSet", ["NSCopying", "NSMutableCopying", "NSSecureCoding", "NSFastEnumeration"]),
        ("NSData", ["NSCopying", "NSMutableCopying", "NSSecureCoding"]),
        ("NSValue", ["NSCopying", "NSSecureCoding"]),
        ("NSNumber", ["NSCopying", "NSSecureCoding"]),
        ("NSDate", ["NSCopying", "NSSecureCoding"]),
        ("NSURL", ["NSCopying", "NSSecureCoding"]),
        ("NSUUID", ["NSCopying", "NSSecureCoding"]),
        ("NSIndexPath", ["NSCopying", "NSSecureCoding"]),
        ("NSIndexSet", ["NSCopying", "NSMutableCopying", "NSSecureCoding"]),
        ("NSCharacterSet", ["NSCopying", "NSMutableCopying", "NSSecureCoding"]),
        ("NSLocale", ["NSCopying", "NSSecureCoding"]),
        ("NSTimeZone", ["NSCopying", "NSSecureCoding"]),
        ("NSError", ["NSCopying", "NSSecureCoding"]),
        ("NSNull", ["NSCopying", "NSSecureCoding"]),
        ("NSEnumerator", ["NSFastEnumeration"]),
        ("NSPresentationIntent", ["NSCopying"]),
        ("NSAttributedStringMarkdownSourcePosition", ["NSCopying"]),
        ("NSAttributedStringMarkdownParsingOptions", ["NSCopying"]),
    ]

    /// Declares the protocols, unless an image already has, and adds them
    /// to the classes.
    static func adopt() {
        for (name, adopting) in protocols where ObjCRuntime.protocolObject(name) == nil {
            ObjCRuntime.defineProtocol(named: name, adopting: adopting, methods: [])
        }
        for (name, adopted) in classes where name.withCString({ ObjC.getClass($0) }) != nil {
            for proto in adopted {
                ObjCRuntime.addProtocol(named: proto, to: ObjCClass(named: name))
            }
        }
    }
}

/// __NSArray0__ and __NSDictionary0__: variables holding the empty array
/// and dictionary every empty literal shares.
enum EmptyCollections {
    nonisolated(unsafe) static let slots: [String: UnsafeMutablePointer<UnsafeMutableRawPointer?>] = {
        func slot() -> UnsafeMutablePointer<UnsafeMutableRawPointer?> {
            let slot = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: 1)
            slot.initialize(to: nil)
            return slot
        }
        return ["___NSArray0__": slot(), "___NSDictionary0__": slot()]
    }()

    static func fill() {
        slots["___NSArray0__"]?.pointee = Arrays.make([])
        slots["___NSDictionary0__"]?.pointee = Dictionaries.make([])
    }
}

// MARK: - NSLog

/// Writes one NSLog line to stderr in Foundation's format:
/// "2026-11-01 21:30:00.123 App[pid:tid] message".
func log(_ message: String) {
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
