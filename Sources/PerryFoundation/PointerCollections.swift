import FoundationEssentials
import PerryObjCInterop

// NSHashTable, NSMapTable and NSPointerArray: collections whose members may
// be held weakly (and drop out once deallocated), strongly, or as opaque
// pointers, and compared by -isEqual: and -hash or by identity, as their
// NSPointerFunctionsOptions say.

/// NSPointerFunctionsOptions: memory (strong 0, zeroing weak 1, opaque 2,
/// malloc 3, Mach virtual 4, weak 5) and personality (object 0, opaque
/// 1 << 8, object pointer 2 << 8, C string 3 << 8, struct 4 << 8, integer
/// 5 << 8); copy in 1 << 16.
struct PointerOptions {
    let weak: Bool
    let retains: Bool
    let equality: Bool
    let copies: Bool

    init(_ raw: UInt) {
        let memory = raw & 0xff, personality = raw & 0xff00
        let objects = personality == 0 || personality == 0x200
        weak = memory == 1 || memory == 5
        retains = memory == 0 && objects
        equality = personality == 0
        copies = raw & 0x10000 != 0 && objects
    }

    static let strong = PointerOptions(0)
    static let weakObjects = PointerOptions(5)
}

/// One member: weak, retained or opaque.
final class PointerSlot {
    private let weakReference: WeakObject?
    private let held: id?

    init(_ value: id?, _ options: PointerOptions) {
        var value = value
        if options.copies, let original = value { value = ObjC.send(original, Selectors.copyWithZone, nil) }
        if options.weak {
            weakReference = WeakObject(value)
            held = nil
            if options.copies { ObjC.release(value) }
        } else {
            weakReference = nil
            held = value
            if options.retains, !options.copies { _ = ObjC.retain(value) }
        }
        retains = options.retains && !options.weak
    }

    private let retains: Bool

    deinit { if retains { ObjC.release(held) } }

    /// The member, or nil once a weak one is gone.
    var value: id? { weakReference.map { $0.object } ?? held }
}

private func same(_ a: id?, _ b: id?, _ options: PointerOptions) -> Bool {
    guard let a, let b else { return a == b }
    return a == b || (options.equality && ObjC.sendBool(a, Selectors.isEqual, b))
}

// MARK: - NSHashTable

final class HashTableState {
    let options: PointerOptions
    let rawOptions: UInt
    var slots: [PointerSlot] = []
    let enumeration = EnumerationBuffer()

    init(_ raw: UInt) {
        rawOptions = raw
        options = PointerOptions(raw)
    }

    /// The members still there.
    var members: [id] {
        slots.removeAll { $0.value == nil }
        return slots.compactMap(\.value)
    }

    func index(of object: id) -> Int? { slots.firstIndex { same($0.value, object, options) } }

    func add(_ object: id) {
        guard index(of: object) == nil else { return }
        slots.append(PointerSlot(object, options))
        enumeration.mutated()
    }

    func remove(_ object: id) {
        slots.removeAll { same($0.value, object, options) }
        enumeration.mutated()
    }
}

enum HashTables {
    nonisolated(unsafe) static var tableClass: Class!

    static func state(_ object: id?) -> HashTableState? { Storage.get(object, as: HashTableState.self) }

    /// A new table, autoreleased.
    static func make(_ options: UInt, cls: UnsafeMutableRawPointer? = nil) -> id {
        let object = Storage.allocate(cls ?? UnsafeMutableRawPointer(tableClass))!
        Storage.set(object, HashTableState(options))
        return ObjC.autorelease(object)!
    }
}

