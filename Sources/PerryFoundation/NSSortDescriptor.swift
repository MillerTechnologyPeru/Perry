import CPerryFoundation
import PerryObjCInterop

// NSSortDescriptor: a key, a direction and a comparison selector or block.

final class SortDescriptorStorage {
    let key: String?
    let ascending: Bool
    let selector: String
    /// A comparator block, copied, which takes the selector's place.
    let comparator: BlockReference?

    init(key: String?, ascending: Bool, selector: String, comparator: BlockReference? = nil) {
        self.key = key
        self.ascending = ascending
        self.selector = selector
        self.comparator = comparator
    }
}

enum SortDescriptors {
    nonisolated(unsafe) static var descriptorClass: Class!

    static func storage(_ object: id?) -> SortDescriptorStorage? {
        Storage.get(object, as: SortDescriptorStorage.self)
    }

    static func make(_ cls: UnsafeMutableRawPointer?, key: String?, ascending: Bool, selector: String,
                     comparator: BlockReference? = nil) -> id {
        let object = Storage.allocate(cls ?? UnsafeMutableRawPointer(descriptorClass))!
        Storage.set(object, SortDescriptorStorage(key: key, ascending: ascending, selector: selector, comparator: comparator))
        return ObjC.autorelease(object)!
    }

    /// `elements` sorted stably by each descriptor of the array `descriptors`
    /// in turn, through -compareObject:toObject:.
    static func sorted(_ elements: [id], by descriptors: id?) -> [id] {
        let keys = Arrays.elements(descriptors)
        guard !keys.isEmpty else { return elements }
        let compare = ObjC.selector("compareObject:toObject:")
        let send = unsafeBitCast(ObjC.msgSend, to: (@convention(c) (id, SEL, id, id) -> Int).self)
        return elements.enumerated().sorted { a, b in
            for descriptor in keys {
                let order = send(descriptor, compare, a.element, b.element)
                if order != 0 { return order < 0 }
            }
            return a.offset < b.offset
        }.map(\.element)
    }
}

/// NSSortDescriptor.
@ObjCClass("NSSortDescriptor")
public class NSSortDescriptor: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        SortDescriptors.descriptorClass = cls.storage
    }

    private var storage: SortDescriptorStorage? { SortDescriptors.storage(objcObject) }

    @ObjCClassMethod("sortDescriptorWithKey:ascending:")
    static func descriptor(_ cls: ObjCClass, key: String?, ascending: Bool) -> ObjCObject {
        ObjCObject(SortDescriptors.make(cls.pointer, key: key, ascending: ascending, selector: "compare:"))
    }

    @ObjCClassMethod("sortDescriptorWithKey:ascending:selector:")
    static func descriptor(_ cls: ObjCClass, key: String?, ascending: Bool, selector: ObjCSelector?) -> ObjCObject {
        ObjCObject(SortDescriptors.make(cls.pointer, key: key, ascending: ascending, selector: selector?.name ?? "compare:"))
    }

    /// Values compared by a block: NSComparisonResult (id, id).
    @ObjCClassMethod("sortDescriptorWithKey:ascending:comparator:")
    static func descriptor(_ cls: ObjCClass, key: String?, ascending: Bool, comparator: ObjCObject?) -> ObjCObject {
        ObjCObject(SortDescriptors.make(cls.pointer, key: key, ascending: ascending, selector: "compare:",
                                        comparator: BlockReference(comparator?.objcObject)))
    }

    @ObjCMethod("initWithKey:ascending:comparator:")
    func initialize(key: String?, ascending: Bool, comparator: ObjCObject?) -> Self {
        Storage.set(objcObject, SortDescriptorStorage(key: key, ascending: ascending, selector: "compare:",
                                                      comparator: BlockReference(comparator?.objcObject)))
        return self
    }

    @ObjCMethod("initWithKey:ascending:")
    func initialize(key: String?, ascending: Bool) -> Self {
        Storage.set(objcObject, SortDescriptorStorage(key: key, ascending: ascending, selector: "compare:"))
        return self
    }

    @ObjCMethod("initWithKey:ascending:selector:")
    func initialize(key: String?, ascending: Bool, selector: ObjCSelector?) -> Self {
        Storage.set(objcObject, SortDescriptorStorage(key: key, ascending: ascending, selector: selector?.name ?? "compare:"))
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: SortDescriptors.descriptorClass)
    }

    @ObjCMethod("key") func key() -> String? { storage?.key }
    @ObjCMethod("ascending") func ascending() -> Bool { storage?.ascending ?? true }
    /// NULL for a descriptor with a comparator, as on Darwin.
    @ObjCMethod("selector")
    func selector() -> ObjCSelector? {
        guard storage?.comparator == nil else { return nil }
        return ObjCSelector(storage?.selector ?? "compare:")
    }

    /// The comparator block; nil for a descriptor with a selector.
    @ObjCMethod("comparator") func comparator() -> UnsafeMutableRawPointer? { storage?.comparator?.block }

    /// For a securely decoded descriptor, which Darwin keeps from comparing
    /// until this is sent; any descriptor compares here.
    @ObjCMethod("allowEvaluation") func allowEvaluation() {}

    @ObjCMethod("reversedSortDescriptor")
    func reversedSortDescriptor() -> ObjCObject {
        ObjCObject(SortDescriptors.make(objCClass.pointer, key: storage?.key, ascending: !(storage?.ascending ?? true),
                                        selector: storage?.selector ?? "compare:", comparator: storage?.comparator))
    }

    /// The order of two objects by the key's values, reversed when
    /// descending: NSComparisonResult.
    @ObjCMethod("compareObject:toObject:")
    func compare(_ a: ObjCObject?, to b: ObjCObject?) -> Int {
        guard let storage else { return 0 }
        let left = storage.key.map { PredicateEvaluation.value(of: $0, in: a?.objcObject) } ?? a?.objcObject
        let right = storage.key.map { PredicateEvaluation.value(of: $0, in: b?.objcObject) } ?? b?.objcObject
        var order: Int
        if let comparator = storage.comparator {
            typealias Compare = @convention(c) (id, id?, id?) -> Int
            order = Blocks.invoke(comparator.block, as: Compare.self)(comparator.block, left, right)
            return storage.ascending ? order : -order
        }
        switch (left, right) {
        case (nil, nil): order = 0
        case (nil, _): order = -1
        case (_, nil): order = 1
        default: order = ObjC.sendInt(left, ObjC.selector(storage.selector), right)
        }
        return storage.ascending ? order : -order
    }

    /// (key, ascending, NO, compare:)
    @ObjCMethod("description")
    func description() -> String {
        guard let storage else { return "" }
        let comparison = storage.comparator.map { "BLOCK(\($0.block))" } ?? storage.selector
        return "(\(storage.key ?? "(null)"), \(storage.ascending ? "ascending" : "descending"), NO, \(comparison))"
    }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> NSSortDescriptor { self }
}
