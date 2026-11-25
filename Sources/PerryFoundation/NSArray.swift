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
            let count = Int(object.load(fromByteOffset: DarwinLayout.arrayCount, as: UInt.self))
            guard let objects = object.load(fromByteOffset: DarwinLayout.arrayObjects, as: UnsafePointer<id>?.self) else { return [] }
            return Array(UnsafeBufferPointer(start: objects, count: count))
        }
        if let storage = storage(object) {
            // A subclass that keeps its elements itself, such as a protocol buffer's proxy for a field's array, has
            // an empty storage and answers count and objectAtIndex: from its own: those are the array.
            guard storage.objects.isEmpty, !overriding else { return storage.objects }
        }
        // Another library's array, such as Swift's: its count and elements.
        guard ObjC.overrides(object, Selectors.count, of: arrayClass) else { return [] }
        overriding = true
        defer { overriding = false }
        return (0..<ObjC.sendUInt(object, Selectors.count)).compactMap { ObjC.sendIndex(object, Selectors.objectAtIndex, $0) }
    }

    /// Set while a subclass's count and objectAtIndex: are being asked for, so that their calls to super's
    /// do not ask again.
    nonisolated(unsafe) private static var overriding = false

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

    /// PERRY_FOUNDATION_RANGE=continue: reading an element past an array's
    /// end gives nil, with a warning, where it raises NSRangeException.
    /// For getting past an exception nothing catches to see what follows.
    nonisolated(unsafe) static let readsPastEnd = getenv("PERRY_FOUNDATION_RANGE").map { String(cString: $0) == "continue" } ?? false

    /// Whether the element can be read; false only under that switch.
    static func canRead(_ index: UInt, _ count: Int, _ method: String) -> Bool {
        if index < UInt(count) { return true }
        if readsPastEnd {
            foundationWarning("-[NSArray \(method)]: index \(index) beyond bounds [0 .. \(count - 1)], giving nil")
            return false
        }
        checkIndex(index, count, method)
        return true
    }

    /// Raises NSRangeException for an index past the end, with Darwin's
    /// reason.
    static func checkIndex(_ index: UInt, _ count: Int, _ method: String) {
        guard index >= UInt(count) else { return }
        let bounds = count == 0 ? "for empty NSArray" : "[0 .. \(count - 1)]"
        Exceptions.raise(name: "NSRangeException", reason: "*** -[NSArray \(method)]: index \(index) beyond bounds \(bounds)")
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


    /// For the class constructors: an app's subclass is made with +alloc
    /// and the init message, so its own -init runs, as on Darwin. nil for
    /// Foundation's own classes.
    static func subclassed(_ cls: id?, capacity: UInt? = nil) -> NSArray? {
        guard let cls, cls != UnsafeMutableRawPointer(arrayClass), cls != UnsafeMutableRawPointer(mutableClass),
              cls != UnsafeMutableRawPointer(constantClass) else { return nil }
        let allocated = ObjC.send(cls, ObjC.selector("alloc"))
        let made: id?
        if let capacity {
            typealias Init = @convention(c) (id?, SEL, UInt) -> id?
            made = unsafeBitCast(ObjC.msgSend, to: Init.self)(allocated, ObjC.selector("initWithCapacity:"), capacity)
        } else {
            made = ObjC.send(allocated, ObjC.selector("init"))
        }
        return made.map { NSArray(objCOwned: $0) }
    }

    /// A new array wrapped for returning, +1.
    static func owned(_ elements: [id], cls: id? = nil) -> NSArray {
        NSArray(objCOwned: make(elements, cls: cls))
    }

    static var constantMutationCounter: UnsafeMutablePointer<UInt> {
        withUnsafeMutablePointer(to: &constantMutations) { $0 }
    }

    /// The indexes among `indexes` (every one when nil) whose element passes
    /// the test block (BOOL (^)(id, NSUInteger, BOOL *)), in ascending
    /// order; tried from the last with NSEnumerationReverse (2), and only up
    /// to the first that passes with `first`. Concurrent tries run in order.
    static func passing(_ elements: [id], _ indexes: [Int]?, options: UInt, block: id, first: Bool, method: String) -> [Int] {
        var order = indexes ?? Array(elements.indices)
        if let beyond = order.first(where: { $0 >= elements.count }) {
            foundationFatal("\(method): index \(beyond) beyond bounds [0 .. \(elements.count - 1)]")
        }
        if options & 2 != 0 { order.reverse() }
        typealias Test = @convention(c) (id, id, UInt, UnsafeMutablePointer<Bool>) -> Bool
        let test = Blocks.invoke(block, as: Test.self)
        var found: [Int] = []
        for index in order {
            var stop = false
            if test(block, elements[index], UInt(index), &stop) {
                found.append(index)
                if first { break }
            }
            if stop { break }
        }
        return found.sorted()
    }

    /// An index set of single indexes, autoreleased.
    static func indexSet(_ indexes: [Int]) -> UnsafeMutableRawPointer? {
        IndexSets.make(UnsafeMutableRawPointer(IndexSets.setClass), indexes.map { $0..<$0 + 1 })
    }

    /// A binary search of the range, which the comparator keeps sorted:
    /// with NSBinarySearchingInsertionIndex (1 << 10) where the object
    /// would go (after any equal ones with NSBinarySearchingLastEqual,
    /// 1 << 9, else before them), otherwise an equal element's index (the
    /// first with NSBinarySearchingFirstEqual, 1 << 8, the last with
    /// LastEqual) or NSNotFound.
    static func search(_ all: [id], for object: id?, in range: NSRange, options: UInt, comparator: ObjCBlock) -> UInt {
        let start = min(Int(range.location), all.count)
        let end = min(all.count, start + Int(range.length))
        let compare = comparator.function(as: (@convention(c) (id, id?, id?) -> Int).self)
        let insertion = options & (1 << 10) != 0, last = options & (1 << 9) != 0
        // The first element not less than the object, or with `last` the
        // first greater than it.
        func bound(upper: Bool) -> Int {
            var low = start, high = end
            while low < high {
                let middle = (low + high) / 2
                let order = compare(comparator.object, all[middle], object)
                if order < 0 || (upper && order == 0) { low = middle + 1 } else { high = middle }
            }
            return low
        }
        if insertion { return UInt(bound(upper: last)) }
        guard object != nil else { return notFound }
        let lower = bound(upper: false)
        guard lower < end, compare(comparator.object, all[lower], object) == 0 else { return notFound }
        return last ? UInt(bound(upper: true) - 1) : UInt(lower)
    }
}

