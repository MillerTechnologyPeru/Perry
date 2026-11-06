import CPerryFoundation
import FoundationEssentials
import Glibc
import PerryObjCInterop

// NSEnumerator, and the enumerators collections hand out: each walks a
// snapshot of the collection's objects, taken when it is made.

/// NSEnumerator: subclasses give -nextObject; -allObjects and fast
/// enumeration are built on it.
@ObjCClass("NSEnumerator")
public class NSEnumerator: NSObject {
    @ObjCMethod("nextObject") func nextObject() -> ObjCObject? { nil }

    @ObjCMethod("allObjects")
    func allObjects() -> NSArray {
        var objects: [id] = []
        while let next = ObjC.send(objcObject, ObjC.selector("nextObject")) { objects.append(next) }
        return NSArray(objcObject: Arrays.autoreleased(objects), ownership: .retain)
    }

    /// One object at a time, through -nextObject.
    @ObjCMethod("countByEnumeratingWithState:objects:count:")
    func enumerate(state: UnsafeMutableRawPointer?, objects: UnsafeMutablePointer<id?>?, count: UInt) -> UInt {
        guard let state, let objects, count > 0, let next = ObjC.send(objcObject, ObjC.selector("nextObject")) else { return 0 }
        objects[0] = next
        state.storeBytes(of: UnsafeMutableRawPointer(objects), toByteOffset: DarwinLayout.enumerationItems,
                         as: UnsafeMutableRawPointer.self)
        // The mutation pointer must point somewhere that does not change.
        state.storeBytes(of: UnsafeMutableRawPointer(state), toByteOffset: DarwinLayout.enumerationMutations,
                         as: UnsafeMutableRawPointer.self)
        return 1
    }
}

final class EnumeratorState {
    let objects: [ObjCObject]
    var index = 0

    init(_ objects: [id]) { self.objects = objects.map { ObjCObject($0) } }
}

/// The enumerator collections hand out, over a snapshot of their objects.
@ObjCClass("__NSFastEnumerationEnumerator")
public final class NSFastEnumerationEnumerator: NSEnumerator {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        Enumerators.enumeratorClass = cls.storage
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
        ObjC.superDealloc(objcObject, from: Enumerators.enumeratorClass)
    }
}

enum Enumerators {
    nonisolated(unsafe) static var enumeratorClass: Class!

    /// A new enumerator over `objects`, autoreleased.
    static func make(_ objects: [id]) -> ObjCObject {
        let enumerator = Storage.allocate(enumeratorClass)!
        Storage.set(enumerator, EnumeratorState(objects))
        return ObjCObject(objcObject: ObjC.autorelease(enumerator)!, ownership: .retain)
    }
}

@ObjCCategory("Enumerators")
extension NSArray {
    @ObjCMethod("objectEnumerator") func arrayObjectEnumerator() -> ObjCObject { Enumerators.make(elements) }
    @ObjCMethod("reverseObjectEnumerator") func arrayReverseObjectEnumerator() -> ObjCObject { Enumerators.make(elements.reversed()) }
}

@ObjCCategory("Enumerators")
extension NSDictionary {
    @ObjCMethod("keyEnumerator") func dictionaryKeyEnumerator() -> ObjCObject { Enumerators.make(entries.map(\.key)) }
    @ObjCMethod("objectEnumerator") func dictionaryObjectEnumerator() -> ObjCObject { Enumerators.make(entries.map(\.value)) }

    /// The keys, in the order the comparator sorts their values.
    @ObjCMethod("keysSortedByValueUsingComparator:")
    func keysSortedByValue(comparator: ObjCBlock) -> NSArray {
        let compare = comparator.function(as: (@convention(c) (id, id?, id?) -> Int).self)
        let sorted = entries.sorted { compare(comparator.object, $0.value, $1.value) < 0 }.map(\.key)
        return NSArray(objcObject: Arrays.autoreleased(sorted), ownership: .retain)
    }

    /// The keys in the order of their values, each compared with the next
    /// by sending it `selector`.
    @ObjCMethod("keysSortedByValueUsingSelector:")
    func keysSortedByValue(using selector: ObjCSelector) -> NSArray {
        let sel = selector.pointer.assumingMemoryBound(to: CChar.self)
        let sorted = entries.sorted { ObjC.sendInt($0.value, sel, $1.value) < 0 }.map(\.key)
        return NSArray(objcObject: Arrays.autoreleased(sorted), ownership: .retain)
    }
}

@ObjCCategory("Enumerators")
extension NSSet {
    @ObjCMethod("objectEnumerator")
    func setObjectEnumerator() -> ObjCObject {
        let all = ObjC.send(objcObject, ObjC.selector("allObjects")).map { Arrays.elements($0) } ?? []
        return Enumerators.make(all)
    }

    /// Each member is sent the message, in no particular order.
    @ObjCMethod("makeObjectsPerformSelector:")
    func setMakeObjectsPerform(_ selector: ObjCSelector) {
        let all = ObjC.send(objcObject, ObjC.selector("allObjects")).map { Arrays.elements($0) } ?? []
        for element in all { _ = ObjC.send(element, selector.pointer.assumingMemoryBound(to: CChar.self)) }
    }

    @ObjCMethod("makeObjectsPerformSelector:withObject:")
    func setMakeObjectsPerform(_ selector: ObjCSelector, with argument: ObjCObject?) {
        let all = ObjC.send(objcObject, ObjC.selector("allObjects")).map { Arrays.elements($0) } ?? []
        for element in all { _ = ObjC.send(element, selector.pointer.assumingMemoryBound(to: CChar.self), argument?.id) }
    }
}
