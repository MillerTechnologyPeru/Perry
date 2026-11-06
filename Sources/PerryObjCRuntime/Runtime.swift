import CPerryObjC
import Glibc

/// Classes, method lookup and +initialize.
public enum Runtime {
    /// Guards class tables, method tables and cache writes. Recursive,
    /// because realizing a class realizes its superclass and metaclass.
    static let lock = RecursiveLock()
    /// Held while a class's +initialize runs. Other threads messaging the
    /// class wait here until it finishes.
    static let initializeLock = RecursiveLock()

    nonisolated(unsafe) static var classesByName: [CStringKey: ClassPointer] = [:]
    nonisolated(unsafe) static var allClasses: [ClassInfo] = []

    /// The classes realized so far, not their metaclasses.
    public static var classes: [ClassPointer] { lock.withLock { allClasses.filter { !$0.isMeta }.map(\.cls) } }

    nonisolated(unsafe) static let emptyCache = perry_objc_empty_cache()!
    nonisolated(unsafe) static let emptyTable = perry_objc_empty_cache_table()!
    nonisolated(unsafe) public static let msgForward = IMP(mutating: perry_objc_msgForward_address()!)

    // MARK: - Realization

    static func cacheSlot(_ cls: ClassPointer) -> UnsafeMutablePointer<UnsafeMutableRawPointer?> {
        UnsafeMutableRawPointer(cls).advanced(by: 16).assumingMemoryBound(to: UnsafeMutableRawPointer?.self)
    }

    /// The runtime state of `cls`, realizing it on first use. Nil for
    /// memory that is not a class this runtime can read.
    @inline(__always)
    public static func info(_ cls: ClassPointer) -> ClassInfo? {
        // A missing class's placeholder has no isa: its "instances" are nil.
        guard Int(bitPattern: cls) != 0 else { return nil }
        if let header = perry_load_acquire(cacheSlot(cls)), header != emptyCache,
           let info = header.load(fromByteOffset: 8, as: UnsafeMutableRawPointer?.self) {
            return Unmanaged<ClassInfo>.fromOpaque(info).takeUnretainedValue()
        }
        return realize(cls, registerName: true)
    }

    /// Builds the runtime state for a class from its class_ro_t, after its
    /// superclass, then realizes its metaclass.
    static func realize(_ cls: ClassPointer, registerName: Bool) -> ClassInfo? {
        lock.withLock {
            if let header = perry_load_acquire(cacheSlot(cls)), header != emptyCache,
               let info = header.load(fromByteOffset: 8, as: UnsafeMutableRawPointer?.self) {
                return Unmanaged<ClassInfo>.fromOpaque(info).takeUnretainedValue()
            }
            let bits = UInt(cls.pointee.bits) & ~7
            guard let ro = UnsafePointer<perry_class_ro>(bitPattern: bits) else {
                return nil
            }
            // A Swift class compiled to deploy before the stable ABI is
            // marked with the legacy bit (0) only; Swift's runtime takes a
            // class for its own by the stable bit (1), which Darwin's libobjc
            // gives such classes in place of the legacy one as it reads them.
            // Without it Swift wraps the class as an Objective-C one, whose
            // super calls then find the class itself; with the legacy bit
            // left, Swift's runtime, which masks only the stable bit off,
            // reads the class_ro_t a byte off. A class of the legacy ABI
            // itself, which the low bit of its Swift flags (after the data
            // pointer) says, keeps its bit.
            if cls.pointee.bits & 3 == 1 {
                let swiftFlags = UnsafeRawPointer(cls).load(fromByteOffset: 40, as: UInt32.self)
                if swiftFlags & 1 == 0 {
                    cls.pointee.bits = (cls.pointee.bits & ~1) | 2
                } else {
                    cls.pointee.bits |= 2
                }
            }
            let superInfo = cls.pointee.superclass.flatMap { Runtime.info($0) }
            // A class whose superclass is not available is not available
            // either, as on Darwin when a weak-linked superclass is missing:
            // it is never realized, and the program goes on until it uses
            // it. A superclass the loader could not find has no class_ro_t,
            // and its name where the vtable goes.
            if let superclass = cls.pointee.superclass, superInfo == nil {
                if superclass.pointee.bits == 0,
                   let name = UnsafeRawPointer(superclass).load(fromByteOffset: 24, as: UnsafePointer<CChar>?.self) {
                    let own = ro.pointee.name.map { String(cString: $0) } ?? "?"
                    objcWarning("class \(own) inherits from \(String(cString: name)), which is not available")
                }
                return nil
            }
            let info = ClassInfo(cls: cls, ro: ro, superInfo: superInfo)
            slideIvars(info, ro: ro)
            if let methods = info.baseMethods {
                info.addMethods(methods, replacing: false)
            }

            perry_store_release(cacheSlot(cls), UnsafeMutableRawPointer(info.header))
            allClasses.append(info)

            if !info.isMeta {
                if registerName {
                    register(cls, name: info.name)
                }
                if let metaclass = cls.pointee.isa, let meta = realize(metaclass, registerName: false) {
                    meta.partner = info
                    info.partner = meta
                }
            }
            return info
        }
    }

