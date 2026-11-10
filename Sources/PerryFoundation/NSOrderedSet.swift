import CPerryFoundation
import Glibc
import PerryObjCInterop

// NSOrderedSet and NSMutableOrderedSet; NSCountedSet, an NSMutableSet that
// counts; and NSCache.

// MARK: - Ordered sets

/// Members in order, each retained, with an index by equality.
final class OrderedSetStorage {
    private(set) var members: [id] = []
    private var positions: [ObjectKey: Int] = [:]
    let enumeration = EnumerationBuffer()

    init(_ members: [id] = []) {
        members.forEach { append($0) }
    }

    deinit {
        members.forEach { ObjC.release($0) }
    }

    private func reindex() {
        positions = Dictionary(members.enumerated().map { (ObjectKey(object: $1), $0) }, uniquingKeysWith: { first, _ in first })
        enumeration.mutated()
    }

    func index(of object: id) -> Int? { positions[ObjectKey(object: object)] }

    @discardableResult
    func append(_ object: id) -> Bool { insert(object, at: members.count) }

    @discardableResult
    func insert(_ object: id, at index: Int) -> Bool {
        guard positions[ObjectKey(object: object)] == nil else { return false }
        members.insert(ObjC.retain(object)!, at: index)
        reindex()
        return true
    }

    func remove(at index: Int) {
        let removed = members.remove(at: index)
        reindex()
        ObjC.release(removed)
    }

    func replace(at index: Int, with object: id) {
        if let existing = self.index(of: object), existing != index { return }
        let old = members[index]
        members[index] = ObjC.retain(object)!
        reindex()
        ObjC.release(old)
    }

    func removeAll() {
        let old = members
        members = []
        reindex()
        old.forEach { ObjC.release($0) }
    }

    func exchange(_ a: Int, _ b: Int) {
        members.swapAt(a, b)
        reindex()
    }
}

enum OrderedSets {
    nonisolated(unsafe) static var setClass: Class!
    nonisolated(unsafe) static var mutableClass: Class!

    static func storage(_ object: id?) -> OrderedSetStorage {
        Storage.get(object, as: OrderedSetStorage.self) ?? OrderedSetStorage()
    }

    static func make(_ cls: id, _ members: [id]) -> id? {
        guard let object = Storage.allocate(cls) else { return nil }
        Storage.set(object, OrderedSetStorage(members))
        return ObjC.autorelease(object)
    }

    static func check(_ index: UInt, _ count: Int, _ method: String) {
        guard Int(index) < count else {
            foundationFatal("-[NSOrderedSet \(method)]: index \(index) beyond bounds [0 .. \(count - 1)]")
        }
    }
}

