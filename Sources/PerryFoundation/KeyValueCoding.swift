import CPerryFoundation
import PerryObjCInterop

// Key-value coding: -valueForKey: and -setValue:forKey: through the
// accessor methods a class has, with scalars wrapped in NSNumber as the
// methods' type encodings say; dictionaries by key, arrays element-wise.

enum KeyValueCoding {
    /// A method's type encoding with the offsets removed: "q@:" for a getter
    /// returning long long, "v@:q" for its setter.
    static func types(_ object: id, _ selector: SEL) -> [Character]? {
        guard let method = ObjC.instanceMethod(ObjC.objectGetClass(object), selector),
              let encoding = ObjC.methodTypes(method) else { return nil }
        // Qualifiers (r, n, N, o, O, R, V) prefix a type; offsets are digits.
        return String(cString: encoding).filter { !$0.isNumber && !"rnNoORV".contains($0) }.map { $0 }
    }

    static func responds(_ object: id, _ selector: SEL) -> Bool {
        ObjC.instanceMethod(ObjC.objectGetClass(object), selector) != nil
    }

    /// The getter's result, as an object.
    static func get(_ object: id, _ selector: SEL) -> id? {
        let send = ObjC.msgSend!
        switch types(object, selector)?.first ?? "@" {
        case "q", "l", "Q", "L":
            let value = unsafeBitCast(send, to: (@convention(c) (id, SEL) -> Int64).self)(object, selector)
            return Numbers.make(nil, types(object, selector)?.first == "Q" || types(object, selector)?.first == "L"
                                ? .unsigned(UInt64(bitPattern: value)) : .signed(value))
        case "i":
            return Numbers.make(nil, .signed(Int64(unsafeBitCast(send, to: (@convention(c) (id, SEL) -> Int32).self)(object, selector))))
        case "I":
            return Numbers.make(nil, .unsigned(UInt64(unsafeBitCast(send, to: (@convention(c) (id, SEL) -> UInt32).self)(object, selector))))
        case "s":
            return Numbers.make(nil, .signed(Int64(unsafeBitCast(send, to: (@convention(c) (id, SEL) -> Int16).self)(object, selector))))
        case "S":
            return Numbers.make(nil, .unsigned(UInt64(unsafeBitCast(send, to: (@convention(c) (id, SEL) -> UInt16).self)(object, selector))))
        case "c":
            return Numbers.make(nil, .signed(Int64(unsafeBitCast(send, to: (@convention(c) (id, SEL) -> Int8).self)(object, selector))))
        case "C":
            return Numbers.make(nil, .unsigned(UInt64(unsafeBitCast(send, to: (@convention(c) (id, SEL) -> UInt8).self)(object, selector))))
        case "B":
            return perry_foundation_boolean(unsafeBitCast(send, to: (@convention(c) (id, SEL) -> Bool).self)(object, selector) ? 1 : 0)
        case "d":
            return Numbers.make(nil, .double(unsafeBitCast(send, to: (@convention(c) (id, SEL) -> Double).self)(object, selector)))
        case "f":
            return Numbers.make(nil, .double(Double(unsafeBitCast(send, to: (@convention(c) (id, SEL) -> Float).self)(object, selector))))
        case "v":
            return nil
        case "{":
            return Structures.encodedTypes(object, selector).first.flatMap { Structures.get(object, selector, type: $0) }
        default:
            return unsafeBitCast(send, to: (@convention(c) (id, SEL) -> id?).self)(object, selector)
        }
    }

