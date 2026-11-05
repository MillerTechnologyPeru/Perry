import FoundationEssentials
import CPerryFoundation
import Glibc
import PerryObjCInterop

/// An NSDictionary's entries in insertion order. Keys are copied and values
/// retained, as Foundation does.
final class DictionaryStorage {
    private(set) var keys: [id] = []
    private(set) var values: [id] = []
    private var index: [ObjectKey: Int] = [:]
    let enumeration = EnumerationBuffer()

    deinit {
        for object in keys + values { ObjC.release(object) }
    }

    func value(for key: id) -> id? {
        index[ObjectKey(object: key)].map { values[$0] }
    }

    func set(_ value: id, for key: id) {
        let retained = ObjC.retain(value)!
        if let position = index[ObjectKey(object: key)] {
            let old = values[position]
            values[position] = retained
            ObjC.release(old)
        } else {
            let copied = ObjC.send(key, Selectors.copyWithZone, nil) ?? ObjC.retain(key)!
            index[ObjectKey(object: copied)] = keys.count
            keys.append(copied)
            values.append(retained)
        }
        enumeration.mutated()
    }

    func remove(_ key: id) {
        guard let position = index.removeValue(forKey: ObjectKey(object: key)) else { return }
        let removed = [keys.remove(at: position), values.remove(at: position)]
        for (key, at) in index where at > position {
            index[key] = at - 1
        }
        enumeration.mutated()
        for object in removed { ObjC.release(object) }
    }

    func removeAll() {
        let removed = keys + values
        keys.removeAll()
        values.removeAll()
        index.removeAll()
        enumeration.mutated()
        for object in removed { ObjC.release(object) }
    }
}

enum Dictionaries {
    nonisolated(unsafe) static var dictionaryClass: Class!
    nonisolated(unsafe) static var mutableClass: Class!
    nonisolated(unsafe) static var constantClass: Class!

    static func storage(_ object: id?) -> DictionaryStorage? {
        Storage.get(object, as: DictionaryStorage.self)
    }

    /// The entries of an NSDictionary, including constant literals:
    /// { isa, options, count, keys, objects }.
    static func entries(_ object: id?) -> [(key: id, value: id)] {
        guard let object else { return [] }
        if ObjC.objectGetClass(object) == constantClass {
            let count = Int(object.load(fromByteOffset: DarwinLayout.dictionaryCount, as: UInt.self))
            guard count > 0,
                  let keys = object.load(fromByteOffset: DarwinLayout.dictionaryKeys, as: UnsafePointer<id>?.self),
                  let values = object.load(fromByteOffset: DarwinLayout.dictionaryObjects, as: UnsafePointer<id>?.self) else { return [] }
            return (0..<count).map { (keys[$0], values[$0]) }
        }
        if let storage = storage(object) {
            return Array(zip(storage.keys, storage.values)).map { (key: $0.0, value: $0.1) }
        }
        // Another library's dictionary, such as Swift's: its keys, and the
        // value for each.
        guard ObjC.overrides(object, Selectors.count, of: dictionaryClass) else { return [] }
        return ObjC.enumerated(ObjC.send(object, Selectors.keyEnumerator)).compactMap { key in
            ObjC.send(object, Selectors.objectForKey, key).map { (key: key, value: $0) }
        }
    }

    static func value(_ object: id?, for key: id?) -> id? {
        guard let key else { return nil }
        if let storage = storage(object) {
            return storage.value(for: key)
        }
        return entries(object).first { ObjectKey(object: $0.key) == ObjectKey(object: key) }?.value
    }

    static func initialize(_ object: id?, _ entries: [(key: id, value: id)]) -> id? {
        guard let object else { return nil }
        let storage = DictionaryStorage()
        for entry in entries { storage.set(entry.value, for: entry.key) }
        Storage.set(object, storage)
        return object
    }

    static func make(_ entries: [(key: id, value: id)], cls: id? = nil) -> id {
        initialize(Storage.allocate(cls ?? UnsafeMutableRawPointer(dictionaryClass)), entries)!
    }

    static func autoreleased(_ entries: [(key: id, value: id)], cls: id? = nil) -> id {
        ObjC.autorelease(make(entries, cls: cls))!
    }

    /// Pairs from two arrays of the same length.
    static func pairs(objects: id?, keys: id?, method: String) -> [(key: id, value: id)] {
        let values = Arrays.elements(objects), keys = Arrays.elements(keys)
        guard values.count == keys.count else {
            foundationFatal("\(method): count of objects (\(values.count)) differs from count of keys (\(keys.count))")
        }
        return zip(keys, values).map { (key: $0, value: $1) }
    }