/// NSOrderedSet.
@ObjCClass("NSOrderedSet")
public class NSOrderedSet: NSObject {
    /// What the Swift runtime asks to tell Foundation's classes apart.
    @ObjCMethod("isNSOrderedSet__") func isNSOrderedSet__() -> Bool { true }

    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        OrderedSets.setClass = cls.storage
        cls.addMethod("orderedSetWithObjects:", types: "@24@0:8@16",
                      implementation: variadicEntry(perry_imp_orderedSetWithObjects), isClassMethod: true)
        cls.addMethod("initWithObjects:", types: "@24@0:8@16",
                      implementation: variadicEntry(perry_imp_initOrderedSetWithObjects), isClassMethod: false)
    }

    var storage: OrderedSetStorage {
        if let storage = Storage.get(objcObject, as: OrderedSetStorage.self) { return storage }
        let storage = OrderedSetStorage()
        Storage.set(objcObject, storage)
        return storage
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: OrderedSets.setClass)
    }

    @ObjCClassMethod("orderedSet") static func empty(_ cls: ObjCClass) -> UnsafeMutableRawPointer? { OrderedSets.make(cls.pointer, []) }

    @ObjCClassMethod("orderedSetWithObject:")
    static func make(_ cls: ObjCClass, object: ObjCObject) -> UnsafeMutableRawPointer? { OrderedSets.make(cls.pointer, [object.id]) }

    @ObjCClassMethod("orderedSetWithArray:")
    static func make(_ cls: ObjCClass, array: ObjCObject) -> UnsafeMutableRawPointer? {
        OrderedSets.make(cls.pointer, Arrays.elements(array.id))
    }

    @ObjCClassMethod("orderedSetWithSet:")
    static func make(_ cls: ObjCClass, set: ObjCObject) -> UnsafeMutableRawPointer? { OrderedSets.make(cls.pointer, Sets.elements(set.id)) }

    @ObjCClassMethod("orderedSetWithOrderedSet:")
    static func make(_ cls: ObjCClass, orderedSet: ObjCObject) -> UnsafeMutableRawPointer? {
        OrderedSets.make(cls.pointer, OrderedSets.storage(orderedSet.id).members)
    }

    /// The members in a range of another ordered set. `copyItems` shares the
    /// members: they are not copied.
    @ObjCClassMethod("orderedSetWithOrderedSet:range:copyItems:")
    static func make(_ cls: ObjCClass, orderedSet: ObjCObject, range: NSRange, copyItems: Bool) -> UnsafeMutableRawPointer? {
        let members = OrderedSets.storage(orderedSet.id).members
        guard Int(range.location + range.length) <= members.count else {
            foundationFatal("+[NSOrderedSet orderedSetWithOrderedSet:range:copyItems:]: range {\(range.location), \(range.length)} extends beyond bounds [0 .. \(members.count - 1)]")
        }
        return OrderedSets.make(cls.pointer, Array(members[Int(range.location)..<Int(range.location + range.length)]))
    }

    @ObjCMethod("init")
    func initialize() -> Self {
        Storage.set(objcObject, OrderedSetStorage())
        return self
    }

    @ObjCMethod("initWithOrderedSet:")
    func initialize(orderedSet other: ObjCObject?) -> Self {
        Storage.set(objcObject, OrderedSetStorage(OrderedSets.storage(other?.id).members))
        return self
    }

    @ObjCMethod("initWithArray:")
    func initialize(array: ObjCObject?) -> Self {
        Storage.set(objcObject, OrderedSetStorage(Arrays.elements(array?.id)))
        return self
    }

    @ObjCMethod("initWithCapacity:")
    func initialize(capacity: UInt) -> Self { initialize() }

    @ObjCMethod("count") func count() -> UInt { UInt(storage.members.count) }

    @ObjCMethod("objectAtIndex:")
    func object(at index: UInt) -> UnsafeMutableRawPointer {
        OrderedSets.check(index, storage.members.count, "objectAtIndex:")
        return storage.members[Int(index)]
    }

    @ObjCMethod("objectAtIndexedSubscript:")
    func objectAtSubscript(_ index: UInt) -> UnsafeMutableRawPointer { object(at: index) }

    @ObjCMethod("indexOfObject:")
    func index(of object: ObjCObject?) -> UInt { object.flatMap { storage.index(of: $0.id) }.map(UInt.init) ?? notFound }

    @ObjCMethod("containsObject:") func contains(_ object: ObjCObject?) -> Bool { object.flatMap { storage.index(of: $0.id) } != nil }
    @ObjCMethod("firstObject") func firstObject() -> UnsafeMutableRawPointer? { storage.members.first }
    @ObjCMethod("lastObject") func lastObject() -> UnsafeMutableRawPointer? { storage.members.last }
    @ObjCMethod("array") func array() -> ObjCObject { ObjCObject(Arrays.autoreleased(storage.members)) }
    @ObjCMethod("set") func set() -> ObjCObject { ObjCObject(Sets.autoreleased(storage.members)) }

    @ObjCMethod("objectsAtIndexes:")
    func objects(atIndexes indexes: ObjCObject) -> ObjCObject {
        let members = storage.members
        return ObjCObject(Arrays.autoreleased(IndexSets.storage(indexes.id).indexes.filter { $0 < members.count }.map { members[$0] }))
    }

    @ObjCMethod("reversedOrderedSet")
    func reversed() -> UnsafeMutableRawPointer? {
        OrderedSets.make(UnsafeMutableRawPointer(OrderedSets.setClass), storage.members.reversed())
    }

    @ObjCMethod("isEqualToOrderedSet:")
    func isEqual(toOrderedSet other: ObjCObject?) -> Bool {
        let theirs = OrderedSets.storage(other?.id).members, mine = storage.members
        return theirs.count == mine.count && zip(mine, theirs).allSatisfy { $0 == $1 || ObjC.sendBool($0, Selectors.isEqual, $1) }
    }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: ObjCObject?) -> Bool {
        guard let other, ObjC.isKind(other.id, of: OrderedSets.setClass) else { return false }
        return isEqual(toOrderedSet: other)
    }

    @ObjCMethod("hash") func hash() -> UInt { UInt(storage.members.count) }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        ObjC.retain(OrderedSets.make(UnsafeMutableRawPointer(OrderedSets.setClass), storage.members))
    }

    @ObjCMethod("mutableCopyWithZone:")
    func mutableCopy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        ObjC.retain(OrderedSets.make(UnsafeMutableRawPointer(OrderedSets.mutableClass), storage.members))
    }

    @ObjCMethod("countByEnumeratingWithState:objects:count:")
    func enumerate(state: UnsafeMutableRawPointer?, objects: UnsafeMutablePointer<id?>?, count: UInt) -> UInt {
        storage.enumeration.enumerate(storage.members, state: state, buffer: objects, count: count)
    }

    @ObjCMethod("enumerateObjectsUsingBlock:")
    func enumerateObjects(using block: ObjCObject) {
        typealias Invoke = @convention(c) (id, id, UInt, UnsafeMutablePointer<Bool>) -> Void
        let invoke = Blocks.invoke(block.id, as: Invoke.self)
        for (index, member) in storage.members.enumerated() {
            var stop = false
            invoke(block.id, member, UInt(index), &stop)
            if stop { return }
        }
    }

    @ObjCMethod("description")
    func description() -> String {
        let name = ObjC.isKind(objcObject, of: OrderedSets.mutableClass) ? "NSMutableOrderedSet" : "NSOrderedSet"
        let lines = storage.members.map { "    " + Format.describe($0) }
        return "{(\n" + lines.joined(separator: ",\n") + "\n)}" + (name.isEmpty ? "" : "")
    }
}

