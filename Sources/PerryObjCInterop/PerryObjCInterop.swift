// Implementing Objective-C classes in Swift.
//
//     @ObjCImplementation
//     enum NSStringMethods {
//         @ObjCMethod("length")
//         static func length(_ string: id?) -> UInt { … }
//
//         @ObjCClassMethod("stringWithUTF8String:")
//         static func string(_ cls: id?, utf8 bytes: UnsafePointer<CChar>?) -> id? { … }
//     }
//
//     NSStringMethods.register(classDefinition)
//
// Each method is a static function whose first parameter is the receiver;
// the selector's arguments follow, and _cmd is supplied by the generated
// thunk. Type encodings come from the Swift types: id → @, Class → #,
// SEL → :, ObjCBlock → @?, UInt → Q, Double → d, and so on. Pass `types:`
// for anything else.

/// Installs the methods an @ObjCImplementation type defines into a class.
public protocol ObjCMethodRegistrar {
    func addMethod(_ selector: String, types: String, implementation: UnsafeRawPointer, isClassMethod: Bool)
}

/// A type whose methods @ObjCImplementation registers.
public protocol ObjCMethodTable {
    static func register(_ registrar: some ObjCMethodRegistrar)
}

/// A block argument, encoded as @?.
public typealias ObjCBlock = UnsafeMutableRawPointer

/// Generates `register(_:)` for the @ObjCMethod and @ObjCClassMethod
/// functions in a type.
@attached(member, names: named(register))
@attached(extension, conformances: ObjCMethodTable)
public macro ObjCImplementation() = #externalMacro(module: "PerryObjCMacros", type: "ObjCImplementationMacro")

/// An instance method. The function's first parameter is the receiver.
@attached(peer)
public macro ObjCMethod(_ selector: String, types: String? = nil) =
    #externalMacro(module: "PerryObjCMacros", type: "ObjCMethodMacro")

/// A class method. The function's first parameter is the class.
@attached(peer)
public macro ObjCClassMethod(_ selector: String, types: String? = nil) =
    #externalMacro(module: "PerryObjCMacros", type: "ObjCMethodMacro")
