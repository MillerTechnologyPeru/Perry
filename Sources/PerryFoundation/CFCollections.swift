import CPerryFoundation
import FoundationEssentials
import Glibc
import PerryObjCInterop

// CFArray, CFDictionary and CFSet. With CoreFoundation's own callbacks
// (kCFTypeArrayCallBacks and the rest, recognised by their retain
// function) a collection is the toll-free bridged NSArray, NSDictionary or
// NSSet. With other callbacks, or none, it holds whatever pointers it is
// given, retained, released and compared by those callbacks: an object of
// __NSCFArray, __NSCFDictionary or __NSCFSet, which only the CF functions
// read.

public typealias CFValue = UnsafeRawPointer?

/// The callbacks the program gave: CFArrayCallBacks, CFDictionaryKeyCallBacks,
/// CFDictionaryValueCallBacks or CFSetCallBacks, which share a layout up to
/// the hash function the key and set callbacks add.
struct CFCallbacks {
    typealias Retain = @convention(c) (UnsafeRawPointer?, UnsafeRawPointer?) -> UnsafeRawPointer?
    typealias Release = @convention(c) (UnsafeRawPointer?, UnsafeRawPointer?) -> Void
    typealias Equal = @convention(c) (UnsafeRawPointer?, UnsafeRawPointer?) -> UInt8
    typealias Hash = @convention(c) (UnsafeRawPointer?) -> UInt

    var retain: Retain?
    var release: Release?
    var equal: Equal?
    var hash: Hash?

    init(_ pointer: UnsafeRawPointer?, hashed: Bool) {
        guard let pointer else { return }
        retain = pointer.load(fromByteOffset: 8, as: Retain?.self)
        release = pointer.load(fromByteOffset: 16, as: Release?.self)
        equal = pointer.load(fromByteOffset: 32, as: Equal?.self)
        if hashed { hash = pointer.load(fromByteOffset: 40, as: Hash?.self) }
    }

    /// CoreFoundation's own callbacks, for objects: the bridged classes.
    static func isStandard(_ pointer: UnsafeRawPointer?) -> Bool {
        guard let pointer, let retain = pointer.load(fromByteOffset: 8, as: UnsafeRawPointer?.self) else { return false }
        return retain == unsafeBitCast(perry_foundation_cf_retain as Retain, to: UnsafeRawPointer.self)
            || retain == unsafeBitCast(perry_foundation_cf_copy_string as Retain, to: UnsafeRawPointer.self)
    }

    func retained(_ value: CFValue) -> CFValue { retain.map { $0(nil, value) } ?? value }
    func released(_ value: CFValue) { release?(nil, value) }

    func isEqual(_ a: CFValue, _ b: CFValue) -> Bool {
        if a == b { return true }
        return equal.map { $0(a, b) != 0 } ?? false
    }
}

/// The callbacks' functions behind kCFTypeArrayCallBacks and the rest.
@c
public func perry_foundation_cf_retain(_ allocator: UnsafeRawPointer?, _ value: UnsafeRawPointer?) -> UnsafeRawPointer? {
    ObjC.retain(UnsafeMutableRawPointer(mutating: value)).map(UnsafeRawPointer.init)
}

@c
public func perry_foundation_cf_copy_string(_ allocator: UnsafeRawPointer?, _ value: UnsafeRawPointer?) -> UnsafeRawPointer? {
    guard let value else { return nil }
    return ObjC.send(UnsafeMutableRawPointer(mutating: value), ObjC.selector("copy")).map(UnsafeRawPointer.init)
}

@c
public func perry_foundation_cf_release(_ allocator: UnsafeRawPointer?, _ value: UnsafeRawPointer?) {
    ObjC.release(UnsafeMutableRawPointer(mutating: value))
}

@c
public func perry_foundation_cf_copy_description(_ value: UnsafeRawPointer?) -> UnsafeRawPointer? {
    CFCopyDescription(UnsafeMutableRawPointer(mutating: value)).map(UnsafeRawPointer.init)
}

@c
public func perry_foundation_cf_equal(_ a: UnsafeRawPointer?, _ b: UnsafeRawPointer?) -> UInt8 {
    CFEqual(UnsafeMutableRawPointer(mutating: a), UnsafeMutableRawPointer(mutating: b)) ? 1 : 0
}

