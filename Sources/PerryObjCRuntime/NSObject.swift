import CPerryObjC
import Glibc
import PerryObjCInterop

/// Installs @ObjCImplementation methods into a class the runtime built.
struct MethodTable: ObjCMethodRegistrar {
    let info: ClassInfo

    init(_ info: ClassInfo, _ registrations: ObjCMethodRegistration...) {
        self.init(info, registrations)
    }

    init(_ info: ClassInfo, _ registrations: [ObjCMethodRegistration]) {
        self.info = info
        for register in registrations { register(self) }
    }

    func addMethod(_ selector: String, types: String, implementation: UnsafeRawPointer, isClassMethod: Bool) {
        guard let target = isClassMethod ? info.partner : info else { return }
        Runtime.addMethod(target, Selectors.register(selector), types: permanentCString(types),
                          imp: IMP(mutating: implementation), replacing: true)
    }
}

public enum RootClasses {
    nonisolated(unsafe) public private(set) static var nsObject: ClassPointer = perry_objc_nsobject_class()

    /// Builds NSObject and Protocol. Runs once, before any image is mapped.
    public static func bootstrap() {
        _ = once
    }

    private static let once: Void = {
        installInterop()
        let object = Runtime.makeClass(perry_objc_nsobject_class(), metaclass: perry_objc_nsobject_metaclass(),
                                       superclass: nil, name: permanentCString("NSObject"),
                                       instanceSize: 8, registerName: true)
        _ = MethodTable(object, NSObject.registerObjCCategoryRuntime)
        Objects.defaultRetain = Runtime.findMethod(object, Sel.retain)?.pointee.imp
        Objects.defaultRelease = Runtime.findMethod(object, Sel.release)?.pointee.imp
        Objects.defaultAutorelease = Runtime.findMethod(object, Sel.autorelease)?.pointee.imp

        // Protocol objects are static data: retain and release do nothing.
        let proto = Runtime.makeClass(perry_objc_protocol_class(), metaclass: perry_objc_protocol_metaclass(),
                                      superclass: perry_objc_nsobject_class(), name: permanentCString("Protocol"),
                                      instanceSize: 8, registerName: true)
        _ = MethodTable(proto, NSObject.registerObjCCategoryImmortal)
    }()

    #if arch(arm)
    private static var stretSend: UnsafeRawPointer? { perry_objc_msgSend_stret_address() }
    private static var stretSuperSend: UnsafeRawPointer? { perry_objc_msgSendSuper2_stret_address() }
    #else
    private static var stretSend: UnsafeRawPointer? { nil }
    private static var stretSuperSend: UnsafeRawPointer? { nil }
    #endif