    static func pairs(objects: UnsafePointer<id?>?, keys: UnsafePointer<id?>?, count: UInt, method: String) -> [(key: id, value: id)] {
        guard let objects, let keys else { return [] }
        return (0..<Int(count)).map { index in
            guard let key = keys[index], let value = objects[index] else {
                foundationFatal("\(method): attempt to insert nil object from objects[\(index)]")
            }
            return (key, value)
        }
    }


    /// A new dictionary wrapped for returning, +1.
    static func owned(_ entries: [(key: id, value: id)], cls: id? = nil) -> NSDictionary {
        NSDictionary(objCOwned: make(entries, cls: cls))
    }
}

/// NSDictionary.
@ObjCClass("NSDictionary")
public class NSDictionary: NSObject {
    /// What the Swift runtime asks to tell Foundation's classes apart.
    @ObjCMethod("isNSDictionary__") func isNSDictionary__() -> Bool { true }

    /// Set-up after the class is defined.
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        Dictionaries.dictionaryClass = cls.storage
        cls.addMethod("dictionaryWithObjectsAndKeys:", types: "@24@0:8@16",
                      implementation: variadicEntry(perry_imp_dictionaryWithObjectsAndKeys), isClassMethod: true)
        cls.addMethod("initWithObjectsAndKeys:", types: "@24@0:8@16",
                      implementation: variadicEntry(perry_imp_initWithObjectsAndKeys), isClassMethod: false)
    }

    var entries: [(key: id, value: id)] { Dictionaries.entries(objcObject) }

    private func setEntries(_ entries: [(key: id, value: id)]) -> Self {
        _ = Dictionaries.initialize(objcObject, entries)
        return self
    }

    // MARK: Creating

    @ObjCClassMethod("dictionary")
    static func dictionary(_ cls: ObjCClass) -> NSDictionary { Dictionaries.owned([], cls: cls.pointer) }

    @ObjCClassMethod("dictionaryWithObject:forKey:")
    static func dictionary(_ cls: ObjCClass, object: ObjCObject, forKey key: ObjCObject) -> NSDictionary {
        Dictionaries.owned([(key.id, object.id)], cls: cls.pointer)
    }

    @ObjCClassMethod("dictionaryWithObjects:forKeys:count:")
    static func dictionary(_ cls: ObjCClass, objects: UnsafePointer<id?>?, forKeys keys: UnsafePointer<id?>?,
                           count: UInt) -> NSDictionary {
        Dictionaries.owned(Dictionaries.pairs(objects: objects, keys: keys, count: count,
                                              method: "+[NSDictionary dictionaryWithObjects:forKeys:count:]"),
                           cls: cls.pointer)
    }

    @ObjCClassMethod("dictionaryWithObjects:forKeys:")
    static func dictionary(_ cls: ObjCClass, objects: ObjCObject?, forKeys keys: ObjCObject?) -> NSDictionary {
        Dictionaries.owned(Dictionaries.pairs(objects: objects?.id, keys: keys?.id,
                                              method: "+[NSDictionary dictionaryWithObjects:forKeys:]"),
                           cls: cls.pointer)
    }

    /// A property list file's dictionary; mutable throughout when sent to
    /// a mutable class.
    @ObjCClassMethod("dictionaryWithContentsOfFile:")
    static func dictionary(_ cls: ObjCClass, contentsOfFile path: String) -> UnsafeMutableRawPointer? {
        PropertyLists.contents(of: URL(filePath: path), cls, expecting: .dictionary)
    }

    @ObjCClassMethod("dictionaryWithContentsOfURL:")
    static func dictionary(_ cls: ObjCClass, contentsOfURL url: NSURL) -> UnsafeMutableRawPointer? {
        PropertyLists.contents(of: url.url, cls, expecting: .dictionary)
    }

    @ObjCClassMethod("dictionaryWithDictionary:")
    static func dictionary(_ cls: ObjCClass, dictionary other: NSDictionary?) -> NSDictionary {
        Dictionaries.owned(other?.entries ?? [], cls: cls.pointer)
    }

    @ObjCMethod("init")
    func initialize() -> Self { setEntries([]) }

    @ObjCMethod("initWithObjects:forKeys:count:")
    func initialize(objects: UnsafePointer<id?>?, forKeys keys: UnsafePointer<id?>?, count: UInt) -> Self {
        setEntries(Dictionaries.pairs(objects: objects, keys: keys, count: count,
                                      method: "-[NSDictionary initWithObjects:forKeys:count:]"))
    }

    @ObjCMethod("initWithObjects:forKeys:")
    func initialize(objects: ObjCObject?, forKeys keys: ObjCObject?) -> Self {
        setEntries(Dictionaries.pairs(objects: objects?.id, keys: keys?.id, method: "-[NSDictionary initWithObjects:forKeys:]"))
    }

    @ObjCMethod("initWithDictionary:")
    func initialize(dictionary other: NSDictionary?) -> Self { setEntries(other?.entries ?? []) }

    /// A property list file's dictionary; nil when the file holds none.
    @ObjCMethod("initWithContentsOfFile:")
    func initialize(contentsOfFile path: String) -> Self? { initialize(contentsOf: URL(filePath: path)) }

    @ObjCMethod("initWithContentsOfURL:")
    func initialize(contentsOfURL url: NSURL) -> Self? { initialize(contentsOf: url.url) }

    private func initialize(contentsOf url: URL) -> Self? {
        guard let object = PropertyLists.contents(of: url, ObjCClass(named: "NSDictionary"), expecting: .dictionary) else { return nil }
        return setEntries(NSDictionary(objcObject: object, ownership: .retain).entries)
    }

    /// The dictionary as an XML property list file.
    @ObjCMethod("writeToFile:atomically:")
    func write(toFile path: String, atomically: Bool) -> Bool {
        PropertyLists.write(objcObject, to: URL(filePath: path), atomically: atomically)
    }

    @ObjCMethod("writeToURL:atomically:")
    func write(toURL url: NSURL, atomically: Bool) -> Bool { PropertyLists.write(objcObject, to: url.url, atomically: atomically) }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: Dictionaries.dictionaryClass)
    }

    // MARK: Querying

    @ObjCMethod("count")
    func count() -> UInt { UInt(entries.count) }

    @ObjCMethod("objectForKey:")
    func object(forKey key: ObjCObject?) -> ObjCObject? {
        Dictionaries.value(objcObject, for: key?.id).map(ObjCObject.init)
    }

    @ObjCMethod("objectForKeyedSubscript:")
    func object(subscript key: ObjCObject?) -> ObjCObject? { object(forKey: key) }

    @ObjCMethod("allKeys")
    func allKeys() -> NSArray { Arrays.owned(entries.map(\.key)) }

    @ObjCMethod("allValues")
    func allValues() -> NSArray { Arrays.owned(entries.map(\.value)) }

    @ObjCMethod("isEqualToDictionary:")
    func isEqual(toDictionary other: NSDictionary?) -> Bool {
        guard let other else { return false }
        let mine = entries
        guard mine.count == other.entries.count else { return false }
        return mine.allSatisfy { entry in
            Dictionaries.value(other.objcObject, for: entry.key)
                .map { ObjectKey(object: $0) == ObjectKey(object: entry.value) } ?? false
        }
    }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: ObjCObject?) -> Bool {
        guard let other else { return false }
        return other.id == objcObject
            || (other.is(NSDictionary.self) && isEqual(toDictionary: other.unsafeCast(to: NSDictionary.self)))
    }

    @ObjCMethod("hash")
    func hash() -> UInt { UInt(entries.count) }

    @ObjCMethod("description")
    func description() -> String { Describe.object(objcObject, indent: 0) }

    @ObjCMethod("enumerateKeysAndObjectsUsingBlock:")
    func enumerate(block: ObjCBlock) {
        let body = block.function(as: (@convention(c) (id, id?, id?, UnsafeMutablePointer<Bool>) -> Void).self)
        var stop = false
        for entry in entries {
            body(block.object, entry.key, entry.value, &stop)
            if stop { break }
        }
    }

    /// for (id key in dictionary) enumerates the keys.
    @ObjCMethod("countByEnumeratingWithState:objects:count:")
    func enumerate(state: UnsafeMutableRawPointer?, objects: UnsafeMutablePointer<id?>?, count: UInt) -> UInt {
        let keys = entries.map(\.key)
        if let storage = Dictionaries.storage(objcObject) {
            return storage.enumeration.enumerate(keys, state: state, buffer: objects, count: count)
        }
        return Dictionaries.constantEnumeration.enumerate(keys, state: state, buffer: objects, count: count)
    }

    // MARK: Copying

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> NSDictionary { self }

    @ObjCMethod("mutableCopyWithZone:")
    func mutableCopy(zone: UnsafeMutableRawPointer?) -> NSDictionary {
        Dictionaries.owned(entries, cls: UnsafeMutableRawPointer(Dictionaries.mutableClass))
    }
}