/// Darwin's arrays, sets and ordered sets can't be observed themselves:
/// adding or removing an observer of one raises.
enum CollectionObserving {
    static func unsupported(_ object: id, _ method: String, _ keyPath: ObjCObject?) -> Never {
        let path = Strings.value(of: keyPath?.objcObject) ?? "(null)"
        Exceptions.raise(name: "NSInvalidArgumentException",
                         reason: "[<\(ObjC.className(object)) \(object)> \(method)] is not supported. Key path: \(path)")
    }
}

/// NSArray.
@ObjCClass("NSArray")
public class NSArray: NSObject {
    /// What the Swift runtime asks to tell Foundation's classes apart.
    @ObjCMethod("isNSArray__") func isNSArray__() -> Bool { true }

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
    static func array(_ cls: ObjCClass) -> NSArray { Arrays.subclassed(cls.pointer) ?? Arrays.owned([], cls: cls.pointer) }

    @ObjCClassMethod("arrayWithObject:")
    static func array(_ cls: ObjCClass, object: ObjCObject) -> NSArray { Arrays.owned([object.id], cls: cls.pointer) }

    /// A property list file's array; mutable throughout when sent to a
    /// mutable class.
    @ObjCClassMethod("arrayWithContentsOfFile:")
    static func array(_ cls: ObjCClass, contentsOfFile path: String?) -> UnsafeMutableRawPointer? {
        // No path, as a resource that is not in the bundle has none, gives nil.
        guard let path else { return nil }
        return PropertyLists.contents(of: URL(filePath: path), cls, expecting: .array)
    }

    @ObjCClassMethod("arrayWithContentsOfURL:")
    static func array(_ cls: ObjCClass, contentsOfURL url: NSURL?) -> UnsafeMutableRawPointer? {
        guard let url else { return nil }
        return PropertyLists.contents(of: url.url, cls, expecting: .array)
    }

