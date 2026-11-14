import PerryObjCInterop

// NSOrderedCollectionDifference and NSOrderedCollectionChange, what
// -[NSArray differenceFromArray:] gives: the insertions and removals that
// turn one array into another, which collection views' data sources apply
// as updates. The difference is a longest common subsequence of the two
// arrays; moves are inferred when asked for.

private func classNamed(_ name: String) -> id? {
    name.withCString { ObjC.getClass($0) }.map { UnsafeMutableRawPointer($0) }
}

private let noAssociatedIndex = Int.max

final class ChangeStorage {
    let object: id?
    let isInsertion: Bool
    let index: Int
    let associatedIndex: Int

    init(object: id?, isInsertion: Bool, index: Int, associatedIndex: Int) {
        self.object = object.flatMap { ObjC.retain($0) }
        self.isInsertion = isInsertion
        self.index = index
        self.associatedIndex = associatedIndex
    }

    deinit { if let object { ObjC.release(object) } }
}

@ObjCClass("NSOrderedCollectionChange")
public class NSOrderedCollectionChange: NSObject {
    nonisolated(unsafe) static var changeClass: Class!

    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        changeClass = cls.storage
    }

    /// A change (+1).
    static func make(object: id?, isInsertion: Bool, index: Int, associatedIndex: Int = noAssociatedIndex) -> id? {
        guard let change = Storage.allocate(UnsafeMutableRawPointer(changeClass)) else { return nil }
        Storage.set(change, ChangeStorage(object: object, isInsertion: isInsertion, index: index, associatedIndex: associatedIndex))
        return change
    }

    private var storage: ChangeStorage {
        if let existing = Storage.get(objcObject, as: ChangeStorage.self) { return existing }
        let made = ChangeStorage(object: nil, isInsertion: true, index: 0, associatedIndex: noAssociatedIndex)
        Storage.set(objcObject, made)
        return made
    }

    @ObjCClassMethod("changeWithObject:type:index:")
    static func change(_ cls: ObjCClass, object: UnsafeMutableRawPointer?, type: Int, index: UInt) -> UnsafeMutableRawPointer? {
        ObjC.autorelease(make(object: object, isInsertion: type == 0, index: Int(index)))
    }

    @ObjCClassMethod("changeWithObject:type:index:associatedIndex:")
    static func change(_ cls: ObjCClass, object: UnsafeMutableRawPointer?, type: Int, index: UInt,
                       associatedIndex: UInt) -> UnsafeMutableRawPointer? {
        ObjC.autorelease(make(object: object, isInsertion: type == 0, index: Int(index), associatedIndex: Int(bitPattern: associatedIndex)))
    }

    @ObjCMethod("initWithObject:type:index:")
    func initialize(object: UnsafeMutableRawPointer?, type: Int, index: UInt) -> Self {
        Storage.set(objcObject, ChangeStorage(object: object, isInsertion: type == 0, index: Int(index), associatedIndex: noAssociatedIndex))
        return self
    }

    @ObjCMethod("initWithObject:type:index:associatedIndex:")
    func initialize(object: UnsafeMutableRawPointer?, type: Int, index: UInt, associatedIndex: UInt) -> Self {
        Storage.set(objcObject, ChangeStorage(object: object, isInsertion: type == 0, index: Int(index),
                                              associatedIndex: Int(bitPattern: associatedIndex)))
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: NSOrderedCollectionChange.changeClass)
    }

    @ObjCMethod("object") func object() -> UnsafeMutableRawPointer? { storage.object }
    /// 0 for an insertion, 1 for a removal.
    @ObjCMethod("changeType") func changeType() -> Int { storage.isInsertion ? 0 : 1 }
    @ObjCMethod("index") func index() -> UInt { UInt(storage.index) }
    @ObjCMethod("associatedIndex") func associatedIndex() -> UInt { UInt(bitPattern: storage.associatedIndex) }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { ObjC.retain(objcObject) }
}

