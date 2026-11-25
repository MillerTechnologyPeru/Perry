import CPerryFoundation
import Glibc
import PerryObjCInterop
import Synchronization

/// An NSString's contents: its own, or for an NSMutableAttributedString's
/// -mutableString, the attributed string's characters, read and changed in
/// place.
/// A program's buffer that a mutable CFString keeps its characters in,
/// and how many of its units the string is. The program may change the
/// units in place, and the string is what the buffer holds now: games
/// lowercase a character by writing it into such a string's buffer and
/// calling CFStringLowercase.
struct ExternalCharacters {
    var characters: UnsafeMutablePointer<UInt16>
    var capacity: Int
    var count: Int

    mutating func copy(_ value: String) {
        var written = 0
        for unit in value.utf16.prefix(capacity) {
            characters[written] = unit
            written += 1
        }
        count = written
    }

    /// The buffer's units as a string.
    var string: String { String(decoding: UnsafeBufferPointer(start: characters, count: count), as: UTF16.self) }

    /// Whether the buffer holds `value`'s units.
    func holds(_ value: String) -> Bool {
        var index = 0
        for unit in value.utf16 {
            guard index < count, characters[index] == unit else { return false }
            index += 1
        }
        return index == count
    }
}

final class StringStorage {
    private var stored: String
    /// The attributed string this string is the characters of.
    var attributed: AttributedStorage?

    /// Changes only for NSMutableString.
    var value: String {
        get {
            if attributed == nil { refreshFromExternal() }
            return attributed?.string ?? stored
        }
        set {
            if let attributed { attributed.replaceChanged(with: Array(newValue.utf16)) } else { stored = newValue }
            external?.copy(newValue)
            free(cString)
            cString = nil
            asciiChecked = false
        }
    }
    /// The program's own buffer of UTF-16 units, for a mutable string made
    /// over it (CFStringCreateMutableWithExternalCharactersNoCopy): each
    /// change is written there, as much as fits.
    var external: ExternalCharacters?
    /// The program's buffer as it is now, if it was changed in place.
    private func refreshFromExternal() {
        guard let external, !external.holds(stored) else { return }
        stored = external.string
        free(cString)
        cString = nil
        asciiChecked = false
    }

    /// Whether the string has been looked at for being all ASCII, and was.
    private var asciiChecked = false
    private var isASCII = false
    private var cString: UnsafeMutablePointer<CChar>?
    /// What cString was made from, for a string changed behind its back.
    private var cStringSource: String?

    init(_ value: String) {
        stored = value
    }

    deinit {
        free(cString)
    }

    /// The UTF8String, when it is the whole string in ASCII: no other
    /// characters and no NUL. Swift reads such a string's bytes straight
    /// from it rather than a character at a time.
    var asciiPointer: UnsafePointer<CChar>? {
        guard attributed == nil else { return nil }
        refreshFromExternal()
        if !asciiChecked {
            isASCII = stored.utf8.allSatisfy { $0 != 0 && $0 < 0x80 }
            asciiChecked = true
        }
        return isASCII ? utf8 : nil
    }

    /// The UTF-16 code unit at `offset`, without copying the string's.
    func utf16Unit(at offset: Int) -> UInt16? {
        let units = value.utf16
        guard offset >= 0, offset < units.count else { return nil }
        return units[units.index(units.startIndex, offsetBy: offset)]
    }

    /// UTF8String: valid as long as the string.
    var utf8: UnsafePointer<CChar> {
        let current = value
        if let cString, attributed == nil || cStringSource == current { return UnsafePointer(cString) }
        free(cString)
        let created = strdup(current)!
        cString = created
        cStringSource = attributed == nil ? nil : current
        return UnsafePointer(created)
    }
}

enum Strings {
    nonisolated(unsafe) static var stringClass: Class!
    nonisolated(unsafe) static var constantClass: Class!