    @ObjCClassMethod("arrayWithContentsOfURL:error:")
    static func array(_ cls: ObjCClass, contentsOfURL url: NSURL, error: UnsafeMutablePointer<id?>?) -> UnsafeMutableRawPointer? {
        if let made = PropertyLists.contents(of: url.url, cls, expecting: .array) { return made }
        error?.pointee = Errors.autoreleased(domain: Errors.cocoaDomain, code: 260, description: "The file couldn’t be opened.")
        return nil
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

    @ObjCMethod("initWithCoder:")
    func initialize(coder: ObjCObject?) -> Self { setElements(CollectionCoding.objects(coder?.id)) }

    /// With copyItems, each element is the element's -copy.
    @ObjCMethod("initWithArray:copyItems:")
    func initialize(array other: NSArray?, copyItems: Bool) -> Self {
        guard copyItems else { return initialize(array: other) }
        let copies = (other?.elements ?? []).map { ObjC.send($0, Selectors.copyWithZone, nil) ?? ObjC.retain($0)! }
        defer { copies.forEach { ObjC.release($0) } }
        return setElements(copies)
    }

    /// A property list file's array; nil when the file holds none.
    @ObjCMethod("initWithContentsOfFile:")
    func initialize(contentsOfFile path: String?) -> Self? { path.flatMap { initialize(contentsOf: URL(filePath: $0)) } }

    @ObjCMethod("initWithContentsOfURL:")
    func initialize(contentsOfURL url: NSURL?) -> Self? { url.flatMap { initialize(contentsOf: $0.url) } }

    /// macOS 10.13's: nil and an error when the file holds no array.
    @ObjCMethod("initWithContentsOfURL:error:")
    func initialize(contentsOfURL url: NSURL, error: UnsafeMutablePointer<id?>?) -> Self? {
        if let made = initialize(contentsOf: url.url) { return made }
        error?.pointee = Errors.autoreleased(domain: Errors.cocoaDomain, code: 260, description: "The file couldn’t be opened.")
        return nil
    }

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
        ObjC.superDealloc(objcObject, from: Arrays.arrayClass)
    }

    // MARK: Querying

    @ObjCMethod("count")
    func count() -> UInt { UInt(elements.count) }

    /// Every element, into a buffer long enough: deprecated, as there is no
    /// knowing that it is.
    @ObjCMethod("getObjects:")
    func getObjects(_ buffer: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) {
        guard let buffer else { return }
        for (offset, element) in elements.enumerated() { buffer[offset] = element }
    }

    @ObjCMethod("getObjects:range:")
    func getObjects(_ buffer: UnsafeMutablePointer<UnsafeMutableRawPointer?>?, range: NSRange) {
        let all = elements
        guard Int(range.location + range.length) <= all.count else {
            foundationFatal("-[NSArray getObjects:range:]: range {\(range.location), \(range.length)} extends beyond bounds [0 .. \(all.count - 1)]")
        }
        guard let buffer else { return }
        for offset in 0..<Int(range.length) { buffer[offset] = all[Int(range.location) + offset] }
    }

    @ObjCMethod("objectAtIndex:")
    func object(at index: UInt) -> ObjCObject? {
        let all = elements
        guard Arrays.canRead(index, all.count, "objectAtIndex:") else { return nil }
        return ObjCObject(all[Int(index)])
    }

