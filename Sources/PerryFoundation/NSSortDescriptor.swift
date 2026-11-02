import CPerryFoundation
import PerryObjCInterop

// NSSortDescriptor: a key, a direction and a comparison selector.

final class SortDescriptorStorage {
    let key: String?
    let ascending: Bool
    let selector: String

    init(key: String?, ascending: Bool, selector: String) {
        self.key = key
        self.ascending = ascending
        self.selector = selector
    }
}

enum SortDescriptors {
    nonisolated(unsafe) static var descriptorClass: Class!

    static func storage(_ object: id?) -> SortDescriptorStorage? {
        Storage.get(object, as: SortDescriptorStorage.self)
    }

    static func make(_ cls: UnsafeMutableRawPointer?, key: String?, ascending: Bool, selector: String) -> id {
        let object = Storage.allocate(cls ?? UnsafeMutableRawPointer(descriptorClass))!
        Storage.set(object, SortDescriptorStorage(key: key, ascending: ascending, selector: selector))
        return ObjC.autorelease(object)!
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
    @ObjCMethod("selector") func selector() -> ObjCSelector? { ObjCSelector(storage?.selector ?? "compare:") }

    @ObjCMethod("reversedSortDescriptor")
    func reversedSortDescriptor() -> ObjCObject {
        ObjCObject(SortDescriptors.make(objCClass.pointer, key: storage?.key, ascending: !(storage?.ascending ?? true),
                                        selector: storage?.selector ?? "compare:"))
    }

    /// The order of two objects by the key's values, reversed when
    /// descending: NSComparisonResult.
    @ObjCMethod("compareObject:toObject:")
    func compare(_ a: ObjCObject?, to b: ObjCObject?) -> Int {
        guard let storage else { return 0 }
        let left = storage.key.map { PredicateEvaluation.value(of: $0, in: a?.objcObject) } ?? a?.objcObject
        let right = storage.key.map { PredicateEvaluation.value(of: $0, in: b?.objcObject) } ?? b?.objcObject
        var order: Int
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
        return "(\(storage.key ?? "(null)"), \(storage.ascending ? "ascending" : "descending"), NO, \(storage.selector))"
    }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> NSSortDescriptor { self }
}
