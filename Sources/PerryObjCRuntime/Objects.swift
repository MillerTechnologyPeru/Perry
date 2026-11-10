import CPerryObjC
import Glibc
import PerryObjCInterop
import Synchronization

/// Allocation, reference counting and destruction.
public enum Objects {

    // MARK: - Lifetime

    /// The room an instance gets, as Darwin's allocator gives it (libPerrySystem's
    /// malloc has the reasons): up to 1008 bytes in 16-byte steps, from there
    /// up to 15 KB in 512-byte steps and 64 bytes more, beyond that in 16 KB
    /// pages. A class may write a little past its instances' size and never
    /// know on Darwin.
    static func blockSize(_ size: Int) -> Int {
        if size <= 1008 { return size <= 16 ? 16 : (size + 15) & ~15 }
        if size <= 15 * 1024 { return ((size + 511) & ~511) + 64 }
        return (size + 16383) & ~16383
    }

    /// A zeroed block aligned to 16 bytes, as Darwin's are: glibc's are to 8
    /// in a 32-bit program, and compiled code stores 128-bit vectors to an
    /// object it takes to be aligned to 16.
    static func zeroedBlock(_ size: Int) -> UnsafeMutableRawPointer? {
        guard Layout.word == 4 else { return calloc(1, size) }
        var block: UnsafeMutableRawPointer?
        guard posix_memalign(&block, 16, size) == 0, let block else { return nil }
        memset(block, 0, size)
        return block
    }

    public static func createInstance(_ cls: ClassPointer, extraBytes: Int = 0) -> ObjectPointer? {
        guard let found = Runtime.info(cls) else { return nil }
        Runtime.runSwiftInitializers(found)
        guard let info = Runtime.info(cls), let object = zeroedBlock(blockSize(info.instanceSize + extraBytes)) else {
            return nil
        }
        object.storeBytes(of: cls, as: ClassPointer.self)
        return constructInstance(object, info)
    }

    /// Runs C++ ivar constructors (.cxx_construct), superclass first.
    static func constructInstance(_ object: ObjectPointer, _ info: ClassInfo) -> ObjectPointer? {
        var chain: [ClassInfo] = []
        var current: ClassInfo? = info
        while let cls = current {
            if cls.hasCxxStructors { chain.append(cls) }
            current = cls.superInfo
        }
        typealias Construct = @convention(c) (ObjectPointer, SEL) -> ObjectPointer?
        for cls in chain.reversed() {
            if let imp = Runtime.ownMethod(cls, Sel.cxxConstruct),
               unsafeBitCast(imp, to: Construct.self)(object, Sel.cxxConstruct) == nil {
                return nil
            }
        }
        return object
    }

    /// Ends an object's life without freeing it: ARC ivars (.cxx_destruct,
    /// subclass first), associated objects, weak references, retain count.
    public static func destructInstance(_ object: ObjectPointer) {
        typealias Destruct = @convention(c) (ObjectPointer, SEL) -> Void
        var current = Runtime.info(classOf(object))
        while let cls = current {
            if cls.hasCxxStructors, let imp = Runtime.ownMethod(cls, Sel.cxxDestruct) {
                unsafeBitCast(imp, to: Destruct.self)(object, Sel.cxxDestruct)
            }
            current = cls.superInfo
        }
        // Weak slots are cleared while the object is still marked
        // deallocating, so no weak load in between can take it back.
        if RetainCounts.isWeaklyReferenced(object) {
            WeakReferences.clear(object)
        }
        let entry = RetainCounts.remove(object)
        if entry.hasAssociations {
            Associations.removeAll(object)
        }
        // The Swift object that is this object goes with it: its deinit runs
        // while the object's memory is still there.
        if let peer = entry.peer { Unmanaged<AnyObject>.fromOpaque(peer).release() }
    }

    // MARK: - Peers

    /// Makes `peer` the Swift object that is `object` (RetainCounts).
    public static func bindPeer(_ object: ObjectPointer, _ peer: UnsafeMutableRawPointer, retained: Bool) {
        RetainCounts.bindPeer(object, peer, retained: retained)
    }