@c
public func perry_foundation_cf_hash(_ value: UnsafeRawPointer?) -> UInt {
    CFHash(UnsafeMutableRawPointer(mutating: value))
}

/// A collection of the program's own pointers.
final class CFCollectionStorage {
    /// An array's values, a set's members, or a dictionary's keys.
    var keys: [CFValue] = []
    /// A dictionary's values.
    var values: [CFValue] = []
    let keyCallbacks: CFCallbacks
    let valueCallbacks: CFCallbacks

    init(keyCallbacks: CFCallbacks, valueCallbacks: CFCallbacks = CFCallbacks(nil, hashed: false)) {
        self.keyCallbacks = keyCallbacks
        self.valueCallbacks = valueCallbacks
    }

    deinit {
        keys.forEach(keyCallbacks.released)
        values.forEach(valueCallbacks.released)
    }

    func index(ofKey key: CFValue) -> Int? { keys.firstIndex { keyCallbacks.isEqual($0, key) } }

    func copy(cls: Class) -> id {
        let copy = CFCollections.make(cls, CFCollectionStorage(keyCallbacks: keyCallbacks, valueCallbacks: valueCallbacks))
        let storage = CFCollections.storage(copy)!
        storage.keys = keys.map(keyCallbacks.retained)
        storage.values = values.map(valueCallbacks.retained)
        return copy
    }
}

enum CFCollections {
    nonisolated(unsafe) static var arrayClass: Class!
    nonisolated(unsafe) static var dictionaryClass: Class!
    nonisolated(unsafe) static var setClass: Class!

    /// The storage of a collection of the program's pointers; nil for a
    /// bridged collection.
    static func storage(_ object: id?) -> CFCollectionStorage? {
        guard let object, let cls = ObjC.objectGetClass(object),
              cls == arrayClass || cls == dictionaryClass || cls == setClass else { return nil }
        return Storage.get(object, as: CFCollectionStorage.self)
    }

    /// A new collection (+1).
    static func make(_ cls: Class, _ storage: CFCollectionStorage) -> id {
        let object = Storage.allocate(UnsafeMutableRawPointer(cls))!
        Storage.set(object, storage)
        return object
    }

    static func object(_ value: CFValue) -> id? { value.map { UnsafeMutableRawPointer(mutating: $0) } }
}

/// A CFArray of the program's pointers. It is an NSArray all the same, as
/// every CFArray is on Darwin: one made without callbacks, so as not to
/// retain its objects, is still sent -objectAtIndex: and -addObject:. The
/// methods here are the ones NSArray's others are built on, and those that
/// change it; what it holds is retained, released and compared by its
/// callbacks.
@ObjCClass("__NSCFArray")
public class NSCFArray: NSArray {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        CFCollections.arrayClass = cls.storage
    }

    @ObjCMethod("dealloc")
    func cfDealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: CFCollections.arrayClass)
    }

    @ObjCMethod("count") func cfCount() -> UInt { UInt(CFCollections.storage(objcObject)?.keys.count ?? 0) }
    @ObjCMethod("_cfTypeID") func cfArrayTypeID() -> UInt { CFTypeIDs.array }

    @ObjCMethod("objectAtIndex:")
    func cfObject(at index: UInt) -> UnsafeMutableRawPointer? {
        guard let keys = CFCollections.storage(objcObject)?.keys, index < UInt(keys.count) else {
            foundationFatal("-[__NSCFArray objectAtIndex:]: index (\(index)) beyond bounds")
        }
        return CFCollections.object(keys[Int(index)])
    }

    @ObjCMethod("addObject:")
    func cfAdd(_ value: UnsafeMutableRawPointer?) { CFArrayAppendValue(objcObject, UnsafeRawPointer(value)) }

    @ObjCMethod("insertObject:atIndex:")
    func cfInsert(_ value: UnsafeMutableRawPointer?, at index: UInt) {
        CFArrayInsertValueAtIndex(objcObject, Int(index), UnsafeRawPointer(value))
    }

    @ObjCMethod("replaceObjectAtIndex:withObject:")
    func cfReplace(at index: UInt, with value: UnsafeMutableRawPointer?) {
        CFArraySetValueAtIndex(objcObject, Int(index), UnsafeRawPointer(value))
    }

    @ObjCMethod("removeObjectAtIndex:")
    func cfRemove(at index: UInt) { CFArrayRemoveValueAtIndex(objcObject, Int(index)) }

    @ObjCMethod("removeLastObject")
    func cfRemoveLast() {
        guard let count = CFCollections.storage(objcObject)?.keys.count, count > 0 else { return }
        CFArrayRemoveValueAtIndex(objcObject, count - 1)
    }

    @ObjCMethod("removeAllObjects") func cfRemoveAll() { CFArrayRemoveAllValues(objcObject) }

    /// Every value its callbacks find equal to `value`.
    @ObjCMethod("removeObject:")
    func cfRemove(_ value: UnsafeMutableRawPointer?) {
        guard let storage = CFCollections.storage(objcObject) else { return }
        let target = UnsafeRawPointer(value)
        let removed = storage.keys.filter { storage.keyCallbacks.isEqual($0, target) }
        storage.keys.removeAll { storage.keyCallbacks.isEqual($0, target) }
        removed.forEach(storage.keyCallbacks.released)
    }
}