    /// Points the interop layer at this runtime's functions.
    private static func installInterop() {
        ObjCRuntime.install(ObjCRuntimeFunctions(
            msgSend: perry_objc_msgSend_address(),
            msgSendSuper2: perry_objc_msgSendSuper2_address(),
            msgSendStret: stretSend, msgSendSuper2Stret: stretSuperSend,
            retain: { $0.map(Objects.retain) },
            release: { if let object = $0 { Objects.release(object) } },
            autorelease: { $0.map(Objects.autorelease) },
            retainBlock: { BlockClasses.copy($0) },
            getClass: { name in name.flatMap(Runtime.lookUpClass).map(UnsafeMutableRawPointer.init) },
            objectGetClass: { $0.map { UnsafeMutableRawPointer(classOf($0)) } },
            registerSelector: { name in name.map { UnsafeRawPointer(Selectors.register($0)) } },
            addMethod: { cls, selector, imp, types in
                guard let cls, let selector, let info = Runtime.info(cls.assumingMemoryBound(to: perry_objc_class.self)),
                      Runtime.findOwnMethod(info, selector.assumingMemoryBound(to: CChar.self)) == nil else { return false }
                Runtime.addMethod(info, selector.assumingMemoryBound(to: CChar.self), types: types.map { permanentCString(String(cString: $0)) },
                                  imp: imp.map(IMP.init(mutating:)), replacing: false)
                return true
            },
            replaceMethod: { cls, selector, imp, types in
                guard let cls, let selector, let info = Runtime.info(cls.assumingMemoryBound(to: perry_objc_class.self)) else { return nil }
                let old = Runtime.addMethod(info, selector.assumingMemoryBound(to: CChar.self),
                                            types: types.map { permanentCString(String(cString: $0)) },
                                            imp: imp.map(IMP.init(mutating:)), replacing: true)
                return old.map(UnsafeRawPointer.init)
            },
            initializeClassPair: { superclass, name, cls, metaclass in
                guard let name, let cls, let metaclass else { return nil }
                return UnsafeMutableRawPointer(Runtime.initializeClassPair(
                    superclass: superclass?.assumingMemoryBound(to: perry_objc_class.self), name: permanentCString(String(cString: name)),
                    cls: cls.assumingMemoryBound(to: perry_objc_class.self),
                    metaclass: metaclass.assumingMemoryBound(to: perry_objc_class.self)))
            },
            allocateClassPair: { superclass, name, extraBytes in
                guard let name, Runtime.lookUpClass(name) == nil else { return nil }
                return UnsafeMutableRawPointer(Runtime.allocateClassPair(
                    superclass: superclass?.assumingMemoryBound(to: perry_objc_class.self),
                    name: permanentCString(String(cString: name)), extraBytes: extraBytes))
            },
            registerClassPair: { cls in
                if let cls { Runtime.registerClassPair(cls.assumingMemoryBound(to: perry_objc_class.self)) }
            }))
        ObjCRuntime.poolFunctions = (push: { AutoreleasePool.push() }, pop: { AutoreleasePool.pop($0) })
        ObjCRuntime.weakFunctions = (store: { slot, object in slot.flatMap { WeakReferences.store($0, object) } },
                                     loadRetained: { slot in slot.flatMap(WeakReferences.loadRetained) })
        ObjCPeers.install(
            bind: { object, peer, retained in
                if let object, let peer { Objects.bindPeer(object, peer, retained: retained) }
            },
            peer: { $0.flatMap(Objects.peer) },
            willDeinitialize: { $0.map(Objects.peerWillDeinitialize) ?? false })
    }
}

// MARK: - NSObject

/// The root class's methods, as the runtime implements them: installed into
/// NSObject, which the runtime builds itself. Memory management methods
/// return raw pointers so ownership passes through untouched.
@ObjCCategory("Runtime")
extension NSObject {
    // MARK: Identity

    @ObjCMethod("init") func initialize() -> Self { self }
    @ObjCMethod("self") func this() -> UnsafeMutableRawPointer { objcObject }
    @ObjCMethod("class") func cls() -> ObjCClass { objCClass }
    @ObjCMethod("superclass") func superclass() -> ObjCClass? { objCClass.superclass }
    @ObjCMethod("zone") func zone() -> UnsafeMutableRawPointer? { nil }
    @ObjCMethod("hash") func hash() -> UInt { UInt(bitPattern: objcObject) }
    @ObjCMethod("isEqual:") func isEqual(_ other: UnsafeMutableRawPointer?) -> Bool { objcObject == other }
    @ObjCMethod("isProxy") func isProxy() -> Bool { false }
    @ObjCMethod("description") func description() -> UnsafeMutableRawPointer? { nil }
    @ObjCMethod("debugDescription")
    func debugDescription() -> UnsafeMutableRawPointer? { Messages.send(objcObject, Sel.description) }

    // MARK: Lifetime

    @ObjCMethod("dealloc") func dealloc() { Objects.dispose(objcObject) }

    @ObjCMethod("retain")
    func retain() -> UnsafeMutableRawPointer {
        RetainCounts.retain(objcObject)
        return objcObject
    }

    @ObjCMethod("release", types: "Vv16@0:8")
    func release() {
        if RetainCounts.release(objcObject) {
            Messages.sendVoid(objcObject, Sel.dealloc)
        }
    }

    @ObjCMethod("autorelease")
    func autorelease() -> UnsafeMutableRawPointer {
        AutoreleasePool.add(objcObject)
        return objcObject
    }

    @ObjCMethod("retainCount") func retainCount() -> UInt { RetainCounts.count(objcObject) }

    @ObjCMethod("copy")
    func copy() -> UnsafeMutableRawPointer? { Messages.send(objcObject, Sel.copyWithZone, nil) }