    public static func peer(_ object: ObjectPointer) -> UnsafeMutableRawPointer? { RetainCounts.peer(object) }

    public static func peerWillDeinitialize(_ object: ObjectPointer) -> Bool { RetainCounts.peerWillDeinitialize(object) }

    public static func dispose(_ object: ObjectPointer) {
        if Zombies.tracing { Zombies.trace(object, "dealloc") }
        if Zombies.enabled {
            Zombies.bury(object)
            destructInstance(object)
            Zombies.mark(object)
            return
        }
        destructInstance(object)
        free(object)
    }

    // MARK: - Retain and release

    nonisolated(unsafe) static var defaultRetain: IMP?
    nonisolated(unsafe) static var defaultRelease: IMP?
    nonisolated(unsafe) static var defaultAutorelease: IMP?

    /// Whether instances of `info` use NSObject's retain/release, so ARC
    /// calls can skip the message send.
    @inline(__always)
    static func usesDefaultRetainRelease(_ info: ClassInfo) -> Bool {
        switch info.retainRelease.load(ordering: .relaxed) {
        case 1: return true
        case 2: return false
        default:
            let isDefault = Runtime.findMethod(info, Sel.retain)?.pointee.imp == defaultRetain
                && Runtime.findMethod(info, Sel.release)?.pointee.imp == defaultRelease
                && Runtime.findMethod(info, Sel.autorelease)?.pointee.imp == defaultAutorelease
            info.retainRelease.store(isDefault ? 1 : 2, ordering: .relaxed)
            return isDefault
        }
    }

    public static func retain(_ object: ObjectPointer) -> ObjectPointer {
        if Zombies.enabled, Zombies.report(object, "retain") { return object }
        // Objects of classes the runtime cannot read are treated as immortal.
        guard let info = Runtime.info(classOf(object)) else { return object }
        if usesDefaultRetainRelease(info) {
            RetainCounts.retain(object)
            return object
        }
        return Messages.send(object, Sel.retain) ?? object
    }

    public static func release(_ object: ObjectPointer) {
        if Zombies.enabled, Zombies.report(object, "release") { return }
        guard let info = Runtime.info(classOf(object)) else { return }
        if usesDefaultRetainRelease(info) {
            if RetainCounts.release(object) {
                Messages.sendVoid(object, Sel.dealloc)
            }
        } else {
            Messages.sendVoid(object, Sel.release)
        }
    }

    public static func autorelease(_ object: ObjectPointer) -> ObjectPointer {
        if Zombies.enabled, Zombies.report(object, "autorelease") { return object }
        guard let info = Runtime.info(classOf(object)) else { return object }
        if usesDefaultRetainRelease(info) {
            AutoreleasePool.add(object)
            return object
        }
        return Messages.send(object, Sel.autorelease) ?? object
    }
}

/// Retain counts beyond the first, in a side table keyed by address, as
/// Apple's runtime keeps them for objects without an inline count.
///
/// An object a Swift class defines has a peer: the Swift object that is
/// the Objective-C object, bound when its Swift initializer runs. As in
/// Darwin's Swift, the two share one reference count, the Swift object's:
/// retains and releases from either side count there, the last release
/// from Objective-C deallocates the object, and the Swift object's deinit
/// runs as the object is destroyed.
/// Debugging switches for reference counting.
///
/// PERRY_OBJC_ZOMBIES=1 keeps deallocated objects' memory instead of freeing
/// it, as NSZombieEnabled does, and reports a retain, release or autorelease
/// of one with its class, in place of the crash a reused address gives.
///
/// PERRY_OBJC_TRACE set to a class's name reports each retain, release,
/// autorelease and deallocation of its instances, with the count after.
///
/// PERRY_OBJC_TRACE_FRAMES=1 ends each report with the return addresses of
/// the frames it came from, nearest first, to tell which code retains and
/// which releases (arm64; /proc/<pid>/maps says whose each address is).
///
/// PERRY_OBJC_TRAP=1 raises SIGTRAP at each report, for a debugger to show
/// where it came from.
enum Zombies {
    static let enabled: Bool = getenv("PERRY_OBJC_ZOMBIES").map { String(cString: $0) != "0" } ?? false
    static let traps: Bool = getenv("PERRY_OBJC_TRAP").map { String(cString: $0) != "0" } ?? false
    /// The traced class's name, as a C string's address.
    static let tracedName: UInt = getenv("PERRY_OBJC_TRACE").map { UInt(bitPattern: strdup($0)) } ?? 0
    static let tracing: Bool = tracedName != 0
    /// Each buried object's class name, by address (addresses, as the
    /// table must be Sendable).
    static let graves = Mutex<[UInt: UInt]>([:])