    static func set(_ object: id, _ selector: SEL, _ value: id?) {
        let send = ObjC.msgSend!
        let number = Numbers.storage(value)
        switch types(object, selector).flatMap({ $0.count > 3 ? $0[3] : nil }) ?? "@" {
        case "q", "l", "Q", "L":
            unsafeBitCast(send, to: (@convention(c) (id, SEL, Int64) -> Void).self)(object, selector, number.int64)
        case "i", "I":
            unsafeBitCast(send, to: (@convention(c) (id, SEL, Int32) -> Void).self)(object, selector, Int32(truncatingIfNeeded: number.int64))
        case "s", "S":
            unsafeBitCast(send, to: (@convention(c) (id, SEL, Int16) -> Void).self)(object, selector, Int16(truncatingIfNeeded: number.int64))
        case "c", "C":
            unsafeBitCast(send, to: (@convention(c) (id, SEL, Int8) -> Void).self)(object, selector, Int8(truncatingIfNeeded: number.int64))
        case "B":
            unsafeBitCast(send, to: (@convention(c) (id, SEL, Bool) -> Void).self)(object, selector, number.int64 != 0)
        case "d":
            unsafeBitCast(send, to: (@convention(c) (id, SEL, Double) -> Void).self)(object, selector, number.double)
        case "f":
            unsafeBitCast(send, to: (@convention(c) (id, SEL, Float) -> Void).self)(object, selector, Float(number.double))
        case "{":
            Structures.set(object, selector, value)
        default:
            unsafeBitCast(send, to: (@convention(c) (id, SEL, id?) -> Void).self)(object, selector, value)
        }
    }

    static func value(_ object: id, _ key: String) -> id? {
        if ObjC.isKind(object, of: Dictionaries.dictionaryClass) {
            return Dictionaries.value(object, for: Strings.autoreleased(key))
        }
        if ObjC.isKind(object, of: Arrays.arrayClass) {
            return Arrays.autoreleased(Arrays.elements(object).map { value($0, key) ?? Nulls.null })
        }
        let capitalized = key.prefix(1).uppercased() + key.dropFirst()
        for name in [key, "is" + capitalized, "get" + capitalized] {
            let selector = ObjC.selector(name)
            if responds(object, selector) { return get(object, selector) }
        }
        if let (storage, type) = instanceVariable(object, key) { return get(storage, type: type) }
        // As Foundation does: the object's -valueForUndefinedKey:, which
        // raises unless a class overrides it.
        return ObjC.send(object, ObjC.selector("valueForUndefinedKey:"), Strings.autoreleased(key))
    }

    static func setValue(_ object: id, _ key: String, _ value: id?) {
        if ObjC.isKind(object, of: Dictionaries.mutableClass) {
            let keyObject = Strings.autoreleased(key)
            if let value { _ = ObjC.send(object, ObjC.selector("setObject:forKey:"), value, keyObject) }
            else { _ = ObjC.send(object, ObjC.selector("removeObjectForKey:"), keyObject) }
            return
        }
        let selector = ObjC.selector("set" + key.prefix(1).uppercased() + key.dropFirst() + ":")
        guard responds(object, selector) else {
            if let (storage, type) = instanceVariable(object, key) {
                set(storage, type: type, value)
                return
            }
            _ = ObjC.send(object, ObjC.selector("setValue:forUndefinedKey:"), value, Strings.autoreleased(key))
            return
        }
        set(object, selector, value)
    }

    // MARK: Instance variables

    /// The instance variable a key without accessors is kept in, as
    /// Foundation looks for one (_key, _isKey, key, isKey): its storage in
    /// the object and its type's first character.
    static func instanceVariable(_ object: id, _ key: String) -> (storage: UnsafeMutableRawPointer, type: UInt8)? {
        guard let cls = ObjC.objectGetClass(object), let find = ObjC.instanceVariable, let offset = ObjC.ivarOffset,
              let encoding = ObjC.ivarType else { return nil }
        let capitalized = key.prefix(1).uppercased() + key.dropFirst()
        for name in ["_" + key, "_is" + capitalized, key, "is" + capitalized] {
            guard let ivar = name.withCString({ find(cls, $0) }) else { continue }
            let type = encoding(ivar).map { UInt8(bitPattern: $0.pointee) } ?? UInt8(ascii: "@")
            return (object + offset(ivar), type)
        }
        return nil
    }

