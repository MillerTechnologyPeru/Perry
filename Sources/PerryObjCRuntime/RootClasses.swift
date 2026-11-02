import CPerryObjC
import Glibc

// Method signatures for the runtime's own classes.
typealias Method0 = @convention(c) (ObjectPointer?, SEL) -> ObjectPointer?
typealias Method0Void = @convention(c) (ObjectPointer?, SEL) -> Void
typealias Method0UInt = @convention(c) (ObjectPointer?, SEL) -> UInt
typealias Method0Bool = @convention(c) (ObjectPointer?, SEL) -> Bool
typealias Method1 = @convention(c) (ObjectPointer?, SEL, UnsafeRawPointer?) -> ObjectPointer?
typealias Method1Void = @convention(c) (ObjectPointer?, SEL, UnsafeRawPointer?) -> Void
typealias Method1Bool = @convention(c) (ObjectPointer?, SEL, UnsafeRawPointer?) -> Bool
typealias Method2 = @convention(c) (ObjectPointer?, SEL, UnsafeRawPointer?, UnsafeRawPointer?) -> ObjectPointer?
typealias Method3 = @convention(c) (ObjectPointer?, SEL, UnsafeRawPointer?, UnsafeRawPointer?, UnsafeRawPointer?) -> ObjectPointer?

/// Adds methods to a class the runtime builds, from Swift functions with C
/// calling conventions.
struct MethodTable {
    let info: ClassInfo

    private func add(_ name: String, _ types: String, _ imp: UnsafeRawPointer) {
        Runtime.addMethod(info, Selectors.register(name), types: permanentCString(types),
                          imp: IMP(mutating: imp), replacing: true)
    }

    func add(_ name: String, _ types: String, _ imp: Method0) { add(name, types, unsafeBitCast(imp, to: UnsafeRawPointer.self)) }
    func add(_ name: String, _ types: String, _ imp: Method0Void) { add(name, types, unsafeBitCast(imp, to: UnsafeRawPointer.self)) }
    func add(_ name: String, _ types: String, _ imp: Method0UInt) { add(name, types, unsafeBitCast(imp, to: UnsafeRawPointer.self)) }
    func add(_ name: String, _ types: String, _ imp: Method0Bool) { add(name, types, unsafeBitCast(imp, to: UnsafeRawPointer.self)) }
    func add(_ name: String, _ types: String, _ imp: Method1) { add(name, types, unsafeBitCast(imp, to: UnsafeRawPointer.self)) }
    func add(_ name: String, _ types: String, _ imp: Method1Void) { add(name, types, unsafeBitCast(imp, to: UnsafeRawPointer.self)) }
    func add(_ name: String, _ types: String, _ imp: Method1Bool) { add(name, types, unsafeBitCast(imp, to: UnsafeRawPointer.self)) }
    func add(_ name: String, _ types: String, _ imp: Method2) { add(name, types, unsafeBitCast(imp, to: UnsafeRawPointer.self)) }
    func add(_ name: String, _ types: String, _ imp: Method3) { add(name, types, unsafeBitCast(imp, to: UnsafeRawPointer.self)) }
}

