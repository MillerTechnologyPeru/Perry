import CPerryFoundation
import FoundationEssentials
import PerryObjCInterop

// CFBinaryHeap: a priority queue of the program's pointers, ordered by its
// callbacks' compare function, smallest first, and retained and released
// by them. It's kept sorted, so its values come out in order.

/// CFBinaryHeapCallBacks: { version, retain, release, copyDescription,
/// compare }, compare where a collection's equal is.
struct HeapCallbacks {
    typealias Compare = @convention(c) (UnsafeRawPointer?, UnsafeRawPointer?, UnsafeMutableRawPointer?) -> Int

    var retain: CFCallbacks.Retain?
    var release: CFCallbacks.Release?
    var compare: Compare?

    init(_ pointer: UnsafeRawPointer?) {
        guard let pointer else { return }
        retain = pointer.load(fromByteOffset: DarwinLayout.callbackRetain, as: CFCallbacks.Retain?.self)
        release = pointer.load(fromByteOffset: DarwinLayout.callbackRelease, as: CFCallbacks.Release?.self)
        compare = pointer.load(fromByteOffset: DarwinLayout.callbackEqual, as: Compare?.self)
    }
}

/// CFBinaryHeapCompareContext: { version, info, retain, release,
/// copyDescription }; its info goes to the compare function.
struct HeapContext {
    typealias Retain = @convention(c) (UnsafeRawPointer?) -> UnsafeRawPointer?
    typealias Release = @convention(c) (UnsafeRawPointer?) -> Void

    var info: UnsafeMutableRawPointer?
    var retain: Retain?
    var release: Release?

    init(_ pointer: UnsafeRawPointer?) {
        guard let pointer else { return }
        info = pointer.load(fromByteOffset: DarwinLayout.word, as: UnsafeMutableRawPointer?.self)
        retain = pointer.load(fromByteOffset: 2 * DarwinLayout.word, as: Retain?.self)
        release = pointer.load(fromByteOffset: 3 * DarwinLayout.word, as: Release?.self)
    }
}

final class HeapStorage {
    /// Smallest first.
    var values: [CFValue] = []
    let callbacksPointer: UnsafeRawPointer?
    let callbacks: HeapCallbacks
    let context: HeapContext
    let contextPointer: UnsafeRawPointer?

    init(callbacks pointer: UnsafeRawPointer?, context: UnsafeRawPointer?) {
        callbacksPointer = pointer
        callbacks = HeapCallbacks(pointer)
        contextPointer = context
        self.context = HeapContext(context)
        if let info = self.context.info, let retain = self.context.retain { _ = retain(info) }
    }

    deinit {
        values.forEach(released)
        if let info = context.info, let release = context.release { release(info) }
    }

    func retained(_ value: CFValue) -> CFValue { callbacks.retain.map { $0(nil, value) } ?? value }
    func released(_ value: CFValue) { callbacks.release?(nil, value) }

    /// Below zero when `a` comes first; pointers compared without a
    /// compare function.
    func compare(_ a: CFValue, _ b: CFValue) -> Int {
        if let compare = callbacks.compare { return compare(a, b, context.info) }
        let x = UInt(bitPattern: a), y = UInt(bitPattern: b)
        return x < y ? -1 : x > y ? 1 : 0
    }

    func add(_ value: CFValue) {
        // After every value not greater, so equal values keep their order.
        var low = 0, high = values.count
        while low < high {
            let middle = (low + high) / 2
            if compare(values[middle], value) <= 0 { low = middle + 1 } else { high = middle }
        }
        values.insert(retained(value), at: low)
    }
}

enum Heaps {
    nonisolated(unsafe) static var heapClass: Class!

    static func storage(_ heap: id?) -> HeapStorage? { Storage.get(heap, as: HeapStorage.self) }

    static func make(_ callbacks: UnsafeRawPointer?, _ context: UnsafeRawPointer?) -> (id, HeapStorage)? {
        guard let object = Storage.allocate(UnsafeMutableRawPointer(heapClass)) else { return nil }
        let storage = HeapStorage(callbacks: callbacks, context: context)
        Storage.set(object, storage)
        return (object, storage)
    }
}