    /// An instance variable's value, as an object; nil for types that
    /// aren't objects or numbers.
    static func get(_ storage: UnsafeMutableRawPointer, type: UInt8) -> id? {
        switch Character(Unicode.Scalar(type)) {
        case "@", "#": return storage.load(as: id?.self)
        case "q", "l": return Numbers.make(nil, .signed(storage.load(as: Int64.self)))
        case "Q", "L": return Numbers.make(nil, .unsigned(storage.load(as: UInt64.self)))
        case "i": return Numbers.make(nil, .signed(Int64(storage.load(as: Int32.self))))
        case "I": return Numbers.make(nil, .unsigned(UInt64(storage.load(as: UInt32.self))))
        case "s": return Numbers.make(nil, .signed(Int64(storage.load(as: Int16.self))))
        case "S": return Numbers.make(nil, .unsigned(UInt64(storage.load(as: UInt16.self))))
        case "c": return Numbers.make(nil, .signed(Int64(storage.load(as: Int8.self))))
        case "C": return Numbers.make(nil, .unsigned(UInt64(storage.load(as: UInt8.self))))
        case "B": return perry_foundation_boolean(storage.load(as: Bool.self) ? 1 : 0)
        case "d": return Numbers.make(nil, .double(storage.load(as: Double.self)))
        case "f": return Numbers.make(nil, .double(Double(storage.load(as: Float.self))))
        default: return nil
        }
    }

    /// Sets an instance variable: an object is retained and the one before
    /// released, a number is converted to the variable's type.
    static func set(_ storage: UnsafeMutableRawPointer, type: UInt8, _ value: id?) {
        let number = Numbers.storage(value)
        switch Character(Unicode.Scalar(type)) {
        case "@", "#":
            let old = storage.load(as: id?.self)
            storage.storeBytes(of: value.map { ObjC.retain($0) } ?? nil, as: id?.self)
            if let old { ObjC.release(old) }
        case "q", "l", "Q", "L": storage.storeBytes(of: number.int64, as: Int64.self)
        case "i", "I": storage.storeBytes(of: Int32(truncatingIfNeeded: number.int64), as: Int32.self)
        case "s", "S": storage.storeBytes(of: Int16(truncatingIfNeeded: number.int64), as: Int16.self)
        case "c", "C": storage.storeBytes(of: Int8(truncatingIfNeeded: number.int64), as: Int8.self)
        case "B": storage.storeBytes(of: number.int64 != 0, as: Bool.self)
        case "d": storage.storeBytes(of: number.double, as: Double.self)
        case "f": storage.storeBytes(of: Float(number.double), as: Float.self)
        default: break
        }
    }
}

/// Structures passed to and returned from accessors as arm64 passes them:
/// up to four floats or doubles in d0 to d3, others up to 16 bytes in two
/// general registers, larger ones through memory. KVC wraps them in NSValue.
enum Structures {
    /// A method's types, whole: "{_NSRange=QQ}", "@", ":".
    static func encodedTypes(_ object: id, _ selector: SEL) -> [String] {
        guard let method = ObjC.instanceMethod(ObjC.objectGetClass(object), selector),
              let encoding = ObjC.methodTypes(method) else { return [] }
        let characters = Array(String(cString: encoding))
        var types: [String] = []
        var index = 0
        while index < characters.count {
            while index < characters.count, "rnNoORV".contains(characters[index]) { index += 1 }
            let start = index
            var depth = 0
            repeat {
                guard index < characters.count else { break }
                switch characters[index] {
                case "{", "(", "[": depth += 1
                case "}", ")", "]": depth -= 1
                default: break
                }
                index += 1
            } while depth > 0 || (index < characters.count && characters[index - 1] == "^")
            types.append(String(characters[start..<index]))
            while index < characters.count, characters[index].isNumber { index += 1 }
        }
        return types
    }

    /// The element type and count if the structure is a homogeneous
    /// floating-point aggregate.
    static func floatingMembers(_ type: String) -> (Character, Int)? {
        var members: [Character] = []
        var inName = false
        for character in type {
            switch character {
            case "{": inName = true
            case "=": inName = false
            case "}": break
            default: if !inName { members.append(character) }
            }
        }
        guard let first = members.first, first == "d" || first == "f", members.count <= 4,
              members.allSatisfy({ $0 == first }) else { return nil }
        return (first, members.count)
    }