    /// A stand-in class with an empty method cache, so that a message to a
    /// buried object reaches Runtime.lookUpIMP, which reports it.
    static let zombieClass: UInt = {
        let cls = calloc(1, 64)!
        cls.storeBytes(of: Runtime.emptyCache, toByteOffset: 16, as: UnsafeMutableRawPointer?.self)
        return UInt(bitPattern: cls)
    }()

    /// Makes a buried object an instance of the stand-in class.
    static func mark(_ object: ObjectPointer) {
        object.storeBytes(of: zombieClass, as: UInt.self)
    }

    static func bury(_ object: ObjectPointer) {
        guard let info = Runtime.info(classOf(object)) else { return }
        let key = UInt(bitPattern: object), name = UInt(bitPattern: info.name)
        graves.withLock { $0[key] = name }
    }

    /// Whether `object` was deallocated; reports the message if so.
    static func report(_ object: ObjectPointer, _ message: String) -> Bool {
        let key = UInt(bitPattern: object)
        guard let name = UnsafePointer<CChar>(bitPattern: graves.withLock({ $0[key] ?? 0 })) else { return false }
        say("perry: objc: -[\(String(cString: name)) \(message)] sent to deallocated instance 0x\(String(key, radix: 16))\n")
        return true
    }

    /// Reports `event` if `object` is of the traced class.
    static func trace(_ object: ObjectPointer, _ event: String) {
        guard let traced = UnsafePointer<CChar>(bitPattern: tracedName), let info = Runtime.info(classOf(object)),
              strcmp(info.name, traced) == 0 else { return }
        say("perry: objc: \(String(cString: traced)) 0x\(String(UInt(bitPattern: object), radix: 16)) \(event), count \(RetainCounts.count(object))\n")
    }

    static let frames: Bool = getenv("PERRY_OBJC_TRACE_FRAMES").map { String(cString: $0) != "0" } ?? false

    static func say(_ text: String) {
        var text = text
        if frames {
            var addresses = [UInt](repeating: 0, count: 24)
            let count = addresses.withUnsafeMutableBufferPointer { perry_caller_frames($0.baseAddress, 24) }
            let list = addresses.prefix(count).map { "0x" + String($0, radix: 16) }.joined(separator: " ")
            text = text.dropLast() + " frames \(list)\n"
        }
        text.withCString { _ = write(2, $0, strlen($0)) }
        if traps { raise(SIGTRAP) }
    }
}

enum RetainCounts {
    struct Entry {
        var extra: UInt = 0
        var deallocating = false
        var weaklyReferenced = false
        var hasAssociations = false
        /// The peer's address, holding one Swift reference for the object's
        /// own; 0 for none. (An address, as the table must be Sendable.)
        var peerAddress: UInt = 0

        var peer: UnsafeMutableRawPointer? { UnsafeMutableRawPointer(bitPattern: peerAddress) }
    }

    final class Shard: Sendable {
        let table = Mutex(EntryTable())
    }

    /// A shard's entries by object address: open addressing with linear
    /// probing, as a Dictionary is, but hashed with one multiply rather than
    /// SipHash, and kept in buffers of its own. It is non-copyable, so it
    /// lives only in its Mutex and its buffers need no copy-on-write checks.
    struct EntryTable: ~Copyable {
        private var keys: UnsafeMutablePointer<UInt>
        private var values: UnsafeMutablePointer<Entry>
        private var capacity: Int
        private var count = 0

