import CPerryFoundation
import PerryObjCInterop

/// NSProxy: Foundation's other root class, for objects that stand in for
/// others. It has NSObject's memory management and introspection, taken
/// from NSObject's own methods; anything else it is sent goes to
/// forwarding, where a subclass's -forwardingTargetForSelector: answers.
/// NSInvocation-based forwarding (-forwardInvocation:) is not supported.
@ObjCClass("NSProxy")
open class NSProxy: NSObject {
    override public class var objCSuperclassName: String? { nil }

    nonisolated(unsafe) static let instanceSelectors = [
        "retain", "release", "autorelease", "retainCount", "dealloc", "self", "class", "superclass", "hash",
        "isEqual:", "zone", "description", "debugDescription", "isKindOfClass:", "isMemberOfClass:",
        "respondsToSelector:", "conformsToProtocol:", "performSelector:", "performSelector:withObject:",
        "allowsWeakReference", "retainWeakReference", "_tryRetain", "_isDeallocating",
    ]
    nonisolated(unsafe) static let classSelectors = [
        "alloc", "allocWithZone:", "class", "self", "superclass", "respondsToSelector:", "instancesRespondToSelector:",
        "conformsToProtocol:", "isSubclassOfClass:", "description", "load", "initialize", "retain", "release",
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
}
