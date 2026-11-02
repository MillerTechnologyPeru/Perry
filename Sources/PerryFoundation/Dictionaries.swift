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
            let count = Int(object.load(fromByteOffset: 16, as: UInt64.self))
            guard count > 0,
                  let keys = object.load(fromByteOffset: 24, as: UnsafePointer<id>?.self),
                  let values = object.load(fromByteOffset: 32, as: UnsafePointer<id>?.self) else { return [] }
            return (0..<count).map { (keys[$0], values[$0]) }
        }
        guard let storage = storage(object) else { return [] }
        return Array(zip(storage.keys, storage.values)).map { (key: $0.0, value: $0.1) }
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

    static func pairs(objects: UnsafePointer<id?>?, keys: UnsafePointer<id?>?, count: UInt, method: String) -> [(key: id, value: id)] {
        guard let objects, let keys else { return [] }
        return (0..<Int(count)).map { index in
            guard let key = keys[index], let value = objects[index] else {
                foundationFatal("\(method): attempt to insert nil object from objects[\(index)]")
            }
            return (key, value)
        }
    }

    static func install(superclass: Class) {
        let dictionary = ClassDefinition(PERRY_CLASS_NSDictionary, name: "NSDictionary", superclass: superclass,
                                         StorageAllocation.self, NSDictionaryMethods.self)
        dictionaryClass = dictionary.cls
        dictionary.addMethod("dictionaryWithObjectsAndKeys:", types: "@24@0:8@16",
                             implementation: variadicEntry(perry_imp_dictionaryWithObjectsAndKeys), isClassMethod: true)
        mutableClass = ClassDefinition(PERRY_CLASS_NSMutableDictionary, name: "NSMutableDictionary",
                                       superclass: dictionary.cls, NSMutableDictionaryMethods.self).cls
        constantClass = ClassDefinition(PERRY_CLASS_NSConstantDictionary, name: "NSConstantDictionary",
                                        superclass: dictionary.cls, ImmortalMethods.self).cls
    }
}

@ObjCImplementation
enum NSDictionaryMethods {
    // MARK: Creating

    @ObjCClassMethod("dictionary")
    static func dictionary(_ cls: id?) -> id? { Dictionaries.autoreleased([], cls: cls) }

    @ObjCClassMethod("dictionaryWithObject:forKey:")
    static func dictionary(_ cls: id?, object: id?, forKey key: id?) -> id? {
        guard let object, let key else { foundationFatal("+[NSDictionary dictionaryWithObject:forKey:]: nil object or key") }
        return Dictionaries.autoreleased([(key, object)], cls: cls)
    }

    @ObjCClassMethod("dictionaryWithObjects:forKeys:count:")
    static func dictionary(_ cls: id?, objects: UnsafePointer<id?>?, forKeys keys: UnsafePointer<id?>?, count: UInt) -> id? {
        Dictionaries.autoreleased(Dictionaries.pairs(objects: objects, keys: keys, count: count,
                                                     method: "+[NSDictionary dictionaryWithObjects:forKeys:count:]"), cls: cls)
    }

    @ObjCClassMethod("dictionaryWithDictionary:")
    static func dictionary(_ cls: id?, dictionary other: id?) -> id? {
        Dictionaries.autoreleased(Dictionaries.entries(other), cls: cls)
    }

    @ObjCMethod("init")
    static func initialize(_ object: id?) -> id? { Dictionaries.initialize(object, []) }

    @ObjCMethod("initWithObjects:forKeys:count:")
    static func initialize(_ object: id?, objects: UnsafePointer<id?>?, forKeys keys: UnsafePointer<id?>?, count: UInt) -> id? {
        Dictionaries.initialize(object, Dictionaries.pairs(objects: objects, keys: keys, count: count,
                                                           method: "-[NSDictionary initWithObjects:forKeys:count:]"))
    }

    @ObjCMethod("initWithDictionary:")
    static func initialize(_ object: id?, dictionary other: id?) -> id? {
        Dictionaries.initialize(object, Dictionaries.entries(other))
    }

    @ObjCMethod("dealloc")
    static func dealloc(_ object: id?) {
        guard let object else { return }
        Storage.set(object, nil)
        ObjC.superDealloc(object, from: Dictionaries.dictionaryClass)
    }

    // MARK: Querying

    @ObjCMethod("count")
    static func count(_ object: id?) -> UInt { UInt(Dictionaries.entries(object).count) }

    @ObjCMethod("objectForKey:")
    static func object(_ object: id?, forKey key: id?) -> id? { Dictionaries.value(object, for: key) }

    @ObjCMethod("objectForKeyedSubscript:")
    static func object(_ object: id?, subscript key: id?) -> id? { Dictionaries.value(object, for: key) }

    @ObjCMethod("allKeys")
    static func allKeys(_ object: id?) -> id? { Arrays.autoreleased(Dictionaries.entries(object).map(\.key)) }

    @ObjCMethod("allValues")
    static func allValues(_ object: id?) -> id? { Arrays.autoreleased(Dictionaries.entries(object).map(\.value)) }

