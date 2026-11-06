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
        // Another library's dictionary, such as Swift's: its keys and
        // values together where it gives them so (Swift's bridged
        // dictionaries do, from their own storage: an [AnyHashable: Any]'s
        // can't always find a key given back as an Objective-C object),
        // else its keys and the value for each.
        guard ObjC.overrides(object, Selectors.count, of: dictionaryClass) else { return [] }
        if ObjC.overrides(object, Selectors.getObjectsAndKeys, of: dictionaryClass) {
            let count = Int(bitPattern: UInt(bitPattern: ObjC.send(object, Selectors.count)))
            guard count > 0 else { return [] }
            var keys = [id?](repeating: nil, count: count), values = [id?](repeating: nil, count: count)
            typealias GetObjects = @convention(c) (id, SEL, UnsafeMutablePointer<id?>, UnsafeMutablePointer<id?>, Int) -> Void
            unsafeBitCast(ObjC.msgSend, to: GetObjects.self)(object, Selectors.getObjectsAndKeys, &values, &keys, count)
            return zip(keys, values).compactMap { pair in pair.0.flatMap { key in pair.1.map { (key: key, value: $0) } } }
        }
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
    static func dictionary(_ cls: ObjCClass) -> NSDictionary {
        // NSDictionary's own is the immortal @{}, as Apple's is: Swift's
        // runtime keeps it for every error without user info, unretained.
        guard cls.pointer != UnsafeMutableRawPointer(Dictionaries.dictionaryClass) else {
            return NSDictionary(objCOwned: ObjC.retain(perry_foundation_empty_dictionary())!)
        }
        return Dictionaries.owned([], cls: cls.pointer)
    }

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
    static func dictionary(_ cls: ObjCClass, contentsOfFile path: String?) -> UnsafeMutableRawPointer? {
        // No path, as a resource that is not in the bundle has none, gives nil.
        guard let path else { return nil }
        return PropertyLists.contents(of: URL(filePath: path), cls, expecting: .dictionary)
    }

    @ObjCClassMethod("dictionaryWithContentsOfURL:")
    static func dictionary(_ cls: ObjCClass, contentsOfURL url: NSURL?) -> UnsafeMutableRawPointer? {
        guard let url else { return nil }
        return PropertyLists.contents(of: url.url, cls, expecting: .dictionary)
    }

    @ObjCClassMethod("dictionaryWithContentsOfURL:error:")
    static func dictionary(_ cls: ObjCClass, contentsOfURL url: NSURL, error: UnsafeMutablePointer<id?>?) -> UnsafeMutableRawPointer? {
        if let made = PropertyLists.contents(of: url.url, cls, expecting: .dictionary) { return made }
        error?.pointee = Errors.autoreleased(domain: Errors.cocoaDomain, code: 260, description: "The file couldn’t be opened.")
        return nil
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

    /// With copyItems, each value is the value's -copy, as Foundation's.
    @ObjCMethod("initWithDictionary:copyItems:")
    func initialize(dictionary other: NSDictionary?, copyItems: Bool) -> Self {
        guard copyItems else { return initialize(dictionary: other) }
        let copies = (other?.entries ?? []).map { entry -> (key: id, value: id) in
            (entry.key, ObjC.send(entry.value, Selectors.copyWithZone, nil) ?? ObjC.retain(entry.value)!)
        }
        defer { for copy in copies { ObjC.release(copy.value) } }
        return setEntries(copies)
    }

    /// A property list file's dictionary; nil when the file holds none.
    @ObjCMethod("initWithContentsOfFile:")
    func initialize(contentsOfFile path: String?) -> Self? { path.flatMap { initialize(contentsOf: URL(filePath: $0)) } }

    @ObjCMethod("initWithContentsOfURL:")
    func initialize(contentsOfURL url: NSURL?) -> Self? { url.flatMap { initialize(contentsOf: $0.url) } }

    /// macOS 10.13's: nil and an error when the file holds no dictionary.
    @ObjCMethod("initWithContentsOfURL:error:")
    func initialize(contentsOfURL url: NSURL, error: UnsafeMutablePointer<id?>?) -> Self? {
        if let made = initialize(contentsOf: url.url) { return made }
        error?.pointee = Errors.autoreleased(domain: Errors.cocoaDomain, code: 260, description: "The file couldn’t be opened.")
        return nil
    }

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

    /// iOS 11's: written atomically, with an error when it can't be.
    @ObjCMethod("writeToURL:error:")
    func write(toURL url: NSURL, error: UnsafeMutablePointer<id?>?) -> Bool {
        if PropertyLists.write(objcObject, to: url.url, atomically: true) { return true }
        error?.pointee = Errors.autoreleased(domain: Errors.cocoaDomain, code: 512, description: "The file couldn’t be saved.")
        return false
    }

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

    // MARK: File attributes (NSFileManager's NSDictionary category)

    private func attribute(_ key: String) -> id? { Dictionaries.value(objcObject, for: Strings.autoreleased(key)) }
    private func attributeNumber(_ key: String) -> NumberStorage? { attribute(key).map { Numbers.storage($0) } }

    @ObjCMethod("fileSize") func fileSize() -> UInt64 { attributeNumber("NSFileSize").map { UInt64(bitPattern: $0.int64) } ?? 0 }
    @ObjCMethod("fileModificationDate") func fileModificationDate() -> ObjCObject? { attribute("NSFileModificationDate").map(ObjCObject.init) }
    @ObjCMethod("fileCreationDate") func fileCreationDate() -> ObjCObject? { attribute("NSFileCreationDate").map(ObjCObject.init) }
    @ObjCMethod("fileType") func fileType() -> ObjCObject? { attribute("NSFileType").map(ObjCObject.init) }
    @ObjCMethod("filePosixPermissions") func filePosixPermissions() -> UInt { attributeNumber("NSFilePosixPermissions").map { UInt(truncatingIfNeeded: $0.int64) } ?? 0 }
    @ObjCMethod("fileOwnerAccountName") func fileOwnerAccountName() -> ObjCObject? { attribute("NSFileOwnerAccountName").map(ObjCObject.init) }
    @ObjCMethod("fileSystemNumber") func fileSystemNumber() -> Int { attributeNumber("NSFileSystemNumber").map { Int($0.int64) } ?? 0 }
    @ObjCMethod("fileSystemFileNumber") func fileSystemFileNumber() -> UInt { attributeNumber("NSFileSystemFileNumber").map { UInt(truncatingIfNeeded: $0.int64) } ?? 0 }
    @ObjCMethod("fileIsImmutable") func fileIsImmutable() -> Bool { (attributeNumber("NSFileImmutable")?.int64 ?? 0) != 0 }

    @ObjCMethod("objectForKeyedSubscript:")
    func object(subscript key: ObjCObject?) -> ObjCObject? { object(forKey: key) }

    /// Swift's subscript of a dictionary bridged from Objective-C.
    @ObjCMethod("__swift_objectForKeyedSubscript:")
    func object(swiftSubscript key: ObjCObject?) -> ObjCObject? { object(forKey: key) }

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

    /// The keys whose values are equal to `object`.
    @ObjCMethod("allKeysForObject:")
    func allKeys(for object: ObjCObject?) -> NSArray {
        guard let object else { return NSArray(objcObject: Arrays.autoreleased([]), ownership: .retain) }
        let keys = entries.filter { $0.value == object.id || ObjC.sendBool($0.value, Selectors.isEqual, object.id) }.map(\.key)
        return NSArray(objcObject: Arrays.autoreleased(keys), ownership: .retain)
    }

    /// The keys' values, in order, with the marker for keys not present.
    @ObjCMethod("objectsForKeys:notFoundMarker:")
    func objects(forKeys keys: ObjCObject?, notFoundMarker marker: ObjCObject) -> NSArray {
        let values = Arrays.elements(keys?.id).map { Dictionaries.value(objcObject, for: $0) ?? marker.id }
        return NSArray(objcObject: Arrays.autoreleased(values), ownership: .retain)
    }

    /// The keys whose entries the block passes, as a set.
    @ObjCMethod("keysOfEntriesPassingTest:")
    func keysOfEntries(passingTest block: ObjCBlock) -> ObjCObject {
        let test = block.function(as: (@convention(c) (id, id?, id?, UnsafeMutablePointer<Bool>) -> Bool).self)
        var keys: [id] = []
        var stop = false
        for entry in entries {
            if test(block.object, entry.key, entry.value, &stop) { keys.append(entry.key) }
            if stop { break }
        }
        return ObjCObject(Sets.autoreleased(keys))
    }

    /// Concurrent enumeration runs in order here.
    @ObjCMethod("keysOfEntriesWithOptions:passingTest:")
    func keysOfEntries(options: UInt, passingTest block: ObjCBlock) -> ObjCObject { keysOfEntries(passingTest: block) }

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

    @ObjCMethod("removeObjectsForKeys:")
    func remove(forKeys keys: ObjCObject?) {
        for key in Arrays.elements(keys?.id) { storage.remove(key) }
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

/// NSDictionaryOfVariableBindings(a, b): the values by the names the macro
/// wrote, "a, b". The values after the first are the Darwin va_list's
/// slots, one per name.
@c
public func perry_foundation_dictionary_of_variable_bindings(_ keys: id?, _ first: id?, _ arguments: UnsafeRawPointer?) -> id? {
    let names = (Strings.value(of: keys) ?? "").split(separator: ",").map { String($0.filter { !$0.isWhitespace }) }
    var entries: [(key: id, value: id)] = []
    for (index, name) in names.enumerated() {
        let value = index == 0 ? first : arguments?.load(fromByteOffset: (index - 1) * 8, as: id?.self)
        if let value { entries.append((Strings.autoreleased(name), value)) }
    }
    return Dictionaries.autoreleased(entries)
}