/// A CFDictionary of the program's pointers.
@ObjCClass("__NSCFDictionary")
public class NSCFDictionary: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        CFCollections.dictionaryClass = cls.storage
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: CFCollections.dictionaryClass)
    }

    @ObjCMethod("count") func count() -> UInt { UInt(CFCollections.storage(objcObject)?.keys.count ?? 0) }
    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { CFTypeIDs.dictionary }
}

/// A CFSet of the program's pointers.
@ObjCClass("__NSCFSet")
public class NSCFSet: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        CFCollections.setClass = cls.storage
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: CFCollections.setClass)
    }

    @ObjCMethod("count") func count() -> UInt { UInt(CFCollections.storage(objcObject)?.keys.count ?? 0) }
    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { CFTypeIDs.set }
}

// MARK: - Arrays

enum CFArrays {
    static func values(_ array: id?) -> [CFValue] {
        if let storage = CFCollections.storage(array) { return storage.keys }
        return Arrays.elements(array).map { UnsafeRawPointer($0) }
    }

    static func range(_ range: CFRange) -> Range<Int> { range.location..<(range.location + range.length) }

    static func isEqual(_ array: id?, _ a: CFValue, _ b: CFValue) -> Bool {
        if let storage = CFCollections.storage(array) { return storage.keyCallbacks.isEqual(a, b) }
        return perry_foundation_cf_equal(a, b) != 0
    }

    static func send(_ array: id?, _ name: String, _ arguments: id?...) {
        switch arguments.count {
        case 0: _ = ObjC.send(array, ObjC.selector(name))
        case 1: _ = ObjC.send(array, ObjC.selector(name), arguments[0])
        default: _ = ObjC.send(array, ObjC.selector(name), arguments[0], arguments[1])
        }
    }

    /// Replaces a bridged array's contents.
    static func setValues(_ array: id?, _ values: [CFValue]) {
        if let storage = CFCollections.storage(array) {
            let old = storage.keys
            storage.keys = values.map(storage.keyCallbacks.retained)
            old.forEach(storage.keyCallbacks.released)
            return
        }
        let replacement = Arrays.autoreleased(values.compactMap(CFCollections.object))
        _ = ObjC.send(array, ObjC.selector("setArray:"), replacement)
    }
}

@c(_CFArrayGetTypeID) public func CFArrayGetTypeID() -> UInt { CFTypeIDs.array }

@c(_CFArrayCreate)
public func CFArrayCreate(_ allocator: UnsafeRawPointer?, _ values: UnsafePointer<CFValue>?, _ count: Int,
                          _ callbacks: UnsafeRawPointer?) -> id? {
    let list = (0..<count).map { values![$0] }
    if CFCallbacks.isStandard(callbacks) { return Arrays.make(list.compactMap(CFCollections.object)) }
    let storage = CFCollectionStorage(keyCallbacks: CFCallbacks(callbacks, hashed: false))
    storage.keys = list.map(storage.keyCallbacks.retained)
    return CFCollections.make(CFCollections.arrayClass, storage)
}

@c(_CFArrayCreateMutable)
public func CFArrayCreateMutable(_ allocator: UnsafeRawPointer?, _ capacity: Int, _ callbacks: UnsafeRawPointer?) -> id? {
    if CFCallbacks.isStandard(callbacks) { return Arrays.make([], cls: UnsafeMutableRawPointer(Arrays.mutableClass)) }
    return CFCollections.make(CFCollections.arrayClass, CFCollectionStorage(keyCallbacks: CFCallbacks(callbacks, hashed: false)))
}

