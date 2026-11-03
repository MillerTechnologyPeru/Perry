import FoundationEssentials
import CPerryFoundation
import Glibc
import PerryObjCInterop

/// An NSArray's elements, each retained.
final class ArrayStorage {
    var objects: [id]
    let enumeration = EnumerationBuffer()

    init(_ objects: [id]) {
        self.objects = objects
    }

    deinit {
        for object in objects { ObjC.release(object) }
    }
}

enum Arrays {
    nonisolated(unsafe) static var arrayClass: Class!
    nonisolated(unsafe) static var mutableClass: Class!
    nonisolated(unsafe) static var constantClass: Class!
    nonisolated(unsafe) private static var constantMutations: UInt = 0

    static func storage(_ object: id?) -> ArrayStorage? {
        Storage.get(object, as: ArrayStorage.self)
    }

    /// The elements of an NSArray, including constant array literals.
    static func elements(_ object: id?) -> [id] {
        guard let object else { return [] }
        if ObjC.objectGetClass(object) == constantClass {
            let count = Int(object.load(fromByteOffset: 8, as: UInt64.self))
            guard let objects = object.load(fromByteOffset: 16, as: UnsafePointer<id>?.self) else { return [] }
            return Array(UnsafeBufferPointer(start: objects, count: count))
        }
        return storage(object)?.objects ?? []
    }

    /// Fills `object` with `elements`, retaining each.
    static func initialize(_ object: id?, _ elements: [id]) -> id? {
        guard let object else { return nil }
        for element in elements { _ = ObjC.retain(element) }
        Storage.set(object, ArrayStorage(elements))
        return object
    }

    /// A new array of `cls` (NSArray by default), retained.
    static func make(_ elements: [id], cls: id? = nil) -> id {
        initialize(Storage.allocate(cls ?? UnsafeMutableRawPointer(arrayClass)), elements)!
    }

    static func autoreleased(_ elements: [id], cls: id? = nil) -> id {
        ObjC.autorelease(make(elements, cls: cls))!
    }

    static func checkIndex(_ index: UInt, _ count: Int, _ method: String) {
        if Int(index) >= count {
            foundationFatal("-[NSArray \(method)]: index \(index) beyond bounds [0 .. \(count - 1)]")
        }
    }

    static func objects(_ buffer: UnsafePointer<id?>?, count: UInt, method: String) -> [id] {
        guard let buffer else { return [] }
        return (0..<Int(count)).map { index in
            guard let object = buffer[index] else {
                foundationFatal("\(method): attempt to insert nil object from objects[\(index)]")
            }
            return object
        }
    }


    /// A new array wrapped for returning, +1.
    static func owned(_ elements: [id], cls: id? = nil) -> NSArray {
        NSArray(objCOwned: make(elements, cls: cls))
    }

    static var constantMutationCounter: UnsafeMutablePointer<UInt> {
        withUnsafeMutablePointer(to: &constantMutations) { $0 }
    }
}