    @ObjCMethod("objectAtIndexedSubscript:")
    func object(subscript index: UInt) -> ObjCObject? {
        let all = elements
        guard Arrays.canRead(index, all.count, "objectAtIndexedSubscript:") else { return nil }
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

    /// The first element that is `target` itself, not only equal to it.
    @ObjCMethod("indexOfObjectIdenticalTo:")
    func index(ofIdentical target: ObjCObject?) -> UInt {
        guard let target else { return notFound }
        return elements.firstIndex { $0 == target.id }.map(UInt.init) ?? notFound
    }

    @ObjCMethod("indexOfObjectIdenticalTo:inRange:")
    func index(ofIdentical target: ObjCObject?, in range: NSRange) -> UInt {
        guard let target else { return notFound }
        let all = elements
        let start = Int(range.location)
        let end = min(all.count, start + Int(range.length))
        guard start < end else { return notFound }
        let found: Int? = (start..<end).first { all[$0] == target.id }
        return found.map { UInt($0) } ?? notFound
    }

    /// The first element in the range equal to `target`, or NSNotFound.
    @ObjCMethod("indexOfObject:inRange:")
    func index(of target: ObjCObject?, in range: NSRange) -> UInt {
        let all = elements
        guard Int(range.location + range.length) <= all.count else {
            foundationFatal("-[NSArray indexOfObject:inRange:]: range {\(range.location), \(range.length)} extends beyond bounds [0 .. \(all.count - 1)]")
        }
        guard let target else { return notFound }
        let start = Int(range.location)
        let found: Int? = (start..<(start + Int(range.length))).first { ObjectKey(object: all[$0]) == ObjectKey(object: target.id) }
        return found.map { UInt($0) } ?? notFound
    }

    /// The first element that the other array has one equal to.
    @ObjCMethod("firstObjectCommonWithArray:")
    func firstObjectCommon(with other: NSArray?) -> ObjCObject? {
        let theirs = Set((other?.elements ?? []).map { ObjectKey(object: $0) })
        return elements.first { theirs.contains(ObjectKey(object: $0)) }.map(ObjCObject.init)
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

    /// The description, whatever the locale: the collection has no
    /// locale-dependent parts of its own.
    @ObjCMethod("descriptionWithLocale:")
    func description(withLocale locale: ObjCObject?) -> String { Describe.object(objcObject, indent: 0) }

    @ObjCMethod("descriptionWithLocale:indent:")
    func description(withLocale locale: ObjCObject?, indent: UInt) -> String {
        Describe.object(objcObject, indent: Int(indent))
    }

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
    func joined(separator: String?) -> String { elements.map { Format.describe($0) }.joined(separator: separator ?? "") }

    @ObjCMethod("makeObjectsPerformSelector:")
    func makeObjectsPerform(_ selector: ObjCSelector) {
        for element in elements { _ = ObjC.send(element, selector.pointer.assumingMemoryBound(to: CChar.self)) }
    }

    @ObjCMethod("makeObjectsPerformSelector:withObject:")
    func makeObjectsPerform(_ selector: ObjCSelector, with argument: ObjCObject?) {
        for element in elements { _ = ObjC.send(element, selector.pointer.assumingMemoryBound(to: CChar.self), argument?.id) }
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

    @ObjCMethod("sortedArrayWithOptions:usingComparator:")
    func sorted(options: UInt, comparator: ObjCBlock) -> NSArray { sorted(comparator: comparator) }

    /// NSInteger (*)(id, id, void *): NSComparisonResult, ascending -1
    /// first.
    @ObjCMethod("sortedArrayUsingFunction:context:")
    func sorted(function: UnsafeRawPointer?, context: UnsafeMutableRawPointer?) -> NSArray {
        guard let function else { return Arrays.owned(elements) }
        let compare = unsafeBitCast(function, to: (@convention(c) (id?, id?, UnsafeMutableRawPointer?) -> Int).self)
        return Arrays.owned(elements.sorted { compare($0, $1, context) < 0 })
    }

    /// A binary search of the range, which the comparator keeps sorted:
    /// with NSBinarySearchingInsertionIndex (1 << 10) where the object
    /// would go (after any equal ones with NSBinarySearchingLastEqual,
    /// 1 << 9, else before them), otherwise an equal element's index (the
    /// first with NSBinarySearchingFirstEqual, 1 << 8, the last with
    /// LastEqual) or NSNotFound.
    @ObjCMethod("indexOfObject:inSortedRange:options:usingComparator:")
    func index(of target: ObjCObject?, inSortedRange range: NSRange, options: UInt, comparator: ObjCBlock) -> UInt {
        Arrays.search(elements, for: target?.id, in: range, options: options, comparator: comparator)
    }

    /// An opaque hint for -sortedArrayUsingFunction:context:hint:, which
    /// sorts as well without it here.
    @ObjCMethod("sortedArrayHint")
    func sortedArrayHint() -> UnsafeMutableRawPointer? {
        var count = UInt64(elements.count)
        return DataObjects.autoreleased(Data(bytes: &count, count: 8))
    }

    @ObjCMethod("sortedArrayUsingFunction:context:hint:")
    func sorted(function: UnsafeRawPointer?, context: UnsafeMutableRawPointer?, hint: ObjCObject?) -> NSArray {
        sorted(function: function, context: context)
    }

    /// The strings whose path extension is one of `extensions`, compared
    /// exactly.
    @ObjCMethod("pathsMatchingExtensions:")
    func paths(matchingExtensions extensions: NSArray?) -> NSArray {
        let wanted = Set((extensions?.elements ?? []).compactMap { Strings.value(of: $0) })
        return Arrays.owned(elements.filter { element in
            guard let path = Strings.value(of: element) else { return false }
            return wanted.contains(Paths.pathExtension(path))
        })
    }

    /// The first of the indexes, by NSEnumerationOptions, whose element passes.
    @ObjCMethod("indexOfObjectAtIndexes:options:passingTest:")
    func index(atIndexes indexes: ObjCObject, options: UInt, passingTest block: ObjCObject) -> UInt {
        let found = Arrays.passing(elements, IndexSets.storage(indexes.id).indexes, options: options, block: block.id, first: true,
                                   method: "-[NSArray indexOfObjectAtIndexes:options:passingTest:]")
        return found.first.map { UInt($0) } ?? notFound
    }

    @ObjCMethod("indexesOfObjectsAtIndexes:options:passingTest:")
    func indexes(atIndexes indexes: ObjCObject, options: UInt, passingTest block: ObjCObject) -> UnsafeMutableRawPointer? {
        Arrays.indexSet(Arrays.passing(elements, IndexSets.storage(indexes.id).indexes, options: options, block: block.id,
                                       first: false, method: "-[NSArray indexesOfObjectsAtIndexes:options:passingTest:]"))
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

    /// NSEnumerationReverse (2) runs from the last; concurrent runs in order.
    @ObjCMethod("enumerateObjectsWithOptions:usingBlock:")
    func enumerate(options: UInt, block: ObjCBlock) {
        let all = Array(elements.enumerated())
        enumerate(all, reverse: options & 2 != 0, block: block)
    }

    @ObjCMethod("enumerateObjectsAtIndexes:options:usingBlock:")
    func enumerate(indexes: NSIndexSet, options: UInt, block: ObjCBlock) {
        let all = Array(elements.enumerated())
        let chosen = Set(indexes.storage.indexes)
        enumerate(all.filter { chosen.contains($0.offset) }, reverse: options & 2 != 0, block: block)
    }

    private func enumerate(_ pairs: [(offset: Int, element: id)], reverse: Bool, block: ObjCBlock) {
        let body = block.function(as: (@convention(c) (id, id?, UInt, UnsafeMutablePointer<Bool>) -> Void).self)
        var stop = false
        for (index, element) in reverse ? pairs.reversed() : pairs {
            body(block.object, element, UInt(index), &stop)
            if stop { break }
        }
    }

    @ObjCMethod("countByEnumeratingWithState:objects:count:")
    func enumerate(state: UnsafeMutableRawPointer?, objects: UnsafeMutablePointer<id?>?, count: UInt) -> UInt {
        Arrays.storage(objcObject)?.enumeration.enumerate(elements, state: state, buffer: objects, count: count) ?? 0
    }

    // MARK: Observing

    /// An array can't be observed itself: these raise, as on Darwin. Its
    /// elements can, through the methods with indexes.
    @ObjCMethod("addObserver:forKeyPath:options:context:")
    func rejectObserver(_ observer: ObjCObject?, forKeyPath keyPath: ObjCObject?, options: UInt, context: UnsafeMutableRawPointer?) {
        CollectionObserving.unsupported(objcObject, "addObserver:forKeyPath:options:context:", keyPath)
    }

    @ObjCMethod("removeObserver:forKeyPath:")
    func rejectRemoval(_ observer: ObjCObject?, forKeyPath keyPath: ObjCObject?) {
        CollectionObserving.unsupported(objcObject, "removeObserver:forKeyPath:", keyPath)
    }

    @ObjCMethod("removeObserver:forKeyPath:context:")
    func rejectRemoval(_ observer: ObjCObject?, forKeyPath keyPath: ObjCObject?, context: UnsafeMutableRawPointer?) {
        CollectionObserving.unsupported(objcObject, "removeObserver:forKeyPath:context:", keyPath)
    }

    private func observed(_ indexes: ObjCObject?, _ method: String) -> [id] {
        let all = elements
        return IndexSets.storage(indexes?.id).indexes.map { index in
            guard index < all.count else { foundationFatal("-[NSArray \(method)]: index \(index) beyond bounds [0 .. \(all.count - 1)]") }
            return all[index]
        }
    }

    /// Each element at the indexes is sent -addObserver:forKeyPath:options:context:.
    @ObjCMethod("addObserver:toObjectsAtIndexes:forKeyPath:options:context:")
    func addObserver(_ observer: ObjCObject?, toObjectsAtIndexes indexes: ObjCObject?, forKeyPath keyPath: ObjCObject?, options: UInt,
                     context: UnsafeMutableRawPointer?) {
        typealias Add = @convention(c) (id, SEL, id?, id?, UInt, UnsafeMutableRawPointer?) -> Void
        let add = unsafeBitCast(ObjC.msgSend, to: Add.self)
        for element in observed(indexes, "addObserver:toObjectsAtIndexes:forKeyPath:options:context:") {
            add(element, ObjC.selector("addObserver:forKeyPath:options:context:"), observer?.objcObject, keyPath?.objcObject, options, context)
        }
    }

    @ObjCMethod("removeObserver:fromObjectsAtIndexes:forKeyPath:")
    func removeObserver(_ observer: ObjCObject?, fromObjectsAtIndexes indexes: ObjCObject?, forKeyPath keyPath: ObjCObject?) {
        for element in observed(indexes, "removeObserver:fromObjectsAtIndexes:forKeyPath:") {
            _ = ObjC.send(element, ObjC.selector("removeObserver:forKeyPath:"), observer?.objcObject, keyPath?.objcObject)
        }
    }

    @ObjCMethod("removeObserver:fromObjectsAtIndexes:forKeyPath:context:")
    func removeObserver(_ observer: ObjCObject?, fromObjectsAtIndexes indexes: ObjCObject?, forKeyPath keyPath: ObjCObject?,
                        context: UnsafeMutableRawPointer?) {
        typealias Remove = @convention(c) (id, SEL, id?, id?, UnsafeMutableRawPointer?) -> Void
        let remove = unsafeBitCast(ObjC.msgSend, to: Remove.self)
        for element in observed(indexes, "removeObserver:fromObjectsAtIndexes:forKeyPath:context:") {
            remove(element, ObjC.selector("removeObserver:forKeyPath:context:"), observer?.objcObject, keyPath?.objcObject, context)
        }
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
    static func array(_ cls: ObjCClass, capacity: UInt) -> NSArray {
        Arrays.subclassed(cls.pointer, capacity: capacity) ?? Arrays.owned([], cls: cls.pointer)
    }

    @ObjCMethod("initWithCapacity:")
    func initialize(capacity: UInt) -> Self {
        _ = Arrays.initialize(objcObject, [])
        return self
    }

    @ObjCMethod("copyWithZone:")
    override func copy(zone: UnsafeMutableRawPointer?) -> NSArray { Arrays.owned(storage.objects) }

    @ObjCMethod("addObject:")
    func add(_ element: ObjCObject?) {
        guard let element else {
            Exceptions.raise(name: "NSInvalidArgumentException", reason: "*** -[__NSArrayM insertObject:atIndex:]: object cannot be nil")
        }
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

    /// The range's elements replaced by those of `other` in `otherRange`.
    @ObjCMethod("replaceObjectsInRange:withObjectsFromArray:range:")
    func replace(range: NSRange, withObjectsFrom other: UnsafeMutableRawPointer?, otherRange: NSRange) {
        let count = storage.objects.count
        if Int(range.location) + Int(range.length) > count {
            foundationFatal("-[NSMutableArray replaceObjectsInRange:withObjectsFromArray:range:]: range {\(range.location), \(range.length)} extends beyond bounds [0 .. \(count - 1)]")
        }
        let source = Arrays.elements(other)
        let start = Int(otherRange.location), end = min(source.count, start + Int(otherRange.length))
        let added = start < end ? Array(source[start..<end]) : []
        let retained = added.compactMap { ObjC.retain($0) }
        let first = Int(range.location)
        let removed = Array(storage.objects[first..<(first + Int(range.length))])
        storage.objects.replaceSubrange(first..<(first + Int(range.length)), with: retained)
        storage.enumeration.mutated()
        removed.forEach { ObjC.release($0) }
    }

    @ObjCMethod("replaceObjectsInRange:withObjectsFromArray:")
    func replace(range: NSRange, withObjectsFrom other: UnsafeMutableRawPointer?) {
        let total = Arrays.elements(other).count
        replace(range: range, withObjectsFrom: other, otherRange: NSRange(location: 0, length: total))
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

    /// Removes every element equal to one of the array's.
    @ObjCMethod("removeObjectsInArray:")
    func remove(objectsIn other: NSArray?) {
        let keys = (other?.elements ?? []).map { ObjectKey(object: $0) }
        guard !keys.isEmpty else { return }
        let matches = { (object: id) in keys.contains(ObjectKey(object: object)) }
        let removed = storage.objects.filter(matches)
        storage.objects.removeAll(where: matches)
        storage.enumeration.mutated()
        for item in removed { ObjC.release(item) }
    }

    /// Removes the elements that are `element` itself.
    @ObjCMethod("removeObjectIdenticalTo:")
    func remove(identical element: ObjCObject?) {
        guard let element else { return }
        let removed = storage.objects.filter { $0 == element.id }
        storage.objects.removeAll { $0 == element.id }
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

    @ObjCMethod("exchangeObjectAtIndex:withObjectAtIndex:")
    func exchange(at first: UInt, with second: UInt) {
        Arrays.checkIndex(first, storage.objects.count, "exchangeObjectAtIndex:withObjectAtIndex:")
        Arrays.checkIndex(second, storage.objects.count, "exchangeObjectAtIndex:withObjectAtIndex:")
        storage.objects.swapAt(Int(first), Int(second))
        storage.enumeration.mutated()
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

    /// NSComparisonResult from the block: ascending -1 first. Swift's sort
    /// is stable, as NSSortStable asks.
    @ObjCMethod("sortUsingComparator:")
    func sort(comparator: ObjCBlock) {
        let compare = comparator.function(as: (@convention(c) (id, id?, id?) -> Int).self)
        storage.objects.sort { compare(comparator.object, $0, $1) < 0 }
        storage.enumeration.mutated()
    }

    /// NSInteger (*)(id, id, void *): NSComparisonResult, ascending -1
    /// first.
    @ObjCMethod("sortUsingFunction:context:")
    func sort(function: UnsafeRawPointer?, context: UnsafeMutableRawPointer?) {
        guard let function else { return }
        let compare = unsafeBitCast(function, to: (@convention(c) (id?, id?, UnsafeMutableRawPointer?) -> Int).self)
        storage.objects.sort { compare($0, $1, context) < 0 }
        storage.enumeration.mutated()
    }

    /// NSSortOptions (concurrent, stable) only tune the sort.
    @ObjCMethod("sortWithOptions:usingComparator:")
    func sort(options: UInt, comparator: ObjCBlock) { sort(comparator: comparator) }

    /// A stable sort by each NSSortDescriptor in turn.
    @ObjCMethod("sortUsingDescriptors:")
    func sort(usingDescriptors descriptors: ObjCObject?) {
        guard !Arrays.elements(descriptors?.objcObject).isEmpty else { return }
        storage.objects = SortDescriptors.sorted(storage.objects, by: descriptors?.objcObject)
        storage.enumeration.mutated()
    }

    /// Replaces the elements with `replacement`, retaining the new ones
    /// before the old ones go.
    private func replaceAll(with replacement: [id]) {
        for element in replacement { _ = ObjC.retain(element) }
        let removed = storage.objects
        storage.objects = replacement
        storage.enumeration.mutated()
        for element in removed { ObjC.release(element) }
    }

    private func checkRange(_ range: NSRange, _ method: String) {
        let count = storage.objects.count
        if Int(range.location) + Int(range.length) > count {
            foundationFatal("-[NSMutableArray \(method)]: range {\(range.location), \(range.length)} extends beyond bounds [0 .. \(count - 1)]")
        }
    }

    /// Removes the elements in the range equal to `element`.
    @ObjCMethod("removeObject:inRange:")
    func remove(_ element: ObjCObject?, inRange range: NSRange) {
        checkRange(range, "removeObject:inRange:")
        guard let element else { return }
        let key = ObjectKey(object: element.id), start = Int(range.location), end = start + Int(range.length)
        replaceAll(with: storage.objects.enumerated().filter { !(start..<end).contains($0.offset) || ObjectKey(object: $0.element) != key }
            .map(\.element))
    }

    /// Removes the elements in the range that are `element` itself.
    @ObjCMethod("removeObjectIdenticalTo:inRange:")
    func remove(identical element: ObjCObject?, inRange range: NSRange) {
        checkRange(range, "removeObjectIdenticalTo:inRange:")
        guard let element else { return }
        let start = Int(range.location), end = start + Int(range.length)
        replaceAll(with: storage.objects.enumerated().filter { !(start..<end).contains($0.offset) || $0.element != element.id }.map(\.element))
    }

    /// Removes the elements at a C array of indexes, in any order.
    @ObjCMethod("removeObjectsFromIndices:numIndices:")
    func remove(fromIndices indices: UnsafePointer<UInt>?, numIndices count: UInt) {
        guard let indices, count > 0 else { return }
        let doomed = Set(UnsafeBufferPointer(start: indices, count: Int(count)).map { Int($0) })
        if let beyond = doomed.first(where: { $0 >= storage.objects.count }) {
            Arrays.checkIndex(UInt(beyond), storage.objects.count, "removeObjectsFromIndices:numIndices:")
        }
        replaceAll(with: storage.objects.enumerated().filter { !doomed.contains($0.offset) }.map(\.element))
    }

    /// The elements at the indexes, in ascending order, replaced by the
    /// array's, in order.
    @ObjCMethod("replaceObjectsAtIndexes:withObjects:")
    func replace(atIndexes indexes: ObjCObject, withObjects objects: NSArray?) {
        let positions = IndexSets.storage(indexes.id).indexes, replacements = objects?.elements ?? []
        guard positions.count == replacements.count else {
            foundationFatal("-[NSMutableArray replaceObjectsAtIndexes:withObjects:]: count of array (\(replacements.count)) differs from count of index set (\(positions.count))")
        }
        var updated = storage.objects
        for (position, replacement) in zip(positions, replacements) {
            Arrays.checkIndex(UInt(position), updated.count, "replaceObjectsAtIndexes:withObjects:")
            updated[position] = replacement
        }
        replaceAll(with: updated)
    }

    /// The array made what the difference turns it into; unchanged if the
    /// difference doesn't apply to it.
    @ObjCMethod("applyDifference:")
    func apply(difference: UnsafeMutableRawPointer?) {
        guard let changed = NSOrderedCollectionDifference.apply(difference, to: storage.objects) else { return }
        replaceAll(with: changed)
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
        state.storeBytes(of: objcObject.load(fromByteOffset: DarwinLayout.arrayObjects, as: UnsafeMutableRawPointer?.self),
                         toByteOffset: DarwinLayout.enumerationItems, as: UnsafeMutableRawPointer?.self)
        state.storeBytes(of: UnsafeMutableRawPointer(Arrays.constantMutationCounter), toByteOffset: DarwinLayout.enumerationMutations,
                         as: UnsafeMutableRawPointer.self)
        return objcObject.load(fromByteOffset: DarwinLayout.arrayCount, as: UInt.self)
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

/// A collection's contents from a keyed coder that isn't NSKeyedUnarchiver
/// (which makes Foundation's collections itself), as Foundation's
/// -initWithCoder: reads them: an array under "NS.objects" (and "NS.keys"),
/// else one object (and key) under each of "NS.object.0", "NS.object.1"…
/// Interface Builder's XIB decoder gives a dictionary this way.
enum CollectionCoding {
    private static func contains(_ coder: id, _ key: String) -> Bool {
        ObjC.sendBool(coder, ObjC.selector("containsValueForKey:"), Strings.autoreleased(key))
    }

    private static func object(_ coder: id, _ key: String) -> id? {
        ObjC.send(coder, ObjC.selector("decodeObjectForKey:"), Strings.autoreleased(key))
    }

    private static func keyed(_ coder: id?) -> id? {
        guard let coder, ObjC.sendBool(coder, ObjC.selector("allowsKeyedCoding"), nil) else { return nil }
        return coder
    }

    static func objects(_ coder: id?) -> [id] {
        guard let coder = keyed(coder) else { return [] }
        if contains(coder, "NS.objects") { return Arrays.elements(object(coder, "NS.objects")) }
        var objects: [id] = []
        while let next = object(coder, "NS.object.\(objects.count)") { objects.append(next) }
        return objects
    }

    static func entries(_ coder: id?) -> [(key: id, value: id)] {
        guard let coder = keyed(coder) else { return [] }
        if contains(coder, "NS.keys") {
            return zip(Arrays.elements(object(coder, "NS.keys")), Arrays.elements(object(coder, "NS.objects"))).map { (key: $0, value: $1) }
        }
        var entries: [(key: id, value: id)] = []
        while let key = object(coder, "NS.key.\(entries.count)"), let value = object(coder, "NS.object.\(entries.count)") {
            entries.append((key: key, value: value))
        }
        return entries
    }
}