/// NSMutableOrderedSet.
@ObjCClass("NSMutableOrderedSet")
public final class NSMutableOrderedSet: NSOrderedSet {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        OrderedSets.mutableClass = cls.storage
    }

    @ObjCMethod("addObject:") func add(_ object: ObjCObject) { storage.append(object.id) }

    @ObjCMethod("addObjectsFromArray:")
    func add(objectsFrom array: ObjCObject) { Arrays.elements(array.id).forEach { storage.append($0) } }

    @ObjCMethod("insertObject:atIndex:")
    func insert(_ object: ObjCObject, at index: UInt) {
        guard Int(index) <= storage.members.count else {
            foundationFatal("-[NSMutableOrderedSet insertObject:atIndex:]: index \(index) beyond bounds")
        }
        storage.insert(object.id, at: Int(index))
    }

    @ObjCMethod("removeObject:")
    func remove(_ object: ObjCObject?) {
        if let object, let index = storage.index(of: object.id) { storage.remove(at: index) }
    }

    @ObjCMethod("removeObjectAtIndex:")
    func remove(at index: UInt) {
        OrderedSets.check(index, storage.members.count, "removeObjectAtIndex:")
        storage.remove(at: Int(index))
    }

    @ObjCMethod("replaceObjectAtIndex:withObject:")
    func replace(at index: UInt, with object: ObjCObject) {
        OrderedSets.check(index, storage.members.count, "replaceObjectAtIndex:withObject:")
        storage.replace(at: Int(index), with: object.id)
    }

    @ObjCMethod("setObject:atIndex:")
    func set(_ object: ObjCObject, at index: UInt) {
        if Int(index) == storage.members.count { storage.append(object.id) } else { replace(at: index, with: object) }
    }

    @ObjCMethod("setObject:atIndexedSubscript:")
    func setSubscript(_ object: ObjCObject, at index: UInt) { set(object, at: index) }

    @ObjCMethod("exchangeObjectAtIndex:withObjectAtIndex:")
    func exchange(_ first: UInt, with second: UInt) {
        OrderedSets.check(max(first, second), storage.members.count, "exchangeObjectAtIndex:withObjectAtIndex:")
        storage.exchange(Int(first), Int(second))
    }

    @ObjCMethod("removeAllObjects") func removeAll() { storage.removeAll() }

    @ObjCMethod("removeObjectsInArray:")
    func remove(objectsIn array: ObjCObject) {
        for object in Arrays.elements(array.id) { if let index = storage.index(of: object) { storage.remove(at: index) } }
    }

    @ObjCMethod("intersectOrderedSet:")
    func intersect(_ other: ObjCObject) {
        let theirs = OrderedSets.storage(other.id)
        for member in storage.members.reversed() where theirs.index(of: member) == nil {
            if let index = storage.index(of: member) { storage.remove(at: index) }
        }
    }

    @ObjCMethod("unionOrderedSet:")
    func union(_ other: ObjCObject) { OrderedSets.storage(other.id).members.forEach { storage.append($0) } }

    @ObjCMethod("minusOrderedSet:")
    func minus(_ other: ObjCObject) { remove(objectsIn: ObjCObject(Arrays.autoreleased(OrderedSets.storage(other.id).members))) }
}

