import Glibc
import PerryInterface
import PerryObjCInterop

// libPerryCoreGraphics: the provider for CoreGraphics, and for ImageIO,
// which the loader maps here so its images and CoreGraphics' are one kind.
// CoreGraphics' objects (images, color spaces, colors, data providers,
// contexts, image sources and destinations) are Objective-C objects, as
// Darwin's CF types are, so CFRetain and CFRelease work on them.
// PerryProviderPlugin generates the entry points; this file binds libobjc
// first and holds the Foundation calls CoreGraphics makes.

private let libobjc = "/usr/lib/libobjc.A.dylib"

/// The loader's symbol lookup, for functions other providers define, and
/// the program's bundle, which the Process Manager answers with.
nonisolated(unsafe) var providerSymbolLookup: (@convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> UnsafeMutableRawPointer?)?
nonisolated(unsafe) var programBundlePath: String?
nonisolated(unsafe) var programExecutablePath: String?

func providerWillStart(_ info: perry_startup_info) -> Bool {
    guard info.version >= 2, let lookup = info.lookup_symbol else { return false }
    providerSymbolLookup = lookup
    programBundlePath = info.bundle_path.map { String(cString: $0) }
    programExecutablePath = info.executable_path.map { String(cString: $0) }
    let loaded = ObjCRuntime.load { name in
        libobjc.withCString { library in name.withCString { lookup(library, $0) } }
    }
    guard loaded else { graphicsFatal("CoreGraphics needs libPerryobjc, which is missing or incomplete") }
    return true
}

func graphicsFatal(_ message: String) -> Never {
    let line = "perry: CoreGraphics: *** \(message)\n"
    line.withCString { _ = write(2, $0, strlen($0)) }
    abort()
}

/// A recursive mutex.
final class Lock: @unchecked Sendable {
    private let mutex = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)

    init() {
        var attributes = pthread_mutexattr_t()
        pthread_mutexattr_init(&attributes)
        pthread_mutexattr_settype(&attributes, Int32(PTHREAD_MUTEX_RECURSIVE))
        pthread_mutex_init(mutex, &attributes)
        pthread_mutexattr_destroy(&attributes)
    }

    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        pthread_mutex_lock(mutex)
        defer { pthread_mutex_unlock(mutex) }
        return try body()
    }
}

/// Swift state per Objective-C object, from creation until -dealloc.
final class StateTable<State: AnyObject>: @unchecked Sendable {
    private let lock = Lock()
    private var states: [UnsafeMutableRawPointer: State] = [:]

    subscript(object: UnsafeMutableRawPointer?) -> State? {
        guard let object else { return nil }
        return lock.withLock { states[object] }
    }

    func set(_ object: UnsafeMutableRawPointer, _ state: State) { lock.withLock { states[object] = state } }
    func remove(_ object: UnsafeMutableRawPointer) { _ = lock.withLock { states.removeValue(forKey: object) } }
}

/// A Create or Copy function's new object (+1) of the class, with its state.
func makeObject<State: AnyObject>(_ cls: ObjCClass, _ table: StateTable<State>, _ state: State) -> UnsafeMutableRawPointer {
    let instance = NSObject(cls.pointer).newInstance()
    let object = withExtendedLifetime(instance) { ObjCRuntime.retain(instance.objcObject)! }
    table.set(object, state)
    return object
}

public typealias Ref = UnsafeMutableRawPointer

// MARK: - Foundation, as CoreGraphics calls it

@ObjCWrapper("NSData")
class NSData: NSObject {
    @ObjCClassMethod("dataWithBytes:length:") static func make(bytes: UnsafeRawPointer?, length: UInt) -> NSData
    @ObjCClassMethod("dataWithContentsOfFile:") static func make(contentsOfFile path: String) -> NSData?
    @ObjCMethod("bytes") func bytes() -> UnsafeRawPointer?
    @ObjCMethod("length") func length() -> UInt
    @ObjCMethod("writeToFile:atomically:") func write(toFile path: String, atomically: Bool) -> Bool

    var array: [UInt8] {
        let count = Int(length())
        guard count > 0, let bytes = bytes() else { return [] }
        return Array(UnsafeRawBufferPointer(start: bytes, count: count))
    }

    static func of(_ bytes: [UInt8]) -> NSData { bytes.withUnsafeBytes { make(bytes: $0.baseAddress, length: UInt($0.count)) } }
}

@ObjCWrapper("NSMutableData")
class NSMutableData: NSData {
    @ObjCMethod("setLength:") func setLength(_ length: UInt)
    @ObjCMethod("appendBytes:length:") func append(bytes: UnsafeRawPointer?, length: UInt)

    func replace(with bytes: [UInt8]) {
        setLength(0)
        bytes.withUnsafeBytes { append(bytes: $0.baseAddress, length: UInt($0.count)) }
    }
}