@ObjCClass("__NSCFBinaryHeap")
final class NSCFBinaryHeap: NSObject {
    override class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        Heaps.heapClass = cls.storage
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: Heaps.heapClass)
    }

    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { 23 }

    @ObjCMethod("count") func count() -> UInt { UInt(Heaps.storage(objcObject)?.values.count ?? 0) }
}

/// kCFStringBinaryHeapCallBacks' compare: CFStringCompare.
@c
public func perry_foundation_cf_string_compare(_ a: UnsafeRawPointer?, _ b: UnsafeRawPointer?,
                                               _ context: UnsafeMutableRawPointer?) -> Int {
    CFStringCompare(UnsafeMutableRawPointer(mutating: a), UnsafeMutableRawPointer(mutating: b), 0)
}

@c(_CFBinaryHeapGetTypeID) public func CFBinaryHeapGetTypeID() -> UInt { 23 }

@c(_CFBinaryHeapCreate)
public func CFBinaryHeapCreate(_ allocator: UnsafeRawPointer?, _ capacity: Int, _ callbacks: UnsafeRawPointer?,
                               _ context: UnsafeRawPointer?) -> id? {
    Heaps.make(callbacks, context)?.0
}

@c(_CFBinaryHeapCreateCopy)
public func CFBinaryHeapCreateCopy(_ allocator: UnsafeRawPointer?, _ capacity: Int, _ heap: id?) -> id? {
    guard let original = Heaps.storage(heap),
          let (copy, storage) = Heaps.make(original.callbacksPointer, original.contextPointer) else { return nil }
    storage.values = original.values.map(storage.retained)
    return copy
}

@c(_CFBinaryHeapGetCount) public func CFBinaryHeapGetCount(_ heap: id?) -> Int { Heaps.storage(heap)?.values.count ?? 0 }

@c(_CFBinaryHeapGetCountOfValue)
public func CFBinaryHeapGetCountOfValue(_ heap: id?, _ value: CFValue) -> Int {
    guard let storage = Heaps.storage(heap) else { return 0 }
    return storage.values.filter { storage.compare($0, value) == 0 }.count
}

@c(_CFBinaryHeapContainsValue)
public func CFBinaryHeapContainsValue(_ heap: id?, _ value: CFValue) -> Bool { CFBinaryHeapGetCountOfValue(heap, value) > 0 }

@c(_CFBinaryHeapGetMinimum) public func CFBinaryHeapGetMinimum(_ heap: id?) -> CFValue { Heaps.storage(heap)?.values.first ?? nil }

@c(_CFBinaryHeapGetMinimumIfPresent)
public func CFBinaryHeapGetMinimumIfPresent(_ heap: id?, _ value: UnsafeMutablePointer<CFValue>?) -> Bool {
    guard let first = Heaps.storage(heap)?.values.first else { return false }
    value?.pointee = first
    return true
}

/// Every value, smallest first.
@c(_CFBinaryHeapGetValues)
public func CFBinaryHeapGetValues(_ heap: id?, _ values: UnsafeMutablePointer<CFValue>?) {
    guard let values, let all = Heaps.storage(heap)?.values else { return }
    for (index, value) in all.enumerated() { values[index] = value }
}

@c(_CFBinaryHeapApplyFunction)
public func CFBinaryHeapApplyFunction(_ heap: id?, _ applier: (@convention(c) (CFValue, UnsafeMutableRawPointer?) -> Void)?,
                                      _ context: UnsafeMutableRawPointer?) {
    guard let applier, let all = Heaps.storage(heap)?.values else { return }
    all.forEach { applier($0, context) }
}

@c(_CFBinaryHeapAddValue) public func CFBinaryHeapAddValue(_ heap: id?, _ value: CFValue) { Heaps.storage(heap)?.add(value) }

@c(_CFBinaryHeapRemoveMinimumValue)
public func CFBinaryHeapRemoveMinimumValue(_ heap: id?) {
    guard let storage = Heaps.storage(heap), !storage.values.isEmpty else { return }
    storage.released(storage.values.removeFirst())
}

@c(_CFBinaryHeapRemoveAllValues)
public func CFBinaryHeapRemoveAllValues(_ heap: id?) {
    guard let storage = Heaps.storage(heap) else { return }
    let old = storage.values
    storage.values = []
    old.forEach(storage.released)
}