// MARK: - Counted sets

/// Each counted set's counts, by its object; members not here count once.
enum CountedSets {
    nonisolated(unsafe) static var setClass: Class!
    nonisolated(unsafe) private static let lock = LockStorage(recursive: true)
    nonisolated(unsafe) private static var counts: [UnsafeMutableRawPointer: [ObjectKey: Int]] = [:]

    static func withCounts<T>(_ set: id, _ body: (inout [ObjectKey: Int]) -> T) -> T {
        pthread_mutex_lock(lock.mutex)
        defer { pthread_mutex_unlock(lock.mutex) }
        var table = counts[set] ?? [:]
        let result = body(&table)
        counts[set] = table
        return result
    }

    static func forget(_ set: id) {
        pthread_mutex_lock(lock.mutex)
        counts[set] = nil
        pthread_mutex_unlock(lock.mutex)
    }

    static func make(_ cls: id, _ members: [id]) -> id? {
        guard let object = Sets.initialize(Storage.allocate(cls), []) else { return nil }
        for member in members { add(object, member) }
        return object
    }

    static func add(_ set: id, _ object: id) {
        let storage = Sets.storage(set)
        let present = storage?.member(object)
        storage?.add(object)
        withCounts(set) { counts in
            let key = ObjectKey(object: present ?? object)
            counts[key] = (counts[key] ?? (present == nil ? 0 : 1)) + 1
        }
    }
}