    @ObjCMethod("mutableCopy")
    func mutableCopy() -> UnsafeMutableRawPointer? { Messages.send(objcObject, Sel.mutableCopyWithZone, nil) }

    // MARK: Introspection

    // What the Swift runtime asks to tell Foundation's classes apart: each
    // Foundation class answers YES for itself.
    @ObjCMethod("isNSObject__") func isNSObject__() -> Bool { true }
    @ObjCMethod("isNSArray__") func isNSArray__() -> Bool { false }
    @ObjCMethod("isNSCFConstantString__") func isNSCFConstantString__() -> Bool { false }
    @ObjCMethod("isNSData__") func isNSData__() -> Bool { false }
    @ObjCMethod("isNSDate__") func isNSDate__() -> Bool { false }
    @ObjCMethod("isNSDictionary__") func isNSDictionary__() -> Bool { false }
    @ObjCMethod("isNSNumber__") func isNSNumber__() -> Bool { false }
    @ObjCMethod("isNSOrderedSet__") func isNSOrderedSet__() -> Bool { false }
    @ObjCMethod("isNSSet__") func isNSSet__() -> Bool { false }
    @ObjCMethod("isNSString__") func isNSString__() -> Bool { false }
    @ObjCMethod("isNSTimeZone__") func isNSTimeZone__() -> Bool { false }
    @ObjCMethod("isNSValue__") func isNSValue__() -> Bool { false }

    @ObjCMethod("isKindOfClass:")
    func isKind(of target: ObjCClass?) -> Bool {
        var current: ObjCClass? = objCClass
        while let cls = current {
            if cls == target { return true }
            current = cls.superclass
        }
        return false
    }

    @ObjCMethod("isMemberOfClass:")
    func isMember(of target: ObjCClass?) -> Bool { objCClass == target }

    @ObjCMethod("respondsToSelector:")
    func responds(to selector: ObjCSelector?) -> Bool {
        guard let selector, let info = Runtime.info(classOf(objcObject)) else { return false }
        return Runtime.responds(info, selector.pointer.assumingMemoryBound(to: CChar.self))
    }

    @ObjCMethod("conformsToProtocol:")
    func conforms(to proto: UnsafeMutableRawPointer?) -> Bool {
        guard let proto, let info = Runtime.info(classOf(objcObject)) else { return false }
        return Protocols.classOrSuperclassConforms(info, to: proto.assumingMemoryBound(to: perry_protocol.self))
    }

    @ObjCMethod("methodForSelector:")
    func method(for selector: ObjCSelector?) -> UnsafeMutableRawPointer? {
        guard let selector else { return nil }
        return Runtime.lookUpIMP(receiver: objcObject, selector: selector.pointer.assumingMemoryBound(to: CChar.self),
                                 cls: classOf(objcObject))
    }

    // MARK: Sending

    @ObjCMethod("performSelector:")
    func perform(_ selector: ObjCSelector?) -> UnsafeMutableRawPointer? {
        selector.flatMap { Messages.send(objcObject, $0.pointer.assumingMemoryBound(to: CChar.self)) }
    }

    @ObjCMethod("performSelector:withObject:")
    func perform(_ selector: ObjCSelector?, with argument: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        selector.flatMap { Messages.send(objcObject, $0.pointer.assumingMemoryBound(to: CChar.self), UnsafeRawPointer(argument)) }
    }

    @ObjCMethod("performSelector:withObject:withObject:")
    func perform(_ selector: ObjCSelector?, with first: UnsafeMutableRawPointer?,
                 with second: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        selector.flatMap {
            Messages.send(objcObject, $0.pointer.assumingMemoryBound(to: CChar.self), UnsafeRawPointer(first), UnsafeRawPointer(second))
        }
    }

    @ObjCMethod("forwardingTargetForSelector:")
    func forwardingTarget(for selector: ObjCSelector?) -> UnsafeMutableRawPointer? { nil }

    @ObjCMethod("doesNotRecognizeSelector:")
    func doesNotRecognize(_ selector: ObjCSelector?) {
        if let selector { Runtime.unrecognized(objcObject, selector.pointer.assumingMemoryBound(to: CChar.self)) }
    }

