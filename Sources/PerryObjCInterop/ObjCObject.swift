// Swift classes exposed to Objective-C. Each @ObjCClass class mirrors an
// Objective-C class and an instance stands for one object, holding one
// reference to it.

/// How a wrapper holds its object.
public enum ObjCOwnership {
    /// Takes a new reference.
    case retain
    /// Takes over a +1 reference the caller already has.
    case adopt
    /// Holds no reference, for receivers of retain, release and dealloc,
    /// which must not be retained.
    case borrow
}

/// A Swift class standing for an Objective-C class.
public protocol AnyObjCObject: AnyObject, ObjCNullable where ObjCType == UnsafeMutableRawPointer? {
    var objcObject: UnsafeMutableRawPointer { get }
    init(objcObject: UnsafeMutableRawPointer, ownership: ObjCOwnership)
    /// The Objective-C class's name.
    static var objCClassName: String { get }
}

extension AnyObjCObject {
    /// The class object.
    public static var objCClass: ObjCClass { ObjCClass(named: objCClassName) }

    /// The object's class.
    public var objCClass: ObjCClass { ObjCClass(ObjCRuntime.objectClass(objcObject)!) }

    public static var objCTypeEncoding: String { "@" }
    public static var objCNil: UnsafeMutableRawPointer? { nil }
    public static func objCIsNil(_ value: UnsafeMutableRawPointer?) -> Bool { value == nil }

    public init(objCArgument value: UnsafeMutableRawPointer?) {
        self.init(objcObject: objCRequire(value, Self.self), ownership: .retain)
    }

    public init(objCReturnValue value: UnsafeMutableRawPointer?) {
        self.init(objcObject: objCRequire(value, Self.self), ownership: .retain)
    }

    public init(objCOwned value: UnsafeMutableRawPointer?) {
        self.init(objcObject: objCRequire(value, Self.self), ownership: .adopt)
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
        self.is(type) ? Other(objcObject: objcObject, ownership: .retain) : nil
    }

    /// The same object as `type`, without checking.
    public func unsafeCast<Other: AnyObjCObject>(to type: Other.Type) -> Other {
        Other(objcObject: objcObject, ownership: .retain)
    }
}

/// The root class, NSObject; also any object (`id`).
open class NSObject: AnyObjCObject {
    public let objcObject: UnsafeMutableRawPointer
    private let ownership: ObjCOwnership

    public required init(objcObject: UnsafeMutableRawPointer, ownership: ObjCOwnership) {
        if ownership == .retain { ObjCRuntime.retain(objcObject) }
        self.objcObject = objcObject
        self.ownership = ownership
    }

    /// Wraps an object, taking a new reference.
    public convenience init(_ object: UnsafeMutableRawPointer) {
        self.init(objcObject: object, ownership: .retain)
    }

    deinit {
        if ownership != .borrow { ObjCRuntime.release(objcObject) }
    }

    open class var objCClassName: String { "NSObject" }

    /// The superclass's name; nil for a root class.
    open class var objCSuperclassName: String? { nil }

    /// Installs the @ObjCMethod and @ObjCClassMethod functions of the class
    /// body into `registrar`. @ObjCClass generates each class's own.
    open class func registerObjCMethods(_ registrar: any ObjCMethodRegistrar) {}

    /// Defines this class in the runtime, with its methods and
    /// `registrations` (other classes' registerObjCMethods, applied like
    /// categories), and registers it.
    @discardableResult
    public class func defineObjCClass(_ registrations: ObjCMethodRegistration...) -> ObjCClass {
        ObjCRuntime.defineClass(named: objCClassName, superclass: objCSuperclassName.map { ObjCClass(named: $0) },
                                [registerObjCMethods] + registrations)
    }
}

/// Any Objective-C object.
public typealias ObjCObject = NSObject

/// A block (`@?`), copied to the heap while held.
public final class ObjCBlock: ObjCNullable {
    /// The heap block, which this holds one reference to.
    public let object: UnsafeMutableRawPointer

    private init(heapBlock: UnsafeMutableRawPointer) {
        object = heapBlock
    }

    deinit {
        ObjCRuntime.release(object)
    }

    /// The block's invoke function, cast to its C signature: the block
    /// itself, then the block's arguments.
    public func function<Function>(as type: Function.Type) -> Function {
        unsafeBitCast(object.load(fromByteOffset: 16, as: UnsafeRawPointer.self), to: type)
    }

    public typealias ObjCType = UnsafeMutableRawPointer?
    public static var objCTypeEncoding: String { "@?" }
    public static var objCNil: UnsafeMutableRawPointer? { nil }
    public static func objCIsNil(_ value: UnsafeMutableRawPointer?) -> Bool { value == nil }

    public convenience init(objCArgument value: UnsafeMutableRawPointer?) {
        self.init(heapBlock: ObjCRuntime.functions.retainBlock(objCRequire(value, ObjCBlock.self))!)
    }

    public convenience init(objCReturnValue value: UnsafeMutableRawPointer?) { self.init(objCArgument: value) }

    public convenience init(objCOwned value: UnsafeMutableRawPointer?) {
        self.init(heapBlock: objCRequire(value, ObjCBlock.self))
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
