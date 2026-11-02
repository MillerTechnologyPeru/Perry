// Swift wrappers for Objective-C objects. A wrapper is a struct holding one
// reference to the object; @ObjCClass generates its members.

/// Owns, or borrows, one reference to an Objective-C object.
public final class ObjCObjectHolder {
    public let object: UnsafeMutableRawPointer
    private let owned: Bool

    /// Takes a new reference.
    public init(retaining object: UnsafeMutableRawPointer) {
        ObjCRuntime.retain(object)
        self.object = object
        owned = true
    }

    /// Takes over a +1 reference the caller already has.
    public init(adopting object: UnsafeMutableRawPointer) {
        self.object = object
        owned = true
    }

    /// Refers to the object without a reference, for receivers of
    /// retain, release and dealloc, which must not be retained.
    public init(borrowing object: UnsafeMutableRawPointer) {
        self.object = object
        owned = false
    }

    deinit {
        if owned { ObjCRuntime.release(object) }
    }
}

/// A Swift wrapper for an Objective-C class.
public protocol AnyObjCObject: ObjCNullable where ObjCType == UnsafeMutableRawPointer? {
    var objcHolder: ObjCObjectHolder { get }
    init(objcHolder: ObjCObjectHolder)
    /// The Objective-C class's name.
    static var objCClassName: String { get }
}

extension AnyObjCObject {
    /// The object.
    @inline(__always)
    public var objcObject: UnsafeMutableRawPointer { objcHolder.object }

    /// The class object.
    public static var objCClass: ObjCClass { ObjCClass(named: objCClassName) }

    /// The object's class.
    public var objCClass: ObjCClass { ObjCClass(ObjCRuntime.objectClass(objcObject)!) }

    public static var objCTypeEncoding: String { "@" }
    public static var objCNil: UnsafeMutableRawPointer? { nil }
    public static func objCIsNil(_ value: UnsafeMutableRawPointer?) -> Bool { value == nil }

    public init(objCArgument value: UnsafeMutableRawPointer?) {
        self.init(objcHolder: ObjCObjectHolder(retaining: objCRequire(value, Self.self)))
    }

    public init(objCReturnValue value: UnsafeMutableRawPointer?) {
        self.init(objcHolder: ObjCObjectHolder(retaining: objCRequire(value, Self.self)))
    }

    public init(objCOwned value: UnsafeMutableRawPointer?) {
        self.init(objcHolder: ObjCObjectHolder(adopting: objCRequire(value, Self.self)))
    }

    public func objCArgument() -> UnsafeMutableRawPointer? { objcObject }

    public func objCReturnValue() -> UnsafeMutableRawPointer? {
        ObjCRuntime.autorelease(ObjCRuntime.retain(objcObject))
    }

    public func objCOwnedReturnValue() -> UnsafeMutableRawPointer? {
        ObjCRuntime.retain(objcObject)
    }

    /// Whether the object is an instance of `type`'s class or a subclass.
    public func `is`<Other: AnyObjCObject>(_ type: Other.Type) -> Bool {
        ObjCRuntime.isKind(objcObject, of: Other.objCClass.pointer)
    }

    /// The object as `type`, if it is an instance of that class.
    public func `as`<Other: AnyObjCObject>(_ type: Other.Type) -> Other? {
        self.is(type) ? Other(objcHolder: objcHolder) : nil
    }

    /// The same object as `type`, without checking. For wrappers of a
    /// superclass, or classes the runtime cannot check.
    public func unsafeCast<Other: AnyObjCObject>(to type: Other.Type) -> Other {
        Other(objcHolder: objcHolder)
    }
}

/// Any Objective-C object: `id`.
public struct ObjCObject: AnyObjCObject {
    public let objcHolder: ObjCObjectHolder
    public init(objcHolder: ObjCObjectHolder) { self.objcHolder = objcHolder }
    public static var objCClassName: String { "NSObject" }
}

extension ObjCObject {
    /// Wraps an object, taking a new reference.
    public init(_ object: UnsafeMutableRawPointer) {
        self.init(objcHolder: ObjCObjectHolder(retaining: object))
    }
}

