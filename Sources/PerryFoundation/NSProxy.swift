import CPerryFoundation
import PerryObjCInterop

/// NSProxy: Foundation's other root class, for objects that stand in for
/// others. It has NSObject's memory management and introspection, taken
/// from NSObject's own methods; anything else it is sent goes to
/// forwarding, where a subclass's -forwardingTargetForSelector: answers,
/// or on arm64 and x86_64 its -methodSignatureForSelector: and
/// -forwardInvocation: (Forwarding.swift).
///
/// As on Darwin, -respondsToSelector:, -isKindOfClass:, -isMemberOfClass:
/// and -conformsToProtocol: are themselves forwarded as invocations, so a
/// proxy answers them as the object it stands for does, and NSProxy's own
/// -methodSignatureForSelector: and -forwardInvocation: raise
/// NSInvalidArgumentException for a subclass that doesn't override them.
@ObjCClass("NSProxy")
open class NSProxy: NSObject {
    override public class var objCSuperclassName: String? { nil }

    nonisolated(unsafe) static let instanceSelectors = [
        "retain", "release", "autorelease", "retainCount", "dealloc", "self", "class", "superclass", "hash",
        "isEqual:", "zone", "debugDescription", "performSelector:", "performSelector:withObject:",
        "allowsWeakReference", "retainWeakReference", "_tryRetain", "_isDeallocating", "doesNotRecognizeSelector:",
    ]
    nonisolated(unsafe) static let classSelectors = [
        "alloc", "allocWithZone:", "class", "self", "superclass", "respondsToSelector:", "instancesRespondToSelector:",
        "conformsToProtocol:", "isSubclassOfClass:", "load", "initialize", "retain", "release",
        "autorelease", "retainCount",
    ]

    /// Copies NSObject's methods, which work on any object.
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        guard let object = "NSObject".withCString({ ObjC.getClass($0) }),
              let metaclass = ObjC.objectGetClass(UnsafeMutableRawPointer(object)),
              let proxyMetaclass = ObjC.objectGetClass(cls.pointer) else { return }
        func copy(_ names: [String], from source: Class, to target: Class) {
            for name in names {
                let selector = ObjC.selector(name)
                guard let method = ObjC.instanceMethod(source, selector), let types = ObjC.methodTypes(method),
                      let imp = ObjC.methodImplementation(source, selector) else { continue }
                _ = ObjC.addMethod(target, selector, imp, types)
            }
        }
        copy(instanceSelectors, from: object, to: cls.storage)
        copy(classSelectors, from: metaclass, to: proxyMetaclass)
    }

    @ObjCMethod("isProxy")
    func isProxy() -> Bool { true }

    /// Foundation's NSObject description, which is a category added after
    /// NSObject's methods are copied: the class and address, as on Darwin.
    @ObjCMethod("description")
    func proxyDescription() -> String { "<\(ObjC.className(objcObject)): \(objcObject)>" }

    @ObjCClassMethod("description")
    static func proxyClassDescription(_ cls: ObjCClass) -> String { ObjC.name(ofClass: cls.pointer) }

    /// Garbage collection's, which nothing runs: nothing to do.
    @ObjCMethod("finalize")
    func proxyFinalize() {}

    /// NSProxy's own: a subclass overrides it to give the signature of the
    /// message it forwards.
    @ObjCMethod("methodSignatureForSelector:")
    func proxyMethodSignature(for selector: UnsafeRawPointer?) -> UnsafeMutableRawPointer? {
        Exceptions.raise(name: "NSInvalidArgumentException", reason: "*** -[NSProxy methodSignatureForSelector:] called!")
    }

    /// NSProxy's own: a subclass overrides it to send the invocation on.
    @ObjCMethod("forwardInvocation:")
    func proxyForward(invocation: UnsafeMutableRawPointer?) {
        Exceptions.raise(name: "NSInvalidArgumentException", reason: "*** -[NSProxy forwardInvocation:] called!")
    }

    @ObjCMethod("respondsToSelector:")
    func proxyResponds(to selector: UnsafeRawPointer?) -> Bool {
        ProxyForwarding.forwardBool(objcObject, "respondsToSelector:", selector.map { UnsafeMutableRawPointer(mutating: $0) })
    }

    @ObjCMethod("isKindOfClass:")
    func proxyIsKind(of cls: UnsafeMutableRawPointer?) -> Bool {
        ProxyForwarding.forwardBool(objcObject, "isKindOfClass:", cls)
    }

    @ObjCMethod("isMemberOfClass:")
    func proxyIsMember(of cls: UnsafeMutableRawPointer?) -> Bool {
        ProxyForwarding.forwardBool(objcObject, "isMemberOfClass:", cls)
    }

    @ObjCMethod("conformsToProtocol:")
    func proxyConforms(to proto: UnsafeMutableRawPointer?) -> Bool {
        ProxyForwarding.forwardBool(objcObject, "conformsToProtocol:", proto)
    }
}

/// A message an NSProxy forwards on its own behalf, as Darwin's NSProxy
/// sends the ones NSObject's protocol has it answer: the proxy's
/// -forwardInvocation: gets an invocation of it. As on Darwin, its
/// -forwardingTargetForSelector: isn't asked, so a proxy that only names a
/// target raises from NSProxy's -methodSignatureForSelector:.
enum ProxyForwarding {
    /// Forwards a message taking one pointer-sized argument and returning a BOOL.
    static func forwardBool(_ object: id, _ name: String, _ argument: UnsafeMutableRawPointer?) -> Bool {
        let selector = ObjC.selector(name)
        // NSProxy's own raises: a subclass that forwards overrides it.
        guard let signature = ObjC.send(object, ObjC.selector("methodSignatureForSelector:"), UnsafeMutableRawPointer(mutating: selector)),
              let invocationClass = "NSInvocation".withCString({ ObjC.getClass($0) }),
              let invocation = ObjC.send(UnsafeMutableRawPointer(invocationClass), ObjC.selector("invocationWithMethodSignature:"), signature)
        else {
            Exceptions.raise(name: "NSInvalidArgumentException",
                             reason: "-[\(ObjC.className(object)) \(name)]: unrecognized selector sent to instance \(object)")
        }
        typealias SetSelector = @convention(c) (id?, SEL, SEL) -> Void
        typealias SetArgument = @convention(c) (id?, SEL, UnsafeMutableRawPointer, Int) -> Void
        typealias GetReturnValue = @convention(c) (id?, SEL, UnsafeMutableRawPointer) -> Void
        unsafeBitCast(ObjC.msgSend, to: SetSelector.self)(invocation, ObjC.selector("setSelector:"), selector)
        _ = ObjC.send(invocation, ObjC.selector("setTarget:"), object)
        var value = argument
        withUnsafeMutablePointer(to: &value) { pointer in
            unsafeBitCast(ObjC.msgSend, to: SetArgument.self)(invocation, ObjC.selector("setArgument:atIndex:"),
                                                              UnsafeMutableRawPointer(pointer), 2)
        }
        _ = ObjC.send(object, ObjC.selector("forwardInvocation:"), invocation)
        // Room for any return value; a BOOL is its first byte.
        var result = [UInt8](repeating: 0, count: 32)
        result.withUnsafeMutableBytes { bytes in
            unsafeBitCast(ObjC.msgSend, to: GetReturnValue.self)(invocation, ObjC.selector("getReturnValue:"), bytes.baseAddress!)
        }
        return result[0] != 0
    }
}
