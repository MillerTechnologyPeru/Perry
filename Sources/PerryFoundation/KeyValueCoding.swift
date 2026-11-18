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

    /// Whether the object's class has an accessor for the selector, once the
    /// class has had the chance to add it (+resolveInstanceMethod:, as
    /// dynamic properties' accessors are made).
    static func responds(_ object: id, _ selector: SEL) -> Bool {
        if ObjC.instanceMethod(ObjC.objectGetClass(object), selector) != nil { return true }
        guard ObjC.sendBool(object, ObjC.selector("respondsToSelector:"), UnsafeMutableRawPointer(mutating: selector)) else { return false }
        return ObjC.instanceMethod(ObjC.objectGetClass(object), selector) != nil
    }

    /// The getter's result, as an object.
    static func get(_ object: id, _ selector: SEL) -> id? {
        let send = ObjC.msgSend!
        switch types(object, selector)?.first ?? "@" {
        case "q", "Q":
            let value = darwinResult(unsafeBitCast(send, to: (@convention(c) (id, SEL) -> Int64.ObjCResultType).self)(object, selector),
                                     as: Int64.self)
            return Numbers.make(nil, types(object, selector)?.first == "Q" ? .unsigned(UInt64(bitPattern: value)) : .signed(value))
        case "l":
            return Numbers.make(nil, .signed(Int64(unsafeBitCast(send, to: (@convention(c) (id, SEL) -> Int).self)(object, selector))))
        case "L":
            return Numbers.make(nil, .unsigned(UInt64(unsafeBitCast(send, to: (@convention(c) (id, SEL) -> UInt).self)(object, selector))))
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
            let value = unsafeBitCast(send, to: (@convention(c) (id, SEL) -> Double.ObjCResultType).self)(object, selector)
            return Numbers.make(nil, .double(darwinResult(value, as: Double.self)))
        case "f":
            let value = unsafeBitCast(send, to: (@convention(c) (id, SEL) -> Float.ObjCResultType).self)(object, selector)
            return Numbers.make(nil, .double(Double(darwinResult(value, as: Float.self))))
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
        case "q", "Q":
            unsafeBitCast(send, to: (@convention(c) (id, SEL, Int64.ObjCType) -> Void).self)(object, selector, number.int64.objCArgument())
        case "l", "L":
            unsafeBitCast(send, to: (@convention(c) (id, SEL, Int) -> Void).self)(object, selector, Int(truncatingIfNeeded: number.int64))
        case "i", "I":
            unsafeBitCast(send, to: (@convention(c) (id, SEL, Int32) -> Void).self)(object, selector, Int32(truncatingIfNeeded: number.int64))
        case "s", "S":
            unsafeBitCast(send, to: (@convention(c) (id, SEL, Int16) -> Void).self)(object, selector, Int16(truncatingIfNeeded: number.int64))
        case "c", "C":
            unsafeBitCast(send, to: (@convention(c) (id, SEL, Int8) -> Void).self)(object, selector, Int8(truncatingIfNeeded: number.int64))
        case "B":
            unsafeBitCast(send, to: (@convention(c) (id, SEL, Bool) -> Void).self)(object, selector, number.int64 != 0)
        case "d":
            unsafeBitCast(send, to: (@convention(c) (id, SEL, Double.ObjCType) -> Void).self)(object, selector, number.double.objCArgument())
        case "f":
            unsafeBitCast(send, to: (@convention(c) (id, SEL, Float.ObjCType) -> Void).self)(object, selector,
                                                                                         Float(number.double).objCArgument())
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
        // A set's values of the key, as a set: a member with none adds nothing.
        if ObjC.isKind(object, of: Sets.setClass) {
            return Sets.autoreleased(Sets.elements(object).compactMap { value($0, key) })
        }
        // An ordered set's, as an ordered set, by the same rule.
        if ObjC.isKind(object, of: OrderedSets.setClass) {
            return OrderedSets.make(OrderedSets.setClass, OrderedSets.storage(object).members.compactMap { value($0, key) })
        }
        let capitalized = key.prefix(1).uppercased() + key.dropFirst()
        // get<Key>, <key>, is<Key>, then _<key>, as Foundation looks.
        for name in ["get" + capitalized, key, "is" + capitalized, "_" + key] {
            let selector = ObjC.selector(name)
            if responds(object, selector) { return get(object, selector) }
        }
        // Indexed accessors, countOf<Key> and objectIn<Key>AtIndex:, as an
        // array of what they give (Foundation's is a proxy that reads them
        // as it goes).
        if let elements = indexedElements(object, capitalized) { return Arrays.autoreleased(elements) }
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
        // set<Key>:, then _set<Key>:, as Foundation looks.
        let capitalized = key.prefix(1).uppercased() + key.dropFirst()
        for name in ["set" + capitalized + ":", "_set" + capitalized + ":"] {
            let selector = ObjC.selector(name)
            if responds(object, selector) { return set(object, selector, value) }
        }
        if let (storage, type) = instanceVariable(object, key) {
            set(storage, type: type, value)
            return
        }
        _ = ObjC.send(object, ObjC.selector("setValue:forUndefinedKey:"), value, Strings.autoreleased(key))
    }

    // MARK: Stored values

    /// The key's value as it is stored, as -storedValueForKey: reads it for
    /// archiving: private accessors first, then the instance variable, then
    /// the public accessors.
    static func storedValue(_ object: id, _ key: String) -> id? {
        let capitalized = key.prefix(1).uppercased() + key.dropFirst()
        for name in ["_get" + capitalized, "_" + key] {
            let selector = ObjC.selector(name)
            if responds(object, selector) { return get(object, selector) }
        }
        if let (storage, type) = instanceVariable(object, key) { return get(storage, type: type) }
        return value(object, key)
    }

    /// Sets the key's stored value, as -takeStoredValue:forKey: does for
    /// unarchiving: _set<Key>:, then the instance variable, then the public
    /// setter. A public setter may do more than store (Xcode's register
    /// changes with their project), which a value being restored mustn't.
    static func setStoredValue(_ object: id, _ key: String, _ value: id?) {
        let capitalized = key.prefix(1).uppercased() + key.dropFirst()
        let selector = ObjC.selector("_set" + capitalized + ":")
        if responds(object, selector) { return set(object, selector, value) }
        if let (storage, type) = instanceVariable(object, key) {
            set(storage, type: type, value)
            return
        }
        setValue(object, key, value)
    }

    // MARK: Instance variables

    /// The instance variable a key without accessors is kept in, as
    /// Foundation looks for one (_key, _isKey, key, isKey): its storage in
    /// the object and its type's first character.
    static func instanceVariable(_ object: id, _ key: String) -> (storage: UnsafeMutableRawPointer, type: UInt8)? {
        guard let cls = ObjC.objectGetClass(object), let find = ObjC.instanceVariable, let offset = ObjC.ivarOffset,
              let encoding = ObjC.ivarType, !key.isEmpty else { return nil }
        // A class that answers NO to +accessInstanceVariablesDirectly keeps
        // its instance variables to itself.
        let allows = ObjC.selector("accessInstanceVariablesDirectly")
        if ObjC.instanceMethod(ObjC.objectGetClass(UnsafeMutableRawPointer(cls)), allows) != nil {
            typealias Send = @convention(c) (UnsafeMutableRawPointer, SEL) -> Bool
            guard unsafeBitCast(ObjC.msgSend!, to: Send.self)(UnsafeMutableRawPointer(cls), allows) else { return nil }
        }
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

/// Structures passed to and returned from accessors as Darwin passes them,
/// which KVC wraps in NSValue. On arm64: up to four floats or doubles in d0
/// to d3, others up to 16 bytes in two general registers, larger ones
/// through memory. On armv7: arguments as words in r2, r3 and then on the
/// stack; results of up to 4 bytes in r0, larger ones through a pointer
/// passed in r0, before self.
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

    #if _pointerBitWidth(_32)
    /// The most words a structure argument may take.
    static let argumentWords = 16

    static func get(_ object: id, _ selector: SEL, type: String) -> id? {
        guard let size = TypeEncoding.size(of: type), let imp = ObjC.methodImplementation(ObjC.objectGetClass(object), selector)
        else { return nil }
        var bytes = [UInt8](repeating: 0, count: max(size, 4))
        #if arch(i386)
        // Floating point comes back on the x87 stack, structures of 1, 2, 4
        // or 8 bytes in eax:edx, and the rest through a pointer.
        if type.hasPrefix("d") {
            let value = unsafeBitCast(imp, to: (@convention(c) (id, SEL) -> Double).self)(object, selector)
            withUnsafeBytes(of: value) { value in bytes.withUnsafeMutableBytes { $0.copyMemory(from: value) } }
        } else if type.hasPrefix("f") {
            let value = unsafeBitCast(imp, to: (@convention(c) (id, SEL) -> Float).self)(object, selector)
            withUnsafeBytes(of: value) { value in bytes.withUnsafeMutableBytes { $0.copyMemory(from: value) } }
        } else if size <= 4 {
            let value = unsafeBitCast(imp, to: (@convention(c) (id, SEL) -> UInt32).self)(object, selector)
            withUnsafeBytes(of: value) { value in bytes.withUnsafeMutableBytes { $0.copyMemory(from: value) } }
        } else if size == 8 {
            let value = unsafeBitCast(imp, to: (@convention(c) (id, SEL) -> UInt64).self)(object, selector)
            withUnsafeBytes(of: value) { value in bytes.withUnsafeMutableBytes { $0.copyMemory(from: value) } }
        } else {
            guard size <= argumentWords * 4 else { return nil }
            let value = unsafeBitCast(imp, to: (@convention(c) (id, SEL) -> perry_words16).self)(object, selector)
            withUnsafeBytes(of: value) { value in
                bytes.withUnsafeMutableBytes { $0.copyMemory(from: UnsafeRawBufferPointer(rebasing: value[0..<size])) }
            }
        }
        #else
        if size <= 4 {
            var word = unsafeBitCast(imp, to: (@convention(c) (id, SEL) -> UInt32).self)(object, selector)
            withUnsafeBytes(of: &word) { word in bytes.withUnsafeMutableBytes { $0.copyMemory(from: word) } }
        } else {
            let getter = unsafeBitCast(imp, to: (@convention(c) (UnsafeMutableRawPointer, id, SEL) -> Void).self)
            bytes.withUnsafeMutableBytes { getter($0.baseAddress!, object, selector) }
        }
        #endif
        return bytes.prefix(size).withUnsafeBytes {
            ObjC.autorelease(Values.make(UnsafeMutableRawPointer(Values.valueClass), bytes: $0.baseAddress, type: type))
        }
    }

    static func set(_ object: id, _ selector: SEL, _ value: id?) {
        guard let storage = Values.storage(value), let imp = ObjC.methodImplementation(ObjC.objectGetClass(object), selector)
        else { return }
        guard storage.bytes.count <= argumentWords * 4 else {
            foundationFatal("-[\(ObjC.className(object)) \(String(cString: selector))]: a \(storage.bytes.count)-byte structure is too large for key-value coding")
        }
        var w = [UInt32](repeating: 0, count: argumentWords)
        storage.bytes.withUnsafeBytes { source in w.withUnsafeMutableBytes { $0.copyMemory(from: source) } }
        typealias Setter = @convention(c) (id, SEL, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32,
                                           UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32) -> Void
        unsafeBitCast(imp, to: Setter.self)(object, selector, w[0], w[1], w[2], w[3], w[4], w[5], w[6], w[7],
                                            w[8], w[9], w[10], w[11], w[12], w[13], w[14], w[15])
    }
    #else
    static func get(_ object: id, _ selector: SEL, type: String) -> id? {
        guard let size = TypeEncoding.size(of: type), let imp = ObjC.methodImplementation(ObjC.objectGetClass(object), selector)
        else { return nil }
        var indirect = [UInt8](repeating: 0, count: max(size, 1))
        var registers = [UInt64](repeating: 0, count: 6)
        #if arch(x86_64)
        // Over 16 bytes returns through a pointer; to 16, each eight bytes
        // come back in xmm registers if floating point, or else rax and rdx.
        var bytes: [UInt8]
        if size > 16 {
            perry_foundation_call_getter(object, selector, imp, &indirect, &registers)
            bytes = indirect
        } else {
            perry_foundation_call_getter(object, selector, imp, nil, &registers)
            let first = floatingMembers(type) != nil ? 2 : 0
            bytes = Array(withUnsafeBytes(of: (registers[first], registers[first + 1])) { Array($0) }.prefix(size))
        }
        #else
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
        #endif
        return bytes.withUnsafeBytes { ObjC.autorelease(Values.make(UnsafeMutableRawPointer(Values.valueClass), bytes: $0.baseAddress, type: type)) }
    }

    static func set(_ object: id, _ selector: SEL, _ value: id?) {
        guard let storage = Values.storage(value), let imp = ObjC.methodImplementation(ObjC.objectGetClass(object), selector)
        else { return }
        var bytes = storage.bytes
        var registers = [UInt64](repeating: 0, count: 6)
        #if arch(x86_64)
        if bytes.count > 16 {
            bytes.withUnsafeBytes { perry_foundation_call_setter_memory(object, selector, imp, $0.baseAddress, $0.count) }
        } else {
            let padded = bytes + [UInt8](repeating: 0, count: 16 - bytes.count)
            let first = floatingMembers(storage.type) != nil ? 2 : 0
            padded.withUnsafeBytes {
                registers[first] = $0.load(as: UInt64.self)
                registers[first + 1] = $0.load(fromByteOffset: 8, as: UInt64.self)
            }
            perry_foundation_call_setter(object, selector, imp, registers)
        }
        #else
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
        #endif
    }    #endif
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

    /// The key's collection, to change in place: the mutable collection
    /// the object holds, else a mutable one set for the key first. Changes
    /// reach the object; they aren't observed as Foundation's proxy has them.
    @ObjCMethod("mutableArrayValueForKey:")
    func mutableArrayValue(forKey key: String) -> UnsafeMutableRawPointer? { KeyValueCoding.mutableCollection(objcObject, key, "NSMutableArray") }

    @ObjCMethod("mutableSetValueForKey:")
    func mutableSetValue(forKey key: String) -> UnsafeMutableRawPointer? { KeyValueCoding.mutableCollection(objcObject, key, "NSMutableSet") }

    @ObjCMethod("mutableOrderedSetValueForKey:")
    func mutableOrderedSetValue(forKey key: String) -> UnsafeMutableRawPointer? {
        KeyValueCoding.mutableCollection(objcObject, key, "NSMutableOrderedSet")
    }

    /// Asks the class's validate<Key>:error:, if it has one, whether the
    /// value may be set; any value is valid otherwise.
    @ObjCMethod("validateValue:forKey:error:")
    func validateValue(_ value: UnsafeMutablePointer<id?>?, forKey key: String, error: UnsafeMutablePointer<id?>?) -> Bool {
        guard let first = key.first else { return true }
        let selector = ObjC.selector("validate" + first.uppercased() + key.dropFirst() + ":error:")
        guard KeyValueCoding.responds(objcObject, selector) else { return true }
        typealias Validate = @convention(c) (id, SEL, UnsafeMutablePointer<id?>?, UnsafeMutablePointer<id?>?) -> Bool
        return unsafeBitCast(ObjC.msgSend!, to: Validate.self)(objcObject, selector, value, error)
    }

    /// What a key without accessors does: raise, as Foundation's, unless a
    /// class overrides these.
    @ObjCMethod("valueForUndefinedKey:")
    func value(forUndefinedKey key: String) -> ObjCObject? {
        // JSON's null, asked for a key: Darwin raises, which a program that
        // reads a configuration this way catches. An exception cannot be
        // caught here, so it is nothing, as for a message to nil.
        if ObjC.className(objcObject) == "NSNull" { return nil }
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

extension KeyValueCoding {
    /// The elements indexed accessors give, if the object has them.
    static func indexedElements(_ object: id, _ capitalized: String) -> [id]? {
        let count = ObjC.selector("countOf" + capitalized), element = ObjC.selector("objectIn" + capitalized + "AtIndex:")
        guard responds(object, count), responds(object, element) else { return nil }
        return (0..<ObjC.sendUInt(object, count)).compactMap { ObjC.sendIndex(object, element, $0) }
    }

    static func mutableCollection(_ object: id, _ key: String, _ className: String) -> id? {
        let capitalized = key.prefix(1).uppercased() + key.dropFirst()
        // A class with the mutating indexed accessors changes through them.
        if className == "NSMutableArray", responds(object, ObjC.selector("insertObject:in" + capitalized + "AtIndex:")),
           responds(object, ObjC.selector("removeObjectFrom" + capitalized + "AtIndex:")) {
            return KeyValueArrayProxies.make(object, capitalized)
        }
        let keyObject = Strings.autoreleased(key)
        guard let cls = ObjC.getClass(className) else { return nil }
        let current = ObjC.send(object, ObjC.selector("valueForKey:"), keyObject)
        if let current, ObjC.isKind(current, of: cls) { return current }
        let made: id?
        if let current {
            made = ObjC.send(current, ObjC.selector("mutableCopy")).flatMap { ObjC.autorelease($0) }
        } else {
            made = ObjC.send(ObjC.send(UnsafeMutableRawPointer(cls), ObjC.selector("alloc")), ObjC.selector("init")).flatMap { ObjC.autorelease($0) }
        }
        if let made { ObjC.send(object, ObjC.selector("setValue:forKey:"), made, keyObject) }
        return made
    }
}

// mutableArrayValueForKey:'s array for a class with indexed accessors: an
// object that answers an NSMutableArray's messages by the accessors,
// countOf<Key>, objectIn<Key>AtIndex:, insertObject:in<Key>AtIndex:,
// removeObjectFrom<Key>AtIndex: and replaceObjectIn<Key>AtIndex:withObject:.

final class KeyValueArrayProxyState {
    let object: id
    let capitalized: String
    /// What fast enumeration goes through, taken when it starts.
    var snapshot: id?

    init(_ object: id, _ capitalized: String) {
        self.object = ObjC.retain(object)!
        self.capitalized = capitalized
    }

    deinit {
        ObjC.release(object)
        if let snapshot { ObjC.release(snapshot) }
    }

    var count: UInt { ObjC.sendUInt(object, ObjC.selector("countOf" + capitalized)) }
    func element(_ index: UInt) -> id? { ObjC.sendIndex(object, ObjC.selector("objectIn" + capitalized + "AtIndex:"), index) }
    var elements: [id] { (0..<count).compactMap(element) }

    func insert(_ value: id?, at index: UInt) {
        typealias Insert = @convention(c) (id?, SEL, id?, UInt) -> Void
        unsafeBitCast(ObjC.msgSend!, to: Insert.self)(object, ObjC.selector("insertObject:in" + capitalized + "AtIndex:"), value, index)
    }

    func remove(at index: UInt) {
        typealias Remove = @convention(c) (id?, SEL, UInt) -> Void
        unsafeBitCast(ObjC.msgSend!, to: Remove.self)(object, ObjC.selector("removeObjectFrom" + capitalized + "AtIndex:"), index)
    }

    func replace(at index: UInt, with value: id?) {
        let selector = ObjC.selector("replaceObjectIn" + capitalized + "AtIndex:withObject:")
        if KeyValueCoding.responds(object, selector) {
            typealias Replace = @convention(c) (id?, SEL, UInt, id?) -> Void
            unsafeBitCast(ObjC.msgSend!, to: Replace.self)(object, selector, index, value)
        } else {
            remove(at: index)
            insert(value, at: index)
        }
    }
}

enum KeyValueArrayProxies {
    nonisolated(unsafe) static var proxyClass: Class!

    static func make(_ object: id, _ capitalized: String) -> id? {
        guard let proxy = Storage.allocate(UnsafeMutableRawPointer(proxyClass)) else { return nil }
        Storage.set(proxy, KeyValueArrayProxyState(object, capitalized))
        return ObjC.autorelease(proxy)
    }
}

@ObjCClass("NSKeyValueIndexedMutableArray")
public final class NSKeyValueIndexedMutableArray: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        KeyValueArrayProxies.proxyClass = cls.storage
    }

    private var proxy: KeyValueArrayProxyState? { Storage.get(objcObject, as: KeyValueArrayProxyState.self) }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: KeyValueArrayProxies.proxyClass)
    }

    @ObjCMethod("count") func count() -> UInt { proxy?.count ?? 0 }
    @ObjCMethod("objectAtIndex:") func object(at index: UInt) -> UnsafeMutableRawPointer? { proxy?.element(index) }
    @ObjCMethod("firstObject") func firstObject() -> UnsafeMutableRawPointer? { count() > 0 ? proxy?.element(0) : nil }
    @ObjCMethod("lastObject") func lastObject() -> UnsafeMutableRawPointer? { count() > 0 ? proxy?.element(count() - 1) : nil }

    @ObjCMethod("indexOfObject:")
    func index(of value: UnsafeMutableRawPointer?) -> UInt {
        guard let proxy, let value else { return UInt.max }
        let elements = proxy.elements
        return elements.firstIndex { ObjC.sendBool($0, Selectors.isEqual, value) }.map(UInt.init) ?? UInt.max   // NSNotFound
    }

    @ObjCMethod("containsObject:") func contains(_ value: UnsafeMutableRawPointer?) -> Bool { index(of: value) != UInt.max }

    @ObjCMethod("insertObject:atIndex:") func insert(_ value: UnsafeMutableRawPointer?, at index: UInt) { proxy?.insert(value, at: index) }
    @ObjCMethod("addObject:") func add(_ value: UnsafeMutableRawPointer?) { proxy?.insert(value, at: count()) }

    @ObjCMethod("addObjectsFromArray:")
    func add(contentsOf array: UnsafeMutableRawPointer?) {
        for value in Arrays.elements(array) { proxy?.insert(value, at: count()) }
    }

    @ObjCMethod("removeObjectAtIndex:") func remove(at index: UInt) { proxy?.remove(at: index) }
    @ObjCMethod("removeLastObject") func removeLast() { if count() > 0 { proxy?.remove(at: count() - 1) } }

    @ObjCMethod("removeObject:")
    func remove(_ value: UnsafeMutableRawPointer?) {
        guard let proxy, let value else { return }
        var index = proxy.count
        while index > 0 {
            index -= 1
            if let element = proxy.element(index), ObjC.sendBool(element, Selectors.isEqual, value) { proxy.remove(at: index) }
        }
    }

    @ObjCMethod("removeAllObjects")
    func removeAll() {
        guard let proxy else { return }
        while proxy.count > 0 { proxy.remove(at: proxy.count - 1) }
    }

    @ObjCMethod("replaceObjectAtIndex:withObject:")
    func replace(at index: UInt, with value: UnsafeMutableRawPointer?) { proxy?.replace(at: index, with: value) }

    @ObjCMethod("setArray:")
    func setArray(_ array: UnsafeMutableRawPointer?) {
        removeAll()
        add(contentsOf: array)
    }

    /// An array of the elements as they are now.
    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { Arrays.make(proxy?.elements ?? []) }

    @ObjCMethod("mutableCopyWithZone:")
    func mutableCopy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        ObjC.send(Arrays.autoreleased(proxy?.elements ?? []), ObjC.selector("mutableCopy"))
    }

    @ObjCMethod("objectEnumerator")
    func objectEnumerator() -> UnsafeMutableRawPointer? {
        ObjC.send(Arrays.autoreleased(proxy?.elements ?? []), ObjC.selector("objectEnumerator"))
    }

    @ObjCMethod("description")
    func description() -> UnsafeMutableRawPointer? { ObjC.send(Arrays.autoreleased(proxy?.elements ?? []), ObjC.selector("description")) }

    /// for-in: over the elements as they are when it starts.
    @ObjCMethod("countByEnumeratingWithState:objects:count:")
    func enumerate(state: UnsafeMutablePointer<UInt>?, objects: UnsafeMutablePointer<id?>?, count: UInt) -> UInt {
        guard let proxy, let state else { return 0 }
        if state.pointee == 0 {
            if let old = proxy.snapshot { ObjC.release(old) }
            proxy.snapshot = Arrays.make(proxy.elements)
        }
        typealias Enumerate = @convention(c) (id?, SEL, UnsafeMutablePointer<UInt>?, UnsafeMutablePointer<id?>?, UInt) -> UInt
        return unsafeBitCast(ObjC.msgSend!, to: Enumerate.self)(proxy.snapshot, ObjC.selector("countByEnumeratingWithState:objects:count:"),
                                                                 state, objects, count)
    }
}

