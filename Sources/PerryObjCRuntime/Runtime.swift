import CPerryObjC
import Glibc

/// Classes, method lookup and +initialize.
public enum Runtime {
    /// Guards class tables, method tables and cache writes. Recursive,
    /// because realizing a class realizes its superclass and metaclass.
    static let lock = RecursiveLock()
    /// Guards which thread is running each class's +initialize. It is not
    /// held while one runs: a +initialize may wait for another thread, and
    /// that thread may be sending a message to a different class.
    static let initializeLock = ClassInitializationMonitor()

    nonisolated(unsafe) static var classesByName: [CStringKey: ClassPointer] = [:]
    nonisolated(unsafe) static var allClasses: [ClassInfo] = []

    /// The classes realized so far, not their metaclasses.
    public static var classes: [ClassPointer] { lock.withLock { allClasses.filter { !$0.isMeta }.map(\.cls) } }

    nonisolated(unsafe) static let emptyCache = perry_objc_empty_cache()!
    nonisolated(unsafe) static let emptyTable = perry_objc_empty_cache_table()!
    nonisolated(unsafe) public static let msgForward = IMP(mutating: perry_objc_msgForward_address()!)
    /// The forwarder for a message that returns a structure through a
    /// pointer: its own on armv7, where the pointer takes the first register.
    #if arch(arm)
    nonisolated(unsafe) public static let msgForwardStret = IMP(mutating: perry_objc_msgForward_stret_address()!)
    #else
    nonisolated(unsafe) public static let msgForwardStret = msgForward
    #endif

    // MARK: - Realization

    static func cacheSlot(_ cls: ClassPointer) -> UnsafeMutablePointer<UnsafeMutableRawPointer?> {
        UnsafeMutableRawPointer(cls).advanced(by: Layout.classCache).assumingMemoryBound(to: UnsafeMutableRawPointer?.self)
    }

    /// The runtime state of `cls`, realizing it on first use. Nil for
    /// memory that is not a class this runtime can read.
    @inline(__always)
    public static func info(_ cls: ClassPointer) -> ClassInfo? {
        // A missing class's placeholder has no isa: its "instances" are nil.
        guard Int(bitPattern: cls) != 0 else { return nil }
        if let header = perry_load_acquire(cacheSlot(cls)), header != emptyCache,
           let info = header.load(fromByteOffset: Layout.headerInfo, as: UnsafeMutableRawPointer?.self) {
            return Unmanaged<ClassInfo>.fromOpaque(info).takeUnretainedValue()
        }
        return realize(cls, registerName: true)
    }

    /// Builds the runtime state for a class from its class_ro_t, after its
    /// superclass, then realizes its metaclass.
    static func realize(_ cls: ClassPointer, registerName: Bool) -> ClassInfo? {
        lock.withLock {
            if let header = perry_load_acquire(cacheSlot(cls)), header != emptyCache,
               let info = header.load(fromByteOffset: Layout.headerInfo, as: UnsafeMutableRawPointer?.self) {
                return Unmanaged<ClassInfo>.fromOpaque(info).takeUnretainedValue()
            }
            guard let ro = Layout.readOnly(cls).map({ UnsafePointer($0) }) else {
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
                   let name = UnsafeRawPointer(superclass).load(fromByteOffset: Layout.classVtable, as: UnsafePointer<CChar>?.self) {
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
                if !awaitsSwiftInitialization(cls) { installReadWrite(cls) }
            }
            return info
        }
    }

    /// Whether Swift's runtime has yet to lay the class out: a Swift class
    /// whose metadata is initialized as the program runs (a resilient
    /// superclass or fields), which its type descriptor's flags say.
    /// Swift's runtime writes such a class's class_ro_t through
    /// objc_class.bits, then calls _objc_realizeClassFromSwift.
    static func awaitsSwiftInitialization(_ cls: ClassPointer) -> Bool {
        guard cls.pointee.bits & UInt(PERRY_CLASS_BITS_FLAGS) != 0 else { return false }
        guard let descriptor = UnsafeRawPointer(cls).load(fromByteOffset: 8 * Layout.word, as: UnsafeRawPointer?.self) else { return true }
        let kindFlags = descriptor.load(as: UInt32.self) >> 16
        // The metadata initialization kind, and a resilient superclass.
        return kindFlags & 3 != 0 || kindFlags & (1 << 13) != 0
    }

    /// PERRY_OBJC_NO_CLASS_RW leaves classes as their images have them.
    private static let installsReadWrite = getenv("PERRY_OBJC_NO_CLASS_RW") == nil

    /// Leaves a realized class and its metaclass as Darwin's libobjc does:
    /// objc_class.bits points at a class_rw_t (flags with RW_REALIZED, a
    /// witness and an index, then the class_ro_t), which reflection
    /// libraries that read Darwin's structures follow to the class_ro_t.
    static func installReadWrite(_ cls: ClassPointer) {
        guard installsReadWrite else { return }
        for target in [cls, cls.pointee.isa].compactMap({ $0 }) {
            let flags = target.pointee.bits & UInt(PERRY_CLASS_BITS_FLAGS)
            guard let data = UnsafeMutableRawPointer(bitPattern: UInt(target.pointee.bits) & Layout.classBitsMask),
                  data.load(as: UInt32.self) & Layout.realizedFlag == 0 else { continue }
            // class_rw_t: flags, witness and index, ro_or_rw_ext, then the
            // first subclass and the next sibling, which are not kept.
            let size = 8 + 3 * Layout.word
            let readWrite = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 8)
            readWrite.initializeMemory(as: UInt8.self, repeating: 0, count: size)
            readWrite.storeBytes(of: Layout.realizedFlag, as: UInt32.self)
            readWrite.storeBytes(of: UInt(bitPattern: data), toByteOffset: 8, as: UInt.self)
            target.pointee.bits = UInt(bitPattern: readWrite) | flags
        }
    }

