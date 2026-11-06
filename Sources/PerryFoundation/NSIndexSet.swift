import CPerryFoundation
import FoundationEssentials
import PerryObjCInterop

/// An index set's indexes as sorted, separate ranges.
final class IndexSetStorage {
    var ranges: [Range<Int>] = []

    init(_ ranges: [Range<Int>] = []) {
        self.ranges = ranges
        normalize()
    }

    var count: Int { ranges.reduce(0) { $0 + $1.count } }

    func normalize() {
        let sorted = ranges.filter { !$0.isEmpty }.sorted { $0.lowerBound < $1.lowerBound }
        var merged: [Range<Int>] = []
        for range in sorted {
            if let last = merged.last, range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        ranges = merged
    }

    func contains(_ index: Int) -> Bool { ranges.contains { $0.contains(index) } }

    func add(_ range: Range<Int>) {
        ranges.append(range)
        normalize()
    }

    func remove(_ removed: Range<Int>) {
        ranges = ranges.flatMap { range -> [Range<Int>] in
            guard range.overlaps(removed) else { return [range] }
            var parts: [Range<Int>] = []
            if range.lowerBound < removed.lowerBound { parts.append(range.lowerBound..<removed.lowerBound) }
            if removed.upperBound < range.upperBound { parts.append(removed.upperBound..<range.upperBound) }
            return parts
        }
    }

    var indexes: [Int] { ranges.flatMap { Array($0) } }

    /// shiftIndexesStartingAtIndex:by: — a negative shift drops the indexes
    /// it moves over.
    func shift(from start: Int, by delta: Int) {
        if delta < 0 { remove(max(0, start + delta)..<start) }
        ranges = ranges.flatMap { range -> [Range<Int>] in
            if range.upperBound <= start { return [range] }
            if range.lowerBound >= start { return [(range.lowerBound + delta)..<(range.upperBound + delta)] }
            return [range.lowerBound..<start, (start + delta)..<(range.upperBound + delta)]
        }
        normalize()
    }
}

enum IndexSets {
    nonisolated(unsafe) static var setClass: Class!
    nonisolated(unsafe) static var mutableClass: Class!

    static func storage(_ object: id?) -> IndexSetStorage {
        Storage.get(object, as: IndexSetStorage.self) ?? IndexSetStorage()
    }

    static func make(_ cls: id, _ ranges: [Range<Int>]) -> id? {
        guard let object = Storage.allocate(cls) else { return nil }
        Storage.set(object, IndexSetStorage(ranges))
        return ObjC.autorelease(object)
    }