// MARK: - Bindings of a key in a class

/// A key of a class, and how its values are got and set: what
/// +keyValueBindingForKey:typeMask: answered in Foundation before Mac OS X
/// 10.5 (Xcode 3's project archiving keeps one for each archived key).
final class KeyValueBindingState {
    let key: String
    let targetClass: Class

    init(key: String, targetClass: Class) {
        self.key = key
        self.targetClass = targetClass
    }

    /// Whether the key's value is a number or structure rather than an
    /// object: by its getter's result, else by its instance variable.
    var isScalar: Bool {
        let capitalized = key.prefix(1).uppercased() + key.dropFirst()
        for name in ["get" + capitalized, key, "is" + capitalized, "_" + key] {
            if let method = ObjC.instanceMethod(targetClass, ObjC.selector(name)), let encoding = ObjC.methodTypes(method) {
                let type = String(cString: encoding).first { !"rnNoORV".contains($0) }
                return type != "@" && type != "#"
            }
        }
        guard let find = ObjC.instanceVariable, let encoding = ObjC.ivarType else { return false }
        for name in ["_" + key, "_is" + capitalized, key, "is" + capitalized] {
            guard let ivar = name.withCString({ find(targetClass, $0) }) else { continue }
            let type = encoding(ivar).map { UInt8(bitPattern: $0.pointee) } ?? UInt8(ascii: "@")
            return type != UInt8(ascii: "@") && type != UInt8(ascii: "#")
        }
        return false
    }
}

