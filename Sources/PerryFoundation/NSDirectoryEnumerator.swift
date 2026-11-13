import PerryObjCInterop

// NSDirectoryEnumerator: what NSFileManager's enumerators are. Like the
// other enumerators it walks a snapshot, taken when it is made, so a
// subtree can't be skipped and every item is at the level it was found at.

@ObjCClass("NSDirectoryEnumerator")
public final class NSDirectoryEnumerator: NSEnumerator {
    nonisolated(unsafe) static var directoryEnumeratorClass: Class!

    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        directoryEnumeratorClass = cls.storage
    }

    /// A new enumerator over `objects`, autoreleased.
    static func make(_ objects: [id]) -> ObjCObject {
        let enumerator = Storage.allocate(directoryEnumeratorClass)!
        Storage.set(enumerator, EnumeratorState(objects))
        return ObjCObject(objcObject: ObjC.autorelease(enumerator)!, ownership: .retain)
    }

    @ObjCMethod("nextObject")
    override func nextObject() -> ObjCObject? {
        guard let state = Storage.get(objcObject, as: EnumeratorState.self), state.index < state.objects.count else { return nil }
        defer { state.index += 1 }
        return state.objects[state.index]
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: NSDirectoryEnumerator.directoryEnumeratorClass)
    }

    @ObjCMethod("skipDescendants") func skipDescendants() {}
    @ObjCMethod("skipDescendents") func skipDescendents() {}
    @ObjCMethod("level") func level() -> UInt { 0 }
    @ObjCMethod("isEnumeratingDirectoryPostOrder") func isEnumeratingDirectoryPostOrder() -> Bool { false }
    @ObjCMethod("fileAttributes") func fileAttributes() -> ObjCObject? { nil }
    @ObjCMethod("directoryAttributes") func directoryAttributes() -> ObjCObject? { nil }
}