    /// String literals: { isa, flags, characters, length }. Flag 0x10 marks
    /// UTF-16 characters; otherwise they are NUL-terminated ASCII.
    private static func constantValue(_ object: id) -> String {
        let flags = object.load(fromByteOffset: DarwinLayout.stringFlags, as: UInt.self)
        let characters = object.load(fromByteOffset: DarwinLayout.stringCharacters, as: UnsafeRawPointer?.self)
        let length = object.load(fromByteOffset: DarwinLayout.stringLength, as: Int.self)
        guard let characters, length > 0 else { return "" }
        if flags & 0x10 != 0 {
            return String(decoding: UnsafeBufferPointer(start: characters.assumingMemoryBound(to: UInt16.self), count: length),
                          as: UTF16.self)
        }
        return String(decoding: UnsafeBufferPointer(start: characters.assumingMemoryBound(to: UInt8.self), count: length),
                      as: UTF8.self)
    }

    /// The contents of an NSString, or nil if `object` is not one.
    static func value(of object: id?) -> String? {
        guard let object, ObjC.isKind(object, of: stringClass) else { return nil }
        let cls = ObjC.objectGetClass(object)
        if cls == constantClass {
            return constantValue(object)
        }
        if let legacy = LegacyConstantStrings.value(object, cls) {
            return legacy
        }
        // Another library's subclass keeps its own characters, even when it
        // was made with NSString's -init.
        if let primitive = primitiveValue(of: object) {
            return primitive
        }
        return Storage.get(object, as: StringStorage.self)?.value ?? ""
    }

    nonisolated(unsafe) private static let lengthSelector = ObjC.selector("length")
    nonisolated(unsafe) private static let getCharactersSelector = ObjC.selector("getCharacters:range:")

    /// The contents of a string of a subclass this library does not
    /// define, such as Swift's bridged strings, which keep their own
    /// characters: through the primitive methods it overrides, as NSString
    /// subclasses do. Nil if it overrides none.
    private static func primitiveValue(of object: id) -> String? {
        let cls = ObjC.objectGetClass(object)
        guard ObjC.methodImplementation(cls, lengthSelector) != ObjC.methodImplementation(stringClass, lengthSelector) else {
            return nil
        }
        let length = Int(ObjC.sendUInt(object, lengthSelector))
        guard length > 0 else { return "" }
        typealias GetCharacters = @convention(c) (id?, SEL, UnsafeMutablePointer<UInt16>?, UInt, UInt) -> Void
        let units = [UInt16](unsafeUninitializedCapacity: length) { buffer, count in
            unsafeBitCast(ObjC.msgSend, to: GetCharacters.self)(object, getCharactersSelector, buffer.baseAddress, 0, UInt(length))
            count = length
        }
        return String(decoding: units, as: UTF16.self)
    }

    /// UTF-16 literals have no C string; keep one per literal, made by
    /// whichever thread asks first.
    private static let literalUTF8 = Mutex<[UInt: StringStorage]>([:])

    /// The string's own bytes when they are all ASCII without NUL, valid as
    /// long as it is and unchanging: a literal's ASCII characters, or an
    /// immutable string's UTF8String. Nil for mutable strings.
    static func asciiPointer(_ object: id) -> UnsafePointer<CChar>? {
        let cls = ObjC.objectGetClass(object)
        if cls == constantClass {
            let flags = object.load(fromByteOffset: DarwinLayout.stringFlags, as: UInt.self)
            guard flags & 0x10 == 0 else { return nil }
            return object.load(fromByteOffset: DarwinLayout.stringCharacters, as: UnsafePointer<CChar>?.self)
        }
        guard cls == stringClass else { return nil }
        return Storage.get(object, as: StringStorage.self)?.asciiPointer
    }

    static func utf8(_ object: id) -> UnsafePointer<CChar>? {
        if let legacy = LegacyConstantStrings.value(object, ObjC.objectGetClass(object)) {
            // Its bytes needn't end at its length: a C string made once.
            let key = UInt(bitPattern: object)
            return literalUTF8.withLock { literals in
                if let cached = literals[key] { return cached.utf8 }
                let storage = StringStorage(legacy)
                literals[key] = storage
                return storage.utf8
            }
        }
        if ObjC.objectGetClass(object) == constantClass {
            let flags = object.load(fromByteOffset: DarwinLayout.stringFlags, as: UInt.self)
            if flags & 0x10 == 0 {
                return object.load(fromByteOffset: DarwinLayout.stringCharacters, as: UnsafePointer<CChar>?.self)
            }
            let key = UInt(bitPattern: object)
            return literalUTF8.withLock { literals in
                if let cached = literals[key] { return cached.utf8 }
                let storage = StringStorage(constantValue(object))
                literals[key] = storage
                return storage.utf8
            }
        }
        if let storage = Storage.get(object, as: StringStorage.self) { return storage.utf8 }
        // A string Swift made, which keeps its own characters: its C string
        // lives a while, as an autoreleased one does.
        let text = value(of: object) ?? ""
        return recentUTF8.withLock { recent in
            let storage = StringStorage(text)
            recent.append(storage)
            if recent.count > 1024 { recent.removeFirst(256) }
            return storage.utf8
        }
    }