@c(_CFArrayCreateCopy)
public func CFArrayCreateCopy(_ allocator: UnsafeRawPointer?, _ array: id?) -> id? {
    if let storage = CFCollections.storage(array) { return storage.copy(cls: CFCollections.arrayClass) }
    return ObjC.send(array, ObjC.selector("copy"))
}

@c(_CFArrayCreateMutableCopy)
public func CFArrayCreateMutableCopy(_ allocator: UnsafeRawPointer?, _ capacity: Int, _ array: id?) -> id? {
    if let storage = CFCollections.storage(array) { return storage.copy(cls: CFCollections.arrayClass) }
    return ObjC.send(array, ObjC.selector("mutableCopy"))
}

@c(_CFArrayGetCount) public func CFArrayGetCount(_ array: id?) -> Int { CFArrays.values(array).count }

@c(_CFArrayGetValueAtIndex)
public func CFArrayGetValueAtIndex(_ array: id?, _ index: Int) -> CFValue {
    let values = CFArrays.values(array)
    guard values.indices.contains(index) else { foundationFatal("CFArrayGetValueAtIndex: index (\(index)) out of bounds") }
    return values[index]
}

@c(_CFArrayGetValues)
public func CFArrayGetValues(_ array: id?, _ range: CFRange, _ values: UnsafeMutablePointer<CFValue>?) {
    let all = CFArrays.values(array)
    for (offset, index) in CFArrays.range(range).enumerated() { values?[offset] = all[index] }
}

@c(_CFArrayContainsValue)
public func CFArrayContainsValue(_ array: id?, _ range: CFRange, _ value: CFValue) -> Bool {
    CFArrayGetFirstIndexOfValue(array, range, value) != -1
}

@c(_CFArrayGetFirstIndexOfValue)
public func CFArrayGetFirstIndexOfValue(_ array: id?, _ range: CFRange, _ value: CFValue) -> Int {
    let all = CFArrays.values(array)
    return CFArrays.range(range).first { CFArrays.isEqual(array, all[$0], value) } ?? -1
}

@c(_CFArrayGetLastIndexOfValue)
public func CFArrayGetLastIndexOfValue(_ array: id?, _ range: CFRange, _ value: CFValue) -> Int {
    let all = CFArrays.values(array)
    return CFArrays.range(range).reversed().first { CFArrays.isEqual(array, all[$0], value) } ?? -1
}

@c(_CFArrayGetCountOfValue)
public func CFArrayGetCountOfValue(_ array: id?, _ range: CFRange, _ value: CFValue) -> Int {
    let all = CFArrays.values(array)
    return CFArrays.range(range).filter { CFArrays.isEqual(array, all[$0], value) }.count
}

@c(_CFArrayApplyFunction)
public func CFArrayApplyFunction(_ array: id?, _ range: CFRange,
                                 _ function: (@convention(c) (CFValue, UnsafeMutableRawPointer?) -> Void)?,
                                 _ context: UnsafeMutableRawPointer?) {
    let all = CFArrays.values(array)
    for index in CFArrays.range(range) { function?(all[index], context) }
}

@c(_CFArrayBSearchValues)
public func CFArrayBSearchValues(_ array: id?, _ range: CFRange, _ value: CFValue,
                                 _ comparator: (@convention(c) (CFValue, CFValue, UnsafeMutableRawPointer?) -> Int)?,
                                 _ context: UnsafeMutableRawPointer?) -> Int {
    let all = CFArrays.values(array)
    var low = range.location, high = range.location + range.length
    while low < high {
        let middle = (low + high) / 2
        if (comparator?(all[middle], value, context) ?? 0) < 0 { low = middle + 1 } else { high = middle }
    }
    return low
}

@c(_CFArrayAppendValue)
public func CFArrayAppendValue(_ array: id?, _ value: CFValue) {
    if let storage = CFCollections.storage(array) { return storage.keys.append(storage.keyCallbacks.retained(value)) }
    CFArrays.send(array, "addObject:", CFCollections.object(value))
}

