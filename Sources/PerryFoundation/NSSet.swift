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
        guard let object else { return [] }
        if let storage = storage(object) {
            return storage.members
        }
        // Another library's set, such as Swift's: what it enumerates.
        guard ObjC.overrides(object, Selectors.count, of: setClass) else { return [] }
        return ObjC.enumerated(ObjC.send(object, Selectors.objectEnumerator))
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


    /// A new set wrapped for returning, +1.
    static func owned(_ members: [id], cls: id? = nil) -> NSSet {
        NSSet(objCOwned: make(members, cls: cls))
    }
}

/// NSSet.
@ObjCClass("NSSet")
public class NSSet: NSObject {
    /// What the Swift runtime asks to tell Foundation's classes apart.
    @ObjCMethod("isNSSet__") func isNSSet__() -> Bool { true }

    /// Set-up after the class is defined.
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        Sets.setClass = cls.storage
        cls.addMethod("setWithObjects:", types: "@24@0:8@16",
                      implementation: variadicEntry(perry_imp_setWithObjects), isClassMethod: true)
        cls.addMethod("initWithObjects:", types: "@24@0:8@16",
                      implementation: variadicEntry(perry_imp_initSetWithObjects), isClassMethod: false)
    }

    var members: [id] { Sets.elements(objcObject) }

    private func setMembers(_ members: [id]) -> Self {
        _ = Sets.initialize(objcObject, members)
        return self
    }

    @ObjCClassMethod("set")
    static func set(_ cls: ObjCClass) -> NSSet { Sets.owned([], cls: cls.pointer) }

    @ObjCClassMethod("setWithObject:")
    static func set(_ cls: ObjCClass, object: ObjCObject) -> NSSet { Sets.owned([object.id], cls: cls.pointer) }

    @ObjCClassMethod("setWithArray:")
    static func set(_ cls: ObjCClass, array: NSArray?) -> NSSet { Sets.owned(array?.elements ?? [], cls: cls.pointer) }

    @ObjCClassMethod("setWithObjects:count:")
    static func set(_ cls: ObjCClass, objects: UnsafePointer<id?>?, count: UInt) -> NSSet {
        Sets.owned(Arrays.objects(objects, count: count, method: "+[NSSet setWithObjects:count:]"), cls: cls.pointer)
    }

    @ObjCClassMethod("setWithSet:")
    static func set(_ cls: ObjCClass, set other: ObjCObject?) -> NSSet { Sets.owned(Sets.elements(other?.id), cls: cls.pointer) }

    @ObjCMethod("init")
    func initialize() -> Self { setMembers([]) }

    @ObjCMethod("setByAddingObjectsFromSet:")
    func adding(objectsFrom other: NSSet?) -> NSSet {
        var members = self.members
        for member in other?.members ?? [] where !members.contains(where: { $0 == member || ObjC.sendBool($0, Selectors.isEqual, member) }) {
            members.append(member)
        }
        return Sets.owned(members)
    }

    @ObjCMethod("objectsPassingTest:")
    func objects(passingTest block: ObjCBlock) -> NSSet {
        let test = block.function(as: (@convention(c) (id, id?, UnsafeMutablePointer<Bool>) -> Bool).self)
        var passed: [id] = []
        var stop = false
        for member in members {
            if test(block.object, member, &stop) { passed.append(member) }
            if stop { break }
        }
        return Sets.owned(passed)
    }

    @ObjCMethod("objectsWithOptions:passingTest:")
    func objects(options: UInt, passingTest block: ObjCBlock) -> NSSet { objects(passingTest: block) }

    @ObjCMethod("initWithSet:")
    func initialize(set other: ObjCObject?) -> Self { setMembers(Sets.elements(other?.id)) }

    /// With copyItems, each member is the member's -copy.
    @ObjCMethod("initWithSet:copyItems:")
    func initialize(set other: ObjCObject?, copyItems: Bool) -> Self {
        guard copyItems else { return initialize(set: other) }
        let copies = Sets.elements(other?.id).map { ObjC.send($0, Selectors.copyWithZone, nil) ?? ObjC.retain($0)! }
        defer { copies.forEach { ObjC.release($0) } }
        return setMembers(copies)
    }

    @ObjCMethod("initWithArray:")
    func initialize(array: NSArray?) -> Self { setMembers(array?.elements ?? []) }

    @ObjCMethod("initWithObjects:count:")
    func initialize(objects: UnsafePointer<id?>?, count: UInt) -> Self {
        setMembers(Arrays.objects(objects, count: count, method: "-[NSSet initWithObjects:count:]"))
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: Sets.setClass)
    }

    @ObjCMethod("count")
    func count() -> UInt { UInt(members.count) }

    @ObjCMethod("member:")
    func member(_ candidate: ObjCObject?) -> ObjCObject? {
        candidate.flatMap { Sets.storage(objcObject)?.member($0.id) }.map(ObjCObject.init)
    }

    @ObjCMethod("containsObject:")
    func contains(_ candidate: ObjCObject?) -> Bool { member(candidate) != nil }

    @ObjCMethod("allObjects")
    func allObjects() -> NSArray { Arrays.owned(members) }

    /// The members, unretained, into a buffer of count slots; Swift's Set
    /// copies a bridged set this way.
    @ObjCMethod("getObjects:")
    func getObjects(_ buffer: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) {
        guard let buffer else { return }
        for (index, member) in members.enumerated() { buffer[index] = member }
    }

    @ObjCMethod("getObjects:count:")
    func getObjects(_ buffer: UnsafeMutablePointer<UnsafeMutableRawPointer?>?, count: UInt) {
        guard let buffer else { return }
        for (index, member) in members.prefix(Int(count)).enumerated() { buffer[index] = member }
    }

    @ObjCMethod("anyObject")
    func anyObject() -> ObjCObject? { members.first.map(ObjCObject.init) }

    @ObjCMethod("isSubsetOfSet:")
    func isSubset(of other: NSSet?) -> Bool {
        guard let other else { return members.isEmpty }
        return members.allSatisfy { other.contains(ObjCObject($0)) }
    }

    @ObjCMethod("intersectsSet:")
    func intersects(_ other: NSSet?) -> Bool {
        guard let other else { return false }
        return members.contains { other.contains(ObjCObject($0)) }
    }

    @ObjCMethod("isEqualToSet:")
    func isEqual(toSet other: NSSet?) -> Bool {
        guard let other else { return false }
        return count() == other.count() && isSubset(of: other)
    }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: ObjCObject?) -> Bool {
        guard let other else { return false }
        return other.id == objcObject || (other.is(NSSet.self) && isEqual(toSet: other.unsafeCast(to: NSSet.self)))
    }

    @ObjCMethod("hash")
    func hash() -> UInt { count() }

    @ObjCMethod("description")
    func description() -> String { Describe.object(objcObject, indent: 0) }

    @ObjCMethod("enumerateObjectsUsingBlock:")
    func enumerate(block: ObjCBlock) {
        let body = block.function(as: (@convention(c) (id, id?, UnsafeMutablePointer<Bool>) -> Void).self)
        var stop = false
        for member in members {
            body(block.object, member, &stop)
            if stop { break }
        }
    }

    @ObjCMethod("countByEnumeratingWithState:objects:count:")
    func enumerate(state: UnsafeMutableRawPointer?, objects: UnsafeMutablePointer<id?>?, count: UInt) -> UInt {
        Sets.storage(objcObject)?.enumeration.enumerate(members, state: state, buffer: objects, count: count) ?? 0
    }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> NSSet { self }

    @ObjCMethod("mutableCopyWithZone:")
    func mutableCopy(zone: UnsafeMutableRawPointer?) -> NSSet {
        Sets.owned(members, cls: UnsafeMutableRawPointer(Sets.mutableClass))
    }
}