    private static let recentUTF8 = Mutex<[StringStorage]>([])

    /// A new NSString, retained (+1).
    static func make(_ value: String) -> id {
        let object = Storage.allocate(UnsafeMutableRawPointer(stringClass))!
        Storage.set(object, StringStorage(value))
        return object
    }

    /// A new autoreleased NSString, as convenience constructors return.
    static func autoreleased(_ value: String) -> id {
        ObjC.autorelease(make(value))!
    }

    /// A new autoreleased string of `cls`: convenience constructors make
    /// their receiver's class, so +[NSMutableString string] is mutable.
    static func autoreleased(_ value: String, of cls: UnsafeMutableRawPointer?) -> id {
        guard let cls, let object = Storage.allocate(cls) else { return autoreleased(value) }
        Storage.set(object, StringStorage(value))
        return ObjC.autorelease(object)!
    }

    /// FNV-1a over UTF-16, so equal strings hash equally in every process:
    /// the 64-bit or the 32-bit variant, as wide as NSUInteger.
    static func hash(_ value: String) -> UInt {
        #if _pointerBitWidth(_64)
        var hash: UInt = 0xcbf2_9ce4_8422_2325
        let prime: UInt = 0x100_0000_01b3
        #else
        var hash: UInt = 0x811c_9dc5
        let prime: UInt = 0x0100_0193
        #endif
        for unit in value.utf16 {
            hash = (hash ^ UInt(unit)) &* prime
        }
        return hash
    }

    /// NSComparisonResult for a literal (code point) comparison.
    static func compare(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs.unicodeScalars), right = Array(rhs.unicodeScalars)
        for (a, b) in zip(left, right) where a != b {
            return a.value < b.value ? -1 : 1
        }
        return left.count == right.count ? 0 : (left.count < right.count ? -1 : 1)
    }


    /// Compares runs of digits by their value ("file9" before "file10").
    static func numericCompare(_ lhs: String, _ rhs: String) -> Int {
        var a = Array(lhs.unicodeScalars)[...], b = Array(rhs.unicodeScalars)[...]
        func isDigit(_ s: Unicode.Scalar) -> Bool { ("0"..."9").contains(s) }
        while let x = a.first, let y = b.first {
            if isDigit(x) && isDigit(y) {
                let left = a.prefix(while: isDigit), right = b.prefix(while: isDigit)
                let l = left.drop { $0 == "0" }, r = right.drop { $0 == "0" }
                if l.count != r.count { return l.count < r.count ? -1 : 1 }
                for (p, q) in zip(l, r) where p != q { return p.value < q.value ? -1 : 1 }
                a = a.dropFirst(left.count)
                b = b.dropFirst(right.count)
            } else {
                if x != y { return x.value < y.value ? -1 : 1 }
                a = a.dropFirst()
                b = b.dropFirst()
            }
        }
        return a.isEmpty && b.isEmpty ? 0 : (a.isEmpty ? -1 : 1)
    }

    /// Leading integer, as -integerValue reads it ("42abc" is 42).
    static func integerPrefix(_ value: String) -> Int {
        value.withCString { strtol($0, nil, 10) }
    }
}

/// NSString.
@ObjCClass("NSString")
public class NSString: NSObject {
    /// What the Swift runtime asks to tell Foundation's classes apart.
    @ObjCMethod("isNSString__") func isNSString__() -> Bool { true }