        init() {
            capacity = 16
            keys = .allocate(capacity: capacity)
            keys.initialize(repeating: 0, count: capacity)
            values = .allocate(capacity: capacity)
        }

        deinit {
            for index in 0..<capacity where keys[index] != 0 { (values + index).deinitialize(count: 1) }
            keys.deallocate()
            values.deallocate()
        }

        /// Where `key` belongs: a multiplicative hash of the address, past
        /// its alignment bits.
        @inline(__always)
        private func home(_ key: UInt) -> Int { Int(truncatingIfNeeded: (key >> 4) &* UInt(truncatingIfNeeded: 0x9E37_79B9_7F4A_7C15 as UInt64)) & (capacity - 1) }

        /// The slot holding `key`, or the empty slot where it would go.
        @inline(__always)
        private func slot(_ key: UInt) -> (index: Int, found: Bool) {
            var index = home(key)
            while true {
                let stored = keys[index]
                if stored == key { return (index, true) }
                if stored == 0 { return (index, false) }
                index = (index + 1) & (capacity - 1)
            }
        }

        subscript(key: UInt) -> Entry? {
            get {
                let (index, found) = slot(key)
                return found ? values[index] : nil
            }
            set {
                if let newValue {
                    insert(key, newValue)
                } else {
                    _ = removeValue(forKey: key)
                }
            }
        }

        subscript(key: UInt, default value: @autoclosure () -> Entry) -> Entry {
            get { self[key] ?? value() }
            set { insert(key, newValue) }
        }

        private mutating func insert(_ key: UInt, _ value: Entry) {
            let (index, found) = slot(key)
            if found {
                values[index] = value
                return
            }
            if (count + 1) * 2 > capacity {
                grow()
                return insert(key, value)
            }
            keys[index] = key
            (values + index).initialize(to: value)
            count += 1
        }

        /// Removes `key`, moving back the entries after it that probed past
        /// its slot, so lookups never need tombstones.
        mutating func removeValue(forKey key: UInt) -> Entry? {
            let (found, present) = slot(key)
            guard present else { return nil }
            let removed = (values + found).move()
            keys[found] = 0
            count -= 1
            var hole = found, index = (found + 1) & (capacity - 1)
            while keys[index] != 0 {
                let home = home(keys[index])
                // Whether the entry's home is cyclically outside (hole, index]:
                // then it may move back into the hole.
                let between = hole <= index ? (hole < home && home <= index) : (hole < home || home <= index)
                if !between {
                    keys[hole] = keys[index]
                    (values + hole).moveInitialize(from: values + index, count: 1)
                    keys[index] = 0
                    hole = index
                }
                index = (index + 1) & (capacity - 1)
            }
            return removed
        }

        private mutating func grow() {
            let (oldKeys, oldValues, oldCapacity) = (keys, values, capacity)
            capacity *= 2
            keys = .allocate(capacity: capacity)
            keys.initialize(repeating: 0, count: capacity)
            values = .allocate(capacity: capacity)
            for index in 0..<oldCapacity where oldKeys[index] != 0 {
                let (slot, _) = slot(oldKeys[index])
                keys[slot] = oldKeys[index]
                (values + slot).moveInitialize(from: oldValues + index, count: 1)
            }
            oldKeys.deallocate()
            oldValues.deallocate()
        }
    }

    /// Many, so threads retaining and releasing different objects seldom
    /// wait on each other: with 64, LightBlue's main thread spent a fifth
    /// of its time spinning on shards its Bluetooth queues held.
    static let shards: [Shard] = (0..<1024).map { _ in Shard() }

    @inline(__always)
    static func shard(_ object: ObjectPointer) -> Shard {
        let address = UInt(bitPattern: object)
        return shards[Int((address >> 4) ^ (address >> 14)) & 1023]
    }