    static func range(_ range: NSRange) -> Range<Int> { Int(range.location)..<Int(range.location + range.length) }
    static func nsRange(_ range: Range<Int>) -> NSRange { NSRange(location: UInt(range.lowerBound), length: UInt(range.count)) }
    static let notFoundIndex = UInt(Int.max)
}

/// NSIndexSet.
@ObjCClass("NSIndexSet")
public class NSIndexSet: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        IndexSets.setClass = cls.storage
    }

    var storage: IndexSetStorage {
        if let storage = Storage.get(objcObject, as: IndexSetStorage.self) { return storage }
        let storage = IndexSetStorage()
        Storage.set(objcObject, storage)
        return storage
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: IndexSets.setClass)
    }

    @ObjCClassMethod("indexSet") static func empty(_ cls: ObjCClass) -> UnsafeMutableRawPointer? { IndexSets.make(cls.pointer, []) }

    @ObjCClassMethod("indexSetWithIndex:")
    static func make(_ cls: ObjCClass, index: UInt) -> UnsafeMutableRawPointer? { IndexSets.make(cls.pointer, [Int(index)..<Int(index) + 1]) }

    @ObjCClassMethod("indexSetWithIndexesInRange:")
    static func make(_ cls: ObjCClass, range: NSRange) -> UnsafeMutableRawPointer? { IndexSets.make(cls.pointer, [IndexSets.range(range)]) }

    @ObjCMethod("init")
    func initialize() -> Self {
        Storage.set(objcObject, IndexSetStorage())
        return self
    }

    @ObjCMethod("initWithIndex:")
    func initialize(index: UInt) -> Self {
        Storage.set(objcObject, IndexSetStorage([Int(index)..<Int(index) + 1]))
        return self
    }

    @ObjCMethod("initWithIndexesInRange:")
    func initialize(range: NSRange) -> Self {
        Storage.set(objcObject, IndexSetStorage([IndexSets.range(range)]))
        return self
    }

    @ObjCMethod("initWithIndexSet:")
    func initialize(indexSet other: ObjCObject?) -> Self {
        Storage.set(objcObject, IndexSetStorage(IndexSets.storage(other?.id).ranges))
        return self
    }

    // MARK: Coding

    /// As Darwin's keyed archives hold an index set: NSRangeCount, then for
    /// one range NSLocation and NSLength, for more NSRangeData, each range's
    /// location and length as unsigned LEB128 numbers.
    @ObjCClassMethod("supportsSecureCoding") static func supportsSecureCoding() -> Bool { true }

    @ObjCMethod("initWithCoder:")
    func initialize(coder: ObjCObject) -> Self {
        typealias DecodeInteger = @convention(c) (id, SEL, id?) -> Int
        let integer = { (key: String) in
            unsafeBitCast(ObjC.msgSend, to: DecodeInteger.self)(coder.id, ObjC.selector("decodeIntegerForKey:"), Strings.autoreleased(key))
        }
        var ranges: [Range<Int>] = []
        let count = integer("NSRangeCount")
        if count == 1 {
            let location = integer("NSLocation")
            ranges = [location..<location + integer("NSLength")]
        } else if count > 1,
                  let data = ObjC.send(coder.id, ObjC.selector("decodeObjectForKey:"), Strings.autoreleased("NSRangeData")) {
            let bytes = DataObjects.data(data)
            var numbers: [Int] = [], value = 0, shift = 0
            for byte in bytes {
                value |= Int(byte & 0x7f) << shift
                if byte & 0x80 != 0 {
                    shift += 7
                } else {
                    numbers.append(value)
                    value = 0
                    shift = 0
                }
            }
            for pair in stride(from: 0, to: numbers.count - 1, by: 2) {
                ranges.append(numbers[pair]..<numbers[pair] + numbers[pair + 1])
            }
        }
        Storage.set(objcObject, IndexSetStorage(ranges))
        return self
    }

    @ObjCMethod("encodeWithCoder:")
    func encode(coder: ObjCObject) {
        typealias EncodeInteger = @convention(c) (id, SEL, Int, id?) -> Void
        let encode = { (value: Int, key: String) in
            unsafeBitCast(ObjC.msgSend, to: EncodeInteger.self)(coder.id, ObjC.selector("encodeInteger:forKey:"), value, Strings.autoreleased(key))
        }
        let ranges = storage.ranges
        encode(ranges.count, "NSRangeCount")
        if ranges.count == 1 {
            encode(ranges[0].lowerBound, "NSLocation")
            encode(ranges[0].count, "NSLength")
        } else if ranges.count > 1 {
            var bytes: [UInt8] = []
            for number in ranges.flatMap({ [$0.lowerBound, $0.count] }) {
                var value = UInt(number)
                repeat {
                    let low = UInt8(value & 0x7f)
                    value >>= 7
                    bytes.append(value != 0 ? low | 0x80 : low)
                } while value != 0
            }
            typealias EncodeObject = @convention(c) (id, SEL, id?, id?) -> Void
            unsafeBitCast(ObjC.msgSend, to: EncodeObject.self)(coder.id, ObjC.selector("encodeObject:forKey:"),
                                                                DataObjects.autoreleased(Data(bytes)), Strings.autoreleased("NSRangeData"))
        }
    }

    @ObjCMethod("count") func count() -> UInt { UInt(storage.count) }
    @ObjCMethod("firstIndex") func firstIndex() -> UInt { storage.ranges.first.map { UInt($0.lowerBound) } ?? IndexSets.notFoundIndex }
    @ObjCMethod("lastIndex") func lastIndex() -> UInt { storage.ranges.last.map { UInt($0.upperBound - 1) } ?? IndexSets.notFoundIndex }
    @ObjCMethod("containsIndex:") func contains(_ index: UInt) -> Bool { storage.contains(Int(index)) }

    @ObjCMethod("containsIndexesInRange:")
    func contains(range: NSRange) -> Bool {
        let wanted = IndexSets.range(range)
        return storage.ranges.contains { $0.lowerBound <= wanted.lowerBound && wanted.upperBound <= $0.upperBound }
    }

    @ObjCMethod("containsIndexes:")
    func contains(indexes other: ObjCObject) -> Bool {
        IndexSets.storage(other.id).ranges.allSatisfy { range in
            storage.ranges.contains { $0.lowerBound <= range.lowerBound && range.upperBound <= $0.upperBound }
        }
    }

    @ObjCMethod("intersectsIndexesInRange:")
    func intersects(range: NSRange) -> Bool { storage.ranges.contains { $0.overlaps(IndexSets.range(range)) } }

    @ObjCMethod("countOfIndexesInRange:")
    func count(in range: NSRange) -> UInt {
        let limit = IndexSets.range(range)
        return UInt(storage.ranges.reduce(0) { $0 + $1.clamped(to: limit).count })
    }

    private func nearest(_ test: (Int) -> Bool, reverse: Bool) -> UInt {
        let indexes = storage.indexes
        let found = reverse ? indexes.last(where: test) : indexes.first(where: test)
        return found.map(UInt.init) ?? IndexSets.notFoundIndex
    }

    @ObjCMethod("indexGreaterThanIndex:") func greater(than index: UInt) -> UInt { nearest({ $0 > Int(index) }, reverse: false) }
    @ObjCMethod("indexGreaterThanOrEqualToIndex:")
    func greaterOrEqual(to index: UInt) -> UInt { nearest({ $0 >= Int(index) }, reverse: false) }
    @ObjCMethod("indexLessThanIndex:") func less(than index: UInt) -> UInt { nearest({ $0 < Int(index) }, reverse: true) }
    @ObjCMethod("indexLessThanOrEqualToIndex:")
    func lessOrEqual(to index: UInt) -> UInt { nearest({ $0 <= Int(index) }, reverse: true) }

    @ObjCMethod("getIndexes:maxCount:inIndexRange:")
    func getIndexes(_ buffer: UnsafeMutablePointer<UInt>?, maxCount: UInt, inIndexRange range: UnsafeMutablePointer<NSRange>?) -> UInt {
        var indexes = storage.indexes
        if let range {
            let limit = IndexSets.range(range.pointee)
            indexes = indexes.filter { limit.contains($0) }
        }
        let taken = Array(indexes.prefix(Int(maxCount)))
        for (offset, index) in taken.enumerated() { buffer?[offset] = UInt(index) }
        if let range, let last = taken.last {
            let end = range.pointee.location + range.pointee.length
            range.pointee = NSRange(location: UInt(last + 1), length: end - UInt(last + 1))
        }
        return UInt(taken.count)
    }

    /// Options: NSEnumerationReverse (2).
    @ObjCMethod("enumerateIndexesWithOptions:usingBlock:")
    func enumerateIndexes(options: UInt, using block: ObjCObject) {
        typealias Invoke = @convention(c) (id, UInt, UnsafeMutablePointer<Bool>) -> Void
        let invoke = Blocks.invoke(block.id, as: Invoke.self)
        var indexes = storage.indexes
        if options & 2 != 0 { indexes.reverse() }
        for index in indexes {
            var stop = false
            invoke(block.id, UInt(index), &stop)
            if stop { return }
        }
    }

    @ObjCMethod("enumerateIndexesUsingBlock:")
    func enumerateIndexes(using block: ObjCObject) { enumerateIndexes(options: 0, using: block) }

    @ObjCMethod("enumerateRangesWithOptions:usingBlock:")
    func enumerateRanges(options: UInt, using block: ObjCObject) {
        typealias Invoke = @convention(c) (id, NSRange, UnsafeMutablePointer<Bool>) -> Void
        let invoke = Blocks.invoke(block.id, as: Invoke.self)
        var ranges = storage.ranges
        if options & 2 != 0 { ranges.reverse() }
        for range in ranges {
            var stop = false
            invoke(block.id, IndexSets.nsRange(range), &stop)
            if stop { return }
        }
    }

    @ObjCMethod("enumerateRangesUsingBlock:")
    func enumerateRanges(using block: ObjCObject) { enumerateRanges(options: 0, using: block) }

    private func passing(_ block: ObjCObject) -> [Int] {
        typealias Invoke = @convention(c) (id, UInt, UnsafeMutablePointer<Bool>) -> Bool
        let invoke = Blocks.invoke(block.id, as: Invoke.self)
        var passed: [Int] = []
        for index in storage.indexes {
            var stop = false
            if invoke(block.id, UInt(index), &stop) { passed.append(index) }
            if stop { break }
        }
        return passed
    }

    @ObjCMethod("indexPassingTest:")
    func index(passingTest block: ObjCObject) -> UInt { passing(block).first.map(UInt.init) ?? IndexSets.notFoundIndex }

    @ObjCMethod("indexesPassingTest:")
    func indexes(passingTest block: ObjCObject) -> UnsafeMutableRawPointer? {
        IndexSets.make(UnsafeMutableRawPointer(IndexSets.setClass), passing(block).map { $0..<$0 + 1 })
    }

    @ObjCMethod("isEqualToIndexSet:")
    func isEqual(toIndexSet other: ObjCObject?) -> Bool { IndexSets.storage(other?.id).ranges == storage.ranges }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: ObjCObject?) -> Bool {
        guard let other, ObjC.isKind(other.id, of: IndexSets.setClass) else { return false }
        return isEqual(toIndexSet: other)
    }

    @ObjCMethod("hash") func hash() -> UInt { UInt(storage.count) }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        ObjC.retain(IndexSets.make(UnsafeMutableRawPointer(IndexSets.setClass), storage.ranges))
    }

    @ObjCMethod("mutableCopyWithZone:")
    func mutableCopy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        ObjC.retain(IndexSets.make(UnsafeMutableRawPointer(IndexSets.mutableClass), storage.ranges))
    }

    /// "<NSIndexSet: 0x…>[number of indexes: 3 (in 2 ranges), indexes: (2 4-5)]"
    @ObjCMethod("description")
    func description() -> String {
        let ranges = storage.ranges.map { $0.count == 1 ? "\($0.lowerBound)" : "\($0.lowerBound)-\($0.upperBound - 1)" }
        let name = ObjC.isKind(objcObject, of: IndexSets.mutableClass) ? "NSMutableIndexSet" : "NSIndexSet"
        return "<\(name): \(objcObject)>[number of indexes: \(storage.count) (in \(storage.ranges.count) ranges), indexes: ("
            + ranges.joined(separator: " ") + ")]"
    }
}

