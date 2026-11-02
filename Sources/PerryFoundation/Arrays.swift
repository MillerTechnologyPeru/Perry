import CPerryFoundation
import Glibc

/// An NSArray's elements, each retained.
final class ArrayStorage {
    var objects: [id]
    /// For fast enumeration: a stable copy of `objects` and a mutation count.
    var enumerationBuffer: UnsafeMutablePointer<id?>?
    let mutations = UnsafeMutablePointer<UInt>.allocate(capacity: 1)

    init(_ objects: [id]) {
        self.objects = objects
        mutations.initialize(to: 0)
    }

    deinit {
        for object in objects { ObjC.release(object) }
        enumerationBuffer?.deallocate()
        mutations.deallocate()
    }
}

enum Arrays {
    nonisolated(unsafe) static var arrayClass: Class!
    nonisolated(unsafe) static var mutableClass: Class!

    static func storage(_ object: id?) -> ArrayStorage? {
        Storage.get(object, as: ArrayStorage.self)
    }

    static func elements(_ object: id?) -> [id] {
        storage(object)?.objects ?? []
    }

    /// Fills `object` with `elements`, retaining each.
    static func initialize(_ object: id, _ elements: [id]) {
        for element in elements { _ = ObjC.retain(element) }
        Storage.set(object, ArrayStorage(elements))
    }

    /// A new autoreleased array of `cls` (or NSArray).
    static func autoreleased(_ elements: [id], cls: id? = nil) -> id {
        let object = Storage.allocate(cls ?? UnsafeMutableRawPointer(arrayClass))!
        initialize(object, elements)
        return ObjC.autorelease(object)!
    }

    static func checkIndex(_ index: UInt, _ count: Int, _ method: String) {
        if Int(index) >= count {
            foundationFatal("-[NSArray \(method)]: index \(index) beyond bounds [0 .. \(count - 1)]")
        }
    }

    static func objectsFromBuffer(_ buffer: UnsafeRawPointer?, _ count: UInt) -> [id] {
        guard let buffer else { return [] }
        let objects = buffer.assumingMemoryBound(to: id?.self)
        return (0..<Int(count)).map { index in
            guard let object = objects[index] else {
                foundationFatal("-[NSArray initWithObjects:count:]: attempt to insert nil object from objects[\(index)]")
            }
            return object
        }
    }

    static func description(_ object: id?) -> String {
        let items = elements(object).map { "    " + Format.describe($0) }
        return items.isEmpty ? "(\n)" : "(\n" + items.joined(separator: ",\n") + "\n)"
    }

    // Blocks: the invoke function is the word after isa, flags and reserved.
    static func invokePointer(_ block: id) -> UnsafeRawPointer {
        block.load(fromByteOffset: 16, as: UnsafeRawPointer.self)
    }

