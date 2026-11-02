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
        _ = MethodTable(object, RootObject.registerObjCMethods)
        Objects.defaultRetain = Runtime.findMethod(object, Sel.retain)?.pointee.imp
        Objects.defaultRelease = Runtime.findMethod(object, Sel.release)?.pointee.imp
        Objects.defaultAutorelease = Runtime.findMethod(object, Sel.autorelease)?.pointee.imp

        // Protocol objects are static data: retain and release do nothing.
        let proto = Runtime.makeClass(perry_objc_protocol_class(), metaclass: perry_objc_protocol_metaclass(),
                                      superclass: perry_objc_nsobject_class(), name: permanentCString("Protocol"),
                                      instanceSize: 8, registerName: true)
        _ = MethodTable(proto, ImmortalObject.registerObjCMethods)
    }()

    /// Points the interop layer at this runtime's functions.
    private static func installInterop() {
        ObjCRuntime.install(ObjCRuntimeFunctions(
            msgSend: perry_objc_msgSend_address(),
            msgSendSuper2: perry_objc_msgSendSuper2_address(),
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
    }
}

// MARK: - NSObject

/// The root class's methods, as the runtime implements them. Memory
/// management methods return raw pointers so ownership passes through
/// untouched.
@ObjCClass("NSObject")
final class RootObject: NSObject {
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

    private static func classPointer(_ cls: ObjCClass) -> ClassPointer {
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

/// retain, release and autorelease for objects that live forever.
@ObjCClass("NSObject")
final class ImmortalObject: NSObject {
    @ObjCMethod("retain") func retain() -> UnsafeMutableRawPointer { objcObject }
    @ObjCMethod("release", types: "Vv16@0:8") func release() {}
    @ObjCMethod("autorelease") func autorelease() -> UnsafeMutableRawPointer { objcObject }
    @ObjCMethod("retainCount") func retainCount() -> UInt { UInt.max }
}

/// The block classes, built inside libSystem's _NSConcrete*Block storage
/// so blocks can be messaged: retained, released and copied.
public enum BlockClasses {
    typealias BlockCopy = @convention(c) (UnsafeRawPointer?) -> UnsafeMutableRawPointer?
    typealias BlockRelease = @convention(c) (UnsafeRawPointer?) -> Void

    nonisolated(unsafe) static var blockCopy: BlockCopy?
    nonisolated(unsafe) static var blockRelease: BlockRelease?

    /// _Block_copy, or the block itself when libSystem has no blocks runtime.
    public static func copy(_ block: UnsafeRawPointer?) -> UnsafeMutableRawPointer? {
        blockCopy.map { $0(block) } ?? UnsafeMutableRawPointer(mutating: block)
    }

    public static func release(_ block: UnsafeRawPointer?) {
        blockRelease?(block)
    }

    /// Storage for each class: libSystem's symbol, class in words 0-15 and
    /// metaclass in words 16-31.
    public struct Storage {
        public var stack, malloc, global, auto, finalizing, weakVariable: UnsafeMutableRawPointer?
        public init(stack: UnsafeMutableRawPointer?, malloc: UnsafeMutableRawPointer?, global: UnsafeMutableRawPointer?,
                    auto: UnsafeMutableRawPointer?, finalizing: UnsafeMutableRawPointer?,
                    weakVariable: UnsafeMutableRawPointer?) {
            self.stack = stack
            self.malloc = malloc
            self.global = global
            self.auto = auto
            self.finalizing = finalizing
            self.weakVariable = weakVariable
        }
    }

    public static func install(_ storage: Storage, copy: UnsafeMutableRawPointer?, release: UnsafeMutableRawPointer?) {
        blockCopy = copy.map { unsafeBitCast($0, to: BlockCopy.self) }
        blockRelease = release.map { unsafeBitCast($0, to: BlockRelease.self) }

        let base = UnsafeMutablePointer<perry_objc_class>.allocate(capacity: 2)
        base.initialize(repeating: perry_objc_class(), count: 2)
        let block = Runtime.makeClass(base, metaclass: base + 1, superclass: RootClasses.nsObject,
                                      name: permanentCString("NSBlock"), instanceSize: 8, registerName: true)
        _ = MethodTable(block, NSBlock.registerObjCMethods)

        func make(_ name: String, _ storage: UnsafeMutableRawPointer?, _ registrations: ObjCMethodRegistration...) {
            guard let storage else { return }
            let info = Runtime.makeClass(storage.assumingMemoryBound(to: perry_objc_class.self),
                                         metaclass: (storage + 128).assumingMemoryBound(to: perry_objc_class.self),
                                         superclass: block.cls, name: permanentCString(name),
                                         instanceSize: 8, registerName: true)
            _ = MethodTable(info, registrations)
        }
        // Heap blocks are reference counted by the blocks runtime; stack and
        // global blocks are not, and copying a stack block moves it to the heap.
        make("__NSMallocBlock__", storage.malloc, HeapBlock.registerObjCMethods)
        make("__NSAutoBlock__", storage.auto, HeapBlock.registerObjCMethods)
        make("__NSFinalizingBlock__", storage.finalizing, HeapBlock.registerObjCMethods)
        make("__NSStackBlock__", storage.stack, ImmortalObject.registerObjCMethods)
        make("__NSGlobalBlock__", storage.global, ImmortalObject.registerObjCMethods)
        make("__NSBlockVariable__", storage.weakVariable, ImmortalObject.registerObjCMethods)
    }
}

/// Blocks, whose classes are built in libSystem's storage.
@ObjCClass("NSBlock")
class NSBlock: NSObject {
    @ObjCMethod("copy") func copy() -> UnsafeMutableRawPointer? { BlockClasses.copy(objcObject) }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { BlockClasses.copy(objcObject) }

    /// Calls a block that takes no arguments.
    @ObjCMethod("invoke")
    func invoke() {
        typealias Invoke = @convention(c) (ObjectPointer) -> Void
        unsafeBitCast(objcObject.load(fromByteOffset: 16, as: UnsafeRawPointer.self), to: Invoke.self)(objcObject)
    }
}

/// Heap blocks, reference counted by the blocks runtime.
@ObjCClass("__NSMallocBlock__")
final class HeapBlock: NSBlock {
    @ObjCMethod("retain") func retain() -> UnsafeMutableRawPointer? { BlockClasses.copy(objcObject) }
    @ObjCMethod("release", types: "Vv16@0:8") func release() { BlockClasses.release(objcObject) }

    @ObjCMethod("autorelease")
    func autorelease() -> UnsafeMutableRawPointer {
        AutoreleasePool.add(objcObject)
        return objcObject
    }

    @ObjCMethod("retainCount") func retainCount() -> UInt { 1 }
}