/// NSArray.
@ObjCClass("NSArray")
public class NSArray: NSObject {
    /// Set-up after the class is defined.
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        Arrays.arrayClass = cls.storage
        cls.addMethod("arrayWithObjects:", types: "@24@0:8@16",
                      implementation: variadicEntry(perry_imp_arrayWithObjects), isClassMethod: true)
        cls.addMethod("initWithObjects:", types: "@24@0:8@16",
                      implementation: variadicEntry(perry_imp_initArrayWithObjects), isClassMethod: false)
    }

    var elements: [id] { Arrays.elements(objcObject) }

    private func setElements(_ elements: [id]) -> Self {
        _ = Arrays.initialize(objcObject, elements)
        return self
    }

    // MARK: Creating

    @ObjCClassMethod("array")
    static func array(_ cls: ObjCClass) -> NSArray { Arrays.owned([], cls: cls.pointer) }

    @ObjCClassMethod("arrayWithObject:")
    static func array(_ cls: ObjCClass, object: ObjCObject) -> NSArray { Arrays.owned([object.id], cls: cls.pointer) }

    /// A property list file's array; mutable throughout when sent to a
    /// mutable class.
    @ObjCClassMethod("arrayWithContentsOfFile:")
    static func array(_ cls: ObjCClass, contentsOfFile path: String) -> UnsafeMutableRawPointer? {
        PropertyLists.contents(of: URL(filePath: path), cls, expecting: .array)
    }

    @ObjCClassMethod("arrayWithContentsOfURL:")
    static func array(_ cls: ObjCClass, contentsOfURL url: NSURL) -> UnsafeMutableRawPointer? {
        PropertyLists.contents(of: url.url, cls, expecting: .array)
    }

    @ObjCClassMethod("arrayWithArray:")
    static func array(_ cls: ObjCClass, array other: NSArray?) -> NSArray {
        Arrays.owned(other?.elements ?? [], cls: cls.pointer)
    }

    @ObjCClassMethod("arrayWithObjects:count:")
    static func array(_ cls: ObjCClass, objects: UnsafePointer<id?>?, count: UInt) -> NSArray {
        Arrays.owned(Arrays.objects(objects, count: count, method: "+[NSArray arrayWithObjects:count:]"), cls: cls.pointer)
    }

    @ObjCMethod("init")
    func initialize() -> Self { setElements([]) }

    @ObjCMethod("initWithObjects:count:")
    func initialize(objects: UnsafePointer<id?>?, count: UInt) -> Self {
        setElements(Arrays.objects(objects, count: count, method: "-[NSArray initWithObjects:count:]"))
    }

    @ObjCMethod("initWithArray:")
    func initialize(array other: NSArray?) -> Self { setElements(other?.elements ?? []) }

    /// A property list file's array; nil when the file holds none.
    @ObjCMethod("initWithContentsOfFile:")
    func initialize(contentsOfFile path: String) -> Self? { initialize(contentsOf: URL(filePath: path)) }

    @ObjCMethod("initWithContentsOfURL:")
    func initialize(contentsOfURL url: NSURL) -> Self? { initialize(contentsOf: url.url) }

    private func initialize(contentsOf url: URL) -> Self? {
        guard let object = PropertyLists.contents(of: url, ObjCClass(named: "NSArray"), expecting: .array) else { return nil }
        return setElements(NSArray(objcObject: object, ownership: .retain).elements)
    }

    /// The array as an XML property list file.
    @ObjCMethod("writeToFile:atomically:")
    func write(toFile path: String, atomically: Bool) -> Bool {
        PropertyLists.write(objcObject, to: URL(filePath: path), atomically: atomically)
    }

    @ObjCMethod("writeToURL:atomically:")
    func write(toURL url: NSURL, atomically: Bool) -> Bool { PropertyLists.write(objcObject, to: url.url, atomically: atomically) }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: Arrays.arrayClass)
    }

    // MARK: Querying

    @ObjCMethod("count")
    func count() -> UInt { UInt(elements.count) }

    @ObjCMethod("objectAtIndex:")
    func object(at index: UInt) -> ObjCObject {
        let all = elements
        Arrays.checkIndex(index, all.count, "objectAtIndex:")
        return ObjCObject(all[Int(index)])
    }

    @ObjCMethod("objectAtIndexedSubscript:")
    func object(subscript index: UInt) -> ObjCObject {
        let all = elements
        Arrays.checkIndex(index, all.count, "objectAtIndexedSubscript:")
        return ObjCObject(all[Int(index)])
    }

    @ObjCMethod("firstObject")
    func first() -> ObjCObject? { elements.first.map(ObjCObject.init) }

    @ObjCMethod("lastObject")
    func last() -> ObjCObject? { elements.last.map(ObjCObject.init) }

    @ObjCMethod("indexOfObject:")
    func index(of target: ObjCObject?) -> UInt {
        guard let target else { return notFound }
        return elements.firstIndex { ObjectKey(object: $0) == ObjectKey(object: target.id) }.map(UInt.init) ?? notFound
    }

    @ObjCMethod("containsObject:")
    func contains(_ target: ObjCObject?) -> Bool { index(of: target) != notFound }

    @ObjCMethod("isEqualToArray:")
    func isEqual(toArray other: NSArray?) -> Bool {
        let a = elements, b = other?.elements ?? []
        return other != nil && a.count == b.count
            && zip(a, b).allSatisfy { ObjectKey(object: $0) == ObjectKey(object: $1) }
    }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: ObjCObject?) -> Bool {
        guard let other else { return false }
        return other.id == objcObject || (other.is(NSArray.self) && isEqual(toArray: other.unsafeCast(to: NSArray.self)))
    }

    @ObjCMethod("hash")
    func hash() -> UInt { UInt(elements.count) }

    @ObjCMethod("description")
    func description() -> String { Describe.object(objcObject, indent: 0) }

    // MARK: Copying

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> NSArray { self }

    @ObjCMethod("mutableCopyWithZone:")
    func mutableCopy(zone: UnsafeMutableRawPointer?) -> NSArray {
        Arrays.owned(elements, cls: UnsafeMutableRawPointer(Arrays.mutableClass))
    }

    // MARK: Deriving

    @ObjCMethod("arrayByAddingObject:")
    func adding(_ element: ObjCObject) -> NSArray { Arrays.owned(elements + [element.id]) }

    @ObjCMethod("arrayByAddingObjectsFromArray:")
    func adding(objectsFrom other: NSArray?) -> NSArray { Arrays.owned(elements + (other?.elements ?? [])) }

    @ObjCMethod("subarrayWithRange:")
    func subarray(range: NSRange) -> NSArray {
        let all = elements
        guard Int(range.location + range.length) <= all.count else {
            foundationFatal("-[NSArray subarrayWithRange:]: range {\(range.location), \(range.length)} extends beyond bounds [0 .. \(all.count - 1)]")
        }
        return Arrays.owned(Array(all[Int(range.location)..<Int(range.location + range.length)]))
    }

    @ObjCMethod("componentsJoinedByString:")
    func joined(separator: String) -> String { elements.map { Format.describe($0) }.joined(separator: separator) }

    @ObjCMethod("makeObjectsPerformSelector:")
    func makeObjectsPerform(_ selector: ObjCSelector) {
        for element in elements { _ = ObjC.send(element, selector.pointer.assumingMemoryBound(to: CChar.self)) }
    }

    @ObjCMethod("sortedArrayUsingSelector:")
    func sorted(using selector: ObjCSelector) -> NSArray {
        let sel = selector.pointer.assumingMemoryBound(to: CChar.self)
        return Arrays.owned(elements.sorted { ObjC.sendInt($0, sel, $1) < 0 })
    }

    @ObjCMethod("sortedArrayUsingComparator:")
    func sorted(comparator: ObjCBlock) -> NSArray {
        let compare = comparator.function(as: (@convention(c) (id, id?, id?) -> Int).self)
        return Arrays.owned(elements.sorted { compare(comparator.object, $0, $1) < 0 })
    }

    @ObjCMethod("enumerateObjectsUsingBlock:")
    func enumerate(block: ObjCBlock) {
        let body = block.function(as: (@convention(c) (id, id?, UInt, UnsafeMutablePointer<Bool>) -> Void).self)
        var stop = false
        for (index, element) in elements.enumerated() {
            body(block.object, element, UInt(index), &stop)
            if stop { break }
        }
    }

    @ObjCMethod("countByEnumeratingWithState:objects:count:")
    func enumerate(state: UnsafeMutableRawPointer?, objects: UnsafeMutablePointer<id?>?, count: UInt) -> UInt {
        Arrays.storage(objcObject)?.enumeration.enumerate(elements, state: state) ?? 0
    }
}