    static func install(superclass: Class) {
        let array = ClassDefinition(PERRY_CLASS_NSArray, name: "NSArray", superclass: superclass)
        arrayClass = array.cls

        array.classMethod("alloc", "@16@0:8", { cls, _ in Storage.allocate(cls) } as IMPObject)
        array.classMethod("allocWithZone:", "@24@0:8^v16", { cls, _, _ in Storage.allocate(cls) } as IMPObjectObject)
        array.classMethod("array", "@16@0:8", { cls, _ in Arrays.autoreleased([], cls: cls) } as IMPObject)
        array.classMethod("arrayWithObject:", "@24@0:8@16", { cls, _, element in
            Arrays.autoreleased(element.map { [$0] } ?? [], cls: cls)
        } as IMPObjectObject)
        array.classMethod("arrayWithArray:", "@24@0:8@16", { cls, _, other in
            Arrays.autoreleased(Arrays.elements(other), cls: cls)
        } as IMPObjectObject)
        array.classMethod("arrayWithObjects:count:", "@32@0:8^@16Q24", { cls, _, objects, count in
            Arrays.autoreleased(Arrays.objectsFromBuffer(objects, count), cls: cls)
        } as @convention(c) (id?, SEL, UnsafeRawPointer?, UInt) -> id?)
        array.classMethod("arrayWithObjects:", "@24@0:8@16", address: unsafeBitCast(
            perry_imp_arrayWithObjects as @convention(c) () -> Void, to: UnsafeRawPointer.self))

        array.method("init", "@16@0:8", { object, _ in
            if let object { Arrays.initialize(object, []) }
            return object
        } as IMPObject)
        array.method("initWithObjects:count:", "@32@0:8^@16Q24", { object, _, objects, count in
            if let object { Arrays.initialize(object, Arrays.objectsFromBuffer(objects, count)) }
            return object
        } as @convention(c) (id?, SEL, UnsafeRawPointer?, UInt) -> id?)
        array.method("initWithArray:", "@24@0:8@16", { object, _, other in
            if let object { Arrays.initialize(object, Arrays.elements(other)) }
            return object
        } as IMPObjectObject)
        array.method("dealloc", "v16@0:8", { object, _ in
            guard let object else { return }
            Storage.set(object, nil)
            ObjC.superDealloc(object, from: Arrays.arrayClass)
        } as IMPVoid)

        array.method("count", "Q16@0:8", { object, _ in UInt(Arrays.elements(object).count) } as IMPUInt)
        array.method("objectAtIndex:", "@24@0:8Q16", { object, _, index in
            let elements = Arrays.elements(object)
            Arrays.checkIndex(index, elements.count, "objectAtIndex:")
            return elements[Int(index)]
        } as @convention(c) (id?, SEL, UInt) -> id?)
        array.method("objectAtIndexedSubscript:", "@24@0:8Q16", { object, _, index in
            let elements = Arrays.elements(object)
            Arrays.checkIndex(index, elements.count, "objectAtIndexedSubscript:")
            return elements[Int(index)]
        } as @convention(c) (id?, SEL, UInt) -> id?)
        array.method("firstObject", "@16@0:8", { object, _ in Arrays.elements(object).first } as IMPObject)
        array.method("lastObject", "@16@0:8", { object, _ in Arrays.elements(object).last } as IMPObject)
        array.method("indexOfObject:", "Q24@0:8@16", { object, _, target in
            let index = Arrays.elements(object).firstIndex { $0 == target || ObjC.sendBool($0, Selectors.isEqual, target) }
            return index.map(UInt.init) ?? UInt(Int.max)    // NSNotFound
        } as @convention(c) (id?, SEL, id?) -> UInt)
        array.method("containsObject:", "B24@0:8@16", { object, _, target in
            Arrays.elements(object).contains { $0 == target || ObjC.sendBool($0, Selectors.isEqual, target) }
        } as IMPBoolObject)
        array.method("description", "@16@0:8", { object, _ in
            Strings.autoreleased(Arrays.description(object))
        } as IMPObject)
        array.method("copyWithZone:", "@24@0:8^v16", { object, _, _ in ObjC.retain(object) } as IMPObjectObject)
        array.method("mutableCopyWithZone:", "@24@0:8^v16", { object, _, _ in
            let copy = Storage.allocate(UnsafeMutableRawPointer(Arrays.mutableClass))!
            Arrays.initialize(copy, Arrays.elements(object))
            return copy
        } as IMPObjectObject)
        array.method("arrayByAddingObject:", "@24@0:8@16", { object, _, element in
            Arrays.autoreleased(Arrays.elements(object) + (element.map { [$0] } ?? []))
        } as IMPObjectObject)
        array.method("componentsJoinedByString:", "@24@0:8@16", { object, _, separator in
            let parts = Arrays.elements(object).map { Format.describe($0) }
            return Strings.autoreleased(parts.joined(separator: Strings.value(of: separator) ?? ""))
        } as IMPObjectObject)
        array.method("makeObjectsPerformSelector:", "v24@0:8:16", { object, _, selector in
            guard let selector = selector?.assumingMemoryBound(to: CChar.self) else { return }
            for element in Arrays.elements(object) { _ = ObjC.send(element, selector) }
        } as @convention(c) (id?, SEL, UnsafeRawPointer?) -> Void)
        array.method("sortedArrayUsingSelector:", "@24@0:8:16", { object, _, selector in
            guard let selector = selector?.assumingMemoryBound(to: CChar.self) else { return nil }
            let sorted = Arrays.elements(object).sorted { ObjC.sendInt($0, selector, $1) < 0 }
            return Arrays.autoreleased(sorted)
        } as @convention(c) (id?, SEL, UnsafeRawPointer?) -> id?)
        array.method("sortedArrayUsingComparator:", "@24@0:8@?16", { object, _, comparator in
            guard let comparator else { return nil }
            typealias Compare = @convention(c) (id, id?, id?) -> Int
            let compare = unsafeBitCast(Arrays.invokePointer(comparator), to: Compare.self)
            return Arrays.autoreleased(Arrays.elements(object).sorted { compare(comparator, $0, $1) < 0 })
        } as IMPObjectObject)
        array.method("enumerateObjectsUsingBlock:", "v24@0:8@?16", { object, _, block in
            guard let block else { return }
            typealias Body = @convention(c) (id, id?, UInt, UnsafeMutablePointer<Bool>) -> Void
            let body = unsafeBitCast(Arrays.invokePointer(block), to: Body.self)
            var stop = false
            for (index, element) in Arrays.elements(object).enumerated() {
                body(block, element, UInt(index), &stop)
                if stop { break }
            }
        } as IMPVoidObject)
        // for (id x in array): hand out the whole array in one batch.
        array.method("countByEnumeratingWithState:objects:count:", "Q40@0:8^v16^@24Q32", { object, _, state, _, _ in
            guard let state, let storage = Arrays.storage(object) else { return 0 }
            // NSFastEnumerationState: state, itemsPtr, mutationsPtr, extra[5]
            if state.load(as: UInt.self) != 0 { return 0 }
            storage.enumerationBuffer?.deallocate()
            let buffer = UnsafeMutablePointer<id?>.allocate(capacity: max(storage.objects.count, 1))
            for (index, element) in storage.objects.enumerated() { (buffer + index).initialize(to: element) }
            storage.enumerationBuffer = buffer
            state.storeBytes(of: 1, as: UInt.self)
            state.storeBytes(of: UnsafeMutableRawPointer(buffer), toByteOffset: 8, as: UnsafeMutableRawPointer.self)
            state.storeBytes(of: UnsafeMutableRawPointer(storage.mutations), toByteOffset: 16, as: UnsafeMutableRawPointer.self)
            return UInt(storage.objects.count)
        } as @convention(c) (id?, SEL, UnsafeMutableRawPointer?, UnsafeRawPointer?, UInt) -> UInt)
        array.register()

        let mutable = ClassDefinition(PERRY_CLASS_NSMutableArray, name: "NSMutableArray", superclass: array.cls)
        mutableClass = mutable.cls
        mutable.classMethod("arrayWithCapacity:", "@24@0:8Q16", { cls, _, _ in
            Arrays.autoreleased([], cls: cls)
        } as @convention(c) (id?, SEL, UInt) -> id?)
        mutable.method("initWithCapacity:", "@24@0:8Q16", { object, _, _ in
            if let object { Arrays.initialize(object, []) }
            return object
        } as @convention(c) (id?, SEL, UInt) -> id?)
        mutable.method("copyWithZone:", "@24@0:8^v16", { object, _, _ in
            let copy = Storage.allocate(UnsafeMutableRawPointer(Arrays.arrayClass))!
            Arrays.initialize(copy, Arrays.elements(object))
            return copy
        } as IMPObjectObject)
        mutable.method("addObject:", "v24@0:8@16", { object, _, element in
            guard let storage = Arrays.storage(object) else { return }
            guard let element else { foundationFatal("-[NSMutableArray addObject:]: object cannot be nil") }
            storage.objects.append(ObjC.retain(element)!)
            storage.mutations.pointee += 1
        } as IMPVoidObject)
        mutable.method("insertObject:atIndex:", "v32@0:8@16Q24", { object, _, element, index in
            guard let storage = Arrays.storage(object) else { return }
            guard let element else { foundationFatal("-[NSMutableArray insertObject:atIndex:]: object cannot be nil") }
            if Int(index) > storage.objects.count { Arrays.checkIndex(index, storage.objects.count, "insertObject:atIndex:") }
            storage.objects.insert(ObjC.retain(element)!, at: Int(index))
            storage.mutations.pointee += 1
        } as @convention(c) (id?, SEL, id?, UInt) -> Void)
        mutable.method("removeObjectAtIndex:", "v24@0:8Q16", { object, _, index in
            guard let storage = Arrays.storage(object) else { return }
            Arrays.checkIndex(index, storage.objects.count, "removeObjectAtIndex:")
            ObjC.release(storage.objects.remove(at: Int(index)))
            storage.mutations.pointee += 1
        } as @convention(c) (id?, SEL, UInt) -> Void)
        mutable.method("removeLastObject", "v16@0:8", { object, _ in
            guard let storage = Arrays.storage(object), let last = storage.objects.popLast() else { return }
            ObjC.release(last)
            storage.mutations.pointee += 1
        } as IMPVoid)
        mutable.method("removeAllObjects", "v16@0:8", { object, _ in
            guard let storage = Arrays.storage(object) else { return }
            let removed = storage.objects
            storage.objects.removeAll()
            storage.mutations.pointee += 1
            for element in removed { ObjC.release(element) }
        } as IMPVoid)
        mutable.method("replaceObjectAtIndex:withObject:", "v32@0:8Q16@24", { object, _, index, element in
            guard let storage = Arrays.storage(object), let element else { return }
            Arrays.checkIndex(index, storage.objects.count, "replaceObjectAtIndex:withObject:")
            let old = storage.objects[Int(index)]
            storage.objects[Int(index)] = ObjC.retain(element)!
            storage.mutations.pointee += 1
            ObjC.release(old)
        } as @convention(c) (id?, SEL, UInt, id?) -> Void)
        mutable.method("setObject:atIndexedSubscript:", "v32@0:8@16Q24", { object, _, element, index in
            guard let storage = Arrays.storage(object), let element else { return }
            if Int(index) == storage.objects.count {
                storage.objects.append(ObjC.retain(element)!)
            } else {
                Arrays.checkIndex(index, storage.objects.count, "setObject:atIndexedSubscript:")
                let old = storage.objects[Int(index)]
                storage.objects[Int(index)] = ObjC.retain(element)!
                ObjC.release(old)
            }
            storage.mutations.pointee += 1
        } as @convention(c) (id?, SEL, id?, UInt) -> Void)
        mutable.register()
    }
}

/// + (id)arrayWithObjects:(id)first, ... — nil-terminated.
@c
public func perry_foundation_arrayWithObjects(_ cls: id?, _ cmd: SEL?, _ first: id?,
                                              _ arguments: UnsafeRawPointer?) -> id? {
    var elements: [id] = []
    if let first, let arguments {
        elements.append(first)
        var darwin = DarwinArguments(arguments)
        while let next = darwin.nextPointer() {
            elements.append(next)
        }
    }
    return Arrays.autoreleased(elements, cls: cls)
}