    /// Non-fragile ivars: when the superclass grew, moves the class's ivars
    /// past it.
    static func slideIvars(_ info: ClassInfo, ro: UnsafePointer<perry_class_ro>) {
        guard !info.isMeta, let superInfo = info.superInfo, Int(ro.pointee.instance_start) < superInfo.instanceSize else {
            return
        }
        let delta = superInfo.instanceSize - Int(ro.pointee.instance_start)
        if let ivars = ro.pointee.ivars {
            IvarList.forEach(ivars) { ivar in
                ivar.pointee.offset?.pointee += Int32(delta)
            }
        }
        info.instanceSize += delta
    }

    static func register(_ cls: ClassPointer, name: UnsafePointer<CChar>) {
        lock.withLock {
            let key = CStringKey(pointer: name)
            if classesByName[key] == nil {
                classesByName[key] = cls
            }
        }
    }

    public static func lookUpClass(_ name: UnsafePointer<CChar>) -> ClassPointer? {
        // Other providers may start before libobjc and look up NSObject.
        RootClasses.bootstrap()
        if let cls = lock.withLock({ classesByName[CStringKey(pointer: name)] }) {
            return cls
        }
        // A Swift class by its demangled name.
        if let mangled = SwiftNames.mangle(name),
           let cls = mangled.withCString({ mangled in lock.withLock { classesByName[CStringKey(pointer: mangled)] } }) {
            return cls
        }
        // Classes not yet known by name, such as Swift's, which its runtime
        // finds from their mangled names.
        var found: ClassPointer?
        return Hooks.getClass(name, &found) ? found : nil
    }

    /// Empties every method cache, after methods change.
    static func flushCaches() {
        lock.withLock {
            for info in allClasses {
                info.flushCache()
            }
        }
    }

    // MARK: - Methods

    /// The method `selector` names in `info` or its superclasses.
    public static func findMethod(_ info: ClassInfo, _ selector: SEL) -> UnsafeMutablePointer<perry_method>? {
        lock.withLock {
            var current: ClassInfo? = info
            while let cls = current {
                if let method = cls.methods[selector] {
                    return method
                }
                current = cls.superInfo
            }
            return nil
        }
    }

    /// A method `info` defines itself, ignoring superclasses.
    static func ownMethod(_ info: ClassInfo, _ selector: SEL) -> IMP? {
        lock.withLock { info.methods[selector]?.pointee.imp }
    }