/// @{…} literals of constants: { isa, options, count, keys, objects }.
@ObjCClass("NSConstantDictionary")
final class NSConstantDictionary: NSDictionary {
    /// Set-up after the class is defined.
    override class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryImmortal(cls)
        Dictionaries.constantClass = cls.markingStatic().storage
        perry_foundation_set_empty_dictionary_class(cls.pointer)
    }
}

extension Dictionaries {
    /// Constant literals have no storage; they share one buffer, which is
    /// enough for one enumeration at a time on one thread.
    nonisolated(unsafe) static let constantEnumeration = EnumerationBuffer()
}

/// NSMutableDictionary.
@ObjCClass("NSMutableDictionary")
public class NSMutableDictionary: NSDictionary {
    /// Set-up after the class is defined.
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        Dictionaries.mutableClass = cls.storage
    }

    private var storage: DictionaryStorage {
        guard let storage = Dictionaries.storage(objcObject) else {
            foundationFatal("mutating method sent to an uninitialized NSMutableDictionary")
        }
        return storage
    }

    @ObjCClassMethod("dictionaryWithCapacity:")
    static func dictionary(_ cls: ObjCClass, capacity: UInt) -> NSDictionary { Dictionaries.owned([], cls: cls.pointer) }

    @ObjCMethod("initWithCapacity:")
    func initialize(capacity: UInt) -> Self {
        _ = Dictionaries.initialize(objcObject, [])
        return self
    }

    @ObjCMethod("copyWithZone:")
    override func copy(zone: UnsafeMutableRawPointer?) -> NSDictionary { Dictionaries.owned(Dictionaries.entries(objcObject)) }

    @ObjCMethod("setObject:forKey:")
    func set(_ value: ObjCObject?, forKey key: ObjCObject?) {
        guard let key else { foundationFatal("-[NSMutableDictionary setObject:forKey:]: key cannot be nil") }
        guard let value else {
            foundationFatal("-[NSMutableDictionary setObject:forKey:]: object cannot be nil (key: \(Format.describe(key.id)))")
        }
        storage.set(value.id, for: key.id)
    }

    /// dictionary[key] = value; nil removes the key.
    @ObjCMethod("setObject:forKeyedSubscript:")
    func set(_ value: ObjCObject?, subscript key: ObjCObject?) {
        guard let key else { foundationFatal("-[NSMutableDictionary setObject:forKeyedSubscript:]: key cannot be nil") }
        if let value {
            storage.set(value.id, for: key.id)
        } else {
            storage.remove(key.id)
        }
    }

    @ObjCMethod("removeObjectForKey:")
    func remove(forKey key: ObjCObject?) {
        if let key { storage.remove(key.id) }
    }

    @ObjCMethod("removeAllObjects")
    func removeAll() { storage.removeAll() }

    @ObjCMethod("addEntriesFromDictionary:")
    func add(entriesFrom other: NSDictionary?) {
        for entry in other?.entries ?? [] { storage.set(entry.value, for: entry.key) }
    }
}

/// + (id)dictionaryWithObjectsAndKeys:(id)first, ... nil — value, key pairs.
@c
public func perry_foundation_dictionaryWithObjectsAndKeys(_ cls: id?, _ cmd: SEL?, _ first: id?,
                                                          _ arguments: UnsafeRawPointer?) -> id? {
    let objects = nilTerminated(first, arguments)
    var entries: [(key: id, value: id)] = []
    var index = 0
    while index + 1 < objects.count {
        entries.append((key: objects[index + 1], value: objects[index]))
        index += 2
    }
    return Dictionaries.autoreleased(entries, cls: cls)
}

/// - (id)initWithObjectsAndKeys:(id)first, ... nil — value, key pairs.
@c
public func perry_foundation_initWithObjectsAndKeys(_ object: id?, _ cmd: SEL?, _ first: id?, _ arguments: UnsafeRawPointer?) -> id? {
    let objects = nilTerminated(first, arguments)
    var entries: [(key: id, value: id)] = []
    var index = 0
    while index + 1 < objects.count {
        entries.append((key: objects[index + 1], value: objects[index]))
        index += 2
    }
    return Dictionaries.initialize(object, entries)
}