@ObjCWrapper("NSNumber")
class NSNumber: NSObject {
    @ObjCClassMethod("numberWithLongLong:") static func make(int64: Int64) -> NSNumber
    @ObjCClassMethod("numberWithDouble:") static func make(double: Double) -> NSNumber
    @ObjCClassMethod("numberWithBool:") static func make(bool: Bool) -> NSNumber
    @ObjCMethod("doubleValue") func doubleValue() -> Double
    @ObjCMethod("longLongValue") func int64Value() -> Int64
    @ObjCMethod("boolValue") func boolValue() -> Bool
}

@ObjCWrapper("NSArray")
class NSArray: NSObject {
    @ObjCMethod("count") func count() -> UInt
    @ObjCMethod("objectAtIndex:") func object(at index: UInt) -> NSObject
}

@ObjCWrapper("NSMutableArray")
class NSMutableArray: NSArray {
    @ObjCClassMethod("array") static func empty() -> NSMutableArray
    @ObjCMethod("addObject:") func add(_ object: NSObject)

    static func of(_ objects: [NSObject]) -> NSMutableArray {
        let array = empty()
        objects.forEach(array.add)
        return array
    }
}

@ObjCWrapper("NSDictionary")
class NSDictionary: NSObject {
    @ObjCMethod("objectForKey:") func object(forKey key: NSObject) -> NSObject?

    func object(_ key: String) -> NSObject? { object(forKey: NSObject.string(key)) }
}

@ObjCWrapper("NSMutableDictionary")
class NSMutableDictionary: NSDictionary {
    @ObjCClassMethod("dictionary") static func empty() -> NSMutableDictionary
    @ObjCMethod("setObject:forKey:") func set(_ object: NSObject, forKey key: NSObject)

    static func of(_ entries: [(String, NSObject)]) -> NSMutableDictionary {
        let dictionary = empty()
        for (key, value) in entries { dictionary.set(value, forKey: NSObject.string(key)) }
        return dictionary
    }
}

/// The strings Get functions return are constants on Darwin, literals that
/// retains and releases leave alone, and programs depend on it: YouTube
/// hands CGImageSourceGetType's result on as if it were owned, which only
/// works because that string is never freed. These are literals made the
/// same way, one for each value, kept for good. ASCII, as the names and type
/// identifiers they stand for are.
enum ConstantStrings {
    nonisolated(unsafe) private static var table: [String: UnsafeMutableRawPointer] = [:]
    private static let lock = Lock()

    static func make(_ value: String) -> UnsafeMutableRawPointer {
        lock.withLock {
            if let known = table[value] { return known }
            let word = MemoryLayout<UInt>.size
            let literal = UnsafeMutableRawPointer.allocate(byteCount: 4 * word, alignment: word)
            literal.storeBytes(of: ObjCRuntime.classObject("__NSCFConstantString"), as: UnsafeMutableRawPointer.self)
            literal.storeBytes(of: 0x7c8, toByteOffset: word, as: UInt.self)
            literal.storeBytes(of: UnsafeRawPointer(strdup(value)!), toByteOffset: 2 * word, as: UnsafeRawPointer.self)
            literal.storeBytes(of: value.utf8.count, toByteOffset: 3 * word, as: Int.self)
            table[value] = literal
            return literal
        }
    }
}

@ObjCWrapper("NSURL")
class NSURL: NSObject {
    @ObjCMethod("path") func path() -> String?
}

extension NSObject {
    @ObjCMethod("new") func newInstance() -> NSObject
    @ObjCMethod("isKindOfClass:") func isKind(of cls: ObjCClass) -> Bool

    static func string(_ value: String) -> NSObject { NSObject(objCReturnValue: value.objCArgument()) }
    static func number(_ value: Int) -> NSObject { NSNumber.make(int64: Int64(value)) }
    static func number(_ value: Double) -> NSObject { NSNumber.make(double: value) }

    var isNumber: Bool { isKind(of: ObjCClass(named: "NSNumber")) }
    var isDictionary: Bool { isKind(of: ObjCClass(named: "NSDictionary")) }
    var doubleValue: Double? { isNumber ? unsafeCast(to: NSNumber.self).doubleValue() : nil }
    var boolValue: Bool? { isNumber ? unsafeCast(to: NSNumber.self).boolValue() : nil }
    var dictionary: NSDictionary? { isDictionary ? unsafeCast(to: NSDictionary.self) : nil }
}

/// An options dictionary's entries, from a CFDictionaryRef argument.
struct Options {
    let dictionary: NSDictionary?

    init(_ pointer: Ref?) { dictionary = pointer.map { NSDictionary(objCArgument: $0) } }

    func number(_ key: String) -> Double? { dictionary?.object(key)?.doubleValue }
    func bool(_ key: String) -> Bool { dictionary?.object(key)?.boolValue ?? false }
    func nested(_ key: String) -> Options { Options(dictionary?.object(key)?.dictionary?.objcObject) }
}