    @ObjCMethod("isEqualToDictionary:")
    static func isEqual(_ object: id?, toDictionary other: id?) -> Bool {
        let mine = Dictionaries.entries(object)
        guard mine.count == Dictionaries.entries(other).count else { return false }
        return mine.allSatisfy { entry in
            Dictionaries.value(other, for: entry.key).map { ObjectKey(object: $0) == ObjectKey(object: entry.value) } ?? false
        }
    }

    @ObjCMethod("isEqual:")
    static func isEqual(_ object: id?, _ other: id?) -> Bool {
        object == other || (ObjC.isKind(other, of: Dictionaries.dictionaryClass) && isEqual(object, toDictionary: other))
    }

    @ObjCMethod("hash")
    static func hash(_ object: id?) -> UInt { UInt(Dictionaries.entries(object).count) }

    @ObjCMethod("description")
    static func description(_ object: id?) -> id? { Strings.autoreleased(Describe.object(object, indent: 0)) }

    @ObjCMethod("enumerateKeysAndObjectsUsingBlock:")
    static func enumerate(_ object: id?, block: ObjCBlock?) {
        guard let block else { return }
        let body = Blocks.invoke(block, as: (@convention(c) (id, id?, id?, UnsafeMutablePointer<Bool>) -> Void).self)
        var stop = false
        for entry in Dictionaries.entries(object) {
            body(block, entry.key, entry.value, &stop)
            if stop { break }
        }
    }

    /// for (id key in dictionary) enumerates the keys.
    @ObjCMethod("countByEnumeratingWithState:objects:count:")
    static func enumerate(_ object: id?, state: UnsafeMutableRawPointer?, objects: UnsafeMutablePointer<id?>?,
                          count: UInt) -> UInt {
        let keys = Dictionaries.entries(object).map(\.key)
        if let storage = Dictionaries.storage(object) {
            return storage.enumeration.enumerate(keys, state: state)
        }
        return Dictionaries.constantEnumeration.enumerate(keys, state: state)
    }

    // MARK: Copying

    @ObjCMethod("copyWithZone:")
    static func copy(_ object: id?, zone: UnsafeMutableRawPointer?) -> id? { ObjC.retain(object) }

    @ObjCMethod("mutableCopyWithZone:")
    static func mutableCopy(_ object: id?, zone: UnsafeMutableRawPointer?) -> id? {
        Dictionaries.make(Dictionaries.entries(object), cls: UnsafeMutableRawPointer(Dictionaries.mutableClass))
    }
}

extension Dictionaries {
    /// Constant literals have no storage; they share one buffer, which is
    /// enough for one enumeration at a time on one thread.
    nonisolated(unsafe) static let constantEnumeration = EnumerationBuffer()
}

@ObjCImplementation
enum NSMutableDictionaryMethods {
    private static func storage(_ object: id?) -> DictionaryStorage {
        guard let storage = Dictionaries.storage(object) else {
            foundationFatal("mutating method sent to an uninitialized NSMutableDictionary")
        }
        return storage
    }

    @ObjCClassMethod("dictionaryWithCapacity:")
    static func dictionary(_ cls: id?, capacity: UInt) -> id? { Dictionaries.autoreleased([], cls: cls) }

    @ObjCMethod("initWithCapacity:")
    static func initialize(_ object: id?, capacity: UInt) -> id? { Dictionaries.initialize(object, []) }

    @ObjCMethod("copyWithZone:")
    static func copy(_ object: id?, zone: UnsafeMutableRawPointer?) -> id? {
        Dictionaries.make(Dictionaries.entries(object))
    }

    @ObjCMethod("setObject:forKey:")
    static func set(_ object: id?, _ value: id?, forKey key: id?) {
        guard let key else { foundationFatal("-[NSMutableDictionary setObject:forKey:]: key cannot be nil") }
        guard let value else { foundationFatal("-[NSMutableDictionary setObject:forKey:]: object cannot be nil (key: \(Format.describe(key)))") }
        storage(object).set(value, for: key)
    }

    /// dictionary[key] = value; nil removes the key.
    @ObjCMethod("setObject:forKeyedSubscript:")
    static func set(_ object: id?, _ value: id?, subscript key: id?) {
        guard let key else { foundationFatal("-[NSMutableDictionary setObject:forKeyedSubscript:]: key cannot be nil") }
        if let value {
            storage(object).set(value, for: key)
        } else {
            storage(object).remove(key)
        }
    }

    @ObjCMethod("removeObjectForKey:")
    static func remove(_ object: id?, forKey key: id?) {
        if let key { storage(object).remove(key) }
    }

    @ObjCMethod("removeAllObjects")
    static func removeAll(_ object: id?) { storage(object).removeAll() }

    @ObjCMethod("addEntriesFromDictionary:")
    static func add(_ object: id?, entriesFrom other: id?) {
        let storage = storage(object)
        for entry in Dictionaries.entries(other) { storage.set(entry.value, for: entry.key) }
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
