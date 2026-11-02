import CPerryObjC
import Glibc
import Synchronization

/// Allocation, reference counting and destruction.
public enum Objects {

    // MARK: - Lifetime

    public static func createInstance(_ cls: ClassPointer, extraBytes: Int = 0) -> ObjectPointer? {
        guard let info = Runtime.info(cls), let object = calloc(1, max(info.instanceSize + extraBytes, 16)) else {
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
        let entry = RetainCounts.remove(object)
        if entry.hasAssociations {
            Associations.removeAll(object)
        }
        if entry.weaklyReferenced {
            WeakReferences.clear(object)
        }
    }

    public static func dispose(_ object: ObjectPointer) {
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
        // Objects of classes the runtime cannot read are treated as immortal.
        guard let info = Runtime.info(classOf(object)) else { return object }
        if usesDefaultRetainRelease(info) {
            RetainCounts.retain(object)
            return object
        }
        return Messages.send(object, Sel.retain) ?? object
    }

    public static func release(_ object: ObjectPointer) {
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
enum RetainCounts {
    struct Entry {
        var extra: UInt = 0
        var deallocating = false
        var weaklyReferenced = false
        var hasAssociations = false
    }

    final class Shard: Sendable {
        let table = Mutex<[UInt: Entry]>([:])
    }

    static let shards: [Shard] = (0..<64).map { _ in Shard() }

    @inline(__always)
    static func shard(_ object: ObjectPointer) -> Shard {
        let address = UInt(bitPattern: object)
        return shards[Int((address >> 4) ^ (address >> 10)) & 63]
    }

    static func retain(_ object: ObjectPointer) {
        shard(object).table.withLock { table in
            table[UInt(bitPattern: object), default: Entry()].extra += 1
        }
    }

    /// Drops a reference; true when it was the last and the object should be
    /// deallocated. The object is marked deallocating so later releases are
    /// ignored.
    static func release(_ object: ObjectPointer) -> Bool {
        shard(object).table.withLock { table in
            let key = UInt(bitPattern: object)
            var entry = table[key] ?? Entry()
            if entry.deallocating {
                return false
            }
            if entry.extra > 0 {
                entry.extra -= 1
                table[key] = entry
                return false
            }
            entry.deallocating = true
            table[key] = entry
            return true
        }
    }

    static func count(_ object: ObjectPointer) -> UInt {
        shard(object).table.withLock { table in
            (table[UInt(bitPattern: object)]?.extra ?? 0) + 1
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
            guard let object = slot.pointee, !RetainCounts.isDeallocating(object) else {
                return nil
            }
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
            // Thread exit: drain whatever is left.
            guard let pointer else { return }
            let stack = Unmanaged<Stack>.fromOpaque(pointer).takeRetainedValue()
            while let last = stack.objects.popLast() {
                if let object = last { Objects.release(object) }
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

    static func add(_ object: ObjectPointer) {
        current.objects.append(object)
    }
}
