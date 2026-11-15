import Glibc
import PerryObjCInterop
import Synchronization

// A CALayer subclass may declare a property @dynamic and leave the
// accessors to Core Animation, which keeps the value in the layer, as
// key-value coding does for keys the layer does not define. The accessors
// are made the first time one is called, from the property's declaration.

enum DynamicProperties {
    typealias GetProperty = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> UnsafeRawPointer?
    typealias GetAttributes = @convention(c) (UnsafeRawPointer?) -> UnsafePointer<CChar>?
    nonisolated(unsafe) static var getProperty: GetProperty?
    nonisolated(unsafe) static var getAttributes: GetAttributes?

    static func load(_ lookup: (String) -> UnsafeMutableRawPointer?) {
        getProperty = lookup("_class_getProperty").map { unsafeBitCast($0, to: GetProperty.self) }
        getAttributes = lookup("_property_getAttributes").map { unsafeBitCast($0, to: GetAttributes.self) }
    }

    /// Each accessor's key, by its selector's address.
    static let keys = Mutex<[UInt: String]>([:])

    static func key(_ selector: UnsafeRawPointer?) -> String? {
        keys.withLock { $0[UInt(bitPattern: selector)] }
    }

    /// A dynamic property's type encoding, its first character.
    static func type(of name: String, in cls: ObjCClass) -> Character? {
        guard let getProperty, let getAttributes,
              let property = name.withCString({ getProperty(cls.pointer, $0) }),
              let attributes = getAttributes(property).map({ String(cString: $0) }) else { return nil }
        let parts = attributes.split(separator: ",")
        guard parts.contains("D"), let type = parts.first, type.first == "T" else { return nil }
        return type.dropFirst().first
    }

    typealias Object = UnsafeMutableRawPointer?
    typealias Selector = UnsafeRawPointer?

    static func value(_ layer: Object, _ selector: Selector) -> NSObject? {
        guard let layer, let key = key(selector) else { return nil }
        return CALayer.wrap(layer).state.values[key]
    }

    static func set(_ layer: Object, _ selector: Selector, _ value: NSObject?) {
        guard let layer, let key = key(selector) else { return }
        CALayer.wrap(layer).state.values[key] = value
    }

    static let getObject: @convention(c) (Object, Selector) -> Object = { layer, selector in
        value(layer, selector)?.objcObject
    }
    static let setObject: @convention(c) (Object, Selector, Object) -> Void = { layer, selector, object in
        set(layer, selector, object.map { NSObject($0) })
    }
    static let getBool: @convention(c) (Object, Selector) -> Bool = { layer, selector in
        value(layer, selector)?.sendBoolValue() ?? false
    }
    static let setBool: @convention(c) (Object, Selector, Bool) -> Void = { layer, selector, flag in
        set(layer, selector, NSNumber.make(bool: flag))
    }
    static let getInteger: @convention(c) (Object, Selector) -> Int = { layer, selector in
        Int(value(layer, selector)?.sendDoubleValue() ?? 0)
    }
    static let setInteger: @convention(c) (Object, Selector, Int) -> Void = { layer, selector, number in
        set(layer, selector, NSNumber.make(double: Double(number)))
    }
    static let getDouble: @convention(c) (Object, Selector) -> Double = { layer, selector in
        value(layer, selector)?.sendDoubleValue() ?? 0
    }
    static let setDouble: @convention(c) (Object, Selector, Double) -> Void = { layer, selector, number in
        set(layer, selector, NSNumber.make(double: number))
    }
    static let getFloat: @convention(c) (Object, Selector) -> Float = { layer, selector in
        Float(value(layer, selector)?.sendDoubleValue() ?? 0)
    }
    static let setFloat: @convention(c) (Object, Selector, Float) -> Void = { layer, selector, number in
        set(layer, selector, NSNumber.make(double: Double(number)))
    }

    /// Adds the accessor `name` to `cls` if it reads or writes one of the
    /// class's dynamic properties: `name` or `isName` reads, `setName:` writes.
    static func resolve(_ name: String, selector: UnsafeRawPointer, in cls: ObjCClass) -> Bool {
        var key = name, setter = false
        if name.hasPrefix("set"), name.hasSuffix(":"), name.count > 4 {
            let body = name.dropFirst(3).dropLast()
            guard !body.contains(":") else { return false }
            key = body.prefix(1).lowercased() + body.dropFirst()
            setter = true
        } else if name.contains(":") {
            return false
        }
        guard let type = type(of: key, in: cls) else { return false }
        let pair: (get: UnsafeRawPointer, set: UnsafeRawPointer, encoding: String)
        switch type {
        case "@": pair = (unsafeBitCast(getObject, to: UnsafeRawPointer.self), unsafeBitCast(setObject, to: UnsafeRawPointer.self), "@")
        case "B", "c", "C": pair = (unsafeBitCast(getBool, to: UnsafeRawPointer.self), unsafeBitCast(setBool, to: UnsafeRawPointer.self), String(type))
        case "q", "Q", "l", "L": pair = (unsafeBitCast(getInteger, to: UnsafeRawPointer.self), unsafeBitCast(setInteger, to: UnsafeRawPointer.self), String(type))
        case "d": pair = (unsafeBitCast(getDouble, to: UnsafeRawPointer.self), unsafeBitCast(setDouble, to: UnsafeRawPointer.self), "d")
        case "f": pair = (unsafeBitCast(getFloat, to: UnsafeRawPointer.self), unsafeBitCast(setFloat, to: UnsafeRawPointer.self), "f")
        default: return false
        }
        keys.withLock { $0[UInt(bitPattern: selector)] = key }
        if setter {
            cls.addMethod(name, types: "v@:\(pair.encoding)", implementation: pair.set, isClassMethod: false)
        } else {
            cls.addMethod(name, types: "\(pair.encoding)@:", implementation: pair.get, isClassMethod: false)
        }
        return true
    }
}

@ObjCCategory("DynamicProperties")
extension CALayer {
    @ObjCClassMethod("resolveInstanceMethod:")
    static func resolveInstanceMethod(_ cls: ObjCClass, selector: ObjCSelector?) -> Bool {
        guard let selector else { return false }
        return DynamicProperties.resolve(selector.name, selector: selector.pointer, in: cls)
    }
}
