import CPerryObjC
import Glibc

// What Darwin's Swift runtime asks of libobjc, whose classes are its
// classes: hooks through which it finds classes by mangled name, names
// generic classes and says which image a class came from; realizing the
// classes whose metadata it builds or updates; and moving a class under
// a superclass found at run time.

/// The hooks Swift's runtime installs. Each starts as a function that
/// finds nothing, which a hook installed later calls for what it does not
/// handle.
public enum Hooks {
    public typealias GetClass = @convention(c) (UnsafePointer<CChar>?, UnsafeMutablePointer<ClassPointer?>?) -> Bool
    public typealias GetImageName = @convention(c) (ClassPointer?, UnsafeMutablePointer<UnsafePointer<CChar>?>?) -> Bool
    public typealias LazyClassNamer = @convention(c) (ClassPointer?) -> UnsafePointer<CChar>?

    nonisolated(unsafe) public static var getClass: GetClass = { _, _ in false }
    nonisolated(unsafe) public static var getImageName: GetImageName = { _, _ in false }
    nonisolated(unsafe) public static var lazyClassNamer: LazyClassNamer = { _ in nil }
}

extension Runtime {
    /// objc_readClassPair and _objc_realizeClassFromSwift: realizes a class
    /// Swift's runtime has built or updated, and registers its name.
    ///
    /// A class whose layout depends on types from other modules is laid out
    /// when its metadata is first initialized, after its image was mapped
    /// and the class realized: Swift's runtime then writes the class_ro_t's
    /// instance size and the ivar offsets afresh, and realizes it again, so
    /// a class already realized takes its size anew.
    public static func realizeFromSwift(_ cls: ClassPointer) -> ClassPointer {
        lock.withLock {
            let known = perry_load_acquire(cacheSlot(cls)).map { $0 != emptyCache } ?? false
            guard let info = info(cls), known,
                  let ro = UnsafePointer<perry_class_ro>(bitPattern: UInt(cls.pointee.bits) & Layout.classBitsMask) else { return }
            info.instanceSize = Int(ro.pointee.instance_size)
            // A class whose superclass Swift's runtime makes, a generic
            // class's specialization, gets it as its metadata is first
            // initialized: one realized before then, from its image, had
            // none, and moves under it now.
            if let superclass = cls.pointee.superclass, info.superInfo?.cls != superclass, let superInfo = Runtime.info(superclass) {
                info.superInfo = superInfo
                if let meta = info.partner, let superMeta = superInfo.partner { meta.superInfo = superMeta }
                flushCaches()
            }
            slideIvars(info, ro: ro)
        }
        return cls
    }

    /// Runs the Swift metadata initializers of `info`'s class and its
    /// superclasses that have not run, superclass first, as Darwin's
    /// libobjc does as it realizes such a class: an instance made from
    /// Objective-C (WMF's [[WMFEventPlatformClient alloc] init]) before any
    /// Swift code touched the class would otherwise be laid out by the
    /// compiler's placeholder ivar offsets, a resilient one at 0, over the
    /// isa. Each initializer calls _objc_realizeClassFromSwift with the
    /// class laid out; it runs outside the lock, as Swift's runtime may
    /// wait on another thread's metadata, and Swift runs it once.
    public static func runSwiftInitializers(_ info: ClassInfo) {
        var pending: [(ClassInfo, ClassInfo.SwiftInitializer)] = []
        lock.withLock {
            var current: ClassInfo? = info
            while let each = current {
                if let initializer = each.swiftInitializer { pending.insert((each, initializer), at: 0) }
                current = each.superInfo
            }
        }
        for (each, initializer) in pending {
            _ = initializer(each.cls, nil)
            lock.withLock { each.swiftInitializer = nil }
        }
    }

    /// class_setSuperclass: moves `cls`, and its metaclass, under
    /// `superclass`. Swift's runtime does so for its classes that subclass
    /// Foundation's, such as its NSError.
    public static func setSuperclass(_ cls: ClassPointer, _ superclass: ClassPointer) -> ClassPointer? {
        lock.withLock {
            let old = cls.pointee.superclass
            cls.pointee.superclass = superclass
            cls.pointee.isa?.pointee.superclass = superclass.pointee.isa
            if let classInfo = info(cls), let superInfo = info(superclass) {
                classInfo.superInfo = superInfo
                classInfo.partner?.superInfo = superInfo.partner
            }
            flushCaches()
            return old
        }
    }
}

extension Objects {
    /// objc_isUniquelyReferenced: whether `object` has one reference.
    public static func isUniquelyReferenced(_ object: ObjectPointer) -> Bool {
        guard let info = Runtime.info(classOf(object)) else { return false }
        if usesDefaultRetainRelease(info) {
            return RetainCounts.count(object) == 1
        }
        typealias RetainCount = @convention(c) (ObjectPointer, SEL) -> UInt
        guard let imp = Runtime.findMethod(info, Sel.retainCount)?.pointee.imp else { return false }
        return unsafeBitCast(imp, to: RetainCount.self)(object, Sel.retainCount) == 1
    }
}

/// Swift's class names, which Objective-C sees mangled ("_TtC6Module4Name")
/// and libobjc gives out demangled ("Module.Name"), as Apple's does for a
/// class at the top level of its module; others keep their mangled names.
/// Lookups take either.
public enum SwiftNames {
    nonisolated(unsafe) private static var demangled: [CStringKey: UnsafePointer<CChar>] = [:]
    private static let lock = RecursiveLock()

    /// "Module.Name" for "_TtC6Module4Name" ("_TtCs…" is module Swift's).
    public static func demangle(_ name: UnsafePointer<CChar>) -> UnsafePointer<CChar>? {
        guard strncmp(name, "_TtC", 4) == 0 else { return nil }
        return lock.withLock {
            let key = CStringKey(pointer: name)
            if let known = demangled[key] { return known }
            var rest = Substring(String(cString: name).dropFirst(4))
            func component() -> Substring? {
                let digits = rest.prefix { $0.isNumber }
                guard let length = Int(digits), length > 0, rest.count >= digits.count + length else { return nil }
                rest = rest.dropFirst(digits.count)
                defer { rest = rest.dropFirst(length) }
                return rest.prefix(length)
            }
            let module: Substring?
            if rest.first == "s" {
                rest = rest.dropFirst()
                module = "Swift"
            } else {
                module = component()
            }
            guard let module, let type = component(), rest.isEmpty else { return nil }
            let result = UnsafePointer(strdup("\(module).\(type)")!)
            demangled[key] = result
            return result
        }
    }

    /// "_TtC6Module4Name" for "Module.Name".
    public static func mangle(_ name: UnsafePointer<CChar>) -> String? {
        let parts = String(cString: name).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        let module = parts[0] == "Swift" ? "s" : "\(parts[0].utf8.count)\(parts[0])"
        return "_TtC\(module)\(parts[1].utf8.count)\(parts[1])"
    }
}
