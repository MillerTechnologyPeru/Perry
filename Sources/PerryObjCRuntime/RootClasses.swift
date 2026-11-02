import CPerryObjC
import Glibc
import PerryObjCInterop

/// Installs @ObjCImplementation method tables into a class the runtime
/// built.
struct MethodTable: ObjCMethodRegistrar {
    let info: ClassInfo

    init(_ info: ClassInfo, _ tables: any ObjCMethodTable.Type...) {
        self.info = info
        for table in tables { table.register(self) }
    }

    func addMethod(_ selector: String, types: String, implementation: UnsafeRawPointer, isClassMethod: Bool) {
        guard let target = isClassMethod ? info.partner : info else { return }
        Runtime.addMethod(target, Selectors.register(selector), types: permanentCString(types),
                          imp: IMP(mutating: implementation), replacing: true)
    }
}

@inline(__always)
private func asClass(_ object: ObjectPointer?) -> ClassPointer? {
    object?.assumingMemoryBound(to: perry_objc_class.self)
}

public enum RootClasses {
    nonisolated(unsafe) public private(set) static var nsObject: ClassPointer = perry_objc_nsobject_class()

    /// Builds NSObject and Protocol. Runs once, before any image is mapped.
    public static func bootstrap() {
        _ = once
    }

    private static let once: Void = {
        let object = Runtime.makeClass(perry_objc_nsobject_class(), metaclass: perry_objc_nsobject_metaclass(),
                                       superclass: nil, name: permanentCString("NSObject"),
                                       instanceSize: 8, registerName: true)
        _ = MethodTable(object, NSObjectMethods.self)
        Objects.defaultRetain = Runtime.findMethod(object, Sel.retain)?.pointee.imp
        Objects.defaultRelease = Runtime.findMethod(object, Sel.release)?.pointee.imp
        Objects.defaultAutorelease = Runtime.findMethod(object, Sel.autorelease)?.pointee.imp

        // Protocol objects are static data: retain and release do nothing.
        let proto = Runtime.makeClass(perry_objc_protocol_class(), metaclass: perry_objc_protocol_metaclass(),
                                      superclass: perry_objc_nsobject_class(), name: permanentCString("Protocol"),
                                      instanceSize: 8, registerName: true)
        _ = MethodTable(proto, ImmortalMethods.self)
    }()
}

/// NSObject, the root class.
@ObjCImplementation
enum NSObjectMethods {
    // MARK: Identity

    @ObjCMethod("init") static func initialize(_ object: ObjectPointer?) -> ObjectPointer? { object }
    @ObjCMethod("self") static func this(_ object: ObjectPointer?) -> ObjectPointer? { object }

    @ObjCMethod("class")
    static func cls(_ object: ObjectPointer?) -> ClassPointer? { object.map(classOf) }

    @ObjCMethod("superclass")
    static func superclass(_ object: ObjectPointer?) -> ClassPointer? { object.flatMap { classOf($0).pointee.superclass } }

    @ObjCMethod("zone") static func zone(_ object: ObjectPointer?) -> UnsafeMutableRawPointer? { nil }
    @ObjCMethod("hash") static func hash(_ object: ObjectPointer?) -> UInt { UInt(bitPattern: object) }
    @ObjCMethod("isEqual:") static func isEqual(_ object: ObjectPointer?, _ other: ObjectPointer?) -> Bool { object == other }
    @ObjCMethod("isProxy") static func isProxy(_ object: ObjectPointer?) -> Bool { false }
    @ObjCMethod("description") static func description(_ object: ObjectPointer?) -> ObjectPointer? { nil }

    @ObjCMethod("debugDescription")
    static func debugDescription(_ object: ObjectPointer?) -> ObjectPointer? { Messages.send(object, Sel.description) }

    // MARK: Lifetime

    @ObjCMethod("dealloc")
    static func dealloc(_ object: ObjectPointer?) {
        if let object { Objects.dispose(object) }
    }

    @ObjCMethod("retain")
    static func retain(_ object: ObjectPointer?) -> ObjectPointer? {
        if let object { RetainCounts.retain(object) }
        return object
    }

    @ObjCMethod("release", types: "Vv16@0:8")
    static func release(_ object: ObjectPointer?) {
        if let object, RetainCounts.release(object) {
            Messages.sendVoid(object, Sel.dealloc)
        }
    }

    @ObjCMethod("autorelease")
    static func autorelease(_ object: ObjectPointer?) -> ObjectPointer? {
        if let object { AutoreleasePool.add(object) }
        return object
    }

    @ObjCMethod("retainCount")
    static func retainCount(_ object: ObjectPointer?) -> UInt { object.map { RetainCounts.count($0) } ?? 0 }

    @ObjCMethod("copy")
    static func copy(_ object: ObjectPointer?) -> ObjectPointer? { Messages.send(object, Sel.copyWithZone, nil) }

