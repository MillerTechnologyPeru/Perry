// Swift classes exposed to Objective-C. Each @ObjCClass class mirrors an
// Objective-C class. An instance of a class with Swift initializers is its
// object's peer, the one Swift object that is that object (ObjCPeers);
// otherwise an instance wraps one object, holding one reference to it.

/// How a wrapper holds its object.
public enum ObjCOwnership {
    /// Takes a new reference.
    case retain
    /// Takes over a +1 reference the caller already has.
    case adopt
    /// Holds no reference, for receivers of retain, release and dealloc,
    /// which must not be retained.
    case borrow
    /// Is the object: its peer, sharing its reference count.
    case peer
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

    /// The object as this type: its peer when it has one of this type,
    /// otherwise a wrapper holding it as `ownership` says.
    public static func objCInstance(_ object: UnsafeMutableRawPointer, ownership: ObjCOwnership) -> Self {
        if let peer = ObjCPeers.peer(of: object) as? Self {
            // The peer is the object; the caller's reference is not needed.
            if ownership == .adopt { ObjCRuntime.release(object) }
            return peer
        }
        return Self(objcObject: object, ownership: ownership)
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
        self.is(type) ? Other.objCInstance(objcObject, ownership: .retain) : nil
    }

    /// The same object as `type`, without checking.
    public func unsafeCast<Other: AnyObjCObject>(to type: Other.Type) -> Other {
        Other.objCInstance(objcObject, ownership: .retain)
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

    /// Makes the Swift object that is an object of this class: the one an
    /// -init message was sent to, while that method's Swift initializer
    /// runs, else a new one. Swift initializers of @ObjCClass classes end
    /// here, through super.init(…).
    public init() {
        let receiver = ObjCPeers.takeReceiver(for: Self.self)
        objcObject = receiver ?? ObjCPeers.allocate(Self.objCClass)
        ownership = .peer
        // The -init's caller is given a reference; a Swift caller's own is
        // the object's first.
        ObjCPeers.bind(objcObject, self, retained: receiver != nil)
    }

    /// Wraps an object, taking a new reference.
    public convenience init(_ object: UnsafeMutableRawPointer) {
        self.init(objcObject: object, ownership: .retain)
    }

    deinit {
        switch ownership {
        case .borrow:
            break
        case .peer:
            // Swift let go last: the object goes now, through -dealloc.
            if ObjCPeers.willDeinitialize(objcObject) {
                typealias Send = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> Void
                unsafeBitCast(ObjCRuntime.msgSend, to: Send.self)(objcObject, ObjCRuntime.selector("dealloc"))
            }
        case .retain, .adopt:
            ObjCRuntime.release(objcObject)
        }
    }

    open class var objCClassName: String { "NSObject" }

    // ObjCValue's conversions, which give an object's peer when it has one.
    public class func objCValue(argument value: UnsafeMutableRawPointer?) -> Self {
        objCInstance(objCRequire(value, Self.self), ownership: .retain)
    }

    public class func objCValue(returnValue value: UnsafeMutableRawPointer?) -> Self {
        objCInstance(objCRequire(value, Self.self), ownership: .retain)
    }

    public class func objCValue(owned value: UnsafeMutableRawPointer?) -> Self {
        objCInstance(objCRequire(value, Self.self), ownership: .adopt)
    }

    /// Whether the object implements `selector` (-respondsToSelector:), as
    /// a caller checks before sending an optional protocol method.
    public final func responds(to selector: String) -> Bool {
        typealias Send = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UnsafeRawPointer?) -> Bool
        return unsafeBitCast(ObjCRuntime.msgSend, to: Send.self)(
            objcObject, ObjCRuntime.selector("respondsToSelector:"), ObjCRuntime.selector(selector))
    }

    /// The superclass's name; nil for a root class.
    open class var objCSuperclassName: String? { nil }

    /// Installs the @ObjCMethod and @ObjCClassMethod functions of the class
    /// body into `registrar`. @ObjCClass generates each class's own.
    open class func registerObjCMethods(_ registrar: any ObjCMethodRegistrar) {}

    /// Sets up a class just defined: shared method sets, extra methods,
    /// singletons. Override it in a class body; the provider's generated
    /// startup calls it for classes that declare it themselves, so a
    /// subclass never runs its superclass's set-up.
    open class func didDefineObjCClass(_ cls: ObjCClass) {}

    /// Defines this class in the runtime, with its methods and
    /// `registrations` (other classes' registerObjCMethods, applied like
    /// categories), and registers it.
    @discardableResult
    public class func defineObjCClass(_ registrations: ObjCMethodRegistration...) -> ObjCClass {
        let cls = ObjCRuntime.defineClass(named: objCClassName, superclass: objCSuperclassName.map { ObjCClass(named: $0) },
                                          [registerObjCMethods] + registrations)
        ObjCPeers.register(cls.pointer, self)
        return cls
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