/// NSCountedSet.
@ObjCClass("NSCountedSet")
public final class NSCountedSet: NSMutableSet {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        CountedSets.setClass = cls.storage
    }

    @ObjCMethod("dealloc")
    func deallocCounted() {
        CountedSets.forget(objcObject)
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: CountedSets.setClass)
    }

    @ObjCClassMethod("set")
    static func emptyCounted(_ cls: ObjCClass) -> UnsafeMutableRawPointer? { ObjC.autorelease(CountedSets.make(cls.pointer, [])) }

    @ObjCClassMethod("setWithArray:")
    static func counted(_ cls: ObjCClass, array: ObjCObject) -> UnsafeMutableRawPointer? {
        ObjC.autorelease(CountedSets.make(cls.pointer, Arrays.elements(array.id)))
    }

    @ObjCMethod("initWithArray:")
    func initializeCounted(array: ObjCObject?) -> Self {
        _ = Sets.initialize(objcObject, [])
        Arrays.elements(array?.id).forEach { CountedSets.add(objcObject, $0) }
        return self
    }

    @ObjCMethod("initWithSet:")
    func initializeCounted(set: ObjCObject?) -> Self {
        _ = Sets.initialize(objcObject, [])
        Sets.elements(set?.id).forEach { CountedSets.add(objcObject, $0) }
        return self
    }

    @ObjCMethod("initWithCapacity:")
    func initializeCounted(capacity: UInt) -> Self {
        _ = Sets.initialize(objcObject, [])
        return self
    }

    @ObjCMethod("addObject:") func addCounted(_ object: ObjCObject) { CountedSets.add(objcObject, object.id) }

    @ObjCMethod("removeObject:")
    func removeCounted(_ object: ObjCObject?) {
        guard let object, let storage = Sets.storage(objcObject), let member = storage.member(object.id) else { return }
        let remaining = CountedSets.withCounts(objcObject) { counts -> Int in
            let key = ObjectKey(object: member)
            let left = (counts[key] ?? 1) - 1
            counts[key] = left > 0 ? left : nil
            return left
        }
        if remaining <= 0 { storage.remove(member) }
    }

    @ObjCMethod("removeAllObjects")
    func removeAllCounted() {
        Sets.storage(objcObject)?.removeAll()
        CountedSets.withCounts(objcObject) { $0 = [:] }
    }

    @ObjCMethod("countForObject:")
    func count(for object: ObjCObject?) -> UInt {
        guard let object, let member = Sets.storage(objcObject)?.member(object.id) else { return 0 }
        return UInt(CountedSets.withCounts(objcObject) { $0[ObjectKey(object: member)] ?? 1 })
    }
}

// MARK: - Caches

final class CacheStorage {
    struct Entry {
        let key: id
        let value: id
        let cost: Int
    }

    let lock = LockStorage(recursive: true)
    /// Least recently used first.
    var entries: [Entry] = []
    var name: id?
    var delegate: id?
    var countLimit = 0
    var totalCostLimit = 0
    var evictsDiscarded = true

    deinit {
        entries.forEach {
            ObjC.release($0.key)
            ObjC.release($0.value)
        }
        ObjC.release(name)
    }

    func locked<T>(_ body: () -> T) -> T {
        pthread_mutex_lock(lock.mutex)
        defer { pthread_mutex_unlock(lock.mutex) }
        return body()
    }

    func position(of key: id) -> Int? {
        entries.firstIndex { $0.key == key || ObjC.sendBool($0.key, Selectors.isEqual, key) }
    }

    /// Evicts the least recently used entries over the limits, telling the
    /// delegate (cache:willEvictObject:).
    func evict(_ cache: id) {
        while (countLimit > 0 && entries.count > countLimit)
                || (totalCostLimit > 0 && entries.reduce(0, { $0 + $1.cost }) > totalCostLimit && entries.count > 0) {
            let entry = entries.removeFirst()
            if let delegate, ObjC.sendBool(delegate, ObjC.selector("respondsToSelector:"),
                                           UnsafeMutableRawPointer(mutating: ObjC.selector("cache:willEvictObject:"))) {
                _ = ObjC.send(delegate, ObjC.selector("cache:willEvictObject:"), cache, entry.value)
            }
            ObjC.release(entry.key)
            ObjC.release(entry.value)
        }
    }
}

enum Caches {
    nonisolated(unsafe) static var cacheClass: Class!
}