/// NSMutableIndexSet.
@ObjCClass("NSMutableIndexSet")
public final class NSMutableIndexSet: NSIndexSet {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        IndexSets.mutableClass = cls.storage
    }

    @ObjCMethod("addIndex:") func add(_ index: UInt) { storage.add(Int(index)..<Int(index) + 1) }
    @ObjCMethod("addIndexesInRange:") func add(range: NSRange) { storage.add(IndexSets.range(range)) }
    @ObjCMethod("addIndexes:") func add(indexes other: ObjCObject) { IndexSets.storage(other.id).ranges.forEach(storage.add) }
    @ObjCMethod("removeIndex:") func remove(_ index: UInt) { storage.remove(Int(index)..<Int(index) + 1) }
    @ObjCMethod("removeIndexesInRange:") func remove(range: NSRange) { storage.remove(IndexSets.range(range)) }
    @ObjCMethod("removeIndexes:") func remove(indexes other: ObjCObject) { IndexSets.storage(other.id).ranges.forEach(storage.remove) }
    @ObjCMethod("removeAllIndexes") func removeAll() { storage.ranges = [] }

    @ObjCMethod("shiftIndexesStartingAtIndex:by:")
    func shift(startingAt index: UInt, by delta: Int) { storage.shift(from: Int(index), by: delta) }
}

