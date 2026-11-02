import CPerryObjC
import Glibc
import Synchronization

/// The runtime's state for one realized class or metaclass. The class's
/// `cache` field points at `header`, whose first word is the method cache
/// objc_msgSend probes and whose second is this object.
///
/// Mutable state is guarded by `Runtime.lock`, except the cache, which
/// objc_msgSend reads without locking.
public final class ClassInfo {
    public let cls: ClassPointer
    let header: UnsafeMutablePointer<perry_class_header>
    public let name: UnsafePointer<CChar>
    public let isMeta: Bool
    public let isRoot: Bool
    public let superInfo: ClassInfo?
    let hasCxxStructors: Bool
    let baseMethods: UnsafeRawPointer?

    /// A class's metaclass, or a metaclass's class.
    public internal(set) var partner: ClassInfo?
    public internal(set) var instanceSize: Int

    /// Methods defined by this class itself, including its categories'.
    var methods: [SEL: UnsafeMutablePointer<perry_method>] = [:]
    /// Protocol lists adopted by the class and its categories.
    var protocolLists: [UnsafeRawPointer] = []
    /// Declared property lists of the class and its categories.
    var propertyLists: [UnsafeRawPointer] = []

    var loadCalled = false
    var initializing = false
    let initialized = Atomic<Bool>(false)

    /// 0 unknown, 1 uses NSObject's retain/release, 2 overrides them.
    let retainRelease = Atomic<UInt8>(0)

    private var cacheCount = 0

    init(cls: ClassPointer, ro: UnsafePointer<perry_class_ro>, superInfo: ClassInfo?) {
        self.cls = cls
        let flags = ro.pointee.flags
        isMeta = flags & ROFlags.meta != 0
        isRoot = flags & ROFlags.root != 0
        hasCxxStructors = flags & ROFlags.hasCxxStructors != 0
        name = ro.pointee.name ?? ClassInfo.unnamed
        baseMethods = ro.pointee.base_methods
        self.superInfo = superInfo
        instanceSize = Int(ro.pointee.instance_size)
        if let protocols = ro.pointee.base_protocols {
            protocolLists.append(protocols)
        }
        if let properties = ro.pointee.base_properties {
            propertyLists.append(properties)
        }
        header = .allocate(capacity: 1)
        header.initialize(to: perry_class_header(cache: perry_objc_empty_cache_table(), info: nil))
        header.pointee.info = Unmanaged.passRetained(self).toOpaque()
    }

    nonisolated(unsafe) private static let unnamed = permanentCString("?")

    public var isInitialized: Bool { initialized.load(ordering: .acquiring) }

    // MARK: - Methods

    /// Adds a method list in Apple's format. Category methods replace the
    /// class's own; a class's base list keeps the first of duplicates.
    func addMethods(_ list: UnsafeRawPointer, replacing: Bool) {
        MethodList.forEach(list) { selector, types, imp in
            addMethod(selector, types: types, imp: imp, replacing: replacing)
        }
    }

    /// Adds or replaces a method; returns the previous IMP.
    @discardableResult
    func addMethod(_ selector: SEL, types: UnsafePointer<CChar>?, imp: IMP?, replacing: Bool) -> IMP? {
        if let method = methods[selector] {
            let old = method.pointee.imp
            if replacing {
                method.pointee.imp = imp
                if let types { method.pointee.types = types }
            }
            return old
        }
        let method = UnsafeMutablePointer<perry_method>.allocate(capacity: 1)
        method.initialize(to: perry_method(name: selector, types: types, imp: imp))
        methods[selector] = method
        return nil
    }

    // MARK: - Cache

    private var cacheSlot: UnsafeMutablePointer<UnsafeMutableRawPointer?> {
        UnsafeMutableRawPointer(header).assumingMemoryBound(to: UnsafeMutableRawPointer?.self)
    }

    /// The cached IMP for `selector`. Safe without the runtime lock.
    @inline(__always)
    func cachedIMP(_ selector: SEL) -> IMP? {
        let table = perry_load_acquire(cacheSlot)!
        let mask = table.load(as: UInt.self)
        let key = UInt(bitPattern: selector)
        var index = (key >> 3) & mask
        while true {
            let bucket = table + 8 + Int(index) * 16
            let sel = bucket.load(as: UInt.self)
            if sel == key {
                return IMP(bitPattern: bucket.load(fromByteOffset: 8, as: UInt.self))
            }
            if sel == 0 {
                return nil
            }
            index = (index + 1) & mask
        }
    }

