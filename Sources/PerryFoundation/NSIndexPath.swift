import CPerryFoundation
import PerryObjCInterop

/// An NSIndexPath's indexes.
final class IndexPathStorage {
    let indexes: [UInt]

    init(_ indexes: [UInt]) {
        self.indexes = indexes
    }
}

enum IndexPaths {
    nonisolated(unsafe) static var indexPathClass: Class!

    static func indexes(_ object: id?) -> [UInt]? {
        Storage.get(object, as: IndexPathStorage.self)?.indexes
    }

    /// A new index path of class `cls`, +1.
    static func make(_ cls: UnsafeMutableRawPointer, _ indexes: [UInt]) -> id? {
        guard let object = Storage.allocate(cls) else { return nil }
        Storage.set(object, IndexPathStorage(indexes))
        return object
    }
}

/// NSIndexPath: an immutable list of indexes, such as a section and a row.
@ObjCClass("NSIndexPath")
public final class NSIndexPath: NSObject {
    /// Set-up after the class is defined.
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        IndexPaths.indexPathClass = cls.storage
    }

    var indexes: [UInt] { IndexPaths.indexes(objcObject) ?? [] }

    private func setIndexes(_ indexes: [UInt]) -> Self {
        Storage.set(objcObject, IndexPathStorage(indexes))
        return self
    }

    @ObjCClassMethod("indexPathWithIndex:")
    static func make(_ cls: ObjCClass, index: UInt) -> NSIndexPath? {
        IndexPaths.make(cls.pointer, [index]).map { NSIndexPath(objCOwned: $0) }
    }

    @ObjCClassMethod("indexPathWithIndexes:length:")
    static func make(_ cls: ObjCClass, indexes: UnsafePointer<UInt>?, length: UInt) -> NSIndexPath? {
        let list = indexes.map { Array(UnsafeBufferPointer(start: $0, count: Int(length))) } ?? []
        return IndexPaths.make(cls.pointer, list).map { NSIndexPath(objCOwned: $0) }
    }

    @ObjCMethod("init") func initialize() -> Self { setIndexes([]) }
    @ObjCMethod("initWithIndex:") func initialize(index: UInt) -> Self { setIndexes([index]) }

    @ObjCMethod("initWithIndexes:length:")
    func initialize(indexes: UnsafePointer<UInt>?, length: UInt) -> Self {
        setIndexes(indexes.map { Array(UnsafeBufferPointer(start: $0, count: Int(length))) } ?? [])
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: IndexPaths.indexPathClass)
    }

    @ObjCMethod("length") func length() -> UInt { UInt(indexes.count) }

    /// NSNotFound past the end.
    @ObjCMethod("indexAtPosition:")
    func index(atPosition position: UInt) -> UInt {
        let indexes = indexes
        return position < indexes.count ? indexes[Int(position)] : UInt(Int.max)
    }

    @ObjCMethod("indexPathByAddingIndex:")
    func adding(_ index: UInt) -> NSIndexPath? {
        IndexPaths.make(IndexPaths.indexPathClass, indexes + [index]).map { NSIndexPath(objCOwned: $0) }
    }

    @ObjCMethod("indexPathByRemovingLastIndex")
    func removingLastIndex() -> NSIndexPath? {
        IndexPaths.make(IndexPaths.indexPathClass, Array(indexes.dropLast())).map { NSIndexPath(objCOwned: $0) }
    }

    @ObjCMethod("getIndexes:")
    func getIndexes(_ buffer: UnsafeMutablePointer<UInt>) {
        for (offset, index) in indexes.enumerated() { buffer[offset] = index }
    }

    @ObjCMethod("getIndexes:range:")
    func getIndexes(_ buffer: UnsafeMutablePointer<UInt>, range: NSRange) {
        let indexes = indexes
        let start = Int(range.location)
        for offset in 0..<Int(range.length) where start + offset < indexes.count {
            buffer[offset] = indexes[start + offset]
        }
    }

    /// NSComparisonResult: index by index, then the shorter first.
    @ObjCMethod("compare:")
    func compare(_ other: NSIndexPath) -> Int {
        let a = indexes, b = other.indexes
        for (x, y) in zip(a, b) where x != y { return x < y ? -1 : 1 }
        return a.count == b.count ? 0 : (a.count < b.count ? -1 : 1)
    }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: ObjCObject?) -> Bool {
        guard let other, other.is(NSIndexPath.self) else { return false }
        return other.unsafeCast(to: NSIndexPath.self).indexes == indexes
    }

    @ObjCMethod("hash")
    func hash() -> UInt { indexes.reduce(UInt(indexes.count)) { $0 &* 31 &+ $1 } }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> NSIndexPath { self }

    @ObjCMethod("description")
    func description() -> String {
        let indexes = indexes
        return "<NSIndexPath: \(objcObject)> {length = \(indexes.count), path = \(indexes.map(String.init).joined(separator: " - "))}"
    }
}
