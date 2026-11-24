import CPerryFoundation
import Glibc
import PerryObjCInterop
import _FoundationICU

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

    /// The range's characters replaced with `length` UTF-16 units, as
    /// Foundation's own strings take them (Xcode's text storage does).
    @ObjCMethod("replaceCharactersInRange:withCharacters:length:")
    func replace(range: NSRange, withCharacters characters: UnsafePointer<UInt16>?, length: UInt) {
        let units = characters.map { Array(UnsafeBufferPointer(start: $0, count: Int(length))) } ?? []
        MutableStrings.replace(objcObject, location: range.location, length: range.length, with: String(decoding: units, as: UTF16.self),
                               method: "replaceCharactersInRange:withCharacters:length:")
    }

    /// The range's characters through an ICU transform (NSStringTransform's
    /// names are ICU's IDs); the range they take afterwards. False, and
    /// nothing changed, for a transform ICU doesn't know.
    @ObjCMethod("applyTransform:reverse:range:updatedRange:")
    func applyTransform(_ transform: String?, reverse: Bool, range: NSRange, updatedRange: UnsafeMutablePointer<NSRange>?) -> Bool {
        let units = Array(storage.value.utf16)
        let start = Int(range.location), end = start + Int(range.length)
        guard let transform, start <= end, end <= units.count,
              let transformed = ICUTransforms.apply(transform, to: String(decoding: units[start..<end], as: UTF16.self), reverse: reverse)
        else { return false }
        MutableStrings.replace(objcObject, location: range.location, length: range.length, with: transformed,
                               method: "applyTransform:reverse:range:updatedRange:")
        updatedRange?.pointee = NSRange(location: range.location, length: UInt(transformed.utf16.count))
        return true
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

/// ICU's transliterators, by transform ID.
enum ICUTransforms {
    /// The text transliterated, forward or in reverse; nil for an ID ICU
    /// can't open.
    static func apply(_ transform: String, to text: String, reverse: Bool) -> String? {
        // Darwin's XML hex transform leaves ASCII as it is, as CFString's
        // does (XMLHex): ICU's own encodes every character, so it is
        // filtered to the rest. Its reverse decodes any "&#x…;".
        let identifier = transform == "Any-Hex/XML" && !reverse ? "[:^ASCII:] Any-Hex/XML" : transform
        var status = U_ZERO_ERROR
        let transliterator = ICU.withUChars(identifier) { id, length in
            swift_utrans_openU(id, length, reverse ? UTRANS_REVERSE : UTRANS_FORWARD, nil, 0, nil, &status)
        }
        guard let transliterator, !ICU.failed(status) else { return nil }
        defer { swift_utrans_close(transliterator) }
        let source = Array(text.utf16)
        var capacity = max(source.count * 4, 64)
        while true {
            var units = source + Array(repeating: 0, count: capacity - source.count)
            var length = Int32(source.count), limit = length
            status = U_ZERO_ERROR
            units.withUnsafeMutableBufferPointer { buffer in
                swift_utrans_transUChars(transliterator, buffer.baseAddress, &length, Int32(capacity), 0, &limit, &status)
            }
            if status == U_BUFFER_OVERFLOW_ERROR, capacity < 1 << 24 {
                capacity = max(capacity * 4, Int(length) + 1)
                continue
            }
            guard !ICU.failed(status) else { return nil }
            return String(decoding: units[0..<Int(length)], as: UTF16.self)
        }
    }
}