@ObjCClass("NSHashTable")
public final class NSHashTable: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        HashTables.tableClass = cls.storage
    }

    private var state: HashTableState {
        if let state = HashTables.state(objcObject) { return state }
        let state = HashTableState(0)
        Storage.set(objcObject, state)
        return state
    }

    @ObjCClassMethod("hashTableWithOptions:")
    static func make(_ cls: ObjCClass, options: UInt) -> UnsafeMutableRawPointer { HashTables.make(options, cls: cls.pointer) }
    @ObjCClassMethod("weakObjectsHashTable")
    static func weakObjects(_ cls: ObjCClass) -> UnsafeMutableRawPointer { HashTables.make(5, cls: cls.pointer) }
    @ObjCClassMethod("hashTableWithWeakObjects")
    static func weakObjectsLegacy(_ cls: ObjCClass) -> UnsafeMutableRawPointer { HashTables.make(5, cls: cls.pointer) }

    @ObjCMethod("init")
    func initialize() -> Self { initialize(options: 0, capacity: 0) }

    @ObjCMethod("initWithOptions:capacity:")
    func initialize(options: UInt, capacity: UInt) -> Self {
        Storage.set(objcObject, HashTableState(options))
        return self
    }

    @ObjCMethod("initWithPointerFunctions:capacity:")
    func initialize(functions: ObjCObject?, capacity: UInt) -> Self { initialize(options: 0, capacity: capacity) }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: HashTables.tableClass)
    }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer {
        let copy = ObjC.retain(HashTables.make(state.rawOptions))!
        for member in state.members { HashTables.state(copy)?.add(member) }
        return copy
    }

    @ObjCMethod("count") func count() -> UInt { UInt(state.members.count) }
    @ObjCMethod("addObject:") func add(_ object: ObjCObject?) { if let object { state.add(object.id) } }
    @ObjCMethod("removeObject:") func remove(_ object: ObjCObject?) { if let object { state.remove(object.id) } }
    @ObjCMethod("removeAllObjects")
    func removeAll() {
        state.slots.removeAll()
        state.enumeration.mutated()
    }
    @ObjCMethod("containsObject:") func contains(_ object: ObjCObject?) -> Bool { object.map { state.index(of: $0.id) != nil } ?? false }
    @ObjCMethod("member:")
    func member(_ object: ObjCObject?) -> UnsafeMutableRawPointer? {
        guard let object, let index = state.index(of: object.id) else { return nil }
        return state.slots[index].value
    }
    @ObjCMethod("anyObject") func anyObject() -> UnsafeMutableRawPointer? { state.members.first }
    @ObjCMethod("allObjects") func allObjects() -> UnsafeMutableRawPointer? { Arrays.autoreleased(state.members) }
    @ObjCMethod("setRepresentation") func setRepresentation() -> UnsafeMutableRawPointer? { Sets.autoreleased(state.members) }
    @ObjCMethod("objectEnumerator") func objectEnumerator() -> ObjCObject { Enumerators.make(state.members) }
    @ObjCMethod("pointerFunctions") func pointerFunctions() -> UnsafeMutableRawPointer? { nil }

    @ObjCMethod("unionHashTable:")
    func union(_ other: ObjCObject?) { for member in HashTables.state(other?.id)?.members ?? [] { state.add(member) } }
    @ObjCMethod("minusHashTable:")
    func minus(_ other: ObjCObject?) { for member in HashTables.state(other?.id)?.members ?? [] { state.remove(member) } }
    @ObjCMethod("intersectHashTable:")
    func intersect(_ other: ObjCObject?) {
        let keep = HashTables.state(other?.id)
        for member in state.members where keep?.index(of: member) == nil { state.remove(member) }
    }
    @ObjCMethod("intersectsHashTable:")
    func intersects(_ other: ObjCObject?) -> Bool {
        let theirs = HashTables.state(other?.id)
        return state.members.contains { theirs?.index(of: $0) != nil }
    }
    @ObjCMethod("isSubsetOfHashTable:")
    func isSubset(of other: ObjCObject?) -> Bool {
        let theirs = HashTables.state(other?.id)
        return state.members.allSatisfy { theirs?.index(of: $0) != nil }
    }
    @ObjCMethod("isEqualToHashTable:")
    func isEqual(toHashTable other: ObjCObject?) -> Bool {
        guard let theirs = HashTables.state(other?.id) else { return false }
        return theirs.members.count == state.members.count && isSubset(of: other)
    }

    @ObjCMethod("countByEnumeratingWithState:objects:count:")
    func enumerate(state enumerationState: UnsafeMutableRawPointer?, objects: UnsafeMutablePointer<id?>?, count: UInt) -> UInt {
        state.enumeration.enumerate(state.members, state: enumerationState, buffer: objects, count: count)
    }

    @ObjCMethod("description")
    func description() -> String { "NSHashTable {\n" + state.members.map { "    " + Format.describe($0) + "\n" }.joined() + "}" }
}

