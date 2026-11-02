import CPerryFoundation
import Glibc
import PerryObjCInterop

/// An NSSet's members in insertion order, each retained.
final class SetStorage {
    private(set) var members: [id] = []
    private var index: [ObjectKey: Int] = [:]
    let enumeration = EnumerationBuffer()

    deinit {
        for member in members { ObjC.release(member) }
    }

    func member(_ object: id) -> id? {
        index[ObjectKey(object: object)].map { members[$0] }
    }

    func add(_ object: id) {
        guard index[ObjectKey(object: object)] == nil else { return }
        index[ObjectKey(object: object)] = members.count
        members.append(ObjC.retain(object)!)
        enumeration.mutated()
    }

    func remove(_ object: id) {
        guard let position = index.removeValue(forKey: ObjectKey(object: object)) else { return }
        let removed = members.remove(at: position)
        for (key, at) in index where at > position {
            index[key] = at - 1
        }
        enumeration.mutated()
        ObjC.release(removed)
    }

    func removeAll() {
        let removed = members
        members.removeAll()
        index.removeAll()
        enumeration.mutated()
        for member in removed { ObjC.release(member) }
    }
}

enum Sets {
    nonisolated(unsafe) static var setClass: Class!
    nonisolated(unsafe) static var mutableClass: Class!

    static func storage(_ object: id?) -> SetStorage? {
        Storage.get(object, as: SetStorage.self)
    }

    static func elements(_ object: id?) -> [id] {
        storage(object)?.members ?? []
    }

    static func initialize(_ object: id?, _ members: [id]) -> id? {
        guard let object else { return nil }
        let storage = SetStorage()
        for member in members { storage.add(member) }
        Storage.set(object, storage)
        return object
    }

    static func make(_ members: [id], cls: id? = nil) -> id {
        initialize(Storage.allocate(cls ?? UnsafeMutableRawPointer(setClass)), members)!
    }

    static func autoreleased(_ members: [id], cls: id? = nil) -> id {
        ObjC.autorelease(make(members, cls: cls))!
    }

    static func install(superclass: Class) {
        let set = ClassDefinition(PERRY_CLASS_NSSet, name: "NSSet", superclass: superclass,
                                  StorageAllocation.self, NSSetMethods.self)
        setClass = set.cls
        set.addMethod("setWithObjects:", types: "@24@0:8@16",
                      implementation: variadicEntry(perry_imp_setWithObjects), isClassMethod: true)
        mutableClass = ClassDefinition(PERRY_CLASS_NSMutableSet, name: "NSMutableSet", superclass: set.cls,
                                       NSMutableSetMethods.self).cls
    }
}

@ObjCImplementation
enum NSSetMethods {
    @ObjCClassMethod("set")
    static func set(_ cls: id?) -> id? { Sets.autoreleased([], cls: cls) }

    @ObjCClassMethod("setWithObject:")
    static func set(_ cls: id?, object: id?) -> id? { Sets.autoreleased(object.map { [$0] } ?? [], cls: cls) }

    @ObjCClassMethod("setWithArray:")
    static func set(_ cls: id?, array: id?) -> id? { Sets.autoreleased(Arrays.elements(array), cls: cls) }

    @ObjCClassMethod("setWithObjects:count:")
    static func set(_ cls: id?, objects: UnsafePointer<id?>?, count: UInt) -> id? {
        Sets.autoreleased(Arrays.objects(objects, count: count, method: "+[NSSet setWithObjects:count:]"), cls: cls)
    }

    @ObjCMethod("init")
    static func initialize(_ object: id?) -> id? { Sets.initialize(object, []) }

    @ObjCMethod("initWithArray:")
    static func initialize(_ object: id?, array: id?) -> id? { Sets.initialize(object, Arrays.elements(array)) }

    @ObjCMethod("initWithObjects:count:")
    static func initialize(_ object: id?, objects: UnsafePointer<id?>?, count: UInt) -> id? {
        Sets.initialize(object, Arrays.objects(objects, count: count, method: "-[NSSet initWithObjects:count:]"))
    }

    @ObjCMethod("dealloc")
    static func dealloc(_ object: id?) {
        guard let object else { return }
        Storage.set(object, nil)
        ObjC.superDealloc(object, from: Sets.setClass)
    }

    @ObjCMethod("count")
    static func count(_ object: id?) -> UInt { UInt(Sets.elements(object).count) }

    @ObjCMethod("member:")
    static func member(_ object: id?, _ candidate: id?) -> id? {
        guard let candidate else { return nil }
        return Sets.storage(object)?.member(candidate)
    }

    @ObjCMethod("containsObject:")
    static func contains(_ object: id?, _ candidate: id?) -> Bool { member(object, candidate) != nil }

    @ObjCMethod("allObjects")
    static func allObjects(_ object: id?) -> id? { Arrays.autoreleased(Sets.elements(object)) }