    /// Set-up after the class is defined.
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        Strings.stringClass = cls.storage
        cls.addMethod("stringWithFormat:", types: "@24@0:8@16",
                      implementation: variadicEntry(perry_imp_stringWithFormat), isClassMethod: true)
        // Formatting isn't localized here, so it is stringWithFormat:.
        cls.addMethod("localizedStringWithFormat:", types: "@24@0:8@16",
                      implementation: variadicEntry(perry_imp_stringWithFormat), isClassMethod: true)
        cls.addMethod("initWithFormat:", types: "@24@0:8@16",
                      implementation: variadicEntry(perry_imp_initWithFormat), isClassMethod: false)
        cls.addMethod("stringByAppendingFormat:", types: "@24@0:8@16",
                      implementation: variadicEntry(perry_imp_stringByAppendingFormat), isClassMethod: false)
        cls.addMethod("initWithFormat:locale:", types: "@32@0:8@16@24",
                      implementation: variadicEntry(perry_imp_initWithFormatLocale), isClassMethod: false)
        // Five fixed arguments: armv7's entry points take four.
        #if !arch(arm)
        cls.addMethod("stringWithValidatedFormat:validFormatSpecifiers:error:", types: "@40@0:8@16@24^@32",
                      implementation: variadicEntry(perry_imp_stringWithValidatedFormat), isClassMethod: true)
        // Formatting isn't localized here, so it is stringWithValidatedFormat:….
        cls.addMethod("localizedStringWithValidatedFormat:validFormatSpecifiers:error:", types: "@40@0:8@16@24^@32",
                      implementation: variadicEntry(perry_imp_stringWithValidatedFormat), isClassMethod: true)
        cls.addMethod("initWithValidatedFormat:validFormatSpecifiers:error:", types: "@40@0:8@16@24^@32",
                      implementation: variadicEntry(perry_imp_initWithValidatedFormat), isClassMethod: false)
        #endif
        // Six: x86_64's take five.
        #if !arch(arm) && !arch(x86_64)
        cls.addMethod("initWithValidatedFormat:validFormatSpecifiers:locale:error:", types: "@48@0:8@16@24@32^@40",
                      implementation: variadicEntry(perry_imp_initWithValidatedFormatLocale), isClassMethod: false)
        #endif
    }

    /// The receiver's contents.
    var value: String { Strings.value(of: objcObject) ?? "" }

    private func setValue(_ value: String) -> Self {
        Storage.set(objcObject, StringStorage(value))
        return self
    }

    // MARK: Creating

    /// Swift's standard library bridges a short ASCII string through this,
    /// for a tagged-pointer string; strings here are objects, which it takes
    /// as well. Returned retained, as its name says.
    @ObjCClassMethod("newTaggedNSStringWithASCIIBytes_:length_:")
    static func newTaggedString(_ cls: ObjCClass, bytes: UnsafePointer<UInt8>?, length: Int) -> UnsafeMutableRawPointer? {
        guard let bytes else { return nil }
        return Strings.make(String(decoding: UnsafeBufferPointer(start: bytes, count: length), as: UTF8.self))
    }

    @ObjCClassMethod("string")
    static func empty(_ cls: ObjCClass) -> ObjCObject { ObjCObject(Strings.autoreleased("", of: cls.pointer)) }

    @ObjCClassMethod("stringWithString:")
    static func string(_ cls: ObjCClass, with other: String) -> ObjCObject {
        ObjCObject(Strings.autoreleased(other, of: cls.pointer))
    }

    /// UserNotifications' addition: the main bundle's string for the key,
    /// with each `%@` (or `%n$@`) replaced by an argument's description in
    /// turn, as a notification's text is localized when it is shown.
    @ObjCClassMethod("localizedUserNotificationStringForKey:arguments:")
    static func localizedUserNotificationString(_ cls: ObjCClass, forKey key: id?, arguments: id?) -> ObjCObject {
        let localized = unsafeBitCast(ObjC.msgSend, to: (@convention(c) (id?, SEL, id?, id?, id?) -> id?).self)(
            Bundles.main, ObjC.selector("localizedStringForKey:value:table:"), key, nil, nil)
        let format = Strings.value(of: localized) ?? Strings.value(of: key) ?? ""
        let values = Arrays.elements(arguments).map { Strings.value(of: $0) ?? Format.describe($0) }
        var text = "", next = 0
        var scalars = format.unicodeScalars[...]
        while let first = scalars.first {
            scalars = scalars.dropFirst()
            guard first == "%" else { text.unicodeScalars.append(first); continue }
            if scalars.first == "%" { text += "%"; scalars = scalars.dropFirst(); continue }
            // An optional position, then the conversion.
            let digits = scalars.prefix { ("0"..."9").contains($0) }
            var position: Int?
            var rest = scalars
            if !digits.isEmpty, rest.dropFirst(digits.count).first == "$" {
                position = Int(String(String.UnicodeScalarView(digits))).map { $0 - 1 }
                rest = rest.dropFirst(digits.count + 1)
            }
            guard let conversion = rest.first, conversion == "@" else { text += "%"; continue }
            scalars = rest.dropFirst()
            let index = position ?? next
            next = index + 1
            text += index < values.count ? values[index] : ""
        }
        return ObjCObject(Strings.autoreleased(text, of: cls.pointer))
    }

    @ObjCClassMethod("stringWithUTF8String:")
    static func string(_ cls: ObjCClass, utf8 bytes: UnsafePointer<CChar>?) -> ObjCObject? {
        bytes.map { ObjCObject(Strings.autoreleased(String(cString: $0), of: cls.pointer)) }
    }

    @ObjCMethod("init")
    func initialize() -> Self { setValue("") }

    /// The contents of `other`; an object that is not one of this library's
    /// strings, such as a string Swift made, is read through its UTF-8.
    @ObjCMethod("initWithString:")
    func initialize(string other: UnsafeMutableRawPointer?) -> Self {
        if let value = Strings.value(of: other) { return setValue(value) }
        if let other, let bytes = ObjC.sendPointer(other, ObjC.selector("UTF8String")) {
            return setValue(String(cString: bytes.assumingMemoryBound(to: CChar.self)))
        }
        return setValue("")
    }

    @ObjCMethod("initWithUTF8String:")
    func initialize(utf8 bytes: UnsafePointer<CChar>?) -> Self? { bytes.map { setValue(String(cString: $0)) } }

    /// NSStringEncoding; String's own conversion to NSString relies on this.
    @ObjCMethod("initWithBytes:length:encoding:")
    func initialize(bytes: UnsafeRawPointer?, length: UInt, encoding: UInt) -> Self? {
        StringEncoding.decode(UnsafeRawBufferPointer(start: bytes, count: Int(length)), encoding).map(setValue)
    }

    /// The bytes are copied, so the string frees them at once when it would
    /// own them. A string that cannot be made leaves them to the caller.
    @ObjCMethod("initWithBytesNoCopy:length:encoding:freeWhenDone:")
    func initialize(bytesNoCopy bytes: UnsafeMutableRawPointer?, length: UInt, encoding: UInt, freeWhenDone: Bool) -> Self? {
        guard let string = initialize(bytes: bytes, length: length, encoding: encoding) else { return nil }
        if freeWhenDone { free(bytes) }
        return string
    }

    /// A Darwin va_list is a pointer to the argument slots.
    @ObjCMethod("initWithFormat:arguments:", types: "@32@0:8@16*24")
    func initialize(format: String, arguments: UnsafeRawPointer?) -> Self {
        guard let arguments else { return setValue(format) }
        var darwin = DarwinArguments(arguments)
        return setValue(Format.string(format, &darwin))
    }

    /// Formats as initWithFormat:arguments: does; the locale is not applied.
    @ObjCMethod("initWithFormat:locale:arguments:", types: "@40@0:8@16@24*32")
    func initialize(format: String, locale: ObjCObject?, arguments: UnsafeRawPointer?) -> Self {
        initialize(format: format, arguments: arguments)
    }

    /// The format with the arguments, when it takes only arguments the
    /// valid specifiers take, each where and of the type they take it;
    /// otherwise nil and NSFormattingError (2048).
    @ObjCMethod("initWithValidatedFormat:validFormatSpecifiers:arguments:error:", types: "@48@0:8@16@24*32^@40")
    func initialize(validatedFormat format: ObjCObject?, validFormatSpecifiers valid: ObjCObject?, arguments: UnsafeRawPointer?,
                    error: UnsafeMutablePointer<id?>?) -> Self? {
        ValidatedFormats.string(format?.id, valid?.id, arguments, error).map(setValue)
    }

    /// As without the locale, which is not applied.
    @ObjCMethod("initWithValidatedFormat:validFormatSpecifiers:locale:arguments:error:", types: "@56@0:8@16@24@32*40^@48")
    func initialize(validatedFormat format: ObjCObject?, validFormatSpecifiers valid: ObjCObject?, locale: ObjCObject?,
                    arguments: UnsafeRawPointer?, error: UnsafeMutablePointer<id?>?) -> Self? {
        ValidatedFormats.string(format?.id, valid?.id, arguments, error).map(setValue)
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: Strings.stringClass)
    }

    // MARK: Contents

    @ObjCMethod("length")
    func length() -> UInt { UInt(value.utf16.count) }

    @ObjCMethod("characterAtIndex:")
    func character(at index: UInt) -> UInt16 {
        let units = value.utf16
        guard Int(index) < units.count else {
            Exceptions.raise(name: "NSRangeException", reason: "-[NSString characterAtIndex:]: Range or index out of bounds")
        }
        return units[units.index(units.startIndex, offsetBy: Int(index))]
    }

    @ObjCMethod("UTF8String")
    func utf8String() -> UnsafePointer<CChar>? { Strings.utf8(objcObject) }

    /// Before -UTF8String's day; the default C string encoding here is UTF-8.
    @ObjCMethod("cString")
    func cString() -> UnsafePointer<CChar>? { Strings.utf8(objcObject) }

    @ObjCMethod("description")
    func description() -> NSString { self }

    @ObjCMethod("copy")
    func copy() -> NSString { self }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> NSString { self }

    @ObjCMethod("mutableCopyWithZone:")
    func mutableCopy(zone: UnsafeMutableRawPointer?) -> ObjCObject {
        ObjCObject(objCOwned: MutableStrings.make(value))
    }

    // MARK: Comparing

    @ObjCMethod("isEqual:")
    func isEqual(_ other: ObjCObject?) -> Bool {
        guard let other else { return false }
        return other.objcObject == objcObject || Strings.value(of: other.objcObject) == value
    }

    @ObjCMethod("isEqualToString:")
    func isEqual(toString other: String?) -> Bool { other == value }

    @ObjCMethod("hash")
    func hash() -> UInt { Strings.hash(value) }

    @ObjCMethod("compare:")
    // A nil argument, which -[NSString compare:] raises on, is taken as the
    // empty string here: a nil in a sorted collection orders first rather
    // than aborting the sort.
    func compare(_ other: String?) -> Int { Strings.compare(value, other ?? "") }

    @ObjCMethod("hasPrefix:")
    func hasPrefix(_ prefix: String) -> Bool { value.hasPrefix(prefix) }

    @ObjCMethod("hasSuffix:")
    func hasSuffix(_ suffix: String) -> Bool { value.hasSuffix(suffix) }

    // MARK: Deriving

    @ObjCMethod("stringByAppendingString:")
    func appending(_ other: String) -> String { value + other }

    /// Cut or padded to `length` UTF-16 units, the pad repeating from
    /// `start`, as Foundation's.
    @ObjCMethod("stringByPaddingToLength:withString:startingAtIndex:")
    func padding(toLength length: UInt, with pad: String, startingAt start: UInt) -> String {
        var units = Array(value.utf16)
        if units.count >= Int(length) { return String(decoding: units.prefix(Int(length)), as: UTF16.self) }
        let padUnits = Array(pad.utf16)
        guard !padUnits.isEmpty else { return value }
        var index = Int(start) % padUnits.count
        while units.count < Int(length) {
            units.append(padUnits[index])
            index = (index + 1) % padUnits.count
        }
        return String(decoding: units, as: UTF16.self)
    }

    @ObjCMethod("uppercaseString")
    func uppercased() -> String { value.uppercased() }

    @ObjCMethod("lowercaseString")
    func lowercased() -> String { value.lowercased() }

    @ObjCMethod("integerValue")
    func integerValue() -> Int { Strings.integerPrefix(value) }

    @ObjCMethod("intValue")
    func intValue() -> Int32 { Int32(truncatingIfNeeded: Strings.integerPrefix(value)) }

    @ObjCMethod("doubleValue")
    func doubleValue() -> Double { value.withCString { strtod($0, nil) } }
}