// MARK: - NSMapTable

final class MapTableState {
    let keyOptions: PointerOptions
    let valueOptions: PointerOptions
    let rawKeyOptions: UInt
    let rawValueOptions: UInt
    var entries: [(key: PointerSlot, value: PointerSlot)] = []
    let enumeration = EnumerationBuffer()

    init(keys: UInt, values: UInt) {
        (rawKeyOptions, rawValueOptions) = (keys, values)
        (keyOptions, valueOptions) = (PointerOptions(keys), PointerOptions(values))
    }

    /// The entries whose key and value are still there.
    var live: [(key: id, value: id)] {
        entries.removeAll { $0.key.value == nil || $0.value.value == nil }
        return entries.compactMap { entry in entry.key.value.flatMap { key in entry.value.value.map { (key, $0) } } }
    }

    func index(of key: id) -> Int? { entries.firstIndex { same($0.key.value, key, keyOptions) } }

    func value(for key: id) -> id? { index(of: key).flatMap { entries[$0].value.value } }

    func set(_ value: id, for key: id) {
        let slot = PointerSlot(value, valueOptions)
        if let index = index(of: key) {
            entries[index].value = slot
        } else {
            // Keys are copied only when the options ask for it.
            entries.append((PointerSlot(key, keyOptions), slot))
        }
        enumeration.mutated()
    }

    func remove(_ key: id) {
        entries.removeAll { same($0.key.value, key, keyOptions) }
        enumeration.mutated()
    }
}

enum MapTables {
    nonisolated(unsafe) static var tableClass: Class!

    static func state(_ object: id?) -> MapTableState? { Storage.get(object, as: MapTableState.self) }

    static func make(keys: UInt, values: UInt, cls: UnsafeMutableRawPointer? = nil) -> id {
        let object = Storage.allocate(cls ?? UnsafeMutableRawPointer(tableClass))!
        Storage.set(object, MapTableState(keys: keys, values: values))
        return ObjC.autorelease(object)!
    }
}