/// NSMutableSet.
@ObjCClass("NSMutableSet")
public class NSMutableSet: NSSet {
    /// Set-up after the class is defined.
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        Sets.mutableClass = cls.storage
    }

    private var storage: SetStorage {
        guard let storage = Sets.storage(objcObject) else {
            foundationFatal("mutating method sent to an uninitialized NSMutableSet")
        }
        return storage
    }

    @ObjCClassMethod("setWithCapacity:")
    static func set(_ cls: ObjCClass, capacity: UInt) -> NSSet { Sets.owned([], cls: cls.pointer) }

    @ObjCMethod("initWithCapacity:")
    func initialize(capacity: UInt) -> Self {
        _ = Sets.initialize(objcObject, [])
        return self
    }

    @ObjCMethod("copyWithZone:")
    override func copy(zone: UnsafeMutableRawPointer?) -> NSSet { Sets.owned(storage.members) }

    @ObjCMethod("addObject:")
    func add(_ member: ObjCObject) { storage.add(member.id) }

    @ObjCMethod("addObjectsFromArray:")
    func add(objectsFrom array: NSArray?) {
        for member in array?.elements ?? [] { storage.add(member) }
    }

    @ObjCMethod("removeObject:")
    func remove(_ member: ObjCObject?) {
        if let member { storage.remove(member.id) }
    }

    @ObjCMethod("removeAllObjects")
    func removeAll() { storage.removeAll() }

    /// Its members become the other set's.
    @ObjCMethod("setSet:")
    func setSet(_ other: NSSet?) {
        let members = other?.members ?? []
        members.forEach { _ = ObjC.retain($0) }
        storage.removeAll()
        for member in members { storage.add(member); ObjC.release(member) }
    }

    @ObjCMethod("unionSet:")
    func union(_ other: NSSet?) {
        for member in other?.members ?? [] { storage.add(member) }
    }

    @ObjCMethod("minusSet:")
    func minus(_ other: NSSet?) {
        for member in other?.members ?? [] { storage.remove(member) }
    }

    @ObjCMethod("intersectSet:")
    func intersect(_ other: NSSet?) {
        for member in storage.members where !(other?.contains(ObjCObject(member)) ?? false) {
            storage.remove(member)
        }
    }
}

/// + (id)setWithObjects:(id)first, ... nil
@c
public func perry_foundation_setWithObjects(_ cls: id?, _ cmd: SEL?, _ first: id?,
                                            _ arguments: UnsafeRawPointer?) -> id? {
    Sets.autoreleased(nilTerminated(first, arguments), cls: cls)
}

/// - (id)initWithObjects:(id)first, ... nil
@c
public func perry_foundation_initSetWithObjects(_ object: id?, _ cmd: SEL?, _ first: id?, _ arguments: UnsafeRawPointer?) -> id? {
    Sets.initialize(object, nilTerminated(first, arguments))
}