final class DifferenceStorage {
    var insertions: [id] = []
    var removals: [id] = []

    deinit {
        for change in insertions { ObjC.release(change) }
        for change in removals { ObjC.release(change) }
    }
}

@ObjCClass("NSOrderedCollectionDifference")
public class NSOrderedCollectionDifference: NSObject {
    nonisolated(unsafe) static var differenceClass: Class!

    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        differenceClass = cls.storage
    }

    private var storage: DifferenceStorage {
        if let existing = Storage.get(objcObject, as: DifferenceStorage.self) { return existing }
        let made = DifferenceStorage()
        Storage.set(objcObject, made)
        return made
    }

    /// A difference of `changes` (+1): insertions by ascending index, removals by descending.
    static func make(changes: [id]) -> id? {
        guard let difference = Storage.allocate(UnsafeMutableRawPointer(differenceClass)) else { return nil }
        let storage = DifferenceStorage()
        func info(_ change: id) -> ChangeStorage? { Storage.get(change, as: ChangeStorage.self) }
        storage.insertions = changes.filter { info($0)?.isInsertion == true }.sorted { info($0)!.index < info($1)!.index }.compactMap { ObjC.retain($0) }
        storage.removals = changes.filter { info($0)?.isInsertion == false }.sorted { info($0)!.index > info($1)!.index }.compactMap { ObjC.retain($0) }
        Storage.set(difference, storage)
        return difference
    }

    @ObjCMethod("initWithChanges:")
    func initialize(changes: UnsafeMutableRawPointer?) -> Self {
        let made = NSOrderedCollectionDifference.make(changes: Arrays.elements(changes))
        if let source = Storage.get(made, as: DifferenceStorage.self) { Storage.set(objcObject, source) }
        if let made { ObjC.release(made) }
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: NSOrderedCollectionDifference.differenceClass)
    }

    @ObjCMethod("insertions") func insertions() -> UnsafeMutableRawPointer? { Arrays.autoreleased(storage.insertions) }
    @ObjCMethod("removals") func removals() -> UnsafeMutableRawPointer? { Arrays.autoreleased(storage.removals) }
    @ObjCMethod("hasChanges") func hasChanges() -> Bool { !storage.insertions.isEmpty || !storage.removals.isEmpty }

    @ObjCMethod("inverseDifference")
    func inverseDifference() -> UnsafeMutableRawPointer? {
        let flipped = (storage.insertions + storage.removals).compactMap { change -> id? in
            guard let info = Storage.get(change, as: ChangeStorage.self) else { return nil }
            return NSOrderedCollectionChange.make(object: info.object, isInsertion: !info.isInsertion, index: info.index,
                                                  associatedIndex: info.associatedIndex)
        }
        let result = NSOrderedCollectionDifference.make(changes: flipped)
        flipped.forEach { ObjC.release($0) }
        return ObjC.autorelease(result)
    }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { ObjC.retain(objcObject) }

    /// The array with the removals, then the insertions, applied.
    static func apply(_ difference: id?, to elements: [id]) -> [id]? {
        guard let storage = Storage.get(difference, as: DifferenceStorage.self) else { return nil }
        var result = elements
        for change in storage.removals {
            guard let info = Storage.get(change, as: ChangeStorage.self), info.index < result.count else { return nil }
            result.remove(at: info.index)
        }
        for change in storage.insertions {
            guard let info = Storage.get(change, as: ChangeStorage.self), let object = info.object, info.index <= result.count else { return nil }
            result.insert(object, at: info.index)
        }
        return result
    }
}

