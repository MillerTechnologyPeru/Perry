import CPerryGeometry
import Glibc
import PerryInterface
import PerryObjCInterop

// libPerryQuartzCore: the provider for QuartzCore.framework, Core
// Animation. It keeps the layer tree that UIKit's views are each backed
// by, renders it through CoreGraphics, composites it on the GPU for UIKit's
// live view, and runs its animations. PerryProviderPlugin generates the
// entry points from the module's Objective-C declarations; this file binds
// libobjc, libdispatch and CoreGraphics first, and holds the Foundation
// calls the framework makes.

private let libobjc = "/usr/lib/libobjc.A.dylib"
private let libdispatch = "/usr/lib/system/libdispatch.dylib"

func providerWillStart(_ info: perry_startup_info) -> Bool {
    guard info.version >= 2, let lookup = info.lookup_symbol else { return false }
    func symbol(_ library: String, _ name: String) -> UnsafeMutableRawPointer? {
        library.withCString { library in name.withCString { lookup(library, $0) } }
    }
    guard ObjCRuntime.load({ symbol(libobjc, $0) }), Dispatch.load({ symbol(libdispatch, $0) }) else {
        quartzFatal("QuartzCore needs libPerryobjc and libPerrySystem, which are missing or incomplete")
    }
    Methods.implementation = symbol(libobjc, "_class_getMethodImplementation").map { unsafeBitCast($0, to: Methods.Implementation.self) }
    guard Methods.implementation != nil, CG.load(symbol) else {
        quartzFatal("QuartzCore needs libPerryCoreGraphics, which is missing or incomplete")
    }
    return true
}

/// QuartzCore's structure constants, which the loader asks for while
/// binding images.
func providerSymbol(_ name: String) -> UnsafeMutableRawPointer? { StructureConstants.values[name] }

enum StructureConstants {
    nonisolated(unsafe) static let values: [String: UnsafeMutableRawPointer] = {
        func value<T>(_ value: T) -> UnsafeMutableRawPointer {
            let storage = UnsafeMutablePointer<T>.allocate(capacity: 1)
            storage.initialize(to: value)
            return UnsafeMutableRawPointer(storage)
        }
        return [
            "_CATransform3DIdentity": value(CATransform3D.identity),
            // CAFrameRateRange: minimum, maximum, preferred; all zero for the
            // display's own rate.
            "_CAFrameRateRangeDefault": value((Float(0), Float(0), Float(0))),
        ]
    }()
}

func quartzFatal(_ message: String) -> Never {
    let line = "perry: QuartzCore: *** \(message)\n"
    line.withCString { _ = write(2, $0, strlen($0)) }
    abort()
}

func quartzWarning(_ message: String) {
    let line = "perry: QuartzCore: \(message)\n"
    line.withCString { _ = write(2, $0, strlen($0)) }
}

/// libdispatch's main queue: transactions' completions and display links
/// run there, as on Darwin.
enum Dispatch {
    typealias Function = @convention(c) (UnsafeMutableRawPointer?) -> Void
    typealias Async = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Function) -> Void
    typealias After = @convention(c) (UInt64, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Function) -> Void
    typealias Time = @convention(c) (UInt64, Int64) -> UInt64
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

    private final class Work {
        let body: () -> Void
        init(_ body: @escaping () -> Void) { self.body = body }
    }

    private static let run: Function = { context in
        guard let context else { return }
        ObjCRuntime.autoreleasepool { Unmanaged<Work>.fromOpaque(context).takeRetainedValue().body() }
    }

    static func onMain(_ body: @escaping () -> Void) { async(main, Unmanaged.passRetained(Work(body)).toOpaque(), run) }

    static func onMain(after seconds: Double, _ body: @escaping () -> Void) {
        after(time(0, Int64(max(0, seconds) * 1_000_000_000)), main, Unmanaged.passRetained(Work(body)).toOpaque(), run)
    }
}

/// Monotonic seconds, the media time animations are timed in.
enum Clock {
    static var now: Double {
        var time = timespec()
        clock_gettime(CLOCK_MONOTONIC, &time)
        return Double(time.tv_sec) + Double(time.tv_nsec) / 1e9
    }
}

/// Method lookups, to tell whether a class overrides a method.
enum Methods {
    typealias Implementation = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> UnsafeRawPointer?
    nonisolated(unsafe) static var implementation: Implementation!

    /// Whether `object`'s class implements `selector` other than as `base`
    /// does.
    static func overrides(_ object: UnsafeMutableRawPointer, _ selector: String, of base: UnsafeMutableRawPointer) -> Bool {
        let sel = ObjCRuntime.selector(selector)
        return implementation(ObjCRuntime.objectClass(object), sel) != implementation(base, sel)
    }
}

/// Calling blocks Core Animation is handed.
enum Blocks {
    static func call(_ block: ObjCBlock) {
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer) -> Void
        block.function(as: Invoke.self)(block.object)
    }
}

// MARK: - Foundation, as this provider calls it

public typealias CGFloat = Double

extension NSObject {
    @ObjCMethod("new") func newInstance() -> NSObject
    @ObjCMethod("alloc") func allocated() -> NSObject
    @ObjCMethod("init") func initialized() -> NSObject
    @ObjCMethod("copy") func sendCopy() -> NSObject
    @ObjCMethod("doubleValue") func sendDoubleValue() -> Double
    @ObjCMethod("boolValue") func sendBoolValue() -> Bool
    var stringValue: String { String(objCArgument: objcObject) }
}

extension ObjCClass {
    var object: NSObject { NSObject(pointer) }
}

@ObjCWrapper("NSArray")
class NSArray: NSObject {
    @ObjCMethod("count") func count() -> UInt
    @ObjCMethod("objectAtIndex:") func object(at index: UInt) -> NSObject

    var elements: [NSObject] { (0..<count()).map { object(at: $0) } }
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

@ObjCWrapper("NSNumber")
class NSNumber: NSObject {
    @ObjCClassMethod("numberWithDouble:") static func make(double: Double) -> NSNumber
    @ObjCClassMethod("numberWithBool:") static func make(bool: Bool) -> NSNumber
}

/// NSValue, which boxes the geometry animations interpolate.
@ObjCWrapper("NSValue")
class NSValue: NSObject {
    @ObjCClassMethod("valueWithBytes:objCType:") static func make(bytes: UnsafeRawPointer, objCType: UnsafePointer<CChar>) -> NSValue
    @ObjCMethod("objCType") func objCType() -> UnsafePointer<CChar>?
    @ObjCMethod("getValue:size:") func getValue(_ buffer: UnsafeMutableRawPointer, size: UInt)

    static func boxing<T: ObjCScalar>(_ value: T) -> NSValue {
        var value = value
        return T.objCTypeEncoding.withCString { type in withUnsafeBytes(of: &value) { make(bytes: $0.baseAddress!, objCType: type) } }
    }

    /// The value, when it holds a `T`.
    func unboxed<T: ObjCScalar>(_ type: T.Type) -> T? {
        guard let encoding = objCType().map({ String(cString: $0) }), encoding == T.objCTypeEncoding else { return nil }
        let buffer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { buffer.deallocate() }
        getValue(buffer, size: UInt(MemoryLayout<T>.size))
        return buffer.pointee
    }
}

@ObjCWrapper("NSNull")
class NSNull: NSObject {
    @ObjCClassMethod("null") static func null() -> NSNull
}