    static func get(_ object: id, _ selector: SEL, type: String) -> id? {
        guard let size = TypeEncoding.size(of: type), let imp = ObjC.methodImplementation(ObjC.objectGetClass(object), selector)
        else { return nil }
        var indirect = [UInt8](repeating: 0, count: max(size, 1))
        var registers = [UInt64](repeating: 0, count: 6)
        perry_foundation_call_getter(object, selector, imp, &indirect, &registers)
        var bytes: [UInt8]
        if let (member, count) = floatingMembers(type) {
            bytes = (0..<count).flatMap { index -> [UInt8] in
                let word = registers[2 + index]
                return member == "d" ? withUnsafeBytes(of: word) { Array($0) } : withUnsafeBytes(of: UInt32(truncatingIfNeeded: word)) { Array($0) }
            }
        } else if size <= 16 {
            bytes = Array(withUnsafeBytes(of: (registers[0], registers[1])) { Array($0) }.prefix(size))
        } else {
            bytes = indirect
        }
        return bytes.withUnsafeBytes { ObjC.autorelease(Values.make(UnsafeMutableRawPointer(Values.valueClass), bytes: $0.baseAddress, type: type)) }
    }

    static func set(_ object: id, _ selector: SEL, _ value: id?) {
        guard let storage = Values.storage(value), let imp = ObjC.methodImplementation(ObjC.objectGetClass(object), selector)
        else { return }
        var bytes = storage.bytes
        var registers = [UInt64](repeating: 0, count: 6)
        if let (member, count) = floatingMembers(storage.type) {
            let width = member == "d" ? 8 : 4
            for index in 0..<count where (index + 1) * width <= bytes.count {
                var word: UInt64 = 0
                withUnsafeMutableBytes(of: &word) { $0.copyMemory(from: UnsafeRawBufferPointer(rebasing: bytes.withUnsafeBytes { $0 }[index * width..<(index + 1) * width])) }
                registers[2 + index] = word
            }
            perry_foundation_call_setter(object, selector, imp, registers)
        } else if bytes.count <= 16 {
            var padded = bytes + [UInt8](repeating: 0, count: 16 - bytes.count)
            padded.withUnsafeBytes { registers[0] = $0.load(as: UInt64.self); registers[1] = $0.load(fromByteOffset: 8, as: UInt64.self) }
            perry_foundation_call_setter(object, selector, imp, registers)
        } else {
            bytes.withUnsafeMutableBytes { buffer in
                registers[0] = UInt64(UInt(bitPattern: buffer.baseAddress))
                perry_foundation_call_setter(object, selector, imp, registers)
            }
        }
    }
}

/// Key-value coding's collection operators: @count, @sum, @avg, @max,
/// @min, @unionOfObjects and @distinctUnionOfObjects, over arrays and sets.
enum CollectionOperators {
    static func apply(_ name: String, to collection: id, path: String) -> id? {
        let members = ObjC.isKind(collection, of: Sets.setClass) ? Sets.elements(collection) : Arrays.elements(collection)
        if name == "@count" { return Numbers.make(nil, .signed(Int64(members.count))) }
        let values = members.compactMap { member -> id? in
            let value = path.isEmpty ? member : ObjC.send(member, ObjC.selector("valueForKeyPath:"), Strings.autoreleased(path))
            return value == Nulls.null ? nil : value
        }
        switch name {
        case "@sum", "@avg":
            let numbers = values.map { Numbers.storage($0).double }
            let total = numbers.reduce(0, +)
            let result = name == "@sum" ? total : (numbers.isEmpty ? 0 : total / Double(numbers.count))
            if result == result.rounded(), abs(result) < 9e18 { return Numbers.make(nil, .signed(Int64(result))) }
            return Numbers.make(nil, .double(result))
        case "@max", "@min":
            let compare = ObjC.selector("compare:")
            return values.reduce(nil as id?) { best, value in
                guard let best else { return value }
                let order = ObjC.sendInt(value, compare, best)
                return (name == "@max" ? order > 0 : order < 0) ? value : best
            }
        case "@unionOfObjects":
            return Arrays.autoreleased(values)
        case "@distinctUnionOfObjects":
            var distinct: [id] = []
            for value in values where !distinct.contains(where: { ObjC.sendBool($0, Selectors.isEqual, value) }) {
                distinct.append(value)
            }
            return Arrays.autoreleased(distinct)
        default:
            foundationFatal("[<\(ObjC.className(collection)) \(collection)> valueForKeyPath:]: this class does not implement the \(name.dropFirst()) operation.")
        }
    }
}

@ObjCCategory("KeyValueCoding")
extension NSObject {
    @ObjCMethod("valueForKey:")
    func keyValue(forKey key: String) -> ObjCObject? { KeyValueCoding.value(objcObject, key).map(ObjCObject.init) }

