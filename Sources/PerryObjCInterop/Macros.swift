// Exposing Swift classes to Objective-C.
//
//     @ObjCClass("NSMutableString")
//     public class NSMutableString: NSString {
//         @ObjCMethod("appendString:")
//         func append(_ other: String) { … }
//
//         @ObjCClassMethod("stringWithCapacity:")
//         static func string(capacity: UInt) -> NSMutableString { … }
//     }
//
//     NSMutableString.defineObjCClass()
//
// The Swift class inherits from the wrapper of the Objective-C superclass.
// Its @ObjCMethod and @ObjCClassMethod functions implement the selectors:
// `self` is a wrapper for the receiver and arguments and results are Swift
// values, converted through ObjCValue. @ObjCClass generates a C thunk for
// each, the class and superclass names, and registerObjCMethods(_:), which
// installs them; defineObjCClass(_:) creates the class from them.
//
// Categories add methods to a class that already exists, from an extension
// of its wrapper:
//
//     @ObjCCategory("Paths")
//     public extension NSString {
//         @ObjCMethod("lastPathComponent")
//         func lastPathComponent() -> String { … }
//     }
//
//     NSString.addObjCCategoryPaths()
//
// Swift does not let subclasses override methods declared in extensions, so
// a category's functions need Swift names that the class's subclasses do
// not also use.

/// Installs methods into a class.
public protocol ObjCMethodRegistrar {
    func addMethod(_ selector: String, types: String, implementation: UnsafeRawPointer, isClassMethod: Bool)
}

/// A function that installs methods, such as a class's registerObjCMethods.
public typealias ObjCMethodRegistration = (any ObjCMethodRegistrar) -> Void

/// Exposes a Swift class, a subclass of an Objective-C class's wrapper, as
/// that Objective-C class.
@attached(member, names: named(objCClassName), named(objCSuperclassName), named(registerObjCMethods))
public macro ObjCClass(_ className: String) =
    #externalMacro(module: "PerryObjCMacros", type: "ObjCClassMacro")

/// Adds an extension's methods to the extended wrapper's Objective-C class,
/// as an Objective-C category does. Generates registerObjCCategory<Name>(_:)
/// and addObjCCategory<Name>(), named after the category so a class can
/// have several.
@attached(member, names: arbitrary)
public macro ObjCCategory(_ categoryName: String) =
    #externalMacro(module: "PerryObjCMacros", type: "ObjCCategoryMacro")

/// Implements an instance method. The function's arguments are the
/// selector's.
@attached(peer)
public macro ObjCMethod(_ selector: String, types: String? = nil) =
    #externalMacro(module: "PerryObjCMacros", type: "ObjCMethodMacro")

/// Implements a class method: a static or class function. It may take the
/// receiving class as a first parameter of type ObjCClass.
@attached(peer)
public macro ObjCClassMethod(_ selector: String, types: String? = nil) =
    #externalMacro(module: "PerryObjCMacros", type: "ObjCMethodMacro")

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