/// String literals: { isa, flags, characters, length }, read in place.
@ObjCClass("__NSCFConstantString")
final class NSCFConstantString: NSString {
    /// Set-up after the class is defined.
    override class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryImmortal(cls)
        Strings.constantClass = cls.markingStatic().storage
    }
}

// MARK: - Variadic methods

@c
public func perry_foundation_stringWithFormat(_ cls: id?, _ cmd: SEL?, _ format: id?,
                                              _ arguments: UnsafeRawPointer?) -> id? {
    guard let arguments else { return nil }
    var darwin = DarwinArguments(arguments)
    return Strings.autoreleased(Format.string(Strings.value(of: format) ?? "", &darwin), of: cls)
}

@c
public func perry_foundation_initWithFormat(_ object: id?, _ cmd: SEL?, _ format: id?,
                                            _ arguments: UnsafeRawPointer?) -> id? {
    guard let object, let arguments else { return object }
    var darwin = DarwinArguments(arguments)
    Storage.set(object, StringStorage(Format.string(Strings.value(of: format) ?? "", &darwin)))
    return object
}

@c
public func perry_foundation_stringByAppendingFormat(_ object: id?, _ cmd: SEL?, _ format: id?,
                                                     _ arguments: UnsafeRawPointer?) -> id? {
    guard let arguments else { return nil }
    var darwin = DarwinArguments(arguments)
    let suffix = Format.string(Strings.value(of: format) ?? "", &darwin)
    return Strings.autoreleased((Strings.value(of: object) ?? "") + suffix)
}