enum KeyValueBindings {
    nonisolated(unsafe) static var bindingClass: Class!

    static func make(_ cls: Class, _ key: String) -> id? {
        guard let binding = Storage.allocate(UnsafeMutableRawPointer(bindingClass)) else { return nil }
        Storage.set(binding, KeyValueBindingState(key: key, targetClass: cls))
        return ObjC.autorelease(binding)
    }
}

@ObjCClass("NSKeyValueBinding")
public final class NSKeyValueBinding: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        KeyValueBindings.bindingClass = cls.storage
    }

    private var state: KeyValueBindingState? { Storage.get(objcObject, as: KeyValueBindingState.self) }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: KeyValueBindings.bindingClass)
    }

    @ObjCMethod("key") func key() -> String { state?.key ?? "" }
    @ObjCMethod("targetClass") func targetClass() -> UnsafeMutableRawPointer? { state.map { UnsafeMutableRawPointer($0.targetClass) } }
    @ObjCMethod("isScalarProperty") func isScalarProperty() -> Bool { state?.isScalar ?? false }

    /// The value as stored, as archiving reads it: not through
    /// -valueForKey:, which a class may take for something else.
    @ObjCMethod("getValueFromObject:")
    func getValue(from object: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        guard let object, let state else { return nil }
        return KeyValueCoding.storedValue(object, state.key)
    }

    @ObjCMethod("setValue:inObject:")
    func setValue(_ value: UnsafeMutableRawPointer?, in object: UnsafeMutableRawPointer?) {
        guard let object, let state else { return }
        KeyValueCoding.setStoredValue(object, state.key, value)
    }
}

@ObjCCategory("KeyValueBindings")
extension NSObject {
    /// The binding of `key` in the class; the type mask is not needed here.
    @ObjCClassMethod("keyValueBindingForKey:typeMask:")
    static func keyValueBinding(_ cls: ObjCClass, forKey key: String?, typeMask: UInt) -> UnsafeMutableRawPointer? {
        guard let key, !key.isEmpty else { return nil }
        return KeyValueBindings.make(cls.storage, key)
    }

    /// The binding of `key` in the object's class.
    @ObjCMethod("keyValueBindingForKey:typeMask:")
    func keyValueBinding(forKey key: String?, typeMask: UInt) -> UnsafeMutableRawPointer? {
        guard let key, !key.isEmpty, let cls = ObjC.objectGetClass(objcObject) else { return nil }
        return KeyValueBindings.make(cls, key)
    }
}