@c(_CFArrayInsertValueAtIndex)
public func CFArrayInsertValueAtIndex(_ array: id?, _ index: Int, _ value: CFValue) {
    if let storage = CFCollections.storage(array) { return storage.keys.insert(storage.keyCallbacks.retained(value), at: index) }
    _ = unsafeBitCast(ObjC.msgSend, to: (@convention(c) (id?, SEL, id?, UInt) -> Void).self)(
        array, ObjC.selector("insertObject:atIndex:"), CFCollections.object(value), UInt(index))
}

@c(_CFArraySetValueAtIndex)
public func CFArraySetValueAtIndex(_ array: id?, _ index: Int, _ value: CFValue) {
    if let storage = CFCollections.storage(array) {
        let retained = storage.keyCallbacks.retained(value)
        if index == storage.keys.count { return storage.keys.append(retained) }
        storage.keyCallbacks.released(storage.keys[index])
        storage.keys[index] = retained
        return
    }
    if index == CFArrayGetCount(array) { return CFArrayAppendValue(array, value) }
    unsafeBitCast(ObjC.msgSend, to: (@convention(c) (id?, SEL, UInt, id?) -> Void).self)(
        array, ObjC.selector("replaceObjectAtIndex:withObject:"), UInt(index), CFCollections.object(value))
}

@c(_CFArrayRemoveValueAtIndex)
public func CFArrayRemoveValueAtIndex(_ array: id?, _ index: Int) {
    if let storage = CFCollections.storage(array) { return storage.keyCallbacks.released(storage.keys.remove(at: index)) }
    unsafeBitCast(ObjC.msgSend, to: (@convention(c) (id?, SEL, UInt) -> Void).self)(array, ObjC.selector("removeObjectAtIndex:"), UInt(index))
}

@c(_CFArrayRemoveAllValues)
public func CFArrayRemoveAllValues(_ array: id?) { CFArrays.setValues(array, []) }

@c(_CFArrayExchangeValuesAtIndices)
public func CFArrayExchangeValuesAtIndices(_ array: id?, _ first: Int, _ second: Int) {
    var values = CFArrays.values(array)
    values.swapAt(first, second)
    CFArrays.setValues(array, values)
}

@c(_CFArrayReplaceValues)
public func CFArrayReplaceValues(_ array: id?, _ range: CFRange, _ newValues: UnsafePointer<CFValue>?, _ count: Int) {
    var values = CFArrays.values(array)
    values.replaceSubrange(CFArrays.range(range), with: (0..<count).map { newValues![$0] })
    CFArrays.setValues(array, values)
}

@c(_CFArrayAppendArray)
public func CFArrayAppendArray(_ array: id?, _ other: id?, _ range: CFRange) {
    let more = CFArrays.values(other)
    for index in CFArrays.range(range) { CFArrayAppendValue(array, more[index]) }
}

/// A stable sort of the range by the comparator.
@c(_CFArraySortValues)
public func CFArraySortValues(_ array: id?, _ range: CFRange,
                              _ comparator: (@convention(c) (CFValue, CFValue, UnsafeMutableRawPointer?) -> Int)?,
                              _ context: UnsafeMutableRawPointer?) {
    var values = CFArrays.values(array)
    let span = CFArrays.range(range)
    let sorted = values[span].enumerated().sorted { a, b in
        let order = comparator?(a.element, b.element, context) ?? 0
        return order != 0 ? order < 0 : a.offset < b.offset
    }.map(\.element)
    values.replaceSubrange(span, with: sorted)
    CFArrays.setValues(array, values)
}

// MARK: - Dictionaries

enum CFDictionaries {
    static func entries(_ dictionary: id?) -> [(key: CFValue, value: CFValue)] {
        if let storage = CFCollections.storage(dictionary) { return Array(zip(storage.keys, storage.values)) }
        return Dictionaries.entries(dictionary).map { (UnsafeRawPointer($0.key), UnsafeRawPointer($0.value)) }
    }

    static func value(_ dictionary: id?, _ key: CFValue) -> CFValue? {
        if let storage = CFCollections.storage(dictionary) { return storage.index(ofKey: key).map { storage.values[$0] } }
        guard let key = CFCollections.object(key) else { return nil }
        return ObjC.send(dictionary, ObjC.selector("objectForKey:"), key).map { UnsafeRawPointer($0) }
    }