    /// objc_msgSend's slow path: the IMP for `selector` sent to `receiver`
    /// starting at `cls`. Runs +initialize first, tries +resolve…Method:,
    /// and falls back to _objc_msgForward.
    public static func lookUpIMP(receiver: ObjectPointer?, selector: SEL, cls: ClassPointer) -> IMP {
        if Zombies.enabled, let receiver, Zombies.report(receiver, String(cString: selector)) {
            objcFatal("message \(String(cString: selector)) sent to a deallocated object")
        }
        guard let info = Runtime.info(cls) else {
            objcFatal("message \(String(cString: selector)) sent to an object whose class is unknown")
        }
        let target = info.isMeta ? info.partner : info
        if let target, !target.isInitialized {
            initialize(target)
        }
        if let imp = info.cachedIMP(selector) {
            return imp
        }
        var imp = findMethod(info, selector)?.pointee.imp
        if imp == nil, resolveMethod(info, selector) {
            imp = findMethod(info, selector)?.pointee.imp
        }
        let result = imp ?? msgForward
        // Until +initialize finishes, every send takes the slow path, so
        // other threads still wait for it.
        lock.withLock {
            if target?.isInitialized ?? true {
                info.cacheInsert(selector, result)
            }
        }
        return result
    }

    /// Whether instances of `info` respond to `selector`, as
    /// -respondsToSelector: answers it.
    public static func responds(_ info: ClassInfo, _ selector: SEL) -> Bool {
        if findMethod(info, selector) != nil {
            return true
        }
        return resolveMethod(info, selector) && findMethod(info, selector) != nil
    }

    /// Sends +resolveInstanceMethod: or +resolveClassMethod:.
    private static func resolveMethod(_ info: ClassInfo, _ selector: SEL) -> Bool {
        let resolver = info.isMeta ? Sel.resolveClassMethod : Sel.resolveInstanceMethod
        guard selector != resolver,
              let cls = info.isMeta ? info.partner : info,
              let meta = cls.partner,
              findMethod(meta, resolver) != nil else {
            return false
        }
        return Messages.sendBool(ObjectPointer(cls.cls), resolver, UnsafeRawPointer(selector))
    }

    // MARK: - +initialize

    /// Sends +initialize to a class and its superclasses, once each.
    static func initialize(_ info: ClassInfo) {
        if info.isInitialized {
            return
        }
        if let superInfo = info.superInfo {
            initialize(superInfo)
        }
        initializeLock.withLock {
            // `initializing` is set when this thread is inside the class's
            // own +initialize: let its messages through.
            if info.isInitialized || info.initializing {
                return
            }
            info.initializing = true
            Messages.sendVoid(ObjectPointer(info.cls), Sel.initialize)
            info.initializing = false
            info.initialized.store(true, ordering: .releasing)
        }
    }

    // MARK: - Forwarding

    /// The handler Foundation installs with objc_setForwardHandler.
    nonisolated(unsafe) public static var forwardHandler: UnsafeMutableRawPointer?

    /// What _objc_msgForward does with an unrecognized message: resend to
    /// -forwardingTargetForSelector:'s answer, jump to the forward handler,
    /// or report the selector and abort.
    public static func forward(receiver: ObjectPointer?, selector: SEL) -> (target: ObjectPointer?, handler: IMP?) {
        guard let receiver else {
            return (nil, nil)
        }
        if let info = Runtime.info(classOf(receiver)), findMethod(info, Sel.forwardingTargetForSelector) != nil,
           let target = Messages.send(receiver, Sel.forwardingTargetForSelector, UnsafeRawPointer(selector)),
           target != receiver {
            return (target, nil)
        }
        if let forwardHandler {
            return (nil, forwardHandler)
        }
        if Unrecognized.continues {
            Unrecognized.report(receiver, selector)
            return (nil, Unrecognized.returnZero)
        }
        if let info = Runtime.info(classOf(receiver)), findMethod(info, Sel.doesNotRecognizeSelector) != nil {
            Messages.sendVoid(receiver, Sel.doesNotRecognizeSelector, UnsafeRawPointer(selector))
        }
        unrecognized(receiver, selector)
    }

    /// With PERRY_OBJC_UNRECOGNIZED=continue, for finding what a program
    /// needs: an unrecognized message is reported, once for each class and
    /// selector, and returns zero instead of aborting.
    enum Unrecognized {
        static let continues = getenv("PERRY_OBJC_UNRECOGNIZED").map { String(cString: $0) == "continue" } ?? false