/// Arrays and index sets.
@ObjCCategory("IndexSetAccess")
extension NSArray {
    @ObjCMethod("objectsAtIndexes:")
    func objects(atIndexes indexes: ObjCObject) -> ObjCObject {
        let elements = Arrays.elements(objcObject)
        let picked = IndexSets.storage(indexes.id).indexes.map { index -> id in
            guard index < elements.count else {
                foundationFatal("-[NSArray objectsAtIndexes:]: index \(index) beyond bounds [0 .. \(elements.count - 1)]")
            }
            return elements[index]
        }
        return ObjCObject(Arrays.autoreleased(picked))
    }

    @ObjCMethod("indexesOfObjectsPassingTest:")
    func indexes(ofObjectsPassingTest block: ObjCObject) -> UnsafeMutableRawPointer? {
        typealias Invoke = @convention(c) (id, id, UInt, UnsafeMutablePointer<Bool>) -> Bool
        let invoke = Blocks.invoke(block.id, as: Invoke.self)
        var passed: [Range<Int>] = []
        for (index, element) in Arrays.elements(objcObject).enumerated() {
            var stop = false
            if invoke(block.id, element, UInt(index), &stop) { passed.append(index..<index + 1) }
            if stop { break }
        }
        return IndexSets.make(UnsafeMutableRawPointer(IndexSets.setClass), passed)
    }