    static func retain(_ object: ObjectPointer) {
        defer { if Zombies.tracing { Zombies.trace(object, "retain") } }
        let peerAddress = shard(object).table.withLock { table -> UInt in
            let key = UInt(bitPattern: object)
            if let address = table[key]?.peerAddress, address != 0 { return address }
            table[key, default: Entry()].extra += 1
            return 0
        }
        if let peer = UnsafeMutableRawPointer(bitPattern: peerAddress) { _ = Unmanaged<AnyObject>.fromOpaque(peer).retain() }
    }

    /// Drops a reference; true when it was the last and the object should be
    /// deallocated. The object is marked deallocating so later releases are
    /// ignored. A peer's count drops outside the lock, as its deinit may
    /// run if Swift let go at the same moment.
    static func release(_ object: ObjectPointer) -> Bool {
        if Zombies.tracing { Zombies.trace(object, "release") }
        enum Outcome { case keep, deallocate, releasePeer(UInt) }
        let outcome = shard(object).table.withLock { table -> Outcome in
            let key = UInt(bitPattern: object)
            var entry = table[key] ?? Entry()
            if entry.deallocating {
                return .keep
            }
            if let peer = entry.peer {
                // The last reference is the object's own.
                guard swift_retainCount(peer) <= 1 else { return .releasePeer(entry.peerAddress) }
                entry.deallocating = true
                table[key] = entry
                return .deallocate
            }
            if entry.extra > 0 {
                entry.extra -= 1
                table[key] = entry
                return .keep
            }
            entry.deallocating = true
            table[key] = entry
            return .deallocate
        }
        switch outcome {
        case .keep: return false
        case .deallocate: return true
        case .releasePeer(let address):
            if let peer = UnsafeMutableRawPointer(bitPattern: address) { Unmanaged<AnyObject>.fromOpaque(peer).release() }
            return false
        }
    }

    static func count(_ object: ObjectPointer) -> UInt {
        let (extra, peerAddress) = shard(object).table.withLock { table -> (UInt, UInt) in
            let entry = table[UInt(bitPattern: object)]
            return (entry?.extra ?? 0, entry?.peerAddress ?? 0)
        }
        if let peer = UnsafeMutableRawPointer(bitPattern: peerAddress) { return UInt(max(swift_retainCount(peer), 1)) }
        return extra + 1
    }

    // MARK: Peers

    /// Makes `peer` the object's Swift object. Its references take over the
    /// object's: one for each it has beyond the first, and, when `retained`,
    /// one for the first, which an -init's caller is given; otherwise the
    /// Swift reference that made the object is the first.
    static func bindPeer(_ object: ObjectPointer, _ peer: UnsafeMutableRawPointer, retained: Bool) {
        let extra = shard(object).table.withLock { table -> UInt in
            let key = UInt(bitPattern: object)
            var entry = table[key] ?? Entry()
            let extra = entry.extra
            entry.extra = 0
            entry.peerAddress = UInt(bitPattern: peer)
            table[key] = entry
            return extra
        }
        let unmanaged = Unmanaged<AnyObject>.fromOpaque(peer)
        for _ in 0..<(extra + (retained ? 1 : 0)) { _ = unmanaged.retain() }
    }

    static func peer(_ object: ObjectPointer) -> UnsafeMutableRawPointer? {
        let address = shard(object).table.withLock { table in table[UInt(bitPattern: object)]?.peerAddress ?? 0 }
        return UnsafeMutableRawPointer(bitPattern: address)
    }

    /// The peer's last Swift reference went before the object's did: true
    /// when the object, no longer counted by it, should now be deallocated;
    /// false when it is already being deallocated.
    static func peerWillDeinitialize(_ object: ObjectPointer) -> Bool {
        shard(object).table.withLock { table in
            let key = UInt(bitPattern: object)
            guard var entry = table[key], entry.peerAddress != 0 else { return false }
            entry.peerAddress = 0
            let deallocate = !entry.deallocating
            entry.deallocating = true
            table[key] = entry
            return deallocate
        }
    }

