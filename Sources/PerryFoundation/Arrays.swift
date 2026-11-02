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

    static func install(superclass: Class) {
        let array = ClassDefinition(PERRY_CLASS_NSArray, name: "NSArray", superclass: superclass,
                                    StorageAllocation.self, NSArrayMethods.self)
        arrayClass = array.cls
        array.addMethod("arrayWithObjects:", types: "@24@0:8@16",
                        implementation: variadicEntry(perry_imp_arrayWithObjects), isClassMethod: true)
        mutableClass = ClassDefinition(PERRY_CLASS_NSMutableArray, name: "NSMutableArray", superclass: array.cls,
                                       NSMutableArrayMethods.self).cls
        constantClass = ClassDefinition(PERRY_CLASS_NSConstantArray, name: "NSConstantArray", superclass: array.cls,
                                        ImmortalMethods.self, NSConstantArrayMethods.self).cls
    }

    static var constantMutationCounter: UnsafeMutablePointer<UInt> {
        withUnsafeMutablePointer(to: &constantMutations) { $0 }
    }
}

@ObjCImplementation
enum NSArrayMethods {
    private static func elements(_ object: id?) -> [id] { Arrays.elements(object) }

    // MARK: Creating

    @ObjCClassMethod("array")
    static func array(_ cls: id?) -> id? { Arrays.autoreleased([], cls: cls) }

    @ObjCClassMethod("arrayWithObject:")
    static func array(_ cls: id?, object: id?) -> id? { Arrays.autoreleased(object.map { [$0] } ?? [], cls: cls) }

    @ObjCClassMethod("arrayWithArray:")
    static func array(_ cls: id?, array other: id?) -> id? { Arrays.autoreleased(elements(other), cls: cls) }

    @ObjCClassMethod("arrayWithObjects:count:")
    static func array(_ cls: id?, objects: UnsafePointer<id?>?, count: UInt) -> id? {
        Arrays.autoreleased(Arrays.objects(objects, count: count, method: "+[NSArray arrayWithObjects:count:]"), cls: cls)
    }

    @ObjCMethod("init")
    static func initialize(_ object: id?) -> id? { Arrays.initialize(object, []) }

    @ObjCMethod("initWithObjects:count:")
    static func initialize(_ object: id?, objects: UnsafePointer<id?>?, count: UInt) -> id? {
        Arrays.initialize(object, Arrays.objects(objects, count: count, method: "-[NSArray initWithObjects:count:]"))
    }

    @ObjCMethod("initWithArray:")
    static func initialize(_ object: id?, array other: id?) -> id? { Arrays.initialize(object, elements(other)) }

    @ObjCMethod("dealloc")
    static func dealloc(_ object: id?) {
        guard let object else { return }
        Storage.set(object, nil)
        ObjC.superDealloc(object, from: Arrays.arrayClass)
    }

    // MARK: Querying

    @ObjCMethod("count")
    static func count(_ object: id?) -> UInt { UInt(elements(object).count) }

    @ObjCMethod("objectAtIndex:")
    static func object(_ object: id?, at index: UInt) -> id? {
        let all = elements(object)
        Arrays.checkIndex(index, all.count, "objectAtIndex:")
        return all[Int(index)]
    }

    @ObjCMethod("objectAtIndexedSubscript:")
    static func object(_ object: id?, subscript index: UInt) -> id? {
        let all = elements(object)
        Arrays.checkIndex(index, all.count, "objectAtIndexedSubscript:")
        return all[Int(index)]
    }

    @ObjCMethod("firstObject")
    static func first(_ object: id?) -> id? { elements(object).first }

    @ObjCMethod("lastObject")
    static func last(_ object: id?) -> id? { elements(object).last }

    @ObjCMethod("indexOfObject:")
    static func index(_ object: id?, of target: id?) -> UInt {
        guard let target else { return UInt(Int.max) }
        let index = elements(object).firstIndex { ObjectKey(object: $0) == ObjectKey(object: target) }
        return index.map(UInt.init) ?? UInt(Int.max)    // NSNotFound
    }

    @ObjCMethod("containsObject:")
    static func contains(_ object: id?, _ target: id?) -> Bool { index(object, of: target) != UInt(Int.max) }

    @ObjCMethod("isEqualToArray:")
    static func isEqual(_ object: id?, toArray other: id?) -> Bool {
        let a = elements(object), b = elements(other)
        return a.count == b.count && zip(a, b).allSatisfy { ObjectKey(object: $0) == ObjectKey(object: $1) }
    }

    @ObjCMethod("isEqual:")
    static func isEqual(_ object: id?, _ other: id?) -> Bool {
        object == other || (ObjC.isKind(other, of: Arrays.arrayClass) && isEqual(object, toArray: other))
    }

