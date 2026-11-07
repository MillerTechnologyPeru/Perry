import CPerryGeometry
import Glibc
import PerryObjCInterop

// What MapKit's providers share: PerryMapKit's for iOS apps, whose views are
// UIKit's, and PerryMapKitAppKit's for Mac apps, whose views are AppKit's.
// Each provider links its own copy of this module, as it does of
// PerryObjCInterop, and binds it at start-up with MapKitShared.load.

public enum MapKitShared {
    private static let libobjc = "/usr/lib/libobjc.A.dylib"
    private static let libSystem = "/usr/lib/libSystem.B.dylib"

    /// Binds libobjc and libdispatch through the loader, or stops the
    /// program: MapKit can't run without them.
    public static func load(_ lookup: (String, String) -> UnsafeMutableRawPointer?) {
        guard ObjCRuntime.load({ lookup(libobjc, $0) }), Dispatch.load({ lookup(libSystem, $0) }) else {
            fatal("MapKit needs libPerryobjc and libPerrySystem, which are missing or incomplete")
        }
    }

    public static func fatal(_ message: String) -> Never {
        let line = "perry: MapKit: *** \(message)\n"
        line.withCString { _ = write(2, $0, strlen($0)) }
        abort()
    }

    /// Whether the main executable is a macOS program: its LC_BUILD_VERSION's
    /// platform is PLATFORM_MACOS.
    public static func isMacApp(_ header: UnsafeRawPointer?) -> Bool {
        guard let header, header.load(as: UInt32.self) == 0xFEED_FACF else { return false }
        let count = header.load(fromByteOffset: 16, as: UInt32.self)
        var command = header + 32    // mach_header_64
        for _ in 0..<count {
            let cmd = command.load(as: UInt32.self), size = command.load(fromByteOffset: 4, as: UInt32.self)
            if cmd == 0x32 { return command.load(fromByteOffset: 8, as: UInt32.self) == 1 }   // LC_BUILD_VERSION, PLATFORM_MACOS
            guard size >= 8 else { return false }
            command += Int(size)
        }
        return false
    }
}

/// libdispatch: delegate messages that follow a change run on the main
/// queue, as MapKit sends them once the map has moved.
public enum Dispatch {
    public typealias Function = @convention(c) (UnsafeMutableRawPointer?) -> Void
    typealias Async = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Function) -> Void
    typealias After = @convention(c) (UInt64.ObjCType, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Function) -> Void
    typealias Time = @convention(c) (UInt64.ObjCType, Int64.ObjCType) -> UInt64
    nonisolated(unsafe) static var async: Async!
    nonisolated(unsafe) static var after: After!
    nonisolated(unsafe) static var time: Time!
    nonisolated(unsafe) static var main: UnsafeMutableRawPointer!

    static func load(_ lookup: (String) -> UnsafeMutableRawPointer?) -> Bool {
        guard let async = lookup("_dispatch_async_f"), let after = lookup("_dispatch_after_f"), let time = lookup("_dispatch_time"),
              let main = lookup("__dispatch_main_q") else { return false }
        self.async = unsafeBitCast(async, to: Async.self)
        self.after = unsafeBitCast(after, to: After.self)
        self.time = unsafeBitCast(time, to: Time.self)
        self.main = main
        return true
    }

    final class Work {
        let body: () -> Void
        init(_ body: @escaping () -> Void) { self.body = body }
    }

    private static let run: Function = { context in
        guard let context else { return }
        ObjCRuntime.autoreleasepool { Unmanaged<Work>.fromOpaque(context).takeRetainedValue().body() }
    }

    public static func onMain(_ body: @escaping () -> Void) { async(main, Unmanaged.passRetained(Work(body)).toOpaque(), run) }

    /// On the main queue, `milliseconds` from now.
    public static func onMain(after milliseconds: Int, _ body: @escaping () -> Void) {
        after(time(UInt64(0).objCArgument(), (Int64(milliseconds) * 1_000_000).objCArgument()).objCArgument(), main, Unmanaged.passRetained(Work(body)).toOpaque(), run)
    }
}

/// Messages to the superclass's implementation from a method defined on
/// `cls`, for MapKit's views, whose superclass is UIKit's or AppKit's.
public enum Super {
    public static func initialize(_ object: UnsafeMutableRawPointer, frame: CGRect, definedOn cls: ObjCClass) {
        var superInfo = (object, cls.pointer)
        typealias Send = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer?, CGRect.ObjCType) -> UnsafeMutableRawPointer?
        _ = withUnsafeMutablePointer(to: &superInfo) {
            unsafeBitCast(ObjCRuntime.msgSendSuper2, to: Send.self)(UnsafeMutableRawPointer($0), ObjCRuntime.selector("initWithFrame:"), frame.objCArgument())
        }
    }

    public static func initialize(_ object: UnsafeMutableRawPointer, coder: NSObject, definedOn cls: ObjCClass) {
        var superInfo = (object, cls.pointer)
        typealias Send = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer?, UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
        _ = withUnsafeMutablePointer(to: &superInfo) {
            unsafeBitCast(ObjCRuntime.msgSendSuper2, to: Send.self)(UnsafeMutableRawPointer($0), ObjCRuntime.selector("initWithCoder:"),
                                                                    coder.objcObject)
        }
    }

    /// A message with no arguments and no result, such as -layoutSubviews
    /// or -layout.
    public static func send(_ object: UnsafeMutableRawPointer, _ selector: String, definedOn cls: ObjCClass) {
        var superInfo = (object, cls.pointer)
        typealias Send = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer?) -> Void
        withUnsafeMutablePointer(to: &superInfo) {
            unsafeBitCast(ObjCRuntime.msgSendSuper2, to: Send.self)(UnsafeMutableRawPointer($0), ObjCRuntime.selector(selector))
        }
    }
}

