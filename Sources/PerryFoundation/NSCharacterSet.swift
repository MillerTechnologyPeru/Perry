import CPerryFoundation
import FoundationEssentials
import PerryObjCInterop

// NSCharacterSet: a set of Unicode scalars, as a membership test. The
// standard sets follow Apple's definitions by Unicode general category.

/// A character set's members.
final class CharacterSetStorage {
    /// Changes only for NSMutableCharacterSet.
    var contains: (Unicode.Scalar) -> Bool

    init(_ contains: @escaping (Unicode.Scalar) -> Bool) {
        self.contains = contains
    }
}

enum CharacterSets {
    nonisolated(unsafe) static var setClass: Class!
    nonisolated(unsafe) static var mutableClass: Class!

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

    static func isWhitespaceOrNewline(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value == 0x09 || newlines.contains(scalar.value)
            || [.spaceSeparator, .lineSeparator, .paragraphSeparator].contains(scalar.properties.generalCategory)
    }

    /// One whitespace-and-newline set, made when first used, kept forever.
    nonisolated(unsafe) private static var whitespaceAndNewlineObject: id?
    static var whitespaceAndNewline: id {
        if let object = whitespaceAndNewlineObject { return object }
        let object = make(UnsafeMutableRawPointer(setClass), isWhitespaceOrNewline)!
        whitespaceAndNewlineObject = object
        return object
    }
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
        set(cls, CharacterSets.isWhitespaceOrNewline)
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

    /// Combining marks: general categories Mn, Mc and Me.
    @ObjCClassMethod("nonBaseCharacterSet")
    static func nonBase(_ cls: ObjCClass) -> NSCharacterSet? {
        set(cls, CharacterSets.categories([.nonspacingMark, .spacingMark, .enclosingMark]))
    }

    /// Titlecase letters (Lt).
    @ObjCClassMethod("capitalizedLetterCharacterSet")
    static func capitalizedLetter(_ cls: ObjCClass) -> NSCharacterSet? { set(cls, CharacterSets.categories([.titlecaseLetter])) }

    /// Code points Unicode has not assigned (Cn).
    @ObjCClassMethod("illegalCharacterSet")
    static func illegal(_ cls: ObjCClass) -> NSCharacterSet? { set(cls, CharacterSets.categories([.unassigned])) }

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

    @ObjCMethod("mutableCopyWithZone:")
    func mutableCopy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        CharacterSets.make(UnsafeMutableRawPointer(CharacterSets.mutableClass), contains)
    }

    @ObjCMethod("isSupersetOfSet:")
    func isSuperset(of other: NSCharacterSet) -> Bool { CharacterSets.isSuperset(contains, of: other.contains) }

    /// Plane 0 is the Basic Multilingual Plane.
    @ObjCMethod("hasMemberInPlane:")
    func hasMember(inPlane plane: UInt8) -> Bool { CharacterSets.hasMember(contains, inPlane: plane) }

    @ObjCMethod("bitmapRepresentation")
    func bitmapRepresentation() -> UnsafeMutableRawPointer? { DataObjects.autoreleased(CharacterSets.bitmap(contains)) }
}

/// A character set whose members change.
@ObjCClass("NSMutableCharacterSet")
public class NSMutableCharacterSet: NSCharacterSet {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        CharacterSets.mutableClass = cls.storage
    }

    @ObjCMethod("init")
    func initialize() -> Self {
        Storage.set(objcObject, CharacterSetStorage { _ in false })
        return self
    }

    @ObjCMethod("copyWithZone:")
    override func copy(zone: UnsafeMutableRawPointer?) -> NSCharacterSet {
        let contains = contains
        return NSCharacterSet(objCOwned: CharacterSets.make(UnsafeMutableRawPointer(CharacterSets.setClass), contains)!)
    }

    private func update(_ change: (@escaping (Unicode.Scalar) -> Bool) -> (Unicode.Scalar) -> Bool) {
        guard let storage = CharacterSets.storage(objcObject) else { return }
        storage.contains = change(storage.contains)
    }

    @ObjCMethod("addCharactersInString:")
    func addCharacters(in string: String) {
        let members = Set(string.unicodeScalars.map(\.value))
        update { old in { old($0) || members.contains($0.value) } }
    }

    @ObjCMethod("removeCharactersInString:")
    func removeCharacters(in string: String) {
        let members = Set(string.unicodeScalars.map(\.value))
        update { old in { old($0) && !members.contains($0.value) } }
    }

    @ObjCMethod("addCharactersInRange:")
    func addCharacters(in range: NSRange) {
        let start = UInt32(range.location), end = UInt32(range.location + range.length)
        update { old in { old($0) || ($0.value >= start && $0.value < end) } }
    }

    @ObjCMethod("removeCharactersInRange:")
    func removeCharacters(in range: NSRange) {
        let start = UInt32(range.location), end = UInt32(range.location + range.length)
        update { old in { old($0) && !($0.value >= start && $0.value < end) } }
    }

    @ObjCMethod("formUnionWithCharacterSet:")
    func formUnion(with other: NSCharacterSet) {
        let theirs = other.contains
        update { old in { old($0) || theirs($0) } }
    }

    @ObjCMethod("formIntersectionWithCharacterSet:")
    func formIntersection(with other: NSCharacterSet) {
        let theirs = other.contains
        update { old in { old($0) && theirs($0) } }
    }

    @ObjCMethod("invert")
    func invert() { update { old in { !old($0) } } }
}

