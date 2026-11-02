import CPerryFoundation
import PerryObjCInterop

// NSCharacterSet: a set of Unicode scalars, as a membership test. The
// standard sets follow Apple's definitions by Unicode general category.

/// A character set's members.
final class CharacterSetStorage {
    let contains: (Unicode.Scalar) -> Bool

    init(_ contains: @escaping (Unicode.Scalar) -> Bool) {
        self.contains = contains
    }
}

enum CharacterSets {
    nonisolated(unsafe) static var setClass: Class!

    static func storage(_ object: id?) -> CharacterSetStorage? {
        Storage.get(object, as: CharacterSetStorage.self)
    }

    /// A new set of `cls`, +1.
    static func make(_ cls: UnsafeMutableRawPointer, _ contains: @escaping (Unicode.Scalar) -> Bool) -> id? {
        guard let object = Storage.allocate(cls) else { return nil }
        Storage.set(object, CharacterSetStorage(contains))
        return object
    }

    static func categories(_ categories: Set<Unicode.GeneralCategory>) -> (Unicode.Scalar) -> Bool {
        { categories.contains($0.properties.generalCategory) }
    }

    static let newlines: Set<UInt32> = [0x0A, 0x0B, 0x0C, 0x0D, 0x85, 0x2028, 0x2029]
    static let letterCategories: Set<Unicode.GeneralCategory> = [
        .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
        .nonspacingMark, .spacingMark, .enclosingMark,
    ]
}

/// NSCharacterSet.
@ObjCClass("NSCharacterSet")
public class NSCharacterSet: NSObject {
    /// Set-up after the class is defined.
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        CharacterSets.setClass = cls.storage
    }

    private static func set(_ cls: ObjCClass, _ contains: @escaping (Unicode.Scalar) -> Bool) -> NSCharacterSet? {
        CharacterSets.make(cls.pointer, contains).map(NSCharacterSet.init(objCOwned:))
    }

    var contains: (Unicode.Scalar) -> Bool { CharacterSets.storage(objcObject)?.contains ?? { _ in false } }

    /// Spaces (general category Zs) and tab.
    @ObjCClassMethod("whitespaceCharacterSet")
    static func whitespace(_ cls: ObjCClass) -> NSCharacterSet? {
        set(cls) { $0.value == 0x09 || $0.properties.generalCategory == .spaceSeparator }
    }

    /// Separators (Z*), tab and newlines.
    @ObjCClassMethod("whitespaceAndNewlineCharacterSet")
    static func whitespaceAndNewline(_ cls: ObjCClass) -> NSCharacterSet? {
        set(cls) { scalar in
            scalar.value == 0x09 || CharacterSets.newlines.contains(scalar.value)
                || [.spaceSeparator, .lineSeparator, .paragraphSeparator].contains(scalar.properties.generalCategory)
        }
    }

    @ObjCClassMethod("newlineCharacterSet")
    static func newline(_ cls: ObjCClass) -> NSCharacterSet? { set(cls) { CharacterSets.newlines.contains($0.value) } }

    @ObjCClassMethod("decimalDigitCharacterSet")
    static func decimalDigit(_ cls: ObjCClass) -> NSCharacterSet? { set(cls, CharacterSets.categories([.decimalNumber])) }

    /// Letters (L*) and marks (M*).
    @ObjCClassMethod("letterCharacterSet")
    static func letter(_ cls: ObjCClass) -> NSCharacterSet? { set(cls, CharacterSets.categories(CharacterSets.letterCategories)) }

    @ObjCClassMethod("lowercaseLetterCharacterSet")
    static func lowercaseLetter(_ cls: ObjCClass) -> NSCharacterSet? { set(cls, CharacterSets.categories([.lowercaseLetter])) }

    @ObjCClassMethod("uppercaseLetterCharacterSet")
    static func uppercaseLetter(_ cls: ObjCClass) -> NSCharacterSet? {
        set(cls, CharacterSets.categories([.uppercaseLetter, .titlecaseLetter]))
    }

    /// Letters, marks and numbers (N*).
    @ObjCClassMethod("alphanumericCharacterSet")
    static func alphanumeric(_ cls: ObjCClass) -> NSCharacterSet? {
        set(cls, CharacterSets.categories(CharacterSets.letterCategories.union([.decimalNumber, .letterNumber, .otherNumber])))
    }

    @ObjCClassMethod("punctuationCharacterSet")
    static func punctuation(_ cls: ObjCClass) -> NSCharacterSet? {
        set(cls, CharacterSets.categories([.connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
                                            .initialPunctuation, .finalPunctuation, .otherPunctuation]))
    }

    @ObjCClassMethod("symbolCharacterSet")
    static func symbol(_ cls: ObjCClass) -> NSCharacterSet? {
        set(cls, CharacterSets.categories([.mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol]))
    }

    @ObjCClassMethod("controlCharacterSet")
    static func control(_ cls: ObjCClass) -> NSCharacterSet? { set(cls, CharacterSets.categories([.control, .format])) }

    @ObjCClassMethod("characterSetWithCharactersInString:")
    static func characters(_ cls: ObjCClass, in string: String) -> NSCharacterSet? {
        let members = Set(string.unicodeScalars.map(\.value))
        return set(cls) { members.contains($0.value) }
    }

    @ObjCClassMethod("characterSetWithRange:")
    static func range(_ cls: ObjCClass, _ range: NSRange) -> NSCharacterSet? {
        let start = UInt32(range.location), end = UInt32(range.location + range.length)
        return set(cls) { $0.value >= start && $0.value < end }
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: CharacterSets.setClass)
    }

    @ObjCMethod("invertedSet")
    func invertedSet() -> NSCharacterSet? {
        let contains = contains
        return NSCharacterSet.set(ObjCClass(UnsafeMutableRawPointer(CharacterSets.setClass))) { !contains($0) }
    }

    /// A UTF-16 unit; surrogates are never members.
    @ObjCMethod("characterIsMember:")
    func characterIsMember(_ character: UInt16) -> Bool {
        Unicode.Scalar(UInt32(character)).map(contains) ?? false
    }

    @ObjCMethod("longCharacterIsMember:")
    func longCharacterIsMember(_ character: UInt32) -> Bool {
        Unicode.Scalar(character).map(contains) ?? false
    }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> NSCharacterSet { self }
}