    @ObjCMethod("mutableCopy")
    static func mutableCopy(_ object: ObjectPointer?) -> ObjectPointer? {
        Messages.send(object, Sel.mutableCopyWithZone, nil)
    }

    // MARK: Introspection

    @ObjCMethod("isKindOfClass:")
    static func isKind(_ object: ObjectPointer?, of target: ClassPointer?) -> Bool {
        guard let object else { return false }
        var cls: ClassPointer? = classOf(object)
        while let current = cls {
            if current == target { return true }
            cls = current.pointee.superclass
        }
        return false
    }

    @ObjCMethod("isMemberOfClass:")
    static func isMember(_ object: ObjectPointer?, of target: ClassPointer?) -> Bool {
        object.map { classOf($0) == target } ?? false
    }

    @ObjCMethod("respondsToSelector:")
    static func responds(_ object: ObjectPointer?, to selector: SEL?) -> Bool {
        guard let object, let selector, let info = Runtime.info(classOf(object)) else { return false }
        return Runtime.responds(info, selector)
    }

    @ObjCMethod("conformsToProtocol:")
    static func conforms(_ object: ObjectPointer?, to proto: UnsafeMutableRawPointer?) -> Bool {
        guard let object, let proto, let info = Runtime.info(classOf(object)) else { return false }
        return Protocols.classOrSuperclassConforms(info, to: proto.assumingMemoryBound(to: perry_protocol.self))
    }

    @ObjCMethod("methodForSelector:")
    static func method(_ object: ObjectPointer?, for selector: SEL?) -> UnsafeMutableRawPointer? {
        guard let object, let selector else { return nil }
        return Runtime.lookUpIMP(receiver: object, selector: selector, cls: classOf(object))
    }

    // MARK: Sending

    @ObjCMethod("performSelector:")
    static func perform(_ object: ObjectPointer?, _ selector: SEL?) -> ObjectPointer? {
        selector.flatMap { Messages.send(object, $0) }
    }

    @ObjCMethod("performSelector:withObject:")
    static func perform(_ object: ObjectPointer?, _ selector: SEL?, with argument: ObjectPointer?) -> ObjectPointer? {
        selector.flatMap { Messages.send(object, $0, UnsafeRawPointer(argument)) }
    }

    @ObjCMethod("performSelector:withObject:withObject:")
    static func perform(_ object: ObjectPointer?, _ selector: SEL?, with first: ObjectPointer?,
                        with second: ObjectPointer?) -> ObjectPointer? {
        selector.flatMap { Messages.send(object, $0, UnsafeRawPointer(first), UnsafeRawPointer(second)) }
    }

    @ObjCMethod("forwardingTargetForSelector:")
    static func forwardingTarget(_ object: ObjectPointer?, for selector: SEL?) -> ObjectPointer? { nil }

    @ObjCMethod("doesNotRecognizeSelector:")
    static func doesNotRecognize(_ object: ObjectPointer?, _ selector: SEL?) {
        if let object, let selector { Runtime.unrecognized(object, selector) }
    }

    // MARK: Class methods

    @ObjCClassMethod("alloc")
    static func alloc(_ cls: ObjectPointer?) -> ObjectPointer? { asClass(cls).flatMap { Objects.createInstance($0) } }

    @ObjCClassMethod("allocWithZone:")
    static func alloc(_ cls: ObjectPointer?, zone: UnsafeMutableRawPointer?) -> ObjectPointer? { alloc(cls) }

    @ObjCClassMethod("new")
    static func new(_ cls: ObjectPointer?) -> ObjectPointer? { Messages.send(Messages.send(cls, Sel.alloc), Sel.`init`) }

    @ObjCClassMethod("class") static func classSelf(_ cls: ObjectPointer?) -> ClassPointer? { asClass(cls) }

    @ObjCClassMethod("superclass")
    static func classSuperclass(_ cls: ObjectPointer?) -> ClassPointer? { asClass(cls)?.pointee.superclass }

    @ObjCClassMethod("initialize") static func classInitialize(_ cls: ObjectPointer?) {}
    @ObjCClassMethod("description") static func classDescription(_ cls: ObjectPointer?) -> ObjectPointer? { nil }

    @ObjCClassMethod("instancesRespondToSelector:")
    static func instancesRespond(_ cls: ObjectPointer?, to selector: SEL?) -> Bool {
        guard let cls = asClass(cls), let selector, let info = Runtime.info(cls) else { return false }
        return Runtime.responds(info, selector)
    }

    @ObjCClassMethod("isSubclassOfClass:")
    static func isSubclass(_ cls: ObjectPointer?, of target: ClassPointer?) -> Bool {
        var current = asClass(cls)
        while let c = current {
            if c == target { return true }
            current = c.pointee.superclass
        }
        return false
    }