        nonisolated(unsafe) static var reported = Set<String>()
        static let lock = RecursiveLock()

        nonisolated(unsafe) static let returnZero: IMP = unsafeBitCast(
            { 0 } as @convention(c) () -> UInt, to: IMP.self)

        static func report(_ receiver: ObjectPointer, _ selector: SEL) {
            let info = Runtime.info(classOf(receiver))
            let isClass = info?.isMeta ?? false
            let name = info.map { String(cString: $0.name) } ?? "?"
            let message = "\(isClass ? "+" : "-")[\(name) \(String(cString: selector))]"
            let first = lock.withLock { reported.insert(message).inserted }
            if first {
                objcWarning("\(message): unrecognized selector, returning 0")
            }
        }
    }

    public static func unrecognized(_ receiver: ObjectPointer, _ selector: SEL) -> Never {
        let cls = classOf(receiver)
        let info = Runtime.info(cls)
        let isClass = info?.isMeta ?? false
        let name = info.map { String(cString: $0.name) } ?? "?"
        objcFatal("\(isClass ? "+" : "-")[\(name) \(String(cString: selector))]: unrecognized selector sent to \(isClass ? "class" : "instance") \(receiver)")
    }

    // MARK: - Building classes

    /// Fills in class storage for a class built by the runtime (NSObject,
    /// the block classes, objc_allocateClassPair) and realizes it.
    static func makeClass(_ cls: ClassPointer, metaclass: ClassPointer, superclass: ClassPointer?,
                          name: UnsafePointer<CChar>, instanceSize: Int, registerName: Bool) -> ClassInfo {
        let rootMetaclass = superclass.map { $0.pointee.isa.pointee.isa! } ?? metaclass
        metaclass.pointee.isa = rootMetaclass
        metaclass.pointee.superclass = superclass?.pointee.isa ?? cls
        metaclass.pointee.cache = emptyCache
        cls.pointee.isa = metaclass
        cls.pointee.superclass = superclass
        cls.pointee.cache = emptyCache

        let superSize = superclass.flatMap { Runtime.info($0)?.instanceSize } ?? 0
        let root: UInt32 = superclass == nil ? ROFlags.root : 0
        cls.pointee.bits = UInt(bitPattern: makeRO(flags: root, start: superSize, size: max(instanceSize, superSize), name: name))
        metaclass.pointee.bits = UInt(bitPattern: makeRO(flags: ROFlags.meta | root, start: 40, size: 40, name: name))
        guard let info = realize(cls, registerName: registerName) else {
            objcFatal("cannot realize built-in class \(String(cString: name))")
        }
        return info
    }

    private static func makeRO(flags: UInt32, start: Int, size: Int, name: UnsafePointer<CChar>) -> UnsafeMutablePointer<perry_class_ro> {
        let ro = UnsafeMutablePointer<perry_class_ro>.allocate(capacity: 1)
        ro.initialize(to: perry_class_ro(
            flags: flags, instance_start: UInt32(start), instance_size: UInt32(size), reserved: 0,
            ivar_layout: nil, name: name, base_methods: nil, base_protocols: nil, ivars: nil,
            weak_ivar_layout: nil, base_properties: nil))
        return ro
    }

    /// Adds a method at run time (class_addMethod and friends).
    @discardableResult
    public static func addMethod(_ info: ClassInfo, _ selector: SEL, types: UnsafePointer<CChar>?, imp: IMP?,
                                 replacing: Bool) -> IMP? {
        let old = lock.withLock { info.addMethod(selector, types: types, imp: imp, replacing: replacing) }
        flushCaches()
        return old
    }
}

// MARK: - Run-time class creation and method changes

extension Runtime {
    /// A method `info` defines itself (not inherited).
    public static func findOwnMethod(_ info: ClassInfo, _ selector: SEL) -> UnsafeMutablePointer<perry_method>? {
        lock.withLock { info.methods[selector] }
    }