extension CharacterSets {
    /// The scalars of a plane, 65,536 code points from plane << 16.
    static func scalars(inPlane plane: UInt8) -> some Sequence<Unicode.Scalar> {
        let base = UInt32(plane) << 16
        return (base..<base + 0x10000).lazy.compactMap(Unicode.Scalar.init)
    }

    static func hasMember(_ contains: (Unicode.Scalar) -> Bool, inPlane plane: UInt8) -> Bool {
        plane <= 16 && scalars(inPlane: plane).contains(where: contains)
    }

    static func isSuperset(_ contains: (Unicode.Scalar) -> Bool, of other: (Unicode.Scalar) -> Bool) -> Bool {
        (0...16).allSatisfy { plane in scalars(inPlane: UInt8(plane)).allSatisfy { !other($0) || contains($0) } }
    }

    /// The bitmap representation: 8,192 bytes for the Basic Multilingual
    /// Plane, a bit per code point, low bit first, then for each other plane
    /// with members its number and its 8,192 bytes.
    static func bitmap(_ contains: (Unicode.Scalar) -> Bool) -> Data {
        func plane(_ number: UInt8) -> [UInt8] {
            var bytes = [UInt8](repeating: 0, count: 8192)
            for scalar in scalars(inPlane: number) where contains(scalar) {
                let offset = Int(scalar.value & 0xFFFF)
                bytes[offset >> 3] |= 1 << (offset & 7)
            }
            return bytes
        }
        var data = Data(plane(0))
        for number in 1...16 where hasMember(contains, inPlane: UInt8(number)) {
            data.append(UInt8(number))
            data.append(contentsOf: plane(UInt8(number)))
        }
        return data
    }

    /// The members a bitmap representation lists.
    static func members(fromBitmap data: Data) -> Set<UInt32> {
        var members = Set<UInt32>()
        let bytes = [UInt8](data)
        func read(_ plane: UInt32, from start: Int) {
            for index in 0..<min(8192, bytes.count - start) where bytes[start + index] != 0 {
                for bit in 0..<8 where bytes[start + index] & (1 << bit) != 0 {
                    members.insert(plane << 16 | UInt32(index * 8 + bit))
                }
            }
        }
        read(0, from: 0)
        var offset = 8192
        while offset < bytes.count {
            read(UInt32(bytes[offset]), from: offset + 1)
            offset += 8193
        }
        return members
    }
}

// MARK: - CFCharacterSet

// CFCharacterSetRef is NSCharacterSet, and CFMutableCharacterSetRef
// NSMutableCharacterSet. CFRange is { location, length }.

private func characterSet(_ object: id?) -> (Unicode.Scalar) -> Bool {
    CharacterSets.storage(object)?.contains ?? { _ in false }
}

private func mutate(_ object: id?, _ change: (@escaping (Unicode.Scalar) -> Bool) -> (Unicode.Scalar) -> Bool) {
    guard let storage = CharacterSets.storage(object) else { return }
    storage.contains = change(storage.contains)
}

@c(_CFCharacterSetCreateMutable)
public func CFCharacterSetCreateMutable(_ allocator: id?) -> id? {
    CharacterSets.make(UnsafeMutableRawPointer(CharacterSets.mutableClass)) { _ in false }
}

@c(_CFCharacterSetCreateMutableCopy)
public func CFCharacterSetCreateMutableCopy(_ allocator: id?, _ set: id?) -> id? {
    CharacterSets.make(UnsafeMutableRawPointer(CharacterSets.mutableClass), characterSet(set))
}

@c(_CFCharacterSetCreateWithCharactersInRange)
public func CFCharacterSetCreateWithCharactersInRange(_ allocator: id?, _ location: Int, _ length: Int) -> id? {
    let start = UInt32(max(location, 0)), end = UInt32(max(location + length, 0))
    return CharacterSets.make(UnsafeMutableRawPointer(CharacterSets.setClass)) { $0.value >= start && $0.value < end }
}