enum OrderedDifferences {
    /// The changes turning `old` into `new`: the elements outside a longest
    /// common subsequence. Options: 1 omits inserted objects, 2 removed
    /// ones, 4 infers moves.
    static func changes(from old: [id], to new: [id], options: UInt, equal: (id, id) -> Bool) -> [id] {
        let n = old.count, m = new.count
        var inOld = [Bool](repeating: false, count: n), inNew = [Bool](repeating: false, count: m)
        if n * m <= 16_000_000 {
            // lengths[i][j]: the common subsequence of old[i...] and new[j...].
            var lengths = [UInt32](repeating: 0, count: (n + 1) * (m + 1))
            let width = m + 1
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    lengths[i * width + j] = equal(old[i], new[j]) ? lengths[(i + 1) * width + j + 1] + 1
                        : max(lengths[(i + 1) * width + j], lengths[i * width + j + 1])
                }
            }
            var i = 0, j = 0
            while i < n && j < m {
                if equal(old[i], new[j]) {
                    inOld[i] = true; inNew[j] = true
                    i += 1; j += 1
                } else if lengths[(i + 1) * width + j] >= lengths[i * width + j + 1] {
                    i += 1
                } else {
                    j += 1
                }
            }
        }
        var removed = (0..<n).filter { !inOld[$0] }, inserted = (0..<m).filter { !inNew[$0] }
        var made: [id] = []
        if options & 4 != 0 {
            var pairs: [(from: Int, to: Int)] = []
            var free = inserted
            for r in removed {
                if let position = free.firstIndex(where: { equal(old[r], new[$0]) }) {
                    pairs.append((r, free.remove(at: position)))
                }
            }
            for pair in pairs {
                if let change = NSOrderedCollectionChange.make(object: options & 2 != 0 ? nil : old[pair.from], isInsertion: false,
                                                               index: pair.from, associatedIndex: pair.to) { made.append(change) }
                if let change = NSOrderedCollectionChange.make(object: options & 1 != 0 ? nil : new[pair.to], isInsertion: true,
                                                               index: pair.to, associatedIndex: pair.from) { made.append(change) }
            }
            removed.removeAll { r in pairs.contains { $0.from == r } }
            inserted.removeAll { j in pairs.contains { $0.to == j } }
        }
        for r in removed {
            if let change = NSOrderedCollectionChange.make(object: options & 2 != 0 ? nil : old[r], isInsertion: false, index: r) { made.append(change) }
        }
        for j in inserted {
            if let change = NSOrderedCollectionChange.make(object: options & 1 != 0 ? nil : new[j], isInsertion: true, index: j) { made.append(change) }
        }
        return made
    }

    static func difference(from old: [id], to new: [id], options: UInt, equal: (id, id) -> Bool) -> id? {
        let made = changes(from: old, to: new, options: options, equal: equal)
        let difference = NSOrderedCollectionDifference.make(changes: made)
        made.forEach { ObjC.release($0) }
        return ObjC.autorelease(difference)
    }
}

@ObjCCategory("OrderedCollectionDifference")
extension NSArray {
    @ObjCMethod("differenceFromArray:withOptions:")
    func difference(from other: UnsafeMutableRawPointer?, options: UInt) -> UnsafeMutableRawPointer? {
        OrderedDifferences.difference(from: Arrays.elements(other), to: elements, options: options) { ObjectKey(object: $0) == ObjectKey(object: $1) }
    }

    @ObjCMethod("differenceFromArray:")
    func difference(from other: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        difference(from: other, options: 0)
    }

    @ObjCMethod("differenceFromArray:withOptions:usingEquivalenceTest:")
    func difference(from other: UnsafeMutableRawPointer?, options: UInt, test: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        guard let test else { return difference(from: other, options: options) }
        let compare = Blocks.invoke(test, as: (@convention(c) (id, id?, id?) -> Bool).self)
        return OrderedDifferences.difference(from: Arrays.elements(other), to: elements, options: options) { compare(test, $0, $1) }
    }

    @ObjCMethod("arrayByApplyingDifference:")
    func applying(difference: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        NSOrderedCollectionDifference.apply(difference, to: elements).map { Arrays.autoreleased($0) }
    }
}