/// NSMutableArray.
@ObjCClass("NSMutableArray")
public class NSMutableArray: NSArray {
    /// Set-up after the class is defined.
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        Arrays.mutableClass = cls.storage
    }

    private var storage: ArrayStorage {
        guard let storage = Arrays.storage(objcObject) else {
            foundationFatal("mutating method sent to an uninitialized NSMutableArray")
        }
        return storage
    }

    @ObjCClassMethod("arrayWithCapacity:")
    static func array(_ cls: ObjCClass, capacity: UInt) -> NSArray { Arrays.owned([], cls: cls.pointer) }

    @ObjCMethod("initWithCapacity:")
    func initialize(capacity: UInt) -> Self {
        _ = Arrays.initialize(objcObject, [])
        return self
    }

    @ObjCMethod("copyWithZone:")
    override func copy(zone: UnsafeMutableRawPointer?) -> NSArray { Arrays.owned(storage.objects) }

    @ObjCMethod("addObject:")
    func add(_ element: ObjCObject) {
        storage.objects.append(ObjC.retain(element.id)!)
        storage.enumeration.mutated()
    }

    @ObjCMethod("addObjectsFromArray:")
    func add(objectsFrom other: NSArray?) {
        for element in other?.elements ?? [] { add(ObjCObject(element)) }
    }

    @ObjCMethod("insertObject:atIndex:")
    func insert(_ element: ObjCObject, at index: UInt) {
        if Int(index) > storage.objects.count {
            Arrays.checkIndex(index, storage.objects.count, "insertObject:atIndex:")
        }
        storage.objects.insert(ObjC.retain(element.id)!, at: Int(index))
        storage.enumeration.mutated()
    }

    @ObjCMethod("removeObjectAtIndex:")
    func remove(at index: UInt) {
        Arrays.checkIndex(index, storage.objects.count, "removeObjectAtIndex:")
        let removed = storage.objects.remove(at: Int(index))
        storage.enumeration.mutated()
        ObjC.release(removed)
    }

    @ObjCMethod("removeObjectsInRange:")
    func remove(range: NSRange) {
        let count = storage.objects.count
        guard range.length > 0 else { return }
        if Int(range.location) + Int(range.length) > count {
            foundationFatal("-[NSMutableArray removeObjectsInRange:]: range {\(range.location), \(range.length)} extends beyond bounds [0 .. \(count - 1)]")
        }
        let start = Int(range.location)
        let removed = storage.objects[start..<(start + Int(range.length))]
        storage.objects.removeSubrange(start..<(start + Int(range.length)))
        storage.enumeration.mutated()
        removed.forEach { ObjC.release($0) }
    }

    @ObjCMethod("removeObject:")
    func remove(_ element: ObjCObject?) {
        guard let element else { return }
        let matches = { (object: id) in ObjectKey(object: object) == ObjectKey(object: element.id) }
        let removed = storage.objects.filter(matches)
        storage.objects.removeAll(where: matches)
        storage.enumeration.mutated()
        for item in removed { ObjC.release(item) }
    }

    @ObjCMethod("removeLastObject")
    func removeLast() {
        guard let last = storage.objects.popLast() else { return }
        storage.enumeration.mutated()
        ObjC.release(last)
    }

    @ObjCMethod("removeAllObjects")
    func removeAll() {
        let removed = storage.objects
        storage.objects.removeAll()
        storage.enumeration.mutated()
        for element in removed { ObjC.release(element) }
    }

    @ObjCMethod("setArray:")
    func setArray(_ other: ObjCObject?) {
        let replacement = Arrays.elements(other?.objcObject)
        for element in replacement { _ = ObjC.retain(element) }
        let removed = storage.objects
        storage.objects = replacement
        storage.enumeration.mutated()
        for element in removed { ObjC.release(element) }
    }

    @ObjCMethod("replaceObjectAtIndex:withObject:")
    func replace(at index: UInt, with element: ObjCObject) {
        Arrays.checkIndex(index, storage.objects.count, "replaceObjectAtIndex:withObject:")
        let old = storage.objects[Int(index)]
        storage.objects[Int(index)] = ObjC.retain(element.id)!
        storage.enumeration.mutated()
        ObjC.release(old)
    }

    @ObjCMethod("setObject:atIndexedSubscript:")
    func set(_ element: ObjCObject, subscript index: UInt) {
        if Int(index) == storage.objects.count {
            add(element)
        } else {
            replace(at: index, with: element)
        }
    }

    @ObjCMethod("sortUsingSelector:")
    func sort(using selector: ObjCSelector) {
        let sel = selector.pointer.assumingMemoryBound(to: CChar.self)
        storage.objects.sort { ObjC.sendInt($0, sel, $1) < 0 }
        storage.enumeration.mutated()
    }
}