@inline(__always)
private func selector(_ raw: UnsafeRawPointer?) -> SEL? {
    raw?.assumingMemoryBound(to: CChar.self)
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
        addInstanceMethods(MethodTable(info: object))
        addClassMethods(MethodTable(info: object.partner!))
        Objects.defaultRetain = Runtime.findMethod(object, Sel.retain)?.pointee.imp
        Objects.defaultRelease = Runtime.findMethod(object, Sel.release)?.pointee.imp
        Objects.defaultAutorelease = Runtime.findMethod(object, Sel.autorelease)?.pointee.imp

        // Protocol objects are static data: retain and release do nothing.
        let proto = Runtime.makeClass(perry_objc_protocol_class(), metaclass: perry_objc_protocol_metaclass(),
                                      superclass: perry_objc_nsobject_class(), name: permanentCString("Protocol"),
                                      instanceSize: 8, registerName: true)
        addImmortalMethods(MethodTable(info: proto))
    }()

    // MARK: - NSObject

    private static func addInstanceMethods(_ table: MethodTable) {
        table.add("init", "@16@0:8") { object, _ in object }
        table.add("self", "@16@0:8") { object, _ in object }
        table.add("class", "#16@0:8") { object, _ in
            object.map { ObjectPointer(classOf($0)) }
        }
        table.add("superclass", "#16@0:8") { object, _ in
            object.flatMap { classOf($0).pointee.superclass.map(ObjectPointer.init) }
        }
        table.add("dealloc", "v16@0:8") { (object: ObjectPointer?, _: SEL) -> Void in
            if let object { Objects.dispose(object) }
        }
        table.add("retain", "@16@0:8") { object, _ in
            if let object { RetainCounts.retain(object) }
            return object
        }
        table.add("release", "Vv16@0:8") { (object: ObjectPointer?, _: SEL) -> Void in
            if let object, RetainCounts.release(object) {
                Messages.sendVoid(object, Sel.dealloc)
            }
        }
        table.add("autorelease", "@16@0:8") { object, _ in
            if let object { AutoreleasePool.add(object) }
            return object
        }
        table.add("retainCount", "Q16@0:8") { object, _ in
            object.map { RetainCounts.count($0) } ?? 0
        }
        table.add("zone", "^v16@0:8") { _, _ in nil }
        table.add("hash", "Q16@0:8") { object, _ in UInt(bitPattern: object) }
        table.add("isEqual:", "B24@0:8@16") { object, _, other in
            UnsafeRawPointer(object) == other
        }
        table.add("isKindOfClass:", "B24@0:8#16") { object, _, target in
            guard let object else { return false }
            var cls: ClassPointer? = classOf(object)
            while let current = cls {
                if UnsafeRawPointer(current) == target { return true }
                cls = current.pointee.superclass
            }
            return false
        }
        table.add("isMemberOfClass:", "B24@0:8#16") { object, _, target in
            object.map { UnsafeRawPointer(classOf($0)) == target } ?? false
        }
        table.add("respondsToSelector:", "B24@0:8:16") { object, _, sel in
            guard let object, let sel = selector(sel), let info = Runtime.info(classOf(object)) else { return false }
            return Runtime.responds(info, sel)
        }
        table.add("conformsToProtocol:", "B24@0:8@16") { object, _, proto in
            guard let object, let proto, let info = Runtime.info(classOf(object)) else { return false }
            return Protocols.classOrSuperclassConforms(info, to: proto.assumingMemoryBound(to: perry_protocol.self))
        }
        table.add("isProxy", "B16@0:8") { _, _ in false }
        table.add("copy", "@16@0:8") { object, _ in
            Messages.send(object, Sel.copyWithZone, nil)
        }
        table.add("mutableCopy", "@16@0:8") { object, _ in
            Messages.send(object, Sel.mutableCopyWithZone, nil)
        }
        table.add("description", "@16@0:8") { _, _ in nil }
        table.add("debugDescription", "@16@0:8") { object, _ in
            Messages.send(object, Sel.description)
        }
        table.add("performSelector:", "@24@0:8:16") { object, _, sel in
            guard let sel = selector(sel) else { return nil }
            return Messages.send(object, sel)
        }
        table.add("performSelector:withObject:", "@32@0:8:16@24") { object, _, sel, argument in
            guard let sel = selector(sel) else { return nil }
            return Messages.send(object, sel, argument)
        }
        table.add("performSelector:withObject:withObject:", "@40@0:8:16@24@32") { object, _, sel, first, second in
            guard let sel = selector(sel) else { return nil }
            return Messages.send(object, sel, first, second)
        }
        table.add("forwardingTargetForSelector:", "@24@0:8:16") { _, _, _ in nil }
        table.add("doesNotRecognizeSelector:", "v24@0:8:16") { (object: ObjectPointer?, _: SEL, sel: UnsafeRawPointer?) -> Void in
            if let object, let sel = selector(sel) {
                Runtime.unrecognized(object, sel)
            }
        }
        table.add("methodForSelector:", "^?24@0:8:16") { object, _, sel in
            guard let object, let sel = selector(sel) else { return nil }
            return Runtime.lookUpIMP(receiver: object, selector: sel, cls: classOf(object))
        }
    }

    private static func addClassMethods(_ table: MethodTable) {
        table.add("alloc", "@16@0:8") { cls, _ in
            asClass(cls).flatMap { Objects.createInstance($0) }
        }
        table.add("allocWithZone:", "@24@0:8^v16") { cls, _, _ in
            asClass(cls).flatMap { Objects.createInstance($0) }
        }
        table.add("new", "@16@0:8") { cls, _ in
            Messages.send(Messages.send(cls, Sel.alloc), Sel.`init`)
        }
        table.add("class", "#16@0:8") { cls, _ in cls }
        table.add("superclass", "#16@0:8") { cls, _ in
            asClass(cls)?.pointee.superclass.map(ObjectPointer.init)
        }
        table.add("initialize", "v16@0:8") { (_: ObjectPointer?, _: SEL) -> Void in }
        table.add("description", "@16@0:8") { _, _ in nil }
        table.add("instancesRespondToSelector:", "B24@0:8:16") { cls, _, sel in
            guard let cls = asClass(cls), let sel = selector(sel), let info = Runtime.info(cls) else { return false }
            return Runtime.responds(info, sel)
        }
        table.add("isSubclassOfClass:", "B24@0:8#16") { cls, _, target in
            var current = asClass(cls)
            while let c = current {
                if UnsafeRawPointer(c) == target { return true }
                current = c.pointee.superclass
            }
            return false
        }
        table.add("conformsToProtocol:", "B24@0:8@16") { cls, _, proto in
            guard let cls = asClass(cls), let proto, let info = Runtime.info(cls) else { return false }
            return Protocols.classOrSuperclassConforms(info, to: proto.assumingMemoryBound(to: perry_protocol.self))
        }
        table.add("resolveClassMethod:", "B24@0:8:16") { _, _, _ in false }
        table.add("resolveInstanceMethod:", "B24@0:8:16") { _, _, _ in false }
        table.add("instanceMethodForSelector:", "^?24@0:8:16") { cls, _, sel in
            guard let cls = asClass(cls), let sel = selector(sel) else { return nil }
            return Runtime.lookUpIMP(receiver: nil, selector: sel, cls: cls)
        }
        // Classes are never deallocated.
        addImmortalMethods(table)
    }

    /// retain, release and autorelease for objects that live forever.
    static func addImmortalMethods(_ table: MethodTable) {
        table.add("retain", "@16@0:8") { object, _ in object }
        table.add("release", "Vv16@0:8") { (_: ObjectPointer?, _: SEL) -> Void in }
        table.add("autorelease", "@16@0:8") { object, _ in object }
        table.add("retainCount", "Q16@0:8") { _, _ in UInt.max }
    }
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
        let blockTable = MethodTable(info: block)
        blockTable.add("copy", "@16@0:8") { object, _ in BlockClasses.copy(object) }
        blockTable.add("copyWithZone:", "@24@0:8^v16") { object, _, _ in BlockClasses.copy(object) }
        blockTable.add("invoke", "v16@0:8") { (object: ObjectPointer?, _: SEL) -> Void in
            guard let object else { return }
            typealias Invoke = @convention(c) (ObjectPointer) -> Void
            let invoke = object.load(fromByteOffset: 16, as: UnsafeRawPointer.self)
            unsafeBitCast(invoke, to: Invoke.self)(object)
        }

        func make(_ name: String, _ storage: UnsafeMutableRawPointer?) -> MethodTable? {
            guard let storage else { return nil }
            let cls = storage.assumingMemoryBound(to: perry_objc_class.self)
            let meta = (storage + 128).assumingMemoryBound(to: perry_objc_class.self)
            let info = Runtime.makeClass(cls, metaclass: meta, superclass: block.cls,
                                         name: permanentCString(name), instanceSize: 8, registerName: true)
            return MethodTable(info: info)
        }

        // Heap blocks are reference counted by the blocks runtime.
        for (name, address) in [("__NSMallocBlock__", storage.malloc), ("__NSAutoBlock__", storage.auto),
                                ("__NSFinalizingBlock__", storage.finalizing)] {
            guard let table = make(name, address) else { continue }
            table.add("retain", "@16@0:8") { object, _ in BlockClasses.copy(object) }
            table.add("release", "Vv16@0:8") { (object: ObjectPointer?, _: SEL) -> Void in BlockClasses.release(object) }
            table.add("autorelease", "@16@0:8") { object, _ in
                if let object { AutoreleasePool.add(object) }
                return object
            }
            table.add("retainCount", "Q16@0:8") { _, _ in 1 }
        }
        // Stack and global blocks are not reference counted; copying a
        // stack block moves it to the heap.
        for (name, address) in [("__NSStackBlock__", storage.stack), ("__NSGlobalBlock__", storage.global),
                                ("__NSBlockVariable__", storage.weakVariable)] {
            guard let table = make(name, address) else { continue }
            RootClasses.addImmortalMethods(table)
        }
    }
}