/// - (instancetype)initWithFormat:(NSString *)format locale:(id)locale, ...:
/// formatted as -initWithFormat: formats; the locale is not applied.
@c
public func perry_foundation_initWithFormatLocale(_ object: id?, _ cmd: SEL?, _ format: id?, _ locale: id?,
                                                  _ arguments: UnsafeRawPointer?) -> id? {
    perry_foundation_initWithFormat(object, cmd, format, arguments)
}

/// + (instancetype)stringWithValidatedFormat:validFormatSpecifiers:error:, ...
/// and +localizedStringWithValidatedFormat:…: nil and the error when the
/// format doesn't match the valid specifiers.
@c
public func perry_foundation_stringWithValidatedFormat(_ cls: id?, _ cmd: SEL?, _ format: id?, _ valid: id?,
                                                       _ error: UnsafeMutablePointer<id?>?, _ arguments: UnsafeRawPointer?) -> id? {
    ValidatedFormats.string(format, valid, arguments, error).map { Strings.autoreleased($0, of: cls) }
}

/// - (instancetype)initWithValidatedFormat:validFormatSpecifiers:error:, ...
@c
public func perry_foundation_initWithValidatedFormat(_ object: id?, _ cmd: SEL?, _ format: id?, _ valid: id?,
                                                     _ error: UnsafeMutablePointer<id?>?, _ arguments: UnsafeRawPointer?) -> id? {
    guard let object else { return nil }
    guard let text = ValidatedFormats.string(format, valid, arguments, error) else {
        ObjC.release(object)
        return nil
    }
    Storage.set(object, StringStorage(text))
    return object
}

