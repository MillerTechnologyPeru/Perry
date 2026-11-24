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

    /// The members made `replacement`, in its order, the first of equal
    /// ones kept; the new ones are retained before the old ones go.
    func setMembers(_ replacement: [id]) {
        let old = members
        var seen: Set<ObjectKey> = []
        members = replacement.filter { seen.insert(ObjectKey(object: $0)).inserted }.map { ObjC.retain($0)! }
        reindex()
        old.forEach { ObjC.release($0) }
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

    /// The members in a range, which must lie within them.
    static func slice(_ members: [id], _ range: NSRange, _ method: String) -> [id] {
        guard Int(range.location + range.length) <= members.count else {
            foundationFatal("\(method): range {\(range.location), \(range.length)} extends beyond bounds [0 .. \(members.count - 1)]")
        }
        return Array(members[Int(range.location)..<Int(range.location + range.length)])
    }

    /// The members, or with `copyItems` each one's -copy (+1, for the caller
    /// to release once stored).
    static func copies(_ members: [id], _ copyItems: Bool) -> [id] {
        copyItems ? members.map { ObjC.send($0, Selectors.copyWithZone, nil) ?? ObjC.retain($0)! } : members
    }

    /// A new ordered set of `cls`, autoreleased, of the members or their copies.
    static func make(_ cls: id, _ members: [id], copyItems: Bool) -> id? {
        let stored = copies(members, copyItems)
        defer { if copyItems { stored.forEach { ObjC.release($0) } } }
        return make(cls, stored)
    }

    /// Fills an allocated ordered set with the members or their copies.
    static func fill(_ object: id, _ members: [id], copyItems: Bool = false) {
        let stored = copies(members, copyItems)
        Storage.set(object, OrderedSetStorage(stored))
        if copyItems { stored.forEach { ObjC.release($0) } }
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

    /// Like the other collections' constructors, these take nil for no members.
    @ObjCClassMethod("orderedSetWithArray:")
    static func make(_ cls: ObjCClass, array: ObjCObject?) -> UnsafeMutableRawPointer? {
        OrderedSets.make(cls.pointer, Arrays.elements(array?.id))
    }

    @ObjCClassMethod("orderedSetWithSet:")
    static func make(_ cls: ObjCClass, set: ObjCObject?) -> UnsafeMutableRawPointer? {
        OrderedSets.make(cls.pointer, set.map { Sets.elements($0.id) } ?? [])
    }

    @ObjCClassMethod("orderedSetWithOrderedSet:")
    static func make(_ cls: ObjCClass, orderedSet: ObjCObject?) -> UnsafeMutableRawPointer? {
        OrderedSets.make(cls.pointer, OrderedSets.storage(orderedSet?.id).members)
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

    /// The members of a range of an array, copied with `copyItems`.
    @ObjCClassMethod("orderedSetWithArray:range:copyItems:")
    static func make(_ cls: ObjCClass, array: ObjCObject?, range: NSRange, copyItems: Bool) -> UnsafeMutableRawPointer? {
        let members = OrderedSets.slice(Arrays.elements(array?.id), range, "+[NSOrderedSet orderedSetWithArray:range:copyItems:]")
        return OrderedSets.make(cls.pointer, members, copyItems: copyItems)
    }

    @ObjCClassMethod("orderedSetWithObjects:count:")
    static func make(_ cls: ObjCClass, objects: UnsafePointer<id?>?, count: UInt) -> UnsafeMutableRawPointer? {
        OrderedSets.make(cls.pointer, Arrays.objects(objects, count: count, method: "+[NSOrderedSet orderedSetWithObjects:count:]"))
    }

    @ObjCClassMethod("orderedSetWithSet:copyItems:")
    static func make(_ cls: ObjCClass, set: ObjCObject?, copyItems: Bool) -> UnsafeMutableRawPointer? {
        OrderedSets.make(cls.pointer, Sets.elements(set?.id), copyItems: copyItems)
    }

    @ObjCMethod("init")
    func initialize() -> Self {
        Storage.set(objcObject, OrderedSetStorage())
        return self
    }

    @ObjCMethod("initWithObject:")
    func initialize(object: ObjCObject) -> Self {
        OrderedSets.fill(objcObject, [object.id])
        return self
    }

    @ObjCMethod("initWithObjects:count:")
    func initialize(objects: UnsafePointer<id?>?, count: UInt) -> Self {
        OrderedSets.fill(objcObject, Arrays.objects(objects, count: count, method: "-[NSOrderedSet initWithObjects:count:]"))
        return self
    }

    @ObjCMethod("initWithCoder:")
    func initialize(coder: ObjCObject?) -> Self {
        OrderedSets.fill(objcObject, CollectionCoding.objects(coder?.id))
        return self
    }

    @ObjCMethod("initWithArray:copyItems:")
    func initialize(array: ObjCObject?, copyItems: Bool) -> Self {
        OrderedSets.fill(objcObject, Arrays.elements(array?.id), copyItems: copyItems)
        return self
    }

    @ObjCMethod("initWithArray:range:copyItems:")
    func initialize(array: ObjCObject?, range: NSRange, copyItems: Bool) -> Self {
        let members = OrderedSets.slice(Arrays.elements(array?.id), range, "-[NSOrderedSet initWithArray:range:copyItems:]")
        OrderedSets.fill(objcObject, members, copyItems: copyItems)
        return self
    }

    @ObjCMethod("initWithOrderedSet:copyItems:")
    func initialize(orderedSet other: ObjCObject?, copyItems: Bool) -> Self {
        OrderedSets.fill(objcObject, OrderedSets.storage(other?.id).members, copyItems: copyItems)
        return self
    }

    @ObjCMethod("initWithOrderedSet:range:copyItems:")
    func initialize(orderedSet other: ObjCObject?, range: NSRange, copyItems: Bool) -> Self {
        let members = OrderedSets.slice(OrderedSets.storage(other?.id).members, range, "-[NSOrderedSet initWithOrderedSet:range:copyItems:]")
        OrderedSets.fill(objcObject, members, copyItems: copyItems)
        return self
    }

    @ObjCMethod("initWithSet:copyItems:")
    func initialize(set: ObjCObject?, copyItems: Bool) -> Self {
        OrderedSets.fill(objcObject, Sets.elements(set?.id), copyItems: copyItems)
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

    /// The set's members, in the order it enumerates them.
    @ObjCMethod("initWithSet:")
    func initialize(set: ObjCObject?) -> Self {
        Storage.set(objcObject, OrderedSetStorage(Sets.elements(set?.id)))
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

    @ObjCMethod("isSubsetOfOrderedSet:")
    func isSubset(ofOrderedSet other: ObjCObject?) -> Bool {
        guard let other else { return storage.members.isEmpty }
        let theirs = OrderedSets.storage(other.id)
        return storage.members.allSatisfy { theirs.index(of: $0) != nil }
    }

    @ObjCMethod("intersectsOrderedSet:")
    func intersects(orderedSet other: ObjCObject?) -> Bool {
        guard let other else { return false }
        let theirs = OrderedSets.storage(other.id)
        return storage.members.contains { theirs.index(of: $0) != nil }
    }

    @ObjCMethod("isSubsetOfSet:")
    func isSubset(ofSet other: ObjCObject?) -> Bool {
        guard let other else { return storage.members.isEmpty }
        let contains = ObjC.selector("containsObject:")
        return storage.members.allSatisfy { ObjC.sendBool(other.id, contains, $0) }
    }

    @ObjCMethod("intersectsSet:")
    func intersects(set other: ObjCObject?) -> Bool {
        guard let other else { return false }
        let contains = ObjC.selector("containsObject:")
        return storage.members.contains { ObjC.sendBool(other.id, contains, $0) }
    }

    /// The first index whose member passes, or NSNotFound.
    @ObjCMethod("indexOfObjectPassingTest:")
    func index(ofObjectPassingTest block: ObjCObject) -> UInt {
        index(options: 0, ofObjectPassingTest: block)
    }

    /// NSEnumerationOptions: reverse 2 searches from the end; concurrent
    /// searching is done in order.
    @ObjCMethod("indexOfObjectWithOptions:passingTest:")
    func index(options: UInt, ofObjectPassingTest block: ObjCObject) -> UInt {
        typealias Invoke = @convention(c) (id, id, UInt, UnsafeMutablePointer<Bool>) -> Bool
        let invoke = Blocks.invoke(block.id, as: Invoke.self)
        let members = storage.members
        let order = options & 2 != 0 ? Array(members.indices.reversed()) : Array(members.indices)
        for index in order {
            var stop = false
            if invoke(block.id, members[index], UInt(index), &stop) { return UInt(index) }
            if stop { break }
        }
        return notFound
    }

    /// "{(" and ")}" around the members, quoted and indented as an array's.
    @ObjCMethod("description")
    func description() -> String { Describe.list(storage.members, open: "{(", close: ")}", indent: 0) }

    @ObjCMethod("descriptionWithLocale:")
    func description(withLocale locale: ObjCObject?) -> String { description() }

    @ObjCMethod("descriptionWithLocale:indent:")
    func description(withLocale locale: ObjCObject?, indent: UInt) -> String {
        Describe.list(storage.members, open: "{(", close: ")}", indent: Int(indent))
    }

    @ObjCMethod("getObjects:range:")
    func getObjects(_ buffer: UnsafeMutablePointer<UnsafeMutableRawPointer?>?, range: NSRange) {
        let members = OrderedSets.slice(storage.members, range, "-[NSOrderedSet getObjects:range:]")
        guard let buffer else { return }
        for (offset, member) in members.enumerated() { buffer[offset] = member }
    }

    @ObjCMethod("objectEnumerator") func objectEnumerator() -> ObjCObject { Enumerators.make(storage.members) }
    @ObjCMethod("reverseObjectEnumerator") func reverseObjectEnumerator() -> ObjCObject { Enumerators.make(storage.members.reversed()) }

    // MARK: Enumerating and searching

    private func enumerate(_ indexes: [Int], options: UInt, block: ObjCObject) {
        typealias Invoke = @convention(c) (id, id, UInt, UnsafeMutablePointer<Bool>) -> Void
        let invoke = Blocks.invoke(block.id, as: Invoke.self)
        let members = storage.members
        for index in options & 2 != 0 ? indexes.reversed() : indexes {
            OrderedSets.check(UInt(index), members.count, "enumerateObjectsAtIndexes:options:usingBlock:")
            var stop = false
            invoke(block.id, members[index], UInt(index), &stop)
            if stop { return }
        }
    }

    /// NSEnumerationReverse (2) runs from the last; concurrent runs in order.
    @ObjCMethod("enumerateObjectsWithOptions:usingBlock:")
    func enumerateObjects(options: UInt, using block: ObjCObject) { enumerate(Array(storage.members.indices), options: options, block: block) }

    @ObjCMethod("enumerateObjectsAtIndexes:options:usingBlock:")
    func enumerateObjects(atIndexes indexes: ObjCObject, options: UInt, using block: ObjCObject) {
        enumerate(IndexSets.storage(indexes.id).indexes, options: options, block: block)
    }

    @ObjCMethod("indexesOfObjectsPassingTest:")
    func indexes(ofObjectsPassingTest block: ObjCObject) -> UnsafeMutableRawPointer? {
        indexes(options: 0, ofObjectsPassingTest: block)
    }

    @ObjCMethod("indexesOfObjectsWithOptions:passingTest:")
    func indexes(options: UInt, ofObjectsPassingTest block: ObjCObject) -> UnsafeMutableRawPointer? {
        Arrays.indexSet(Arrays.passing(storage.members, nil, options: options, block: block.id, first: false,
                                       method: "-[NSOrderedSet indexesOfObjectsWithOptions:passingTest:]"))
    }

    @ObjCMethod("indexesOfObjectsAtIndexes:options:passingTest:")
    func indexes(atIndexes indexes: ObjCObject, options: UInt, passingTest block: ObjCObject) -> UnsafeMutableRawPointer? {
        Arrays.indexSet(Arrays.passing(storage.members, IndexSets.storage(indexes.id).indexes, options: options, block: block.id,
                                       first: false, method: "-[NSOrderedSet indexesOfObjectsAtIndexes:options:passingTest:]"))
    }

    @ObjCMethod("indexOfObjectAtIndexes:options:passingTest:")
    func index(atIndexes indexes: ObjCObject, options: UInt, passingTest block: ObjCObject) -> UInt {
        Arrays.passing(storage.members, IndexSets.storage(indexes.id).indexes, options: options, block: block.id, first: true,
                       method: "-[NSOrderedSet indexOfObjectAtIndexes:options:passingTest:]").first.map { UInt($0) } ?? notFound
    }

    /// A binary search of the range, as NSArray's.
    @ObjCMethod("indexOfObject:inSortedRange:options:usingComparator:")
    func index(of target: ObjCObject?, inSortedRange range: NSRange, options: UInt, comparator: ObjCBlock) -> UInt {
        Arrays.search(storage.members, for: target?.id, in: range, options: options, comparator: comparator)
    }

    // MARK: Deriving

    @ObjCMethod("filteredOrderedSetUsingPredicate:")
    func filtered(using predicate: NSPredicate) -> UnsafeMutableRawPointer? {
        OrderedSets.make(UnsafeMutableRawPointer(OrderedSets.setClass), storage.members.filter { predicate.evaluate(with: ObjCObject($0)) })
    }

    @ObjCMethod("sortedArrayUsingComparator:")
    func sortedArray(comparator: ObjCBlock) -> ObjCObject {
        let compare = comparator.function(as: (@convention(c) (id, id?, id?) -> Int).self)
        return ObjCObject(Arrays.autoreleased(storage.members.sorted { compare(comparator.object, $0, $1) < 0 }))
    }

    /// NSSortOptions only tune the sort, which is stable.
    @ObjCMethod("sortedArrayWithOptions:usingComparator:")
    func sortedArray(options: UInt, comparator: ObjCBlock) -> ObjCObject { sortedArray(comparator: comparator) }

    @ObjCMethod("sortedArrayUsingDescriptors:")
    func sortedArray(usingDescriptors descriptors: ObjCObject?) -> ObjCObject {
        ObjCObject(Arrays.autoreleased(SortDescriptors.sorted(storage.members, by: descriptors?.objcObject)))
    }

    // MARK: Differences

    @ObjCMethod("differenceFromOrderedSet:withOptions:usingEquivalenceTest:")
    func difference(from other: ObjCObject?, options: UInt, test: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        let old = OrderedSets.storage(other?.id).members
        guard let test else {
            return OrderedDifferences.difference(from: old, to: storage.members, options: options) { ObjectKey(object: $0) == ObjectKey(object: $1) }
        }
        let compare = Blocks.invoke(test, as: (@convention(c) (id, id?, id?) -> Bool).self)
        return OrderedDifferences.difference(from: old, to: storage.members, options: options) { compare(test, $0, $1) }
    }

    @ObjCMethod("differenceFromOrderedSet:withOptions:")
    func difference(from other: ObjCObject?, options: UInt) -> UnsafeMutableRawPointer? { difference(from: other, options: options, test: nil) }

    @ObjCMethod("differenceFromOrderedSet:")
    func difference(from other: ObjCObject?) -> UnsafeMutableRawPointer? { difference(from: other, options: 0, test: nil) }

    /// nil when the difference doesn't apply to the members.
    @ObjCMethod("orderedSetByApplyingDifference:")
    func applying(difference: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        NSOrderedCollectionDifference.apply(difference, to: storage.members).flatMap {
            OrderedSets.make(UnsafeMutableRawPointer(OrderedSets.setClass), $0)
        }
    }

    // MARK: Observing

    /// An ordered set can't be observed itself: these raise, as on Darwin.
    @ObjCMethod("addObserver:forKeyPath:options:context:")
    func rejectObserver(_ observer: ObjCObject?, forKeyPath keyPath: ObjCObject?, options: UInt, context: UnsafeMutableRawPointer?) {
        CollectionObserving.unsupported(objcObject, "addObserver:forKeyPath:options:context:", keyPath)
    }

    @ObjCMethod("removeObserver:forKeyPath:")
    func rejectRemoval(_ observer: ObjCObject?, forKeyPath keyPath: ObjCObject?) {
        CollectionObserving.unsupported(objcObject, "removeObserver:forKeyPath:", keyPath)
    }

    @ObjCMethod("removeObserver:forKeyPath:context:")
    func rejectRemoval(_ observer: ObjCObject?, forKeyPath keyPath: ObjCObject?, context: UnsafeMutableRawPointer?) {
        CollectionObserving.unsupported(objcObject, "removeObserver:forKeyPath:context:", keyPath)
    }
}

/// NSMutableOrderedSet.
@ObjCClass("NSMutableOrderedSet")
public final class NSMutableOrderedSet: NSOrderedSet {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        OrderedSets.mutableClass = cls.storage
    }

    @ObjCClassMethod("orderedSetWithCapacity:")
    static func make(_ cls: ObjCClass, capacity: UInt) -> UnsafeMutableRawPointer? { OrderedSets.make(cls.pointer, []) }

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
    func union(_ other: ObjCObject?) {
        guard let other else { return }
        OrderedSets.storage(other.id).members.forEach { storage.append($0) }
    }

    @ObjCMethod("unionSet:")
    func union(set other: ObjCObject?) { Sets.elements(other?.id).forEach { storage.append($0) } }

    @ObjCMethod("minusSet:")
    func minus(set other: ObjCObject?) {
        guard let other else { return }
        remove(objectsIn: ObjCObject(Arrays.autoreleased(Sets.elements(other.id))))
    }

    @ObjCMethod("minusOrderedSet:")
    func minus(_ other: ObjCObject) { remove(objectsIn: ObjCObject(Arrays.autoreleased(OrderedSets.storage(other.id).members))) }

    @ObjCMethod("addObjects:count:")
    func add(objects: UnsafePointer<id?>?, count: UInt) {
        Arrays.objects(objects, count: count, method: "-[NSMutableOrderedSet addObjects:count:]").forEach { storage.append($0) }
    }

    /// Keeps the members the set has.
    @ObjCMethod("intersectSet:")
    func intersect(set other: ObjCObject?) {
        let contains = ObjC.selector("containsObject:")
        storage.setMembers(storage.members.filter { member in other.map { ObjC.sendBool($0.id, contains, member) } ?? false })
    }

    @ObjCMethod("filterUsingPredicate:")
    func filter(using predicate: NSPredicate) {
        storage.setMembers(storage.members.filter { predicate.evaluate(with: ObjCObject($0)) })
    }

    /// Each object inserted at its index, in ascending order; an object
    /// already a member is left where it is.
    @ObjCMethod("insertObjects:atIndexes:")
    func insert(_ objects: ObjCObject?, atIndexes indexes: ObjCObject) {
        let added = Arrays.elements(objects?.id), positions = IndexSets.storage(indexes.id).indexes
        guard added.count == positions.count else {
            foundationFatal("-[NSMutableOrderedSet insertObjects:atIndexes:]: count of array (\(added.count)) differs from count of index set (\(positions.count))")
        }
        for (object, position) in zip(added, positions) {
            guard position <= storage.members.count else {
                foundationFatal("-[NSMutableOrderedSet insertObjects:atIndexes:]: index \(position) beyond bounds [0 .. \(storage.members.count)]")
            }
            storage.insert(object, at: position)
        }
    }

    @ObjCMethod("removeObjectsAtIndexes:")
    func remove(atIndexes indexes: ObjCObject) {
        let doomed = Set(IndexSets.storage(indexes.id).indexes)
        if let beyond = doomed.first(where: { $0 >= storage.members.count }) {
            OrderedSets.check(UInt(beyond), storage.members.count, "removeObjectsAtIndexes:")
        }
        storage.setMembers(storage.members.enumerated().filter { !doomed.contains($0.offset) }.map(\.element))
    }

    @ObjCMethod("removeObjectsInRange:")
    func remove(range: NSRange) {
        _ = OrderedSets.slice(storage.members, range, "-[NSMutableOrderedSet removeObjectsInRange:]")
        let start = Int(range.location), end = start + Int(range.length)
        storage.setMembers(storage.members.enumerated().filter { !(start..<end).contains($0.offset) }.map(\.element))
    }

    /// The members at the indexes taken out, then put back in their order
    /// at `index` of what remains.
    @ObjCMethod("moveObjectsAtIndexes:toIndex:")
    func move(atIndexes indexes: ObjCObject, to index: UInt) {
        let positions = Set(IndexSets.storage(indexes.id).indexes), members = storage.members
        if let beyond = positions.first(where: { $0 >= members.count }) {
            OrderedSets.check(UInt(beyond), members.count, "moveObjectsAtIndexes:toIndex:")
        }
        let moved = members.enumerated().filter { positions.contains($0.offset) }.map(\.element)
        var rest = members.enumerated().filter { !positions.contains($0.offset) }.map(\.element)
        guard Int(index) <= rest.count else {
            foundationFatal("-[NSMutableOrderedSet moveObjectsAtIndexes:toIndex:]: index \(index) beyond bounds [0 .. \(rest.count)]")
        }
        rest.insert(contentsOf: moved, at: Int(index))
        storage.setMembers(rest)
    }

    @ObjCMethod("replaceObjectsAtIndexes:withObjects:")
    func replace(atIndexes indexes: ObjCObject, withObjects objects: ObjCObject?) {
        let positions = IndexSets.storage(indexes.id).indexes, replacements = Arrays.elements(objects?.id)
        guard positions.count == replacements.count else {
            foundationFatal("-[NSMutableOrderedSet replaceObjectsAtIndexes:withObjects:]: count of array (\(replacements.count)) differs from count of index set (\(positions.count))")
        }
        for (position, replacement) in zip(positions, replacements) {
            OrderedSets.check(UInt(position), storage.members.count, "replaceObjectsAtIndexes:withObjects:")
            storage.replace(at: position, with: replacement)
        }
    }

    /// The range's members replaced by the C array's objects; an object
    /// equal to a member before the range is left out.
    @ObjCMethod("replaceObjectsInRange:withObjects:count:")
    func replace(range: NSRange, withObjects objects: UnsafePointer<id?>?, count: UInt) {
        _ = OrderedSets.slice(storage.members, range, "-[NSMutableOrderedSet replaceObjectsInRange:withObjects:count:]")
        let added = Arrays.objects(objects, count: count, method: "-[NSMutableOrderedSet replaceObjectsInRange:withObjects:count:]")
        let members = storage.members, start = Int(range.location), end = start + Int(range.length)
        storage.setMembers(Array(members[..<start]) + added + Array(members[end...]))
    }

    private func sort(_ range: Range<Int>, comparator: ObjCBlock) {
        let compare = comparator.function(as: (@convention(c) (id, id?, id?) -> Int).self)
        var members = storage.members
        members.replaceSubrange(range, with: members[range].sorted { compare(comparator.object, $0, $1) < 0 })
        storage.setMembers(members)
    }

    @ObjCMethod("sortUsingComparator:")
    func sort(comparator: ObjCBlock) { sort(0..<storage.members.count, comparator: comparator) }

    /// NSSortOptions only tune the sort, which is stable.
    @ObjCMethod("sortWithOptions:usingComparator:")
    func sort(options: UInt, comparator: ObjCBlock) { sort(comparator: comparator) }

    @ObjCMethod("sortRange:options:usingComparator:")
    func sort(range: NSRange, options: UInt, comparator: ObjCBlock) {
        _ = OrderedSets.slice(storage.members, range, "-[NSMutableOrderedSet sortRange:options:usingComparator:]")
        sort(IndexSets.range(range), comparator: comparator)
    }

    @ObjCMethod("sortUsingDescriptors:")
    func sort(usingDescriptors descriptors: ObjCObject?) {
        storage.setMembers(SortDescriptors.sorted(storage.members, by: descriptors?.objcObject))
    }

    /// The members made what the difference turns them into; unchanged if
    /// it doesn't apply to them.
    @ObjCMethod("applyDifference:")
    func apply(difference: UnsafeMutableRawPointer?) {
        guard let changed = NSOrderedCollectionDifference.apply(difference, to: storage.members) else { return }
        storage.setMembers(changed)
    }
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
    /// An entry, in a list from the least recently used to the most.
    struct Entry {
        let key: id
        let value: id
        let cost: Int
        let hash: UInt
        var previous: Int?
        var next: Int?
    }

    let lock = LockStorage(recursive: true)
    /// The entries by a number each gets when added.
    var entries: [Int: Entry] = [:]
    /// The entries' numbers by their keys' hashes, so a key is found
    /// without comparing it to every other.
    var buckets: [UInt: [Int]] = [:]
    /// The least and the most recently used.
    var first: Int?
    var last: Int?
    var nextNumber = 0
    var totalCost = 0
    var name: id?
    var delegate: id?
    var countLimit = 0
    var totalCostLimit = 0
    var evictsDiscarded = true

    deinit {
        entries.values.forEach {
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

    /// The number of the entry for a key equal to `key`.
    func position(of key: id) -> Int? {
        guard !entries.isEmpty, let candidates = buckets[ObjC.sendUInt(key, Selectors.hash)] else { return nil }
        return candidates.first { number in
            guard let other = entries[number]?.key else { return false }
            return other == key || ObjC.sendBool(other, Selectors.isEqual, key)
        }
    }

    private func unlink(_ number: Int) {
        guard let entry = entries[number] else { return }
        if let previous = entry.previous { entries[previous]?.next = entry.next } else { first = entry.next }
        if let next = entry.next { entries[next]?.previous = entry.previous } else { last = entry.previous }
    }

    private func link(_ number: Int) {
        entries[number]?.previous = last
        entries[number]?.next = nil
        if let last { entries[last]?.next = number } else { first = number }
        last = number
    }

    /// Makes the entry the most recently used.
    func touch(_ number: Int) {
        guard last != number else { return }
        unlink(number)
        link(number)
    }

    /// Adds an entry as the most recently used. The key and value are
    /// retained.
    func add(key: id, value: id, cost: Int) {
        let hash = ObjC.sendUInt(key, Selectors.hash), number = nextNumber
        nextNumber += 1
        entries[number] = Entry(key: ObjC.retain(key)!, value: ObjC.retain(value)!, cost: cost, hash: hash)
        buckets[hash, default: []].append(number)
        totalCost += cost
        link(number)
    }

    /// Takes the entry out; its key and value are the caller's to release.
    @discardableResult
    func remove(_ number: Int) -> Entry? {
        unlink(number)
        guard let entry = entries.removeValue(forKey: number) else { return nil }
        if var bucket = buckets[entry.hash] {
            bucket.removeAll { $0 == number }
            buckets[entry.hash] = bucket.isEmpty ? nil : bucket
        }
        totalCost -= entry.cost
        return entry
    }

    func removeAll() {
        entries.values.forEach {
            ObjC.release($0.key)
            ObjC.release($0.value)
        }
        entries = [:]
        buckets = [:]
        first = nil
        last = nil
        totalCost = 0
    }

    /// Evicts the least recently used entries over the limits, telling the
    /// delegate (cache:willEvictObject:).
    func evict(_ cache: id) {
        while (countLimit > 0 && entries.count > countLimit) || (totalCostLimit > 0 && totalCost > totalCostLimit),
              let first, let entry = remove(first) {
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
            guard let position = storage.position(of: key.id), let entry = storage.entries[position] else { return nil }
            storage.touch(position)
            return ObjC.autorelease(ObjC.retain(entry.value))
        }
    }

    @ObjCMethod("setObject:forKey:cost:")
    func set(_ value: ObjCObject, forKey key: ObjCObject, cost: UInt) {
        let storage = self.storage
        storage.locked {
            // The new entry is in before the old one's objects go, which
            // may be the same ones.
            let old = storage.position(of: key.id).flatMap { storage.remove($0) }
            storage.add(key: key.id, value: value.id, cost: Int(clamping: cost))
            if let old {
                ObjC.release(old.key)
                ObjC.release(old.value)
            }
            storage.evict(objcObject)
        }
    }

    @ObjCMethod("setObject:forKey:")
    func set(_ value: ObjCObject, forKey key: ObjCObject) { set(value, forKey: key, cost: 0) }

    @ObjCMethod("removeObjectForKey:")
    func removeObject(forKey key: ObjCObject) {
        let storage = self.storage
        storage.locked {
            guard let position = storage.position(of: key.id), let old = storage.remove(position) else { return }
            ObjC.release(old.key)
            ObjC.release(old.value)
        }
    }

    @ObjCMethod("removeAllObjects")
    func removeAllObjects() {
        let storage = self.storage
        storage.locked { storage.removeAll() }
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
            // NSUIntegerMax, which apps set for no limit, doesn't fit an Int.
            storage.countLimit = Int(clamping: limit)
            storage.evict(objcObject)
        }
    }

    @ObjCMethod("totalCostLimit") func totalCostLimit() -> UInt { UInt(storage.totalCostLimit) }

    @ObjCMethod("setTotalCostLimit:")
    func setTotalCostLimit(_ limit: UInt) {
        storage.locked {
            storage.totalCostLimit = Int(clamping: limit)
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