@ObjCClass("NSMapTable")
public final class NSMapTable: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        MapTables.tableClass = cls.storage
    }

    private var state: MapTableState {
        if let state = MapTables.state(objcObject) { return state }
        let state = MapTableState(keys: 0, values: 0)
        Storage.set(objcObject, state)
        return state
    }

    @ObjCClassMethod("mapTableWithKeyOptions:valueOptions:")
    static func make(_ cls: ObjCClass, keyOptions: UInt, valueOptions: UInt) -> UnsafeMutableRawPointer {
        MapTables.make(keys: keyOptions, values: valueOptions, cls: cls.pointer)
    }
    @ObjCClassMethod("strongToStrongObjectsMapTable")
    static func strongToStrong(_ cls: ObjCClass) -> UnsafeMutableRawPointer { MapTables.make(keys: 0, values: 0, cls: cls.pointer) }
    @ObjCClassMethod("strongToWeakObjectsMapTable")
    static func strongToWeak(_ cls: ObjCClass) -> UnsafeMutableRawPointer { MapTables.make(keys: 0, values: 5, cls: cls.pointer) }
    @ObjCClassMethod("weakToStrongObjectsMapTable")
    static func weakToStrong(_ cls: ObjCClass) -> UnsafeMutableRawPointer { MapTables.make(keys: 5, values: 0, cls: cls.pointer) }
    @ObjCClassMethod("weakToWeakObjectsMapTable")
    static func weakToWeak(_ cls: ObjCClass) -> UnsafeMutableRawPointer { MapTables.make(keys: 5, values: 5, cls: cls.pointer) }

    @ObjCMethod("init")
    func initialize() -> Self { initialize(keyOptions: 0, valueOptions: 0, capacity: 0) }

    @ObjCMethod("initWithKeyOptions:valueOptions:capacity:")
    func initialize(keyOptions: UInt, valueOptions: UInt, capacity: UInt) -> Self {
        Storage.set(objcObject, MapTableState(keys: keyOptions, values: valueOptions))
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: MapTables.tableClass)
    }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer {
        let copy = ObjC.retain(MapTables.make(keys: state.rawKeyOptions, values: state.rawValueOptions))!
        for entry in state.live { MapTables.state(copy)?.set(entry.value, for: entry.key) }
        return copy
    }

    @ObjCMethod("count") func count() -> UInt { UInt(state.live.count) }
    @ObjCMethod("objectForKey:") func object(forKey key: ObjCObject?) -> UnsafeMutableRawPointer? { key.flatMap { state.value(for: $0.id) } }
    @ObjCMethod("setObject:forKey:")
    func set(_ value: ObjCObject?, forKey key: ObjCObject?) {
        guard let key else { return }
        if let value { state.set(value.id, for: key.id) } else { state.remove(key.id) }
    }
    @ObjCMethod("removeObjectForKey:") func remove(forKey key: ObjCObject?) { if let key { state.remove(key.id) } }
    @ObjCMethod("removeAllObjects")
    func removeAll() {
        state.entries.removeAll()
        state.enumeration.mutated()
    }
    @ObjCMethod("keyEnumerator") func keyEnumerator() -> ObjCObject { Enumerators.make(state.live.map(\.key)) }
    @ObjCMethod("objectEnumerator") func objectEnumerator() -> ObjCObject { Enumerators.make(state.live.map(\.value)) }
    @ObjCMethod("dictionaryRepresentation")
    func dictionaryRepresentation() -> UnsafeMutableRawPointer? { Dictionaries.autoreleased(state.live) }
    @ObjCMethod("keyPointerFunctions") func keyPointerFunctions() -> UnsafeMutableRawPointer? { nil }
    @ObjCMethod("valuePointerFunctions") func valuePointerFunctions() -> UnsafeMutableRawPointer? { nil }

    /// for (id key in table) enumerates the keys.
    @ObjCMethod("countByEnumeratingWithState:objects:count:")
    func enumerate(state enumerationState: UnsafeMutableRawPointer?, objects: UnsafeMutablePointer<id?>?, count: UInt) -> UInt {
        state.enumeration.enumerate(state.live.map(\.key), state: enumerationState, buffer: objects, count: count)
    }

    @ObjCMethod("description")
    func description() -> String {
        "NSMapTable {\n" + state.live.map { "    \(Format.describe($0.key)) -> \(Format.describe($0.value))\n" }.joined() + "}"
    }
}

// MARK: - NSPointerArray

final class PointerArrayState {
    let options: PointerOptions
    let rawOptions: UInt
    var slots: [PointerSlot?] = []
    let enumeration = EnumerationBuffer()

    init(_ raw: UInt) {
        rawOptions = raw
        options = PointerOptions(raw)
    }

    func slot(_ value: UnsafeMutableRawPointer?) -> PointerSlot? { value.map { PointerSlot($0, options) } }
}

enum PointerArrays {
    nonisolated(unsafe) static var arrayClass: Class!

    static func state(_ object: id?) -> PointerArrayState? { Storage.get(object, as: PointerArrayState.self) }

    static func make(_ options: UInt, cls: UnsafeMutableRawPointer? = nil) -> id {
        let object = Storage.allocate(cls ?? UnsafeMutableRawPointer(arrayClass))!
        Storage.set(object, PointerArrayState(options))
        return ObjC.autorelease(object)!
    }
}