    @ObjCMethod("anyObject")
    static func anyObject(_ object: id?) -> id? { Sets.elements(object).first }

    @ObjCMethod("isSubsetOfSet:")
    static func isSubset(_ object: id?, of other: id?) -> Bool {
        Sets.elements(object).allSatisfy { contains(other, $0) }
    }

    @ObjCMethod("intersectsSet:")
    static func intersects(_ object: id?, _ other: id?) -> Bool {
        Sets.elements(object).contains { contains(other, $0) }
    }

    @ObjCMethod("isEqualToSet:")
    static func isEqual(_ object: id?, toSet other: id?) -> Bool {
        count(object) == count(other) && isSubset(object, of: other)
    }

    @ObjCMethod("isEqual:")
    static func isEqual(_ object: id?, _ other: id?) -> Bool {
        object == other || (ObjC.isKind(other, of: Sets.setClass) && isEqual(object, toSet: other))
    }

    @ObjCMethod("hash")
    static func hash(_ object: id?) -> UInt { count(object) }

    @ObjCMethod("description")
    static func description(_ object: id?) -> id? { Strings.autoreleased(Describe.object(object, indent: 0)) }

    @ObjCMethod("enumerateObjectsUsingBlock:")
    static func enumerate(_ object: id?, block: ObjCBlock?) {
        guard let block else { return }
        let body = Blocks.invoke(block, as: (@convention(c) (id, id?, UnsafeMutablePointer<Bool>) -> Void).self)
        var stop = false
        for member in Sets.elements(object) {
            body(block, member, &stop)
            if stop { break }
        }
    }

    @ObjCMethod("countByEnumeratingWithState:objects:count:")
    static func enumerate(_ object: id?, state: UnsafeMutableRawPointer?, objects: UnsafeMutablePointer<id?>?,
                          count: UInt) -> UInt {
        Sets.storage(object)?.enumeration.enumerate(Sets.elements(object), state: state) ?? 0
    }

    @ObjCMethod("copyWithZone:")
    static func copy(_ object: id?, zone: UnsafeMutableRawPointer?) -> id? { ObjC.retain(object) }

    @ObjCMethod("mutableCopyWithZone:")
    static func mutableCopy(_ object: id?, zone: UnsafeMutableRawPointer?) -> id? {
        Sets.make(Sets.elements(object), cls: UnsafeMutableRawPointer(Sets.mutableClass))
    }
}

@ObjCImplementation
enum NSMutableSetMethods {
    private static func storage(_ object: id?) -> SetStorage {
        guard let storage = Sets.storage(object) else {
            foundationFatal("mutating method sent to an uninitialized NSMutableSet")
        }
        return storage
    }

    @ObjCClassMethod("setWithCapacity:")
    static func set(_ cls: id?, capacity: UInt) -> id? { Sets.autoreleased([], cls: cls) }

    @ObjCMethod("initWithCapacity:")
    static func initialize(_ object: id?, capacity: UInt) -> id? { Sets.initialize(object, []) }

    @ObjCMethod("copyWithZone:")
    static func copy(_ object: id?, zone: UnsafeMutableRawPointer?) -> id? { Sets.make(Sets.elements(object)) }

    @ObjCMethod("addObject:")
    static func add(_ object: id?, _ member: id?) {
        guard let member else { foundationFatal("-[NSMutableSet addObject:]: object cannot be nil") }
        storage(object).add(member)
    }

    @ObjCMethod("addObjectsFromArray:")
    static func add(_ object: id?, objectsFrom array: id?) {
        for member in Arrays.elements(array) { storage(object).add(member) }
    }

    @ObjCMethod("removeObject:")
    static func remove(_ object: id?, _ member: id?) {
        if let member { storage(object).remove(member) }
    }

    @ObjCMethod("removeAllObjects")
    static func removeAll(_ object: id?) { storage(object).removeAll() }

    @ObjCMethod("unionSet:")
    static func union(_ object: id?, _ other: id?) {
        for member in Sets.elements(other) { storage(object).add(member) }
    }

    @ObjCMethod("minusSet:")
    static func minus(_ object: id?, _ other: id?) {
        for member in Sets.elements(other) { storage(object).remove(member) }
    }

    @ObjCMethod("intersectSet:")
    static func intersect(_ object: id?, _ other: id?) {
        for member in Sets.elements(object) where !NSSetMethods.contains(other, member) {
            storage(object).remove(member)
        }
    }
}

/// + (id)setWithObjects:(id)first, ... nil
@c
public func perry_foundation_setWithObjects(_ cls: id?, _ cmd: SEL?, _ first: id?,
                                            _ arguments: UnsafeRawPointer?) -> id? {
    Sets.autoreleased(nilTerminated(first, arguments), cls: cls)
}