    @ObjCClassMethod("conformsToProtocol:")
    static func classConforms(_ cls: ObjectPointer?, to proto: UnsafeMutableRawPointer?) -> Bool {
        guard let cls = asClass(cls), let proto, let info = Runtime.info(cls) else { return false }
        return Protocols.classOrSuperclassConforms(info, to: proto.assumingMemoryBound(to: perry_protocol.self))
    }

    @ObjCClassMethod("resolveClassMethod:")
    static func resolveClassMethod(_ cls: ObjectPointer?, _ selector: SEL?) -> Bool { false }

    @ObjCClassMethod("resolveInstanceMethod:")
    static func resolveInstanceMethod(_ cls: ObjectPointer?, _ selector: SEL?) -> Bool { false }

    @ObjCClassMethod("instanceMethodForSelector:")
    static func instanceMethod(_ cls: ObjectPointer?, for selector: SEL?) -> UnsafeMutableRawPointer? {
        guard let cls = asClass(cls), let selector else { return nil }
        return Runtime.lookUpIMP(receiver: nil, selector: selector, cls: cls)
    }

    // Classes are never deallocated.
    @ObjCClassMethod("retain") static func classRetain(_ cls: ObjectPointer?) -> ObjectPointer? { cls }
    @ObjCClassMethod("release", types: "Vv16@0:8") static func classRelease(_ cls: ObjectPointer?) {}
    @ObjCClassMethod("autorelease") static func classAutorelease(_ cls: ObjectPointer?) -> ObjectPointer? { cls }
    @ObjCClassMethod("retainCount") static func classRetainCount(_ cls: ObjectPointer?) -> UInt { UInt.max }
}

/// retain, release and autorelease for objects that live forever.
@ObjCImplementation
enum ImmortalMethods {
    @ObjCMethod("retain") static func retain(_ object: ObjectPointer?) -> ObjectPointer? { object }
    @ObjCMethod("release", types: "Vv16@0:8") static func release(_ object: ObjectPointer?) {}
    @ObjCMethod("autorelease") static func autorelease(_ object: ObjectPointer?) -> ObjectPointer? { object }
    @ObjCMethod("retainCount") static func retainCount(_ object: ObjectPointer?) -> UInt { UInt.max }
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
        _ = MethodTable(block, NSBlockMethods.self)

        func make(_ name: String, _ storage: UnsafeMutableRawPointer?, _ tables: any ObjCMethodTable.Type...) {
            guard let storage else { return }
            let info = Runtime.makeClass(storage.assumingMemoryBound(to: perry_objc_class.self),
                                         metaclass: (storage + 128).assumingMemoryBound(to: perry_objc_class.self),
                                         superclass: block.cls, name: permanentCString(name),
                                         instanceSize: 8, registerName: true)
            for table in tables { table.register(MethodTable(info)) }
        }
        // Heap blocks are reference counted by the blocks runtime; stack and
        // global blocks are not, and copying a stack block moves it to the heap.
        make("__NSMallocBlock__", storage.malloc, HeapBlockMethods.self)
        make("__NSAutoBlock__", storage.auto, HeapBlockMethods.self)
        make("__NSFinalizingBlock__", storage.finalizing, HeapBlockMethods.self)
        make("__NSStackBlock__", storage.stack, ImmortalMethods.self)
        make("__NSGlobalBlock__", storage.global, ImmortalMethods.self)
        make("__NSBlockVariable__", storage.weakVariable, ImmortalMethods.self)
    }
}

@ObjCImplementation
enum NSBlockMethods {
    @ObjCMethod("copy") static func copy(_ block: ObjectPointer?) -> ObjectPointer? { BlockClasses.copy(block) }

    @ObjCMethod("copyWithZone:")
    static func copy(_ block: ObjectPointer?, zone: UnsafeMutableRawPointer?) -> ObjectPointer? { BlockClasses.copy(block) }

    /// Calls a block that takes no arguments.
    @ObjCMethod("invoke")
    static func invoke(_ block: ObjectPointer?) {
        guard let block else { return }
        typealias Invoke = @convention(c) (ObjectPointer) -> Void
        unsafeBitCast(block.load(fromByteOffset: 16, as: UnsafeRawPointer.self), to: Invoke.self)(block)
    }
}

@ObjCImplementation
enum HeapBlockMethods {
    @ObjCMethod("retain") static func retain(_ block: ObjectPointer?) -> ObjectPointer? { BlockClasses.copy(block) }
    @ObjCMethod("release", types: "Vv16@0:8") static func release(_ block: ObjectPointer?) { BlockClasses.release(block) }

    @ObjCMethod("autorelease")
    static func autorelease(_ block: ObjectPointer?) -> ObjectPointer? {
        if let block { AutoreleasePool.add(block) }
        return block
    }

    @ObjCMethod("retainCount") static func retainCount(_ block: ObjectPointer?) -> UInt { 1 }
}