    @ObjCMethod("hash")
    static func hash(_ object: id?) -> UInt { UInt(elements(object).count) }

    @ObjCMethod("description")
    static func description(_ object: id?) -> id? { Strings.autoreleased(Describe.object(object, indent: 0)) }

    // MARK: Copying

    @ObjCMethod("copyWithZone:")
    static func copy(_ object: id?, zone: UnsafeMutableRawPointer?) -> id? { ObjC.retain(object) }

    @ObjCMethod("mutableCopyWithZone:")
    static func mutableCopy(_ object: id?, zone: UnsafeMutableRawPointer?) -> id? {
        Arrays.make(elements(object), cls: UnsafeMutableRawPointer(Arrays.mutableClass))
    }

    // MARK: Deriving

    @ObjCMethod("arrayByAddingObject:")
    static func adding(_ object: id?, _ element: id?) -> id? {
        Arrays.autoreleased(elements(object) + (element.map { [$0] } ?? []))
    }

    @ObjCMethod("arrayByAddingObjectsFromArray:")
    static func adding(_ object: id?, objectsFrom other: id?) -> id? {
        Arrays.autoreleased(elements(object) + elements(other))
    }

    @ObjCMethod("subarrayWithRange:")
    static func subarray(_ object: id?, range: NSRange) -> id? {
        let location = range.location, length = range.length
        let all = elements(object)
        guard Int(location + length) <= all.count else {
            foundationFatal("-[NSArray subarrayWithRange:]: range {\(location), \(length)} extends beyond bounds [0 .. \(all.count - 1)]")
        }
        return Arrays.autoreleased(Array(all[Int(location)..<Int(location + length)]))
    }

    @ObjCMethod("componentsJoinedByString:")
    static func joined(_ object: id?, separator: id?) -> id? {
        let parts = elements(object).map { Format.describe($0) }
        return Strings.autoreleased(parts.joined(separator: Strings.value(of: separator) ?? ""))
    }

    @ObjCMethod("makeObjectsPerformSelector:")
    static func makeObjectsPerform(_ object: id?, _ selector: SEL?) {
        guard let selector else { return }
        for element in elements(object) { _ = ObjC.send(element, selector) }
    }

    @ObjCMethod("sortedArrayUsingSelector:")
    static func sorted(_ object: id?, using selector: SEL?) -> id? {
        guard let selector else { return nil }
        return Arrays.autoreleased(elements(object).sorted { ObjC.sendInt($0, selector, $1) < 0 })
    }

    @ObjCMethod("sortedArrayUsingComparator:")
    static func sorted(_ object: id?, comparator: ObjCBlock?) -> id? {
        guard let comparator else { return nil }
        let compare = Blocks.invoke(comparator, as: (@convention(c) (id, id?, id?) -> Int).self)
        return Arrays.autoreleased(elements(object).sorted { compare(comparator, $0, $1) < 0 })
    }

    @ObjCMethod("enumerateObjectsUsingBlock:")
    static func enumerate(_ object: id?, block: ObjCBlock?) {
        guard let block else { return }
        let body = Blocks.invoke(block, as: (@convention(c) (id, id?, UInt, UnsafeMutablePointer<Bool>) -> Void).self)
        var stop = false
        for (index, element) in elements(object).enumerated() {
            body(block, element, UInt(index), &stop)
            if stop { break }
        }
    }

    @ObjCMethod("countByEnumeratingWithState:objects:count:")
    static func enumerate(_ object: id?, state: UnsafeMutableRawPointer?, objects: UnsafeMutablePointer<id?>?,
                          count: UInt) -> UInt {
        Arrays.storage(object)?.enumeration.enumerate(elements(object), state: state) ?? 0
    }
}

@ObjCImplementation
enum NSMutableArrayMethods {
    private static func storage(_ object: id?) -> ArrayStorage {
        guard let storage = Arrays.storage(object) else {
            foundationFatal("mutating method sent to an uninitialized NSMutableArray")
        }
        return storage
    }

    @ObjCClassMethod("arrayWithCapacity:")
    static func array(_ cls: id?, capacity: UInt) -> id? { Arrays.autoreleased([], cls: cls) }

    @ObjCMethod("initWithCapacity:")
    static func initialize(_ object: id?, capacity: UInt) -> id? { Arrays.initialize(object, []) }

    @ObjCMethod("copyWithZone:")
    static func copy(_ object: id?, zone: UnsafeMutableRawPointer?) -> id? { Arrays.make(Arrays.elements(object)) }

