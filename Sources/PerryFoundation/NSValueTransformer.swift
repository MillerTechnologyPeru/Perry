import CPerryFoundation
import PerryObjCInterop

// NSValueTransformer: a value converted to another and back, as bindings
// apply them, with the named transformers Foundation registers.

enum ValueTransformers {
    /// Registered transformers by name, retained.
    nonisolated(unsafe) static var named: [String: id] = [:]
    nonisolated(unsafe) static var registeredBuiltIns = false

    static func boolValue(_ object: id?) -> Bool {
        guard let object else { return false }
        typealias Fn = @convention(c) (id?, SEL) -> Bool
        return unsafeBitCast(ObjC.msgSend, to: Fn.self)(object, ObjC.selector("boolValue"))
    }

    static func boolean(_ value: Bool) -> id? { Numbers.make(nil, .bool(value)) }

    /// The built-in transformers, made the first time one is looked up.
    static func registerBuiltIns() {
        guard !registeredBuiltIns else { return }
        registeredBuiltIns = true
        let builtIns: [(String, String)] = [
            ("NSNegateBoolean", "_NSNegateBooleanTransformer"),
            ("NSIsNil", "_NSIsNilTransformer"),
            ("NSIsNotNil", "_NSIsNotNilTransformer"),
            ("NSUnarchiveFromData", "_NSUnarchiveFromDataTransformer"),
            ("NSKeyedUnarchiveFromData", "_NSKeyedUnarchiveFromDataTransformer"),
            ("NSSecureUnarchiveFromData", "_NSKeyedUnarchiveFromDataTransformer"),
        ]
        for (name, className) in builtIns where named[name] == nil {
            guard let cls = className.withCString({ ObjC.getClass($0) }),
                  let object = ObjC.send(ObjC.send(UnsafeMutableRawPointer(cls), ObjC.selector("alloc")), ObjC.selector("init"))
            else { continue }
            named[name] = object
        }
    }
}

@ObjCClass("NSValueTransformer")
open class NSValueTransformer: NSObject {
    @ObjCClassMethod("setValueTransformer:forName:")
    static func setValueTransformer(_ transformer: UnsafeMutableRawPointer?, forName name: String) {
        ValueTransformers.registerBuiltIns()
        if let old = ValueTransformers.named[name] { ObjC.release(old) }
        ValueTransformers.named[name] = transformer.flatMap { ObjC.retain($0) }
    }

    @ObjCClassMethod("valueTransformerForName:")
    static func valueTransformer(forName name: String) -> UnsafeMutableRawPointer? {
        ValueTransformers.registerBuiltIns()
        return ValueTransformers.named[name]
    }

    @ObjCClassMethod("valueTransformerNames")
    static func valueTransformerNames() -> UnsafeMutableRawPointer? {
        ValueTransformers.registerBuiltIns()
        return Arrays.autoreleased(ValueTransformers.named.keys.sorted().map { Strings.autoreleased($0) })
    }

    @ObjCClassMethod("allowsReverseTransformation") static func allowsReverseTransformation() -> Bool { true }
    @ObjCClassMethod("transformedValueClass") static func transformedValueClass() -> UnsafeMutableRawPointer? {
        "NSObject".withCString { ObjC.getClass($0) }.map { UnsafeMutableRawPointer($0) }
    }

    /// The value as it is: subclasses convert it.
    @ObjCMethod("transformedValue:")
    func transformedValue(_ value: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { value }

    /// The value converted back, which is the conversion itself unless a
    /// subclass says otherwise.
    @ObjCMethod("reverseTransformedValue:")
    func reverseTransformedValue(_ value: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        ObjC.send(objcObject, ObjC.selector("transformedValue:"), value)
    }
}

@ObjCClass("_NSNegateBooleanTransformer")
final class _NSNegateBooleanTransformer: NSValueTransformer {
    @ObjCMethod("transformedValue:")
    override func transformedValue(_ value: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        ValueTransformers.boolean(!ValueTransformers.boolValue(value))
    }
}

@ObjCClass("_NSIsNilTransformer")
final class _NSIsNilTransformer: NSValueTransformer {
    @ObjCMethod("transformedValue:")
    override func transformedValue(_ value: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        ValueTransformers.boolean(value == nil)
    }
}

@ObjCClass("_NSIsNotNilTransformer")
final class _NSIsNotNilTransformer: NSValueTransformer {
    @ObjCMethod("transformedValue:")
    override func transformedValue(_ value: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        ValueTransformers.boolean(value != nil)
    }
}

/// Data unarchived into the object it holds, and archived again.
@ObjCClass("_NSKeyedUnarchiveFromDataTransformer")
class _NSKeyedUnarchiveFromDataTransformer: NSValueTransformer {
    @ObjCMethod("transformedValue:")
    override func transformedValue(_ value: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        guard let value, let unarchiver = "NSKeyedUnarchiver".withCString({ ObjC.getClass($0) }) else { return nil }
        return ObjC.send(UnsafeMutableRawPointer(unarchiver), ObjC.selector("unarchiveObjectWithData:"), value)
    }

    @ObjCMethod("reverseTransformedValue:")
    override func reverseTransformedValue(_ value: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        guard let value, let archiver = "NSKeyedArchiver".withCString({ ObjC.getClass($0) }) else { return nil }
        return ObjC.send(UnsafeMutableRawPointer(archiver), ObjC.selector("archivedDataWithRootObject:"), value)
    }
}

@ObjCClass("_NSUnarchiveFromDataTransformer")
final class _NSUnarchiveFromDataTransformer: _NSKeyedUnarchiveFromDataTransformer {}

/// The built-in transformers' names.
@ObjCConstants
enum ValueTransformerNames {
    static let NSNegateBooleanTransformerName = "NSNegateBoolean"
    static let NSIsNilTransformerName = "NSIsNil"
    static let NSIsNotNilTransformerName = "NSIsNotNil"
    static let NSUnarchiveFromDataTransformerName = "NSUnarchiveFromData"
    static let NSKeyedUnarchiveFromDataTransformerName = "NSKeyedUnarchiveFromData"
    static let NSSecureUnarchiveFromDataTransformerName = "NSSecureUnarchiveFromData"
}