    @ObjCMethod("setValue:forKey:")
    func setKeyValue(_ value: ObjCObject?, forKey key: String) { KeyValueCoding.setValue(objcObject, key, value?.objcObject) }

    /// What a key without accessors does: raise, as Foundation's, unless a
    /// class overrides these.
    @ObjCMethod("valueForUndefinedKey:")
    func value(forUndefinedKey key: String) -> ObjCObject? {
        foundationFatal("[<\(ObjC.className(objcObject)) \(objcObject)> valueForUndefinedKey:]: this class is not key value coding-compliant for the key \(key).")
    }

    @ObjCMethod("setValue:forUndefinedKey:")
    func setValue(_ value: ObjCObject?, forUndefinedKey key: String) {
        foundationFatal("[<\(ObjC.className(objcObject)) \(objcObject)> setValue:forUndefinedKey:]: this class is not key value coding-compliant for the key \(key).")
    }

    /// Each key in turn, by -valueForKey:, so classes' own versions apply.
    /// A key starting with @ is a collection operator, applied to the
    /// collection so far with the rest of the path.
    @ObjCMethod("valueForKeyPath:")
    func keyValue(forKeyPath path: String) -> ObjCObject? {
        var current: id? = objcObject
        var keys = path.split(separator: ".", omittingEmptySubsequences: false).map(String.init)[...]
        while let key = keys.popFirst() {
            guard let object = current else { return nil }
            if key.hasPrefix("@") {
                return CollectionOperators.apply(key, to: object, path: keys.joined(separator: ".")).map(ObjCObject.init)
            }
            current = ObjC.send(object, ObjC.selector("valueForKey:"), Strings.autoreleased(key))
        }
        return current.map(ObjCObject.init)
    }

    /// Each entry set by -setValue:forKey:, NSNull as nil.
    @ObjCMethod("setValuesForKeysWithDictionary:")
    func setKeyValues(_ dictionary: ObjCObject?) {
        for (key, value) in Dictionaries.entries(dictionary?.id) {
            _ = ObjC.send(objcObject, ObjC.selector("setValue:forKey:"), value == Nulls.null ? nil : value, key)
        }
    }

    /// Each key's -valueForKey:, nil as NSNull.
    @ObjCMethod("dictionaryWithValuesForKeys:")
    func keyValues(forKeys keys: ObjCObject?) -> ObjCObject {
        let entries = Arrays.elements(keys?.id).map { key -> (key: id, value: id) in
            (key, ObjC.send(objcObject, ObjC.selector("valueForKey:"), key) ?? Nulls.null)
        }
        return ObjCObject(Dictionaries.autoreleased(entries))
    }

    /// The path's last key set, by -setValue:forKey:, on the object the
    /// keys before it reach, by -valueForKey:; nothing if one is nil.
    @ObjCMethod("setValue:forKeyPath:")
    func setKeyValue(_ value: ObjCObject?, forKeyPath path: String) {
        var keys = path.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let last = keys.removeLast()
        var current: id? = objcObject
        for key in keys {
            guard let object = current else { return }
            current = ObjC.send(object, ObjC.selector("valueForKey:"), Strings.autoreleased(key))
        }
        guard let target = current else { return }
        _ = ObjC.send(target, ObjC.selector("setValue:forKey:"), value?.objcObject, Strings.autoreleased(last))
    }
}

/// Sorting by descriptors.
@ObjCCategory("SortDescriptors")
extension NSArray {
    /// A stable sort by each descriptor in turn.
    @ObjCMethod("sortedArrayUsingDescriptors:")
    func sorted(usingDescriptors descriptors: ObjCObject?) -> ObjCObject {
        let keys = descriptors.map { Arrays.elements($0.objcObject) } ?? []
        let compare = ObjC.selector("compareObject:toObject:")
        let sorted = Arrays.elements(objcObject).enumerated().sorted { a, b in
            for descriptor in keys {
                let order = unsafeBitCast(ObjC.msgSend, to: (@convention(c) (id, SEL, id, id) -> Int).self)(
                    descriptor, compare, a.element, b.element)
                if order != 0 { return order < 0 }
            }
            return a.offset < b.offset
        }.map(\.element)
        return ObjCObject(Arrays.autoreleased(sorted))
    }
}