/// NSCache: least-recently-used eviction by count and cost.
@ObjCClass("NSCache")
public final class NSCache: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        Caches.cacheClass = cls.storage
    }

    var storage: CacheStorage {
        if let storage = Storage.get(objcObject, as: CacheStorage.self) { return storage }
        let storage = CacheStorage()
        Storage.set(objcObject, storage)
        return storage
    }

    @ObjCMethod("init")
    func initialize() -> Self {
        _ = storage
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: Caches.cacheClass)
    }

    @ObjCMethod("objectForKey:")
    func object(forKey key: ObjCObject) -> UnsafeMutableRawPointer? {
        let storage = self.storage
        return storage.locked {
            guard let position = storage.position(of: key.id) else { return nil }
            let entry = storage.entries.remove(at: position)
            storage.entries.append(entry)
            return ObjC.autorelease(ObjC.retain(entry.value))
        }
    }

    @ObjCMethod("setObject:forKey:cost:")
    func set(_ value: ObjCObject, forKey key: ObjCObject, cost: UInt) {
        let storage = self.storage
        storage.locked {
            if let position = storage.position(of: key.id) {
                let old = storage.entries.remove(at: position)
                ObjC.release(old.key)
                ObjC.release(old.value)
            }
            let copiedKey = ObjC.retain(key.id)!
            storage.entries.append(CacheStorage.Entry(key: copiedKey, value: ObjC.retain(value.id)!, cost: Int(cost)))
            storage.evict(objcObject)
        }
    }

    @ObjCMethod("setObject:forKey:")
    func set(_ value: ObjCObject, forKey key: ObjCObject) { set(value, forKey: key, cost: 0) }

    @ObjCMethod("removeObjectForKey:")
    func removeObject(forKey key: ObjCObject) {
        let storage = self.storage
        storage.locked {
            guard let position = storage.position(of: key.id) else { return }
            let old = storage.entries.remove(at: position)
            ObjC.release(old.key)
            ObjC.release(old.value)
        }
    }

    @ObjCMethod("removeAllObjects")
    func removeAllObjects() {
        let storage = self.storage
        storage.locked {
            storage.entries.forEach {
                ObjC.release($0.key)
                ObjC.release($0.value)
            }
            storage.entries = []
        }
    }

    @ObjCMethod("name") func name() -> UnsafeMutableRawPointer? { storage.name ?? Strings.autoreleased("") }

    @ObjCMethod("setName:")
    func setName(_ name: ObjCObject?) {
        let copy = name.flatMap { ObjC.send($0.id, Selectors.copyWithZone, nil) }
        ObjC.release(storage.name)
        storage.name = copy
    }

    /// The delegate is not retained.
    @ObjCMethod("delegate") func delegate() -> UnsafeMutableRawPointer? { storage.delegate }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: ObjCObject?) { storage.delegate = delegate?.id }
    @ObjCMethod("countLimit") func countLimit() -> UInt { UInt(storage.countLimit) }

    @ObjCMethod("setCountLimit:")
    func setCountLimit(_ limit: UInt) {
        storage.locked {
            storage.countLimit = Int(limit)
            storage.evict(objcObject)
        }
    }

    @ObjCMethod("totalCostLimit") func totalCostLimit() -> UInt { UInt(storage.totalCostLimit) }

    @ObjCMethod("setTotalCostLimit:")
    func setTotalCostLimit(_ limit: UInt) {
        storage.locked {
            storage.totalCostLimit = Int(limit)
            storage.evict(objcObject)
        }
    }

    @ObjCMethod("evictsObjectsWithDiscardedContent") func evictsDiscarded() -> Bool { storage.evictsDiscarded }
    @ObjCMethod("setEvictsObjectsWithDiscardedContent:") func setEvictsDiscarded(_ value: Bool) { storage.evictsDiscarded = value }
}

/// + (id)orderedSetWithObjects:(id)first, ... nil
@c
public func perry_foundation_orderedSetWithObjects(_ cls: id?, _ cmd: SEL?, _ first: id?, _ arguments: UnsafeRawPointer?) -> id? {
    guard let cls else { return nil }
    return OrderedSets.make(cls, nilTerminated(first, arguments))
}

/// - (id)initWithObjects:(id)first, ... nil
@c
public func perry_foundation_initOrderedSetWithObjects(_ object: id?, _ cmd: SEL?, _ first: id?, _ arguments: UnsafeRawPointer?) -> id? {
    guard let object else { return nil }
    Storage.set(object, OrderedSetStorage(nilTerminated(first, arguments)))
    return object
}
