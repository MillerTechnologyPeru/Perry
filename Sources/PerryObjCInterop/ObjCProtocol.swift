// Objective-C protocols as Swift protocols. @ObjCProtocol, on a Swift
// protocol, generates `Any<Name>`: a subclass of ObjCProtocolObject that
// conforms by sending each requirement's message to the object it wraps,
// so Swift code calls any conforming Objective-C object through the
// protocol. A provider's generated startup registers the protocol with the
// runtime and adds it to the @ObjCClass classes that adopt it.

/// libobjc's protocol functions.
public struct ObjCProtocolFunctions {
    public typealias Pointer = UnsafeMutableRawPointer
    public var getProtocol: @convention(c) (UnsafePointer<CChar>?) -> Pointer?
    public var allocateProtocol: @convention(c) (UnsafePointer<CChar>?) -> Pointer?
    public var addProtocol: @convention(c) (Pointer?, Pointer?) -> Void
    public var addMethodDescription: @convention(c) (Pointer?, UnsafeRawPointer?, UnsafePointer<CChar>?, Bool, Bool) -> Void
    public var registerProtocol: @convention(c) (Pointer?) -> Void
    public var classAddProtocol: @convention(c) (Pointer?, Pointer?) -> Bool
}

/// A method a protocol declares.
public struct ObjCProtocolMethod {
    public let selector: String
    public let types: String
    public let isRequired: Bool

    public init(_ selector: String, types: String, isRequired: Bool) {
        self.selector = selector
        self.types = types
        self.isRequired = isRequired
    }
}

extension ObjCRuntime {
    nonisolated(unsafe) public static var protocolFunctions: ObjCProtocolFunctions?

    private static var protocols: ObjCProtocolFunctions {
        guard let protocolFunctions else { objcInteropFatal("libobjc's protocol functions are not bound") }
        return protocolFunctions
    }

    /// The protocol named `name`, if registered.
    public static func protocolObject(_ name: String) -> UnsafeMutableRawPointer? {
        name.withCString { protocols.getProtocol($0) }
    }

    /// Registers a protocol with its adopted protocols and instance
    /// methods, unless one with the name exists (an image declared it).
    public static func defineProtocol(named name: String, adopting adopted: [String], methods: [ObjCProtocolMethod]) {
        guard let proto = name.withCString({ protocols.allocateProtocol($0) }) else { return }
        for parent in adopted {
            guard let parentProtocol = protocolObject(parent) else {
                objcInteropFatal("protocol \(name) adopts \(parent), which is not registered")
            }
            protocols.addProtocol(proto, parentProtocol)
        }
        for method in methods {
            method.types.withCString {
                protocols.addMethodDescription(proto, selector(method.selector), $0, method.isRequired, true)
            }
        }
        protocols.registerProtocol(proto)
    }

    /// Adds the protocol named `name` to a class's adopted protocols.
    public static func addProtocol(named name: String, to cls: ObjCClass) {
        guard let proto = protocolObject(name) else { objcInteropFatal("protocol \(name) is not registered") }
        _ = protocols.classAddProtocol(cls.pointer, proto)
    }
}

/// An object that conforms to an Objective-C protocol, which may be of any
/// class. @ObjCProtocol's `Any<Name>` classes inherit from this, or from
/// the class of the protocol they refine.
open class ObjCProtocolObject: NSObject {
    /// The protocol's name. @ObjCProtocol overrides it.
    open class var objCProtocolName: String { "NSObject" }

    /// Registers the protocol with the runtime. @ObjCProtocol overrides it.
    open class func defineObjCProtocol() {}

    /// Whether `object` conforms to the protocol (-conformsToProtocol:).
    public class func conforms(_ object: NSObject) -> Bool {
        guard let proto = ObjCRuntime.protocolObject(objCProtocolName) else { return false }
        typealias Send = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UnsafeMutableRawPointer?) -> Bool
        return unsafeBitCast(ObjCRuntime.msgSend, to: Send.self)(
            object.objcObject, ObjCRuntime.selector("conformsToProtocol:"), proto)
    }

}

// MARK: - Results of optional methods

/// An optional method's result as an Optional: a scalar is always present
/// once the method ran.
public func objCOptionalResult<Value: ObjCValue>(_ value: Value.ObjCType, as type: Value.Type, owned: Bool) -> Value? {
    owned ? Value(objCOwned: value) : Value(objCReturnValue: value)
}

/// An object result is nil when the method returned nil.
public func objCOptionalResult<Value: ObjCNullable>(_ value: Value.ObjCType, as type: Value.Type, owned: Bool) -> Value? {
    if Value.objCIsNil(value) { return nil }
    return owned ? Value(objCOwned: value) : Value(objCReturnValue: value)
}