/// A block (`@?`), copied to the heap while held.
public struct ObjCBlock: ObjCNullable {
    public let objcHolder: ObjCObjectHolder

    public var object: UnsafeMutableRawPointer { objcHolder.object }

    /// The block's invoke function, cast to its C signature: the block
    /// itself, then the block's arguments.
    public func function<Function>(as type: Function.Type) -> Function {
        unsafeBitCast(object.load(fromByteOffset: 16, as: UnsafeRawPointer.self), to: type)
    }

    public typealias ObjCType = UnsafeMutableRawPointer?
    public static var objCTypeEncoding: String { "@?" }
    public static var objCNil: UnsafeMutableRawPointer? { nil }
    public static func objCIsNil(_ value: UnsafeMutableRawPointer?) -> Bool { value == nil }

    public init(objCArgument value: UnsafeMutableRawPointer?) {
        let copied = ObjCRuntime.functions.retainBlock(objCRequire(value, Self.self))!
        objcHolder = ObjCObjectHolder(adopting: copied)
    }

    public init(objCReturnValue value: UnsafeMutableRawPointer?) { self.init(objCArgument: value) }

    public init(objCOwned value: UnsafeMutableRawPointer?) {
        objcHolder = ObjCObjectHolder(adopting: objCRequire(value, Self.self))
    }

    public func objCArgument() -> UnsafeMutableRawPointer? { object }
    public func objCReturnValue() -> UnsafeMutableRawPointer? { ObjCRuntime.autorelease(ObjCRuntime.retain(object)) }
    public func objCOwnedReturnValue() -> UnsafeMutableRawPointer? { ObjCRuntime.retain(object) }
}

// MARK: - String

/// Swift strings cross as NSString objects. Foundation must be loaded.
extension String: ObjCNullable {
    public typealias ObjCType = UnsafeMutableRawPointer?
    public static var objCTypeEncoding: String { "@" }
    public static var objCNil: UnsafeMutableRawPointer? { nil }
    public static func objCIsNil(_ value: UnsafeMutableRawPointer?) -> Bool { value == nil }

    /// Reads an NSString through -UTF8String.
    public init(objCArgument value: UnsafeMutableRawPointer?) {
        guard let value else { objCUnexpectedNil(String.self) }
        typealias Send = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> UnsafePointer<CChar>?
        let utf8 = unsafeBitCast(ObjCRuntime.msgSend, to: Send.self)(value, ObjCRuntime.selector("UTF8String"))
        self = utf8.map { String(cString: $0) } ?? ""
    }

    public init(objCReturnValue value: UnsafeMutableRawPointer?) { self.init(objCArgument: value) }

    public init(objCOwned value: UnsafeMutableRawPointer?) {
        self.init(objCArgument: value)
        ObjCRuntime.release(value)
    }

    /// A new NSString, +1.
    public func objCOwnedReturnValue() -> UnsafeMutableRawPointer? {
        typealias Alloc = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> UnsafeMutableRawPointer?
        typealias Initialize = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UnsafeRawPointer?, UInt, UInt)
            -> UnsafeMutableRawPointer?
        let string = unsafeBitCast(ObjCRuntime.msgSend, to: Alloc.self)(ObjCRuntime.classObject("NSString"),
                                                                       ObjCRuntime.selector("alloc"))
        var utf8 = self
        return utf8.withUTF8 { bytes in
            unsafeBitCast(ObjCRuntime.msgSend, to: Initialize.self)(
                string, ObjCRuntime.selector("initWithBytes:length:encoding:"),
                UnsafeRawPointer(bytes.baseAddress), UInt(bytes.count), 4)    // NSUTF8StringEncoding
        }
    }

    public func objCArgument() -> UnsafeMutableRawPointer? { ObjCRuntime.autorelease(objCOwnedReturnValue()) }
    public func objCReturnValue() -> UnsafeMutableRawPointer? { objCArgument() }
}