    // MARK: Class methods

    fileprivate static func classPointer(_ cls: ObjCClass) -> ClassPointer {
        cls.pointer.assumingMemoryBound(to: perry_objc_class.self)
    }

    @ObjCClassMethod("alloc")
    static func alloc(_ cls: ObjCClass) -> UnsafeMutableRawPointer? { Objects.createInstance(classPointer(cls)) }

    @ObjCClassMethod("allocWithZone:")
    static func alloc(_ cls: ObjCClass, zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { alloc(cls) }

    @ObjCClassMethod("new")
    static func new(_ cls: ObjCClass) -> UnsafeMutableRawPointer? {
        Messages.send(Messages.send(cls.pointer, Sel.alloc), Sel.`init`)
    }

    @ObjCClassMethod("class") static func classSelf(_ cls: ObjCClass) -> ObjCClass { cls }
    @ObjCClassMethod("superclass") static func classSuperclass(_ cls: ObjCClass) -> ObjCClass? { cls.superclass }
    @ObjCClassMethod("initialize") static func classInitialize() {}
    /// Does nothing, as on Darwin: subclasses' +load call [super load].
    @ObjCClassMethod("load") static func classLoad() {}
    @ObjCClassMethod("description") static func classDescription() -> UnsafeMutableRawPointer? { nil }

    @ObjCClassMethod("instancesRespondToSelector:")
    static func instancesRespond(_ cls: ObjCClass, to selector: ObjCSelector?) -> Bool {
        guard let selector, let info = Runtime.info(classPointer(cls)) else { return false }
        return Runtime.responds(info, selector.pointer.assumingMemoryBound(to: CChar.self))
    }

    @ObjCClassMethod("isSubclassOfClass:")
    static func isSubclass(_ cls: ObjCClass, of target: ObjCClass?) -> Bool {
        var current: ObjCClass? = cls
        while let c = current {
            if c == target { return true }
            current = c.superclass
        }
        return false
    }

    @ObjCClassMethod("conformsToProtocol:")
    static func classConforms(_ cls: ObjCClass, to proto: UnsafeMutableRawPointer?) -> Bool {
        guard let proto, let info = Runtime.info(classPointer(cls)) else { return false }
        return Protocols.classOrSuperclassConforms(info, to: proto.assumingMemoryBound(to: perry_protocol.self))
    }

    @ObjCClassMethod("resolveClassMethod:") static func resolveClassMethod(_ selector: ObjCSelector?) -> Bool { false }
    @ObjCClassMethod("resolveInstanceMethod:") static func resolveInstanceMethod(_ selector: ObjCSelector?) -> Bool { false }

    @ObjCClassMethod("instanceMethodForSelector:")
    static func instanceMethod(_ cls: ObjCClass, for selector: ObjCSelector?) -> UnsafeMutableRawPointer? {
        guard let selector else { return nil }
        return Runtime.lookUpIMP(receiver: nil, selector: selector.pointer.assumingMemoryBound(to: CChar.self),
                                 cls: classPointer(cls))
    }

    // Classes are never deallocated.
    @ObjCClassMethod("retain") static func classRetain(_ cls: ObjCClass) -> UnsafeMutableRawPointer { cls.pointer }
    @ObjCClassMethod("release", types: "Vv16@0:8") static func classRelease() {}
    @ObjCClassMethod("autorelease") static func classAutorelease(_ cls: ObjCClass) -> UnsafeMutableRawPointer { cls.pointer }
    @ObjCClassMethod("retainCount") static func classRetainCount() -> UInt { UInt.max }
}

/// retain, release and autorelease for objects that live forever, installed
/// into Protocol and the stack and global block classes. The Swift names
/// differ from the Runtime category's, as extension methods must.
@ObjCCategory("Immortal")
extension NSObject {
    @ObjCMethod("retain") func immortalRetain() -> UnsafeMutableRawPointer { objcObject }
    @ObjCMethod("release", types: "Vv16@0:8") func immortalRelease() {}
    @ObjCMethod("autorelease") func immortalAutorelease() -> UnsafeMutableRawPointer { objcObject }
    @ObjCMethod("retainCount") func immortalRetainCount() -> UInt { UInt.max }
}