/// - (instancetype)initWithValidatedFormat:validFormatSpecifiers:locale:error:, ...:
/// the locale is not applied.
@c
public func perry_foundation_initWithValidatedFormatLocale(_ object: id?, _ cmd: SEL?, _ format: id?, _ valid: id?, _ locale: id?,
                                                           _ error: UnsafeMutablePointer<id?>?, _ arguments: UnsafeRawPointer?) -> id? {
    perry_foundation_initWithValidatedFormat(object, cmd, format, valid, error, arguments)
}

/// Formats checked against the specifiers a program says are valid.
enum ValidatedFormats {
    /// The formatted string, when the format takes only arguments the
    /// valid specifiers take (a format may take fewer); else nil and
    /// NSFormattingError, as CFStringCreateStringWithValidatedFormat.
    static func string(_ format: id?, _ valid: id?, _ arguments: UnsafeRawPointer?, _ error: UnsafeMutablePointer<id?>?) -> String? {
        let text = Strings.value(of: format) ?? "", allowed = Strings.value(of: valid) ?? ""
        guard CFStringMore.validate(text, against: allowed) else {
            error?.pointee = Errors.autoreleased(domain: Errors.cocoaDomain, code: 2048,
                                                 description: "Format \u{2018}\(text)\u{2019} does not match valid format specifiers \u{2018}\(allowed)\u{2019}")
            return nil
        }
        error?.pointee = nil
        guard let arguments else { return text }
        var darwin = DarwinArguments(arguments)
        return Format.string(text, &darwin)
    }
}