@ObjCClass("NSPointerArray")
public final class NSPointerArray: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        PointerArrays.arrayClass = cls.storage
    }

    private var state: PointerArrayState {
        if let state = PointerArrays.state(objcObject) { return state }
        let state = PointerArrayState(0)
        Storage.set(objcObject, state)
        return state
    }

    @ObjCClassMethod("pointerArrayWithOptions:")
    static func make(_ cls: ObjCClass, options: UInt) -> UnsafeMutableRawPointer { PointerArrays.make(options, cls: cls.pointer) }
    @ObjCClassMethod("strongObjectsPointerArray")
    static func strongObjects(_ cls: ObjCClass) -> UnsafeMutableRawPointer { PointerArrays.make(0, cls: cls.pointer) }
    @ObjCClassMethod("weakObjectsPointerArray")
    static func weakObjects(_ cls: ObjCClass) -> UnsafeMutableRawPointer { PointerArrays.make(5, cls: cls.pointer) }

    @ObjCMethod("init") func initialize() -> Self { initialize(options: 0) }
    @ObjCMethod("initWithOptions:")
    func initialize(options: UInt) -> Self {
        Storage.set(objcObject, PointerArrayState(options))
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: PointerArrays.arrayClass)
    }

    @ObjCMethod("count") func count() -> UInt { UInt(state.slots.count) }

    /// Fewer drops the end; more adds NULLs.
    @ObjCMethod("setCount:")
    func setCount(_ count: UInt) {
        let wanted = Int(count)
        if wanted < state.slots.count { state.slots.removeLast(state.slots.count - wanted) }
        else { state.slots += Array(repeating: nil, count: wanted - state.slots.count) }
        state.enumeration.mutated()
    }

    private func check(_ index: UInt, _ method: String, limit: Int? = nil) {
        guard Int(index) < (limit ?? state.slots.count) else {
            foundationFatal("-[NSPointerArray \(method)]: index (\(index)) beyond bounds (\(state.slots.count))")
        }
    }

    @ObjCMethod("pointerAtIndex:")
    func pointer(at index: UInt) -> UnsafeMutableRawPointer? {
        check(index, "pointerAtIndex:")
        return state.slots[Int(index)]?.value
    }

    @ObjCMethod("addPointer:")
    func add(_ pointer: UnsafeMutableRawPointer?) {
        state.slots.append(state.slot(pointer))
        state.enumeration.mutated()
    }

    @ObjCMethod("insertPointer:atIndex:")
    func insert(_ pointer: UnsafeMutableRawPointer?, at index: UInt) {
        check(index, "insertPointer:atIndex:", limit: state.slots.count + 1)
        state.slots.insert(state.slot(pointer), at: Int(index))
        state.enumeration.mutated()
    }

    @ObjCMethod("removePointerAtIndex:")
    func removePointer(at index: UInt) {
        check(index, "removePointerAtIndex:")
        state.slots.remove(at: Int(index))
        state.enumeration.mutated()
    }

    @ObjCMethod("replacePointerAtIndex:withPointer:")
    func replacePointer(at index: UInt, with pointer: UnsafeMutableRawPointer?) {
        check(index, "replacePointerAtIndex:withPointer:")
        state.slots[Int(index)] = state.slot(pointer)
        state.enumeration.mutated()
    }

    /// Drops the NULLs, and weak members that are gone.
    @ObjCMethod("compact")
    func compact() {
        state.slots.removeAll { $0?.value == nil }
        state.enumeration.mutated()
    }

    @ObjCMethod("allObjects") func allObjects() -> UnsafeMutableRawPointer? { Arrays.autoreleased(state.slots.compactMap { $0?.value }) }

    @ObjCMethod("countByEnumeratingWithState:objects:count:")
    func enumerate(state enumerationState: UnsafeMutableRawPointer?, objects: UnsafeMutablePointer<id?>?, count: UInt) -> UInt {
        state.enumeration.enumerate(state.slots.compactMap { $0?.value }, state: enumerationState, buffer: objects, count: count)
    }
}
