// Macros for Objective-C classes in Swift. They work in two directions.
//
// Calling Objective-C:
//
//     @ObjCClass("NSString")
//     struct NSString {
//         @ObjCMethod("characterAtIndex:")
//         func character(at index: UInt) -> UInt16
//
//         @ObjCMethod("initWithUTF8String:")
//         init(utf8 bytes: UnsafePointer<CChar>)
//
//         @ObjCClassMethod("string")
//         static func empty() -> NSString
//     }
//
//     let length = text.character(at: 0)
//
// Methods without a body get one that sends the message, converting each
// argument and the result through ObjCValue.
//
// Implementing Objective-C:
//
//     @ObjCImplementation
//     extension NSString {
//         @ObjCMethod("stringByAppendingString:")
//         func appending(_ other: String) -> String { … }
//     }
//
//     NSString.register(classDefinition)
//
// Methods with a body are implementations: `self` is the wrapper for the
// receiver and the arguments are Swift values. The macro generates a C
// thunk for each (receiver, _cmd, arguments) and `register(_:)`, which
// installs them into a class.

/// Installs the methods an @ObjCImplementation extension defines.
public protocol ObjCMethodRegistrar {
    func addMethod(_ selector: String, types: String, implementation: UnsafeRawPointer, isClassMethod: Bool)
}

/// The function @ObjCImplementation generates, as a value.
public typealias ObjCMethodRegistration = (any ObjCMethodRegistrar) -> Void

/// Declares a struct as the Swift wrapper for an Objective-C class.
@attached(member, names: named(objcHolder), named(init(objcHolder:)), named(objCClassName))
@attached(extension, conformances: AnyObjCObject)
public macro ObjCClass(_ className: String) =
    #externalMacro(module: "PerryObjCMacros", type: "ObjCClassMacro")

/// An instance method. Without a body it sends the message; with a body
/// in an @ObjCImplementation extension it implements the method.
@attached(body)
public macro ObjCMethod(_ selector: String, types: String? = nil) =
    #externalMacro(module: "PerryObjCMacros", type: "ObjCMethodMacro")

/// A class method: a static function. An implementation may take the
/// receiving class as a first parameter of type ObjCClass.
@attached(body)
public macro ObjCClassMethod(_ selector: String, types: String? = nil) =
    #externalMacro(module: "PerryObjCMacros", type: "ObjCMethodMacro")

/// Implements the @ObjCMethod and @ObjCClassMethod functions with bodies
/// in an extension of an @ObjCClass wrapper. Generates a static function,
/// `register` unless named otherwise, that installs them into a class; name
/// each extension's function differently when a class has several.
@attached(member, names: arbitrary)
public macro ObjCImplementation(_ registrationName: String = "register") =
    #externalMacro(module: "PerryObjCMacros", type: "ObjCImplementationMacro")

// MARK: - Type encodings

/// Method type encodings, as clang writes them: return type, frame size,
/// then each argument at its offset ("S24@0:8Q16").
public enum ObjCTypeEncoding {
    private static func size<Value: ObjCValue>(_ type: Value.Type) -> Int {
        max(MemoryLayout<Value.ObjCType>.size, 4)
    }

    public static func method(returning result: (any ObjCValue.Type)?, arguments: [any ObjCValue.Type]) -> String {
        var offset = 16
        var encoded = "@0:8"
        for argument in arguments {
            encoded += "\(argument.objCTypeEncoding)\(offset)"
            offset += size(argument)
        }
        return (result?.objCTypeEncoding ?? "v") + "\(offset)" + encoded
    }
}