    static func set(_ dictionary: id?, _ key: CFValue, _ value: CFValue, add: Bool, replace: Bool) {
        if let storage = CFCollections.storage(dictionary) {
            if let index = storage.index(ofKey: key) {
                guard replace else { return }
                let retained = storage.valueCallbacks.retained(value)
                storage.valueCallbacks.released(storage.values[index])
                storage.values[index] = retained
            } else if add {
                storage.keys.append(storage.keyCallbacks.retained(key))
                storage.values.append(storage.valueCallbacks.retained(value))
            }
            return
        }
        let present = CFDictionaries.value(dictionary, key) != nil
        guard present ? replace : add, let keyObject = CFCollections.object(key) else { return }
        _ = ObjC.send(dictionary, ObjC.selector("setObject:forKey:"), CFCollections.object(value), keyObject)
    }
}

@c(_CFDictionaryGetTypeID) public func CFDictionaryGetTypeID() -> UInt { CFTypeIDs.dictionary }

@c(_CFDictionaryCreate)
public func CFDictionaryCreate(_ allocator: UnsafeRawPointer?, _ keys: UnsafePointer<CFValue>?, _ values: UnsafePointer<CFValue>?,
                               _ count: Int, _ keyCallbacks: UnsafeRawPointer?, _ valueCallbacks: UnsafeRawPointer?) -> id? {
    let dictionary = CFDictionaryCreateMutable(allocator, count, keyCallbacks, valueCallbacks)
    for index in 0..<count { CFDictionaries.set(dictionary, keys![index], values![index], add: true, replace: true) }
    guard CFCollections.storage(dictionary) == nil else { return dictionary }
    defer { ObjC.release(dictionary) }
    return ObjC.send(dictionary, ObjC.selector("copy"))
}

@c(_CFDictionaryCreateMutable)
public func CFDictionaryCreateMutable(_ allocator: UnsafeRawPointer?, _ capacity: Int, _ keyCallbacks: UnsafeRawPointer?,
                                      _ valueCallbacks: UnsafeRawPointer?) -> id? {
    if CFCallbacks.isStandard(keyCallbacks) && CFCallbacks.isStandard(valueCallbacks) {
        return Dictionaries.make([], cls: UnsafeMutableRawPointer(Dictionaries.mutableClass))
    }
    return CFCollections.make(CFCollections.dictionaryClass, CFCollectionStorage(
        keyCallbacks: CFCallbacks(keyCallbacks, hashed: true), valueCallbacks: CFCallbacks(valueCallbacks, hashed: false)))
}

@c(_CFDictionaryCreateCopy)
public func CFDictionaryCreateCopy(_ allocator: UnsafeRawPointer?, _ dictionary: id?) -> id? {
    if let storage = CFCollections.storage(dictionary) { return storage.copy(cls: CFCollections.dictionaryClass) }
    return ObjC.send(dictionary, ObjC.selector("copy"))
}

@c(_CFDictionaryCreateMutableCopy)
public func CFDictionaryCreateMutableCopy(_ allocator: UnsafeRawPointer?, _ capacity: Int, _ dictionary: id?) -> id? {
    if let storage = CFCollections.storage(dictionary) { return storage.copy(cls: CFCollections.dictionaryClass) }
    return ObjC.send(dictionary, ObjC.selector("mutableCopy"))
}

@c(_CFDictionaryGetCount) public func CFDictionaryGetCount(_ dictionary: id?) -> Int { CFDictionaries.entries(dictionary).count }

@c(_CFDictionaryGetValue)
public func CFDictionaryGetValue(_ dictionary: id?, _ key: CFValue) -> CFValue { CFDictionaries.value(dictionary, key) ?? nil }

@c(_CFDictionaryGetValueIfPresent)
public func CFDictionaryGetValueIfPresent(_ dictionary: id?, _ key: CFValue, _ value: UnsafeMutablePointer<CFValue>?) -> Bool {
    guard let found = CFDictionaries.value(dictionary, key) else { return false }
    value?.pointee = found
    return true
}

@c(_CFDictionaryContainsKey)
public func CFDictionaryContainsKey(_ dictionary: id?, _ key: CFValue) -> Bool { CFDictionaries.value(dictionary, key) != nil }