    /// objc_allocateClassPair: a new class and metaclass, usable for adding
    /// methods at once, found by name after registerClassPair.
    public static func allocateClassPair(superclass: ClassPointer?, name: UnsafePointer<CChar>,
                                         extraBytes: Int) -> ClassPointer {
        let size = MemoryLayout<perry_objc_class>.size + max(extraBytes, 0)
        let cls = calloc(1, size)!.assumingMemoryBound(to: perry_objc_class.self)
        let meta = calloc(1, size)!.assumingMemoryBound(to: perry_objc_class.self)
        let superSize = superclass.flatMap { Runtime.info($0)?.instanceSize } ?? 8
        _ = makeClass(cls, metaclass: meta, superclass: superclass, name: name,
                      instanceSize: superSize, registerName: false)
        return cls
    }

    public static func initializeClassPair(superclass: ClassPointer?, name: UnsafePointer<CChar>,
                                           cls: ClassPointer, metaclass: ClassPointer) -> ClassPointer {
        let superSize = superclass.flatMap { Runtime.info($0)?.instanceSize } ?? 8
        _ = makeClass(cls, metaclass: metaclass, superclass: superclass, name: name,
                      instanceSize: superSize, registerName: false)
        return cls
    }

    /// class_addIvar: an instance variable at the end of a class built at
    /// run time, before it is registered, as Foundation lays out classes
    /// whose instance variables other images read at fixed offsets.
    public static func addIvar(_ cls: ClassPointer, name: UnsafePointer<CChar>, size: Int, alignment: UInt8,
                               types: UnsafePointer<CChar>?) -> Bool {
        guard let info = Runtime.info(cls), !info.isMeta, size >= 0, alignment < 16,
              let ro = UnsafeMutablePointer<perry_class_ro>(bitPattern: UInt(cls.pointee.bits) & ~7) else { return false }
        return lock.withLock {
            guard classesByName.values.allSatisfy({ $0 != cls }) else { return false }
            var ivars: [perry_ivar] = []
            if let list = ro.pointee.ivars { IvarList.forEach(list) { ivars.append($0.pointee) } }
            guard !ivars.contains(where: { $0.name.map { strcmp($0, name) == 0 } ?? false }) else { return false }
            let align = 1 << Int(alignment)
            let offset = (info.instanceSize + align - 1) & ~(align - 1)
            let offsetWord = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
            offsetWord.initialize(to: Int32(offset))
            ivars.append(perry_ivar(offset: offsetWord, name: UnsafePointer(strdup(name)), type: types.map { UnsafePointer(strdup($0)!) },
                                    alignment_raw: UInt32(alignment), size: UInt32(size)))
            let stride = MemoryLayout<perry_ivar>.stride
            let list = UnsafeMutableRawPointer.allocate(byteCount: 8 + stride * ivars.count, alignment: 8)
            list.storeBytes(of: UInt32(stride), as: UInt32.self)
            list.storeBytes(of: UInt32(ivars.count), toByteOffset: 4, as: UInt32.self)
            for (index, ivar) in ivars.enumerated() { (list + 8 + index * stride).storeBytes(of: ivar, as: perry_ivar.self) }
            ro.pointee.ivars = UnsafeRawPointer(list)
            info.instanceSize = offset + size
            ro.pointee.instance_size = UInt32(info.instanceSize)
            return true
        }
    }

    public static func registerClassPair(_ cls: ClassPointer) {
        guard let info = Runtime.info(cls) else { return }
        register(cls, name: info.name)
    }

    public static func setImplementation(_ method: UnsafeMutablePointer<perry_method>, _ imp: IMP?) -> IMP? {
        let old = lock.withLock {
            let old = method.pointee.imp
            method.pointee.imp = imp
            return old
        }
        flushCaches()
        return old
    }

    public static func exchangeImplementations(_ first: UnsafeMutablePointer<perry_method>,
                                               _ second: UnsafeMutablePointer<perry_method>) {
        lock.withLock {
            let imp = first.pointee.imp
            first.pointee.imp = second.pointee.imp
            second.pointee.imp = imp
        }
        flushCaches()
    }
}