@c(_CFCharacterSetCreateWithBitmapRepresentation)
public func CFCharacterSetCreateWithBitmapRepresentation(_ allocator: id?, _ data: id?) -> id? {
    let members = CharacterSets.members(fromBitmap: DataObjects.data(data))
    return CharacterSets.make(UnsafeMutableRawPointer(CharacterSets.setClass)) { members.contains($0.value) }
}

@c(_CFCharacterSetCreateBitmapRepresentation)
public func CFCharacterSetCreateBitmapRepresentation(_ allocator: id?, _ set: id?) -> id? {
    ObjC.retain(DataObjects.autoreleased(CharacterSets.bitmap(characterSet(set))))
}

@c(_CFCharacterSetAddCharactersInRange)
public func CFCharacterSetAddCharactersInRange(_ set: id?, _ location: Int, _ length: Int) {
    let start = UInt32(max(location, 0)), end = UInt32(max(location + length, 0))
    mutate(set) { old in { old($0) || ($0.value >= start && $0.value < end) } }
}

@c(_CFCharacterSetRemoveCharactersInRange)
public func CFCharacterSetRemoveCharactersInRange(_ set: id?, _ location: Int, _ length: Int) {
    let start = UInt32(max(location, 0)), end = UInt32(max(location + length, 0))
    mutate(set) { old in { old($0) && !($0.value >= start && $0.value < end) } }
}

@c(_CFCharacterSetAddCharactersInString)
public func CFCharacterSetAddCharactersInString(_ set: id?, _ string: id?) {
    let members = Set((Strings.value(of: string) ?? "").unicodeScalars.map(\.value))
    mutate(set) { old in { old($0) || members.contains($0.value) } }
}

@c(_CFCharacterSetRemoveCharactersInString)
public func CFCharacterSetRemoveCharactersInString(_ set: id?, _ string: id?) {
    let members = Set((Strings.value(of: string) ?? "").unicodeScalars.map(\.value))
    mutate(set) { old in { old($0) && !members.contains($0.value) } }
}

@c(_CFCharacterSetUnion)
public func CFCharacterSetUnion(_ set: id?, _ other: id?) {
    let theirs = characterSet(other)
    mutate(set) { old in { old($0) || theirs($0) } }
}

@c(_CFCharacterSetIntersect)
public func CFCharacterSetIntersect(_ set: id?, _ other: id?) {
    let theirs = characterSet(other)
    mutate(set) { old in { old($0) && theirs($0) } }
}

@c(_CFCharacterSetInvert)
public func CFCharacterSetInvert(_ set: id?) { mutate(set) { old in { !old($0) } } }

@c(_CFCharacterSetIsSupersetOfSet)
public func CFCharacterSetIsSupersetOfSet(_ set: id?, _ other: id?) -> Bool {
    CharacterSets.isSuperset(characterSet(set), of: characterSet(other))
}

@c(_CFCharacterSetHasMemberInPlane)
public func CFCharacterSetHasMemberInPlane(_ set: id?, _ plane: Int) -> Bool {
    plane >= 0 && plane <= 16 && CharacterSets.hasMember(characterSet(set), inPlane: UInt8(plane))
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

    @ObjCMethod("rangeOfCharacterFromSet:options:")
    func rangeOfCharacter(from set: NSCharacterSet, options: UInt) -> NSRange {
        rangeOfCharacter(from: set, options: options, range: NSRange(location: 0, length: UInt(value.utf16.count)))
    }

    /// The first (or with the backwards option 4, the last) character of
    /// the set in the range; with the anchored option 8, only at the
    /// range's start (or end).
    @ObjCMethod("rangeOfCharacterFromSet:options:range:")
    func rangeOfCharacter(from set: NSCharacterSet, options: UInt, range: NSRange) -> NSRange {
        let contains = set.contains
        let lower = Int(range.location), upper = lower + Int(range.length)
        var found: [(offset: Int, width: Int)] = []
        var offset = 0
        for scalar in value.unicodeScalars {
            let width = scalar.utf16.count
            if offset >= upper { break }
            if offset >= lower { found.append((offset, contains(scalar) ? width : 0)) }
            offset += width
        }
        let backwards = options & 4 != 0, anchored = options & 8 != 0
        let candidates = backwards ? Array(found.reversed()) : found
        for (index, candidate) in candidates.enumerated() {
            if candidate.width > 0 { return NSRange(location: UInt(candidate.offset), length: UInt(candidate.width)) }
            if anchored && index == 0 { break }
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