    /// Non-fragile ivars: when the superclass grew, moves the class's ivars
    /// past it.
    static func slideIvars(_ info: ClassInfo, ro: UnsafePointer<perry_class_ro>) {
        guard !info.isMeta, let superInfo = info.superInfo, Int(ro.pointee.instance_start) < superInfo.instanceSize else {
            return
        }
        var delta = superInfo.instanceSize - Int(ro.pointee.instance_start)
        // The ivars keep their alignment, as the compiler laid them out: a
        // slide that is not a multiple of the largest breaks the atomic
        // 64-bit accesses of a 32-bit program, which fault when misaligned.
        if let ivars = ro.pointee.ivars {
            var alignment = 1
            IvarList.forEach(ivars) { ivar in
                let raw = ivar.pointee.alignment_raw
                alignment = max(alignment, raw == UInt32.max ? Layout.word : 1 << Int(min(raw, 6)))
            }
            delta = (delta + alignment - 1) & ~(alignment - 1)
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
    public static func lookUpIMP(receiver: ObjectPointer?, selector: SEL, cls: ClassPointer, stret: Bool = false) -> IMP {
        if Zombies.enabled, let receiver, Zombies.report(receiver, String(cString: selector)) {
            objcFatal("message \(String(cString: selector)) sent to a deallocated object")
        }
        guard let info = Runtime.info(cls) else {
            objcFatal("message \(String(cString: selector)) sent to an object whose class is unknown")
        }
        if Profile.enabled { Profile.record(info, selector) }
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
        if stret, imp == nil { return msgForwardStret }
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
        // The thread inside the class's own +initialize gets its messages
        // through; any other thread messaging the class waits for it.
        let thread = UInt(pthread_self())
        initializeLock.lock()
        while !info.isInitialized, info.initializingThread != 0 {
            if info.initializingThread == thread {
                initializeLock.unlock()
                return
            }
            initializeLock.wait()
        }
        if info.isInitialized {
            initializeLock.unlock()
            return
        }
        info.initializingThread = thread
        initializeLock.unlock()

        Messages.sendVoid(ObjectPointer(info.cls), Sel.initialize)

        initializeLock.lock()
        info.initializingThread = 0
        info.initialized.store(true, ordering: .releasing)
        initializeLock.broadcast()
        initializeLock.unlock()
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
        notForwarded(receiver, selector)
        return (nil, Unrecognized.returnZero)
    }

    /// The end of forwarding, when nothing took the message: the receiver's
    /// -doesNotRecognizeSelector:, then the report and abort. It returns
    /// only with PERRY_OBJC_UNRECOGNIZED=continue, for the message to
    /// answer zero.
    public static func notForwarded(_ receiver: ObjectPointer, _ selector: SEL) {
        if Unrecognized.continues {
            Unrecognized.report(receiver, selector)
            return
        }
        if let info = Runtime.info(classOf(receiver)), findMethod(info, Sel.doesNotRecognizeSelector) != nil {
            Messages.sendVoid(receiver, Sel.doesNotRecognizeSelector, UnsafeRawPointer(selector))
        }
        unrecognized(receiver, selector)
    }

    /// With PERRY_OBJC_UNRECOGNIZED=continue, for finding what a program
    /// needs: an unrecognized message is reported, once for each class and
    /// selector, and returns zero instead of aborting.
    /// The address a message to be forwarded was sent from, on arm64: set by
    /// the forwarder for the report of an unrecognized selector.
    nonisolated(unsafe) public static var forwardCaller: UnsafeRawPointer?

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
                if getenv("PERRY_OBJC_CALLER") != nil, let caller = Runtime.forwardCaller {
                    objcWarning("\(message): sent from \(caller)")
                }
                objcWarning("\(message): unrecognized selector, returning 0")
                // PERRY_OBJC_TRAP=<text> stops in the crash reporter, with
                // PERRY_CRASH_REPORT=1 showing where it was sent from, at the
                // first unrecognized message that contains the text.
                if let trap = getenv("PERRY_OBJC_TRAP"), message.contains(String(cString: trap)) {
                    raise(SIGTRAP)
                }
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
        // A 64-bit class_ro_t pads after instance_size; armv7's does not.
#if _pointerBitWidth(_64)
        ro.initialize(to: perry_class_ro(
            flags: flags, instance_start: UInt32(start), instance_size: UInt32(size), reserved: 0,
            ivar_layout: nil, name: name, base_methods: nil, base_protocols: nil, ivars: nil,
            weak_ivar_layout: nil, base_properties: nil))
#else
        ro.initialize(to: perry_class_ro(
            flags: flags, instance_start: UInt32(start), instance_size: UInt32(size),
            ivar_layout: nil, name: name, base_methods: nil, base_protocols: nil, ivars: nil,
            weak_ivar_layout: nil, base_properties: nil))
#endif
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
        let cls = swiftSubclassStorage(superclass, extraBytes: extraBytes)
            ?? calloc(1, size)!.assumingMemoryBound(to: perry_objc_class.self)
        let meta = calloc(1, size)!.assumingMemoryBound(to: perry_objc_class.self)
        let superSize = superclass.flatMap { Runtime.info($0)?.instanceSize } ?? 8
        _ = makeClass(cls, metaclass: meta, superclass: superclass, name: name,
                      instanceSize: superSize, registerName: false)
        return cls
    }

    /// A subclass of a Swift class is as large as the Swift class's metadata and begins
    /// with a copy of it: Swift code reads what follows the class's own fields (its
    /// generic arguments, its vtable) from the metadata of an instance's class, which
    /// a class made at run time (KVO's) must still have. nil for a class that is
    /// not Swift's, or whose metadata has no more than the ObjC class.
    private static func swiftSubclassStorage(_ superclass: ClassPointer?, extraBytes: Int) -> UnsafeMutablePointer<perry_objc_class>? {
        guard let superclass, superclass.pointee.bits & 3 != 0 else { return nil }
        let base = UnsafeMutableRawPointer(superclass)
        // ClassMetadata: classSize and classAddressPoint, after the flags,
        // instance address point and size, alignment mask and reserved words.
#if _pointerBitWidth(_64)
        let sizeOffset = 56
#else
        let sizeOffset = 36
#endif
        let classSize = Int(base.load(fromByteOffset: sizeOffset, as: UInt32.self))
        let addressPoint = Int(base.load(fromByteOffset: sizeOffset + 4, as: UInt32.self))
        guard classSize > MemoryLayout<perry_objc_class>.size, addressPoint <= classSize,
              classSize < 1 << 20 else { return nil }
        let storage = calloc(1, classSize + max(extraBytes, 0))!
        memcpy(storage, base - addressPoint, classSize)
        return (storage + addressPoint).assumingMemoryBound(to: perry_objc_class.self)
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
              let ro = Layout.readOnly(cls) else { return false }
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

    /// objc_disposeClassPair: the class's name is free for another. Its
    /// memory is kept, as instances or caches may still point to it.
    public static func disposeClassPair(_ cls: ClassPointer) {
        guard let info = Runtime.info(cls) else { return }
        lock.withLock {
            let key = CStringKey(pointer: info.name)
            if classesByName[key] == cls { classesByName[key] = nil }
        }
        flushCaches()
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