@c(_CFDictionaryContainsValue)
public func CFDictionaryContainsValue(_ dictionary: id?, _ value: CFValue) -> Bool { CFDictionaryGetCountOfValue(dictionary, value) > 0 }

@c(_CFDictionaryGetCountOfValue)
public func CFDictionaryGetCountOfValue(_ dictionary: id?, _ value: CFValue) -> Int {
    let storage = CFCollections.storage(dictionary)
    return CFDictionaries.entries(dictionary).filter { entry in
        storage.map { $0.valueCallbacks.isEqual(entry.value, value) } ?? (perry_foundation_cf_equal(entry.value, value) != 0)
    }.count
}

@c(_CFDictionaryGetCountOfKey)
public func CFDictionaryGetCountOfKey(_ dictionary: id?, _ key: CFValue) -> Int { CFDictionaryContainsKey(dictionary, key) ? 1 : 0 }

@c(_CFDictionaryGetKeysAndValues)
public func CFDictionaryGetKeysAndValues(_ dictionary: id?, _ keys: UnsafeMutablePointer<CFValue>?,
                                         _ values: UnsafeMutablePointer<CFValue>?) {
    for (index, entry) in CFDictionaries.entries(dictionary).enumerated() {
        keys?[index] = entry.key
        values?[index] = entry.value
    }
}

@c(_CFDictionaryApplyFunction)
public func CFDictionaryApplyFunction(_ dictionary: id?,
                                      _ function: (@convention(c) (CFValue, CFValue, UnsafeMutableRawPointer?) -> Void)?,
                                      _ context: UnsafeMutableRawPointer?) {
    for entry in CFDictionaries.entries(dictionary) { function?(entry.key, entry.value, context) }
}

@c(_CFDictionaryAddValue)
public func CFDictionaryAddValue(_ dictionary: id?, _ key: CFValue, _ value: CFValue) {
    CFDictionaries.set(dictionary, key, value, add: true, replace: false)
}

@c(_CFDictionarySetValue)
public func CFDictionarySetValue(_ dictionary: id?, _ key: CFValue, _ value: CFValue) {
    CFDictionaries.set(dictionary, key, value, add: true, replace: true)
}

@c(_CFDictionaryReplaceValue)
public func CFDictionaryReplaceValue(_ dictionary: id?, _ key: CFValue, _ value: CFValue) {
    CFDictionaries.set(dictionary, key, value, add: false, replace: true)
}

@c(_CFDictionaryRemoveValue)
public func CFDictionaryRemoveValue(_ dictionary: id?, _ key: CFValue) {
    if let storage = CFCollections.storage(dictionary) {
        guard let index = storage.index(ofKey: key) else { return }
        storage.keyCallbacks.released(storage.keys.remove(at: index))
        storage.valueCallbacks.released(storage.values.remove(at: index))
        return
    }
    guard let key = CFCollections.object(key) else { return }
    _ = ObjC.send(dictionary, ObjC.selector("removeObjectForKey:"), key)
}

@c(_CFDictionaryRemoveAllValues)
public func CFDictionaryRemoveAllValues(_ dictionary: id?) {
    if let storage = CFCollections.storage(dictionary) {
        let (keys, values) = (storage.keys, storage.values)
        storage.keys = []
        storage.values = []
        keys.forEach(storage.keyCallbacks.released)
        values.forEach(storage.valueCallbacks.released)
        return
    }
    _ = ObjC.send(dictionary, ObjC.selector("removeAllObjects"))
}

// MARK: - Sets

enum CFSets {
    static func members(_ set: id?) -> [CFValue] {
        if let storage = CFCollections.storage(set) { return storage.keys }
        return Sets.elements(set).map { UnsafeRawPointer($0) }
    }

    static func member(_ set: id?, _ value: CFValue) -> CFValue? {
        if let storage = CFCollections.storage(set) { return storage.index(ofKey: value).map { storage.keys[$0] } }
        guard let object = CFCollections.object(value) else { return nil }
        return ObjC.send(set, ObjC.selector("member:"), object).map { UnsafeRawPointer($0) }
    }
}

@c(_CFSetGetTypeID) public func CFSetGetTypeID() -> UInt { CFTypeIDs.set }