    @ObjCMethod("addObject:")
    static func add(_ object: id?, _ element: id?) {
        guard let element else { foundationFatal("-[NSMutableArray addObject:]: object cannot be nil") }
        let storage = storage(object)
        storage.objects.append(ObjC.retain(element)!)
        storage.enumeration.mutated()
    }

    @ObjCMethod("addObjectsFromArray:")
    static func add(_ object: id?, objectsFrom other: id?) {
        for element in Arrays.elements(other) { add(object, element) }
    }

    @ObjCMethod("insertObject:atIndex:")
    static func insert(_ object: id?, _ element: id?, at index: UInt) {
        guard let element else { foundationFatal("-[NSMutableArray insertObject:atIndex:]: object cannot be nil") }
        let storage = storage(object)
        if Int(index) > storage.objects.count {
            Arrays.checkIndex(index, storage.objects.count, "insertObject:atIndex:")
        }
        storage.objects.insert(ObjC.retain(element)!, at: Int(index))
        storage.enumeration.mutated()
    }

    @ObjCMethod("removeObjectAtIndex:")
    static func remove(_ object: id?, at index: UInt) {
        let storage = storage(object)
        Arrays.checkIndex(index, storage.objects.count, "removeObjectAtIndex:")
        let removed = storage.objects.remove(at: Int(index))
        storage.enumeration.mutated()
        ObjC.release(removed)
    }

    @ObjCMethod("removeObject:")
    static func remove(_ object: id?, _ element: id?) {
        guard let element else { return }
        let storage = storage(object)
        let removed = storage.objects.filter { ObjectKey(object: $0) == ObjectKey(object: element) }
        storage.objects.removeAll { ObjectKey(object: $0) == ObjectKey(object: element) }
        storage.enumeration.mutated()
        for item in removed { ObjC.release(item) }
    }

    @ObjCMethod("removeLastObject")
    static func removeLast(_ object: id?) {
        let storage = storage(object)
        guard let last = storage.objects.popLast() else { return }
        storage.enumeration.mutated()
        ObjC.release(last)
    }

    @ObjCMethod("removeAllObjects")
    static func removeAll(_ object: id?) {
        let storage = storage(object)
        let removed = storage.objects
        storage.objects.removeAll()
        storage.enumeration.mutated()
        for element in removed { ObjC.release(element) }
    }

    @ObjCMethod("replaceObjectAtIndex:withObject:")
    static func replace(_ object: id?, at index: UInt, with element: id?) {
        guard let element else { foundationFatal("-[NSMutableArray replaceObjectAtIndex:withObject:]: object cannot be nil") }
        let storage = storage(object)
        Arrays.checkIndex(index, storage.objects.count, "replaceObjectAtIndex:withObject:")
        let old = storage.objects[Int(index)]
        storage.objects[Int(index)] = ObjC.retain(element)!
        storage.enumeration.mutated()
        ObjC.release(old)
    }

    @ObjCMethod("setObject:atIndexedSubscript:")
    static func set(_ object: id?, _ element: id?, subscript index: UInt) {
        if Int(index) == storage(object).objects.count {
            add(object, element)
        } else {
            replace(object, at: index, with: element)
        }
    }

    @ObjCMethod("sortUsingSelector:")
    static func sort(_ object: id?, using selector: SEL?) {
        guard let selector else { return }
        let storage = storage(object)
        storage.objects.sort { ObjC.sendInt($0, selector, $1) < 0 }
        storage.enumeration.mutated()
    }
}

/// @[…] literals of constants: { isa, count, objects }, read in place.
@ObjCImplementation
enum NSConstantArrayMethods {
    @ObjCMethod("countByEnumeratingWithState:objects:count:")
    static func enumerate(_ object: id?, state: UnsafeMutableRawPointer?, objects: UnsafeMutablePointer<id?>?,
                          count: UInt) -> UInt {
        guard let object, let state, state.load(as: UInt.self) == 0 else { return 0 }
        state.storeBytes(of: 1, as: UInt.self)
        state.storeBytes(of: object.load(fromByteOffset: 16, as: UnsafeMutableRawPointer?.self),
                         toByteOffset: 8, as: UnsafeMutableRawPointer?.self)
        state.storeBytes(of: UnsafeMutableRawPointer(Arrays.constantMutationCounter), toByteOffset: 16,
                         as: UnsafeMutableRawPointer.self)
        return UInt(object.load(fromByteOffset: 8, as: UInt64.self))
    }
}

/// + (id)arrayWithObjects:(id)first, ... — nil-terminated.
@c
public func perry_foundation_arrayWithObjects(_ cls: id?, _ cmd: SEL?, _ first: id?,
                                              _ arguments: UnsafeRawPointer?) -> id? {
    Arrays.autoreleased(nilTerminated(first, arguments), cls: cls)
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