/// NSString's methods that take character sets.
@ObjCCategory("CharacterSets")
extension NSString {
    @ObjCMethod("stringByTrimmingCharactersInSet:")
    func trimming(_ set: NSCharacterSet) -> String {
        let contains = set.contains
        let scalars = value.unicodeScalars
        guard let first = scalars.firstIndex(where: { !contains($0) }),
              let last = scalars.lastIndex(where: { !contains($0) }) else { return "" }
        return String(scalars[first...last])
    }

    @ObjCMethod("componentsSeparatedByCharactersInSet:")
    func components(separatedBy set: NSCharacterSet) -> ObjCObject {
        let contains = set.contains
        var parts: [String] = []
        var current = String.UnicodeScalarView()
        for scalar in value.unicodeScalars {
            if contains(scalar) {
                parts.append(String(current))
                current = String.UnicodeScalarView()
            } else {
                current.append(scalar)
            }
        }
        parts.append(String(current))
        return ObjCObject(Arrays.autoreleased(parts.map { Strings.autoreleased($0) }))
    }

    /// The first member's range in UTF-16 units, or {NSNotFound, 0}.
    @ObjCMethod("rangeOfCharacterFromSet:")
    func rangeOfCharacter(from set: NSCharacterSet) -> NSRange {
        let contains = set.contains
        var offset = 0
        for scalar in value.unicodeScalars {
            let width = scalar.utf16.count
            if contains(scalar) { return NSRange(location: UInt(offset), length: UInt(width)) }
            offset += width
        }
        return NSRange(location: UInt(Int.max), length: 0)
    }

    /// The path as the file system takes it: UTF-8.
    @ObjCMethod("fileSystemRepresentation")
    func fileSystemRepresentation() -> UnsafePointer<CChar>? { Strings.utf8(objcObject) }

    @ObjCMethod("getFileSystemRepresentation:maxLength:")
    func getFileSystemRepresentation(_ buffer: UnsafeMutablePointer<CChar>?, maxLength: UInt) -> Bool {
        let bytes = Array(value.utf8)
        guard let buffer, bytes.count < Int(maxLength) else { return false }
        for (index, byte) in bytes.enumerated() { buffer[index] = CChar(bitPattern: byte) }
        buffer[bytes.count] = 0
        return true
    }
}
