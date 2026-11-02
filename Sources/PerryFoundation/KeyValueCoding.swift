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
        foundationFatal("[<\(ObjC.className(object)) \(object)> valueForUndefinedKey:]: this class is not key value coding-compliant for the key \(key).")
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
            foundationFatal("[<\(ObjC.className(object)) \(object)> setValue:forUndefinedKey:]: this class is not key value coding-compliant for the key \(key).")
        }
        set(object, selector, value)
    }
}

@ObjCCategory("KeyValueCoding")
extension NSObject {
    @ObjCMethod("valueForKey:")
    func keyValue(forKey key: String) -> ObjCObject? { KeyValueCoding.value(objcObject, key).map(ObjCObject.init) }

    @ObjCMethod("setValue:forKey:")
    func setKeyValue(_ value: ObjCObject?, forKey key: String) { KeyValueCoding.setValue(objcObject, key, value?.objcObject) }

    /// Each key in turn, by -valueForKey:, so classes' own versions apply.
    @ObjCMethod("valueForKeyPath:")
    func keyValue(forKeyPath path: String) -> ObjCObject? {
        var current: id? = objcObject
        for key in path.split(separator: ".") {
            guard let object = current else { return nil }
            current = ObjC.send(object, ObjC.selector("valueForKey:"), Strings.autoreleased(String(key)))
        }
        return current.map(ObjCObject.init)
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
