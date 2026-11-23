import CPerryFoundation
import FoundationEssentials
import PerryObjCInterop

// CFBag: a multiset of the program's pointers, retained, released, compared
// and hashed by its callbacks, as CFSet's are. As on Darwin, each distinct
// value is kept, and retained, once, with how many times it was added, and
// released when the last of it is removed.

final class BagStorage {
    var entries: [(value: CFValue, count: Int)] = []
    let callbacks: CFCallbacks
    let callbacksPointer: UnsafeRawPointer?

    init(callbacks pointer: UnsafeRawPointer?) {
        callbacksPointer = pointer
        callbacks = CFCallbacks(pointer, hashed: true)
    }

    deinit {
        entries.forEach { callbacks.released($0.value) }
    }

    func index(of value: CFValue) -> Int? { entries.firstIndex { callbacks.isEqual($0.value, value) } }

    var count: Int { entries.reduce(0) { $0 + $1.count } }

    /// Every value, once for each time it was added.
    var values: [CFValue] { entries.flatMap { Array(repeating: $0.value, count: $0.count) } }

    func add(_ value: CFValue) {
        if let index = index(of: value) {
            entries[index].count += 1
        } else {
            entries.append((callbacks.retained(value), 1))
        }
    }

    /// The value found equal to `value` becomes `value`.
    func replace(_ value: CFValue, at index: Int) {
        let old = entries[index].value
        entries[index].value = callbacks.retained(value)
        callbacks.released(old)
    }
}

enum Bags {
    nonisolated(unsafe) static var bagClass: Class!

    static func storage(_ bag: id?) -> BagStorage? { Storage.get(bag, as: BagStorage.self) }

    /// A new bag (+1) of these values.
    static func make(_ callbacks: UnsafeRawPointer?, _ values: [CFValue]) -> id? {
        guard let object = Storage.allocate(UnsafeMutableRawPointer(bagClass)) else { return nil }
        let storage = BagStorage(callbacks: callbacks)
        Storage.set(object, storage)
        values.forEach(storage.add)
        return object
    }
}

@ObjCClass("__NSCFBag")
final class NSCFBag: NSObject {
    override class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        Bags.bagClass = cls.storage
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: Bags.bagClass)
    }

    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { 4 }

    /// Equal bags hold equal values as many times each.
    @ObjCMethod("isEqual:")
    func isEqual(_ other: UnsafeMutableRawPointer?) -> Bool {
        guard let other, other != objcObject else { return other == objcObject }
        guard let mine = Bags.storage(objcObject), let theirs = Bags.storage(other),
              mine.entries.count == theirs.entries.count else { return false }
        return mine.entries.allSatisfy { entry in theirs.index(of: entry.value).map { theirs.entries[$0].count == entry.count } ?? false }
    }

    @ObjCMethod("hash") func hash() -> UInt { UInt(Bags.storage(objcObject)?.count ?? 0) }

    @ObjCMethod("count") func count() -> UInt { UInt(Bags.storage(objcObject)?.count ?? 0) }
}

@c(_CFBagGetTypeID) public func CFBagGetTypeID() -> UInt { 4 }

@c(_CFBagCreate)
public func CFBagCreate(_ allocator: UnsafeRawPointer?, _ values: UnsafePointer<CFValue>?, _ count: Int,
                        _ callbacks: UnsafeRawPointer?) -> id? {
    Bags.make(callbacks, values.map { Array(UnsafeBufferPointer(start: $0, count: max(count, 0))) } ?? [])
}

@c(_CFBagCreateMutable)
public func CFBagCreateMutable(_ allocator: UnsafeRawPointer?, _ capacity: Int, _ callbacks: UnsafeRawPointer?) -> id? {
    Bags.make(callbacks, [])
}

@c(_CFBagCreateCopy)
public func CFBagCreateCopy(_ allocator: UnsafeRawPointer?, _ bag: id?) -> id? {
    guard let storage = Bags.storage(bag) else { return nil }
    return Bags.make(storage.callbacksPointer, storage.values)
}

@c(_CFBagCreateMutableCopy)
public func CFBagCreateMutableCopy(_ allocator: UnsafeRawPointer?, _ capacity: Int, _ bag: id?) -> id? {
    CFBagCreateCopy(allocator, bag)
}

@c(_CFBagGetCount) public func CFBagGetCount(_ bag: id?) -> Int { Bags.storage(bag)?.count ?? 0 }

@c(_CFBagGetCountOfValue)
public func CFBagGetCountOfValue(_ bag: id?, _ value: CFValue) -> Int {
    guard let storage = Bags.storage(bag), let index = storage.index(of: value) else { return 0 }
    return storage.entries[index].count
}

@c(_CFBagContainsValue)
public func CFBagContainsValue(_ bag: id?, _ value: CFValue) -> Bool { Bags.storage(bag)?.index(of: value) != nil }

/// The value in the bag equal to `value`; nil when there's none.
@c(_CFBagGetValue)
public func CFBagGetValue(_ bag: id?, _ value: CFValue) -> CFValue {
    guard let storage = Bags.storage(bag), let index = storage.index(of: value) else { return nil }
    return storage.entries[index].value
}

@c(_CFBagGetValueIfPresent)
public func CFBagGetValueIfPresent(_ bag: id?, _ candidate: CFValue, _ value: UnsafeMutablePointer<CFValue>?) -> Bool {
    guard let storage = Bags.storage(bag), let index = storage.index(of: candidate) else { return false }
    value?.pointee = storage.entries[index].value
    return true
}

/// Every value, once for each time it's in the bag.
@c(_CFBagGetValues)
public func CFBagGetValues(_ bag: id?, _ values: UnsafeMutablePointer<CFValue>?) {
    guard let values, let all = Bags.storage(bag)?.values else { return }
    for (index, value) in all.enumerated() { values[index] = value }
}

@c(_CFBagApplyFunction)
public func CFBagApplyFunction(_ bag: id?, _ applier: (@convention(c) (CFValue, UnsafeMutableRawPointer?) -> Void)?,
                               _ context: UnsafeMutableRawPointer?) {
    guard let applier, let all = Bags.storage(bag)?.values else { return }
    all.forEach { applier($0, context) }
}

@c(_CFBagAddValue) public func CFBagAddValue(_ bag: id?, _ value: CFValue) { Bags.storage(bag)?.add(value) }

/// Replaces the value equal to `value`, if there is one.
@c(_CFBagReplaceValue)
public func CFBagReplaceValue(_ bag: id?, _ value: CFValue) {
    guard let storage = Bags.storage(bag), let index = storage.index(of: value) else { return }
    storage.replace(value, at: index)
}

/// Replaces the value equal to `value`, or adds it.
@c(_CFBagSetValue)
public func CFBagSetValue(_ bag: id?, _ value: CFValue) {
    guard let storage = Bags.storage(bag) else { return }
    if let index = storage.index(of: value) { storage.replace(value, at: index) } else { storage.add(value) }
}

/// Removes `value` once.
@c(_CFBagRemoveValue)
public func CFBagRemoveValue(_ bag: id?, _ value: CFValue) {
    guard let storage = Bags.storage(bag), let index = storage.index(of: value) else { return }
    storage.entries[index].count -= 1
    guard storage.entries[index].count == 0 else { return }
    storage.callbacks.released(storage.entries.remove(at: index).value)
}

@c(_CFBagRemoveAllValues)
public func CFBagRemoveAllValues(_ bag: id?) {
    guard let storage = Bags.storage(bag) else { return }
    let old = storage.entries
    storage.entries = []
    old.forEach { storage.callbacks.released($0.value) }
}