@c(_CFSetCreate)
public func CFSetCreate(_ allocator: UnsafeRawPointer?, _ values: UnsafePointer<CFValue>?, _ count: Int,
                        _ callbacks: UnsafeRawPointer?) -> id? {
    let set = CFSetCreateMutable(allocator, count, callbacks)
    for index in 0..<count { CFSetAddValue(set, values![index]) }
    guard CFCollections.storage(set) == nil else { return set }
    defer { ObjC.release(set) }
    return ObjC.send(set, ObjC.selector("copy"))
}

@c(_CFSetCreateMutable)
public func CFSetCreateMutable(_ allocator: UnsafeRawPointer?, _ capacity: Int, _ callbacks: UnsafeRawPointer?) -> id? {
    if CFCallbacks.isStandard(callbacks) { return Sets.make([], cls: UnsafeMutableRawPointer(Sets.mutableClass)) }
    return CFCollections.make(CFCollections.setClass, CFCollectionStorage(keyCallbacks: CFCallbacks(callbacks, hashed: true)))
}

@c(_CFSetCreateCopy)
public func CFSetCreateCopy(_ allocator: UnsafeRawPointer?, _ set: id?) -> id? {
    if let storage = CFCollections.storage(set) { return storage.copy(cls: CFCollections.setClass) }
    return ObjC.send(set, ObjC.selector("copy"))
}

@c(_CFSetCreateMutableCopy)
public func CFSetCreateMutableCopy(_ allocator: UnsafeRawPointer?, _ capacity: Int, _ set: id?) -> id? {
    if let storage = CFCollections.storage(set) { return storage.copy(cls: CFCollections.setClass) }
    return ObjC.send(set, ObjC.selector("mutableCopy"))
}

@c(_CFSetGetCount) public func CFSetGetCount(_ set: id?) -> Int { CFSets.members(set).count }
@c(_CFSetContainsValue) public func CFSetContainsValue(_ set: id?, _ value: CFValue) -> Bool { CFSets.member(set, value) != nil }
@c(_CFSetGetValue) public func CFSetGetValue(_ set: id?, _ value: CFValue) -> CFValue { CFSets.member(set, value) ?? nil }
@c(_CFSetGetCountOfValue) public func CFSetGetCountOfValue(_ set: id?, _ value: CFValue) -> Int { CFSetContainsValue(set, value) ? 1 : 0 }

@c(_CFSetGetValues)
public func CFSetGetValues(_ set: id?, _ values: UnsafeMutablePointer<CFValue>?) {
    for (index, member) in CFSets.members(set).enumerated() { values?[index] = member }
}

@c(_CFSetApplyFunction)
public func CFSetApplyFunction(_ set: id?, _ function: (@convention(c) (CFValue, UnsafeMutableRawPointer?) -> Void)?,
                               _ context: UnsafeMutableRawPointer?) {
    for member in CFSets.members(set) { function?(member, context) }
}

@c(_CFSetAddValue)
public func CFSetAddValue(_ set: id?, _ value: CFValue) {
    if let storage = CFCollections.storage(set) {
        if storage.index(ofKey: value) == nil { storage.keys.append(storage.keyCallbacks.retained(value)) }
        return
    }
    guard let object = CFCollections.object(value) else { return }
    _ = ObjC.send(set, ObjC.selector("addObject:"), object)
}

@c(_CFSetSetValue)
public func CFSetSetValue(_ set: id?, _ value: CFValue) {
    CFSetRemoveValue(set, value)
    CFSetAddValue(set, value)
}

@c(_CFSetReplaceValue)
public func CFSetReplaceValue(_ set: id?, _ value: CFValue) {
    guard CFSetContainsValue(set, value) else { return }
    CFSetSetValue(set, value)
}

@c(_CFSetRemoveValue)
public func CFSetRemoveValue(_ set: id?, _ value: CFValue) {
    if let storage = CFCollections.storage(set) {
        if let index = storage.index(ofKey: value) { storage.keyCallbacks.released(storage.keys.remove(at: index)) }
        return
    }
    guard let object = CFCollections.object(value) else { return }
    _ = ObjC.send(set, ObjC.selector("removeObject:"), object)
}

@c(_CFSetRemoveAllValues)
public func CFSetRemoveAllValues(_ set: id?) {
    if let storage = CFCollections.storage(set) {
        let members = storage.keys
        storage.keys = []
        members.forEach(storage.keyCallbacks.released)
        return
    }
    _ = ObjC.send(set, ObjC.selector("removeAllObjects"))
}