/// A recursive mutex.
public final class Lock: @unchecked Sendable {
    private let mutex = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)

    public init() {
        var attributes = pthread_mutexattr_t()
        pthread_mutexattr_init(&attributes)
        pthread_mutexattr_settype(&attributes, Int32(PTHREAD_MUTEX_RECURSIVE))
        pthread_mutex_init(mutex, &attributes)
        pthread_mutexattr_destroy(&attributes)
    }

    public func withLock<T>(_ body: () throws -> T) rethrows -> T {
        pthread_mutex_lock(mutex)
        defer { pthread_mutex_unlock(mutex) }
        return try body()
    }
}

/// Swift state for an Objective-C object, from creation until -dealloc.
open class ObjectState {
    public required init() {}
}

public final class StateTable<State: ObjectState>: @unchecked Sendable {
    private let lock = Lock()
    private var states: [UnsafeMutableRawPointer: State] = [:]

    public init() {}

    /// The object's state, made on first use.
    public subscript(object: UnsafeMutableRawPointer) -> State {
        lock.withLock {
            if let state = states[object] { return state }
            let state = State()
            states[object] = state
            return state
        }
    }

    public func remove(_ object: UnsafeMutableRawPointer) { _ = lock.withLock { states.removeValue(forKey: object) } }
}

// MARK: - Foundation, as MapKit calls it

#if _pointerBitWidth(_32)
public typealias CGFloat = Float
#else
public typealias CGFloat = Double
#endif

extension CGPoint: ObjCStructure {
    #if _pointerBitWidth(_32)
    public typealias ObjCType = ObjCWords2
    public static var objCTypeEncoding: String { "{CGPoint=ff}" }
    #else
    public typealias ObjCType = CGPoint
    public static var objCTypeEncoding: String { "{CGPoint=dd}" }
    #endif
}
extension CGSize: ObjCStructure {
    #if _pointerBitWidth(_32)
    public typealias ObjCType = ObjCWords2
    public static var objCTypeEncoding: String { "{CGSize=ff}" }
    #else
    public typealias ObjCType = CGSize
    public static var objCTypeEncoding: String { "{CGSize=dd}" }
    #endif
}
extension CGRect: ObjCStructure {
    #if _pointerBitWidth(_32)
    public typealias ObjCType = ObjCWords4
    public static var objCTypeEncoding: String { "{CGRect={CGPoint=ff}{CGSize=ff}}" }
    #else
    public typealias ObjCType = CGRect
    public static var objCTypeEncoding: String { "{CGRect={CGPoint=dd}{CGSize=dd}}" }
    #endif
}
extension UIEdgeInsets: ObjCStructure {
    #if _pointerBitWidth(_32)
    public typealias ObjCType = ObjCWords4
    public static var objCTypeEncoding: String { "{UIEdgeInsets=ffff}" }
    #else
    public typealias ObjCType = UIEdgeInsets
    public static var objCTypeEncoding: String { "{UIEdgeInsets=dddd}" }
    #endif
}

public extension NSObject {
    @ObjCMethod("new") func newInstance() -> NSObject
    @ObjCMethod("alloc") func allocated() -> NSObject
    @ObjCMethod("init") func initialized() -> NSObject
    var stringValue: String { String(objCArgument: objcObject) }
}

public extension ObjCClass {
    var object: NSObject { NSObject(pointer) }
}

@ObjCWrapper("NSArray")
public class NSArray: NSObject {
    @ObjCMethod("count") public func count() -> UInt
    @ObjCMethod("objectAtIndex:") public func object(at index: UInt) -> NSObject

    public var elements: [NSObject] { (0..<count()).map { object(at: $0) } }
}

@ObjCWrapper("NSMutableArray")
public class NSMutableArray: NSArray {
    @ObjCClassMethod("array") public static func empty() -> NSMutableArray
    @ObjCMethod("addObject:") public func add(_ object: NSObject)

    public static func of(_ objects: [NSObject]) -> NSMutableArray {
        let array = empty()
        objects.forEach(array.add)
        return array
    }
}

@ObjCWrapper("NSMutableSet")
public class NSMutableSet: NSObject {
    @ObjCClassMethod("set") public static func empty() -> NSMutableSet
    @ObjCMethod("addObject:") public func add(_ object: NSObject)

    public static func of(_ objects: [NSObject]) -> NSMutableSet {
        let set = empty()
        objects.forEach(set.add)
        return set
    }
}
