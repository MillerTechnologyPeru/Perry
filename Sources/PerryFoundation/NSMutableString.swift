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

}

/// NSMutableString.
@ObjCClass("NSMutableString")
public class NSMutableString: NSString {
    /// Set-up after the class is defined.
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        MutableStrings.mutableClass = cls.storage
        cls.addMethod("appendFormat:", types: "v24@0:8@16",
                      implementation: variadicEntry(perry_imp_appendFormat), isClassMethod: false)
    }

    private var storage: StringStorage { MutableStrings.storage(objcObject) }

    @ObjCClassMethod("stringWithCapacity:")
    static func string(_ cls: ObjCClass, capacity: UInt) -> ObjCObject? {
        guard let object = Storage.allocate(cls.pointer) else { return nil }
        Storage.set(object, StringStorage(""))
        return ObjCObject(objCOwned: object)
    }

    @ObjCMethod("initWithCapacity:")
    func initialize(capacity: UInt) -> Self {
        Storage.set(objcObject, StringStorage(""))
        return self
    }

    /// Copies of a mutable string are immutable.
    @ObjCMethod("copyWithZone:")
    override func copy(zone: UnsafeMutableRawPointer?) -> NSString {
        NSString(objCOwned: Strings.make(storage.value))
    }

    @ObjCMethod("copy")
    override func copy() -> NSString { copy(zone: nil) }

    @ObjCMethod("appendString:")
    func append(_ other: String) { storage.value += other }

    @ObjCMethod("setString:")
    func set(string other: String) { storage.value = other }

    @ObjCMethod("insertString:atIndex:")
    func insert(_ other: String, at index: UInt) {
        MutableStrings.replace(objcObject, location: index, length: 0, with: other, method: "insertString:atIndex:")
    }

    @ObjCMethod("deleteCharactersInRange:")
    func delete(range: NSRange) {
        MutableStrings.replace(objcObject, location: range.location, length: range.length, with: "",
                               method: "deleteCharactersInRange:")
    }

    @ObjCMethod("replaceCharactersInRange:withString:")
    func replace(range: NSRange, with other: String) {
        MutableStrings.replace(objcObject, location: range.location, length: range.length, with: other,
                               method: "replaceCharactersInRange:withString:")
    }

    /// Each match in the range, searched with the options; the number replaced.
    @ObjCMethod("replaceOccurrencesOfString:withString:options:range:")
    func replaceOccurrences(of target: String, with replacement: String, options: UInt, range: NSRange) -> UInt {
        guard !target.isEmpty else { return 0 }
        let search = ObjC.selector("rangeOfString:options:range:")
        let find = unsafeBitCast(ObjCRuntime.msgSend(returning: NSRange.self), to: (@convention(c) (id?, SEL, id?, UInt, NSRange) -> NSRange).self)
        let replacementLength = UInt(replacement.utf16.count)
        var scope = range
        var count: UInt = 0
        // Forward only: a backwards search option makes no difference to the result.
        while true {
            let found = find(objcObject, search, Strings.autoreleased(target), options & ~4, scope)
            guard found.location != UInt(Int.max) else { return count }
            MutableStrings.replace(objcObject, location: found.location, length: found.length, with: replacement,
                                   method: "replaceOccurrencesOfString:withString:options:range:")
            count += 1
            let end = scope.location + scope.length + replacementLength - found.length
            let next = found.location + replacementLength
            scope = NSRange(location: next, length: end - next)
        }
    }
}

/// - (void)appendFormat:(NSString *)format, ...
@c
public func perry_foundation_appendFormat(_ object: id?, _ cmd: SEL?, _ format: id?, _ arguments: UnsafeRawPointer?) {
    guard let arguments else { return }
    var darwin = DarwinArguments(arguments)
    MutableStrings.storage(object).value += Format.string(Strings.value(of: format) ?? "", &darwin)
}