    /// Caches `imp` for `selector`. Called with the runtime lock held.
    /// Buckets are written IMP first, then selector, and never rewritten;
    /// a full table is replaced by a larger copy. Old tables are never
    /// freed, since objc_msgSend may still be reading them.
    func cacheInsert(_ selector: SEL, _ imp: IMP) {
        var table = perry_load_acquire(cacheSlot)!
        var mask = table.load(as: UInt.self)
        let isEmpty = table == Runtime.emptyTable
        if isEmpty || (cacheCount + 1) * 4 > Int(mask + 1) * 3 {
            let capacity = isEmpty ? 8 : Int(mask + 1) * 2
            let grown = UnsafeMutableRawPointer.allocate(byteCount: 8 + capacity * 16, alignment: 16)
            memset(grown, 0, 8 + capacity * 16)
            grown.storeBytes(of: UInt(capacity - 1), as: UInt.self)
            var count = 0
            if !isEmpty {
                for index in 0...Int(mask) {
                    let bucket = table + 8 + index * 16
                    let sel = bucket.load(as: UInt.self)
                    let oldIMP = bucket.load(fromByteOffset: 8, as: UInt.self)
                    if sel != 0 && oldIMP != 0 {
                        Self.place(sel, oldIMP, in: grown, mask: UInt(capacity - 1))
                        count += 1
                    }
                }
            }
            perry_store_release(cacheSlot, grown)
            table = grown
            mask = UInt(capacity - 1)
            cacheCount = count
        }
        let key = UInt(bitPattern: selector)
        var index = (key >> 3) & mask
        while true {
            let bucket = table + 8 + Int(index) * 16
            let sel = bucket.load(as: UInt.self)
            if sel == key {
                return
            }
            if sel == 0 {
                bucket.storeBytes(of: UInt(bitPattern: imp), toByteOffset: 8, as: UInt.self)
                perry_release_fence()
                bucket.storeBytes(of: key, as: UInt.self)
                cacheCount += 1
                return
            }
            index = (index + 1) & mask
        }
    }

    private static func place(_ sel: UInt, _ imp: UInt, in table: UnsafeMutableRawPointer, mask: UInt) {
        var index = (sel >> 3) & mask
        while table.load(fromByteOffset: 8 + Int(index) * 16, as: UInt.self) != 0 {
            index = (index + 1) & mask
        }
        table.storeBytes(of: sel, toByteOffset: 8 + Int(index) * 16, as: UInt.self)
        table.storeBytes(of: imp, toByteOffset: 16 + Int(index) * 16, as: UInt.self)
    }

    /// Empties the cache. Called with the runtime lock held.
    func flushCache() {
        perry_store_release(cacheSlot, Runtime.emptyTable)
        cacheCount = 0
        retainRelease.store(0, ordering: .relaxed)
    }
}

enum ROFlags {
    static let meta: UInt32 = 1 << 0
    static let root: UInt32 = 1 << 1
    static let hasCxxStructors: UInt32 = 1 << 2
}

/// Reads method lists in the layouts clang and ld64 emit.
enum MethodList {
    static let relative: UInt32 = 0x8000_0000
    static let directSelectors: UInt32 = 0x4000_0000
    static let entsizeMask: UInt32 = 0x0000_fffc

    static func forEach(_ list: UnsafeRawPointer, _ body: (SEL, UnsafePointer<CChar>?, IMP?) -> Void) {
        let flags = list.load(as: UInt32.self)
        let count = Int(list.load(fromByteOffset: 4, as: UInt32.self))
        let entsize = Int(flags & entsizeMask)
        for index in 0..<count {
            let entry = list + 8 + index * entsize
            if flags & relative != 0 {
                // Each field is an offset from its own address.
                let name = entry + Int(entry.load(as: Int32.self))
                let typesOffset = Int(entry.load(fromByteOffset: 4, as: Int32.self))
                let impOffset = Int(entry.load(fromByteOffset: 8, as: Int32.self))
                let string = flags & directSelectors != 0
                    ? name.assumingMemoryBound(to: CChar.self)
                    : name.load(as: UnsafePointer<CChar>.self)
                let types = (entry + 4 + typesOffset).assumingMemoryBound(to: CChar.self)
                let imp = impOffset == 0 ? nil : IMP(mutating: entry + 8 + impOffset)
                body(Selectors.register(string, copying: false), types, imp)
            } else {
                let method = entry.assumingMemoryBound(to: perry_method.self).pointee
                guard let name = method.name else { continue }
                body(Selectors.register(name, copying: false), method.types, method.imp)
            }
        }
    }

    /// Finds `selector` in one list, without inheritance or categories.
    static func find(_ selector: SEL, in list: UnsafeRawPointer?) -> IMP? {
        guard let list else { return nil }
        var found: IMP?
        forEach(list) { sel, _, imp in
            if found == nil && sel == selector { found = imp }
        }
        return found
    }
}

/// Reads ivar lists.
enum IvarList {
    static func forEach(_ list: UnsafeRawPointer, _ body: (UnsafeMutablePointer<perry_ivar>) -> Void) {
        let entsize = Int(list.load(as: UInt32.self) & MethodList.entsizeMask)
        let count = Int(list.load(fromByteOffset: 4, as: UInt32.self))
        for index in 0..<count {
            body(UnsafeMutableRawPointer(mutating: list + 8 + index * entsize).assumingMemoryBound(to: perry_ivar.self))
        }
    }
}
