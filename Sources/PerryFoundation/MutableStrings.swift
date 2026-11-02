import CPerryFoundation
import Glibc
import PerryObjCInterop

enum MutableStrings {
    nonisolated(unsafe) static var mutableClass: Class!

    /// A new NSMutableString, retained (+1).
    static func make(_ value: String) -> id {
        let object = Storage.allocate(UnsafeMutableRawPointer(mutableClass))!
        Storage.set(object, StringStorage(value))
        return object
    }

    static func storage(_ object: id?) -> StringStorage {
        guard let storage = Storage.get(object, as: StringStorage.self) else {
            foundationFatal("mutating method sent to an uninitialized NSMutableString")
        }
        return storage
    }

    /// Replaces UTF-16 units `location ..< location + length`, as NSString
    /// ranges count them.
    static func replace(_ object: id?, location: UInt, length: UInt, with replacement: String, method: String) {
        let storage = storage(object)
        var units = Array(storage.value.utf16)
        guard Int(location + length) <= units.count else {
            foundationFatal("-[NSMutableString \(method)]: Range {\(location), \(length)} out of bounds; string length \(units.count)")
        }
        units.replaceSubrange(Int(location)..<Int(location + length), with: replacement.utf16)
        storage.value = String(decoding: units, as: UTF16.self)
    }

    static func install(superclass: Class) {
        let mutable = ClassDefinition(PERRY_CLASS_NSMutableString, name: "NSMutableString", superclass: superclass,
                                      NSMutableStringMethods.self)
        mutableClass = mutable.cls
        mutable.addMethod("appendFormat:", types: "v24@0:8@16",
                          implementation: variadicEntry(perry_imp_appendFormat), isClassMethod: false)
    }
}

@ObjCImplementation
enum NSMutableStringMethods {
    @ObjCClassMethod("stringWithCapacity:")
    static func string(_ cls: id?, capacity: UInt) -> id? {
        let object = Storage.allocate(cls)
        if let object { Storage.set(object, StringStorage("")) }
        return ObjC.autorelease(object)
    }

    @ObjCMethod("initWithCapacity:")
    static func initialize(_ object: id?, capacity: UInt) -> id? {
        if let object { Storage.set(object, StringStorage("")) }
        return object
    }

    /// Copies of a mutable string are immutable.
    @ObjCMethod("copyWithZone:")
    static func copy(_ object: id?, zone: UnsafeMutableRawPointer?) -> id? {
        Strings.make(Strings.value(of: object) ?? "")
    }

    @ObjCMethod("copy")
    static func copy(_ object: id?) -> id? { copy(object, zone: nil) }

    @ObjCMethod("appendString:")
    static func append(_ object: id?, _ other: id?) {
        MutableStrings.storage(object).value += Strings.value(of: other) ?? ""
    }

    @ObjCMethod("setString:")
    static func set(_ object: id?, string other: id?) {
        MutableStrings.storage(object).value = Strings.value(of: other) ?? ""
    }

    @ObjCMethod("insertString:atIndex:")
    static func insert(_ object: id?, _ other: id?, at index: UInt) {
        MutableStrings.replace(object, location: index, length: 0, with: Strings.value(of: other) ?? "",
                               method: "insertString:atIndex:")
    }

    @ObjCMethod("deleteCharactersInRange:")
    static func delete(_ object: id?, range: NSRange) {
        MutableStrings.replace(object, location: range.location, length: range.length, with: "",
                               method: "deleteCharactersInRange:")
    }

    @ObjCMethod("replaceCharactersInRange:withString:")
    static func replace(_ object: id?, range: NSRange, with other: id?) {
        MutableStrings.replace(object, location: range.location, length: range.length,
                               with: Strings.value(of: other) ?? "", method: "replaceCharactersInRange:withString:")
    }
}

/// - (void)appendFormat:(NSString *)format, ...
@c
public func perry_foundation_appendFormat(_ object: id?, _ cmd: SEL?, _ format: id?, _ arguments: UnsafeRawPointer?) {
    guard let arguments else { return }
    var darwin = DarwinArguments(arguments)
    MutableStrings.storage(object).value += Format.string(Strings.value(of: format) ?? "", &darwin)
}