/// @[…] literals of constants: { isa, count, objects }, read in place.
@ObjCClass("NSConstantArray")
final class NSConstantArray: NSArray {
    /// Set-up after the class is defined.
    override class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryImmortal(cls)
        Arrays.constantClass = cls.markingStatic().storage
        perry_foundation_set_empty_array_class(cls.pointer)
    }

    @ObjCMethod("countByEnumeratingWithState:objects:count:")
    override func enumerate(state: UnsafeMutableRawPointer?, objects: UnsafeMutablePointer<id?>?, count: UInt) -> UInt {
        guard let state, state.load(as: UInt.self) == 0 else { return 0 }
        state.storeBytes(of: 1, as: UInt.self)
        state.storeBytes(of: objcObject.load(fromByteOffset: 16, as: UnsafeMutableRawPointer?.self),
                         toByteOffset: 8, as: UnsafeMutableRawPointer?.self)
        state.storeBytes(of: UnsafeMutableRawPointer(Arrays.constantMutationCounter), toByteOffset: 16,
                         as: UnsafeMutableRawPointer.self)
        return UInt(objcObject.load(fromByteOffset: 8, as: UInt64.self))
    }
}

/// + (id)arrayWithObjects:(id)first, ... — nil-terminated.
@c
public func perry_foundation_arrayWithObjects(_ cls: id?, _ cmd: SEL?, _ first: id?,
                                              _ arguments: UnsafeRawPointer?) -> id? {
    Arrays.autoreleased(nilTerminated(first, arguments), cls: cls)
}

/// - (id)initWithObjects:(id)first, ... nil
@c
public func perry_foundation_initArrayWithObjects(_ object: id?, _ cmd: SEL?, _ first: id?, _ arguments: UnsafeRawPointer?) -> id? {
    Arrays.initialize(object, nilTerminated(first, arguments))
}

/// The objects of a nil-terminated variadic list.
func nilTerminated(_ first: id?, _ arguments: UnsafeRawPointer?) -> [id] {
    guard let first, let arguments else { return [] }
    var objects = [first]
    var darwin = DarwinArguments(arguments)
    while let next = darwin.nextPointer() {
        objects.append(next)
    }
    return objects
}