    /// The first index whose element passes, or NSNotFound.
    @ObjCMethod("indexOfObjectPassingTest:")
    func index(ofObjectPassingTest block: ObjCObject) -> UInt {
        typealias Invoke = @convention(c) (id, id, UInt, UnsafeMutablePointer<Bool>) -> Bool
        let invoke = Blocks.invoke(block.id, as: Invoke.self)
        for (index, element) in Arrays.elements(objcObject).enumerated() {
            var stop = false
            if invoke(block.id, element, UInt(index), &stop) { return UInt(index) }
            if stop { break }
        }
        return UInt(Int.max)
    }

    /// NSEnumerationOptions: reverse 2 searches from the end; concurrent
    /// searching is done in order.
    @ObjCMethod("indexOfObjectWithOptions:passingTest:")
    func index(options: UInt, ofObjectPassingTest block: ObjCObject) -> UInt {
        typealias Invoke = @convention(c) (id, id, UInt, UnsafeMutablePointer<Bool>) -> Bool
        let invoke = Blocks.invoke(block.id, as: Invoke.self)
        let elements = Arrays.elements(objcObject)
        let order = options & 2 != 0 ? Array(elements.indices.reversed()) : Array(elements.indices)
        for index in order {
            var stop = false
            if invoke(block.id, elements[index], UInt(index), &stop) { return UInt(index) }
            if stop { break }
        }
        return UInt(Int.max)
    }

    @ObjCMethod("indexesOfObjectsWithOptions:passingTest:")
    func indexes(options: UInt, ofObjectsPassingTest block: ObjCObject) -> UnsafeMutableRawPointer? {
        indexes(ofObjectsPassingTest: block)
    }

    /// For NSMutableArray.
    @ObjCMethod("removeObjectsAtIndexes:")
    func removeObjects(atIndexes indexes: ObjCObject) {
        for index in IndexSets.storage(indexes.id).indexes.reversed() {
            _ = ObjC.send(objcObject, ObjC.selector("removeObjectAtIndex:"), UnsafeMutableRawPointer(bitPattern: UInt(index)))
        }
    }

    /// For NSMutableArray.
    @ObjCMethod("insertObjects:atIndexes:")
    func insert(_ objects: ObjCObject, atIndexes indexes: ObjCObject) {
        typealias Insert = @convention(c) (id, SEL, id, UInt) -> Void
        let insert = unsafeBitCast(ObjC.msgSend, to: Insert.self)
        for (object, index) in zip(Arrays.elements(objects.id), IndexSets.storage(indexes.id).indexes) {
            insert(objcObject, ObjC.selector("insertObject:atIndex:"), object, UInt(index))
        }
    }
}