    /// Retains the object unless it is being deallocated; false if it is.
    /// A peer is retained only while Swift still holds it.
    static func tryRetain(_ object: ObjectPointer) -> Bool {
        defer { if Zombies.tracing { Zombies.trace(object, "retain") } }
        return shard(object).table.withLock { table -> Bool in
            let key = UInt(bitPattern: object)
            var entry = table[key] ?? Entry()
            if entry.deallocating { return false }
            if let peer = entry.peer { return swift_tryRetain(peer) != nil }
            entry.extra += 1
            table[key] = entry
            return true
        }
    }

    static func isWeaklyReferenced(_ object: ObjectPointer) -> Bool {
        shard(object).table.withLock { table in
            table[UInt(bitPattern: object)]?.weaklyReferenced ?? false
        }
    }

    static func isDeallocating(_ object: ObjectPointer) -> Bool {
        shard(object).table.withLock { table in
            table[UInt(bitPattern: object)]?.deallocating ?? false
        }
    }

    static func update(_ object: ObjectPointer, _ body: (inout Entry) -> Void) {
        shard(object).table.withLock { table in
            body(&table[UInt(bitPattern: object), default: Entry()])
        }
    }

    static func remove(_ object: ObjectPointer) -> Entry {
        shard(object).table.withLock { table in
            table.removeValue(forKey: UInt(bitPattern: object)) ?? Entry()
        }
    }
}

/// The Swift runtime's strong reference count of an object.
@_silgen_name("swift_retainCount")
func swift_retainCount(_ object: UnsafeMutableRawPointer) -> Int

/// Retains a Swift object unless its deinit has begun: the object, or nil
/// (a pointer, not a Bool: its low byte can be 0).
@_silgen_name("swift_tryRetain")
func swift_tryRetain(_ object: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer?

/// __weak variables: the slots pointing at each object, cleared when it is
/// deallocated.
public enum WeakReferences {
    static let lock = RecursiveLock()
    nonisolated(unsafe) static var slots: [UInt: [UnsafeMutablePointer<ObjectPointer?>]] = [:]

    /// Stores `object` in a weak slot, or nil if it is being deallocated.
    @discardableResult
    public static func store(_ slot: UnsafeMutablePointer<ObjectPointer?>, _ object: ObjectPointer?) -> ObjectPointer? {
        lock.withLock {
            if let old = slot.pointee {
                let key = UInt(bitPattern: old)
                slots[key]?.removeAll { $0 == slot }
                if slots[key]?.isEmpty == true { slots[key] = nil }
            }
            guard let object, !RetainCounts.isDeallocating(object) else {
                slot.pointee = nil
                return nil
            }
            slots[UInt(bitPattern: object), default: []].append(slot)
            RetainCounts.update(object) { $0.weaklyReferenced = true }
            slot.pointee = object
            return object
        }
    }

    public static func loadRetained(_ slot: UnsafeMutablePointer<ObjectPointer?>) -> ObjectPointer? {
        lock.withLock {
            guard let object = slot.pointee else { return nil }
            // A reference taken only if the object is not being deallocated,
            // in one step: a release on another thread may be starting it.
            if let info = Runtime.info(classOf(object)), Objects.usesDefaultRetainRelease(info) {
                return RetainCounts.tryRetain(object) ? object : nil
            }
            guard !RetainCounts.isDeallocating(object) else { return nil }
            return Objects.retain(object)
        }
    }

    static func clear(_ object: ObjectPointer) {
        lock.withLock {
            for slot in slots.removeValue(forKey: UInt(bitPattern: object)) ?? [] where slot.pointee == object {
                slot.pointee = nil
            }
        }
    }
}

/// objc_setAssociatedObject storage.
public enum Associations {
    public enum Policy {
        static let retain: UInt = 1
        static let copy: UInt = 3
        static let getterRetain: UInt = 1 << 8
    }

    static let lock = RecursiveLock()
    nonisolated(unsafe) static var table: [UInt: [UInt: (value: ObjectPointer, policy: UInt)]] = [:]

    public static func set(_ object: ObjectPointer, key: UnsafeRawPointer, value: ObjectPointer?, policy: UInt) {
        var stored = value
        if let value {
            switch policy & 0xff {
            case Policy.copy: stored = Messages.send(value, Sel.copy)
            case Policy.retain: stored = Objects.retain(value)
            default: break
            }
        }
        let old: (value: ObjectPointer, policy: UInt)? = lock.withLock {
            let objectKey = UInt(bitPattern: object)
            let keyValue = UInt(bitPattern: key)
            let old = table[objectKey]?[keyValue]
            if let stored {
                table[objectKey, default: [:]][keyValue] = (stored, policy)
            } else {
                table[objectKey]?[keyValue] = nil
            }
            return old
        }
        if stored != nil {
            RetainCounts.update(object) { $0.hasAssociations = true }
        }
        if let old, old.policy & 0xff != 0 {
            Objects.release(old.value)
        }
    }

    public static func get(_ object: ObjectPointer, key: UnsafeRawPointer) -> ObjectPointer? {
        guard let entry = lock.withLock({ table[UInt(bitPattern: object)]?[UInt(bitPattern: key)] }) else {
            return nil
        }
        if entry.policy & Policy.getterRetain != 0 {
            return Objects.autorelease(Objects.retain(entry.value))
        }
        return entry.value
    }

    public static func removeAll(_ object: ObjectPointer) {
        let entries = lock.withLock { table.removeValue(forKey: UInt(bitPattern: object)) } ?? [:]
        for entry in entries.values where entry.policy & 0xff != 0 {
            Objects.release(entry.value)
        }
    }
}

/// @synchronized: one recursive lock per object, kept for the process.
public enum Synchronized {
    static let lock = RecursiveLock()
    nonisolated(unsafe) static var locks: [UInt: RecursiveLock] = [:]

    static func lock(for object: ObjectPointer) -> RecursiveLock {
        lock.withLock {
            let key = UInt(bitPattern: object)
            if let existing = locks[key] { return existing }
            let created = RecursiveLock()
            locks[key] = created
            return created
        }
    }

    public static func enter(_ object: ObjectPointer) { lock(for: object).lock() }
    public static func exit(_ object: ObjectPointer) { lock(for: object).unlock() }
}

/// Per-thread autorelease pools: a stack of objects, with nil marking each
/// pool's start. A pool token is the stack depth just after its marker.
public enum AutoreleasePool {
    final class Stack {
        var objects: [ObjectPointer?] = []
    }

    static let key: pthread_key_t = {
        var key = pthread_key_t()
        pthread_key_create(&key) { pointer in
            // Thread exit, from glibc: drain whatever is left.
            guard let pointer else { return }
            let stack = Unmanaged<Stack>.fromOpaque(pointer).takeRetainedValue()
            keepingLinuxRegisters {
                while let last = stack.objects.popLast() {
                    if let object = last { Objects.release(object) }
                }
            }
        }
        return key
    }()

    static var current: Stack {
        if let pointer = pthread_getspecific(key) {
            return Unmanaged<Stack>.fromOpaque(pointer).takeUnretainedValue()
        }
        let stack = Stack()
        pthread_setspecific(key, Unmanaged.passRetained(stack).toOpaque())
        return stack
    }

    public static func push() -> UnsafeMutableRawPointer {
        let stack = current
        stack.objects.append(nil)
        return UnsafeMutableRawPointer(bitPattern: stack.objects.count)!
    }

    public static func pop(_ token: UnsafeMutableRawPointer?) {
        let stack = current
        let start = Int(bitPattern: token) - 1
        guard start >= 0 else { return }
        // Releasing can autorelease more objects; keep going until the
        // stack is back below this pool.
        while stack.objects.count > start {
            if let object = stack.objects.removeLast() {
                Objects.release(object)
            }
        }
    }

    /// An object already being deallocated is left out: its memory is gone
    /// by the time the pool drains. (A getter's result, retained and
    /// autoreleased, can be one: a subview's -superview, sent from its
    /// superview's -dealloc.)
    public static func add(_ object: ObjectPointer) {
        if Zombies.tracing { Zombies.trace(object, "autorelease") }
        if RetainCounts.isDeallocating(object) { return }
        current.objects.append(object)
    }
}
