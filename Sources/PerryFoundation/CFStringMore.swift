import CPerryFoundation
import FoundationEssentials
import Glibc
import PerryObjCInterop

// The rest of CFString: Pascal strings, searching with the options NSString
// leaves out (diacritics and widths) and for characters of a set, folding
// and normalizing, line and paragraph bounds, character clusters, the list
// of encodings, hashes and formats checked against the specifiers allowed.

/// kCFNotFound.
private let stringNotFound = -1

/// kCFStringEncodingInvalidId.
private let invalidEncoding: UInt32 = 0xFFFF_FFFF

enum CFStringMore {
    // CFStringCompareFlags beyond those CFStrings.find passes on.
    static let caseInsensitive: UInt = 1, backwards: UInt = 4, anchored: UInt = 8
    static let diacriticInsensitive: UInt = 128, widthInsensitive: UInt = 256

    /// The range, kept within `count` units.
    static func clamp(_ range: CFRange, _ count: Int) -> Range<Int> {
        let start = max(0, min(range.location, count))
        return start..<max(start, min(start + max(0, range.length), count))
    }

    // MARK: Normalization

    /// Text in a CFStringNormalizationForm, by ICU: D 0, KD 1, C 2, KC 3.
    /// Text ICU can't normalize is given back as it is.
    static func normalize(_ text: String, _ form: Int) -> String {
        var status: Int32 = 0
        let normalizer: UnsafeRawPointer?
        switch form {
        case 0: normalizer = swift_unorm2_getNFDInstance(&status)
        case 1: normalizer = swift_unorm2_getNFKDInstance(&status)
        case 2: normalizer = swift_unorm2_getNFCInstance(&status)
        case 3: normalizer = swift_unorm2_getNFKCInstance(&status)
        default: return text
        }
        guard let normalizer, status <= 0 else { return text }
        let units = Array(text.utf16)
        guard !units.isEmpty else { return text }
        var result = [UInt16](repeating: 0, count: units.count * 4 + 16)
        var length = swift_unorm2_normalize(normalizer, units, Int32(units.count), &result, Int32(result.count), &status)
        if status == 15 {   // U_BUFFER_OVERFLOW_ERROR: it says how long
            status = 0
            result = [UInt16](repeating: 0, count: Int(length) + 1)
            length = swift_unorm2_normalize(normalizer, units, Int32(units.count), &result, Int32(result.count), &status)
        }
        guard status <= 0, length >= 0 else { return text }
        return String(decoding: result.prefix(Int(length)), as: UTF16.self)
    }

    // MARK: Folding

    /// Full case foldings that a character's lowercase mapping doesn't give.
    static let caseFoldings: [UInt32: String] = [
        0x00DF: "ss", 0x1E9E: "ss", 0x017F: "s", 0x03C2: "\u{03C3}", 0x03D0: "\u{03B2}", 0x03D1: "\u{03B8}",
        0x03D5: "\u{03C6}", 0x03D6: "\u{03C0}", 0x03F0: "\u{03BA}", 0x03F1: "\u{03C1}", 0x03F5: "\u{03B5}",
        0x1E9B: "\u{1E61}", 0x0345: "\u{03B9}", 0x1FBE: "\u{03B9}", 0x0130: "i\u{0307}", 0x0149: "\u{02BC}n",
        0xFB00: "ff", 0xFB01: "fi", 0xFB02: "fl", 0xFB03: "ffi", 0xFB04: "ffl", 0xFB05: "st", 0xFB06: "st",
    ]

    /// Whether a locale folds case as Turkish and Azerbaijani do (I to ı,
    /// İ to i). A NULL locale is no language's.
    static func foldsTurkic(_ locale: id?) -> Bool {
        guard locale != nil, let language = Locales.locale(locale).language.languageCode?.identifier else { return false }
        return language == "tr" || language == "az"
    }

    /// One character folded as the flags say: widths (fullwidth ASCII and
    /// halfwidth kana to their usual forms), diacritics (nonspacing marks
    /// removed from its canonical decomposition), then case (Unicode's full
    /// case folding).
    static func fold(_ scalar: Unicode.Scalar, _ flags: UInt, turkic: Bool) -> String {
        var text = String(scalar)
        if flags & widthInsensitive != 0 {
            let value = scalar.value
            if (0xFF01...0xFF5E).contains(value) {
                text = String(Unicode.Scalar(value - 0xFEE0)!)
            } else if value == 0x3000 {
                text = " "
            } else if (0xFF61...0xFFDC).contains(value) || (0xFFE0...0xFFEE).contains(value) {
                text = normalize(text, 3)
            }
        }
        if flags & diacriticInsensitive != 0 {
            var stripped = String.UnicodeScalarView()
            for part in normalize(text, 0).unicodeScalars where part.properties.generalCategory != .nonspacingMark {
                stripped.append(part)
            }
            text = String(stripped)
        }
        if flags & caseInsensitive != 0 {
            var folded = ""
            for part in text.unicodeScalars {
                if turkic, part == "I" {
                    folded += "\u{0131}"
                } else if turkic, part.value == 0x0130 {
                    folded += "i"
                } else if let special = caseFoldings[part.value] {
                    folded += special
                } else if part.properties.changesWhenCaseFolded {
                    folded += part.properties.lowercaseMapping
                } else {
                    folded.unicodeScalars.append(part)
                }
            }
            text = folded
        }
        return text
    }

    /// Text folded character by character, each folded unit knowing where
    /// its character starts and ends in the original's UTF-16 units. A unit
    /// that doesn't start (or end) a character's folding has -1; a character
    /// that folds to nothing (a removed mark) joins the one before.
    struct Folded {
        var units: [UInt16] = []
        var begins: [Int] = []
        var ends: [Int] = []
    }

    static func folded(_ units: ArraySlice<UInt16>, offset: Int, _ flags: UInt, turkic: Bool) -> Folded {
        var result = Folded()
        var position = offset
        for scalar in String(decoding: units, as: UTF16.self).unicodeScalars {
            let width = scalar.utf16.count
            let piece = Array(fold(scalar, flags, turkic: turkic).utf16)
            if piece.isEmpty {
                if let last = result.ends.indices.last, result.ends[last] != -1 { result.ends[last] = position + width }
            } else {
                for (index, unit) in piece.enumerated() {
                    result.units.append(unit)
                    result.begins.append(index == 0 ? position : -1)
                    result.ends.append(index == piece.count - 1 ? position + width : -1)
                }
            }
            position += width
        }
        return result
    }

    // MARK: Searching

    /// A search as CFStringFindWithOptions makes it, and with diacritics or
    /// widths ignored, or case folded as a Turkic locale folds it, through
    /// the folded text, matching whole characters. Other locales' rules
    /// aren't consulted.
    static func find(_ string: id?, _ target: id?, _ range: CFRange, _ flags: UInt, _ locale: id?) -> CFRange {
        let turkic = flags & caseInsensitive != 0 && foldsTurkic(locale)
        guard flags & (diacriticInsensitive | widthInsensitive) != 0 || turkic else {
            return CFStrings.find(string, target, range, flags)
        }
        let units = CFStrings.units(string)
        let scope = clamp(range, units.count)
        let text = folded(units[scope], offset: scope.lowerBound, flags, turkic: turkic)
        let pattern = folded(CFStrings.units(target)[...], offset: 0, flags, turkic: turkic).units
        let none = CFRange(location: stringNotFound, length: 0)
        guard !pattern.isEmpty, pattern.count <= text.units.count else { return none }
        var starts = Array(0...(text.units.count - pattern.count))
        if flags & backwards != 0 { starts.reverse() }
        if flags & anchored != 0 { starts = [starts[0]] }
        for start in starts {
            let end = start + pattern.count - 1
            guard text.begins[start] != -1, text.ends[end] != -1,
                  text.units[start...end].elementsEqual(pattern) else { continue }
            return CFRange(location: text.begins[start], length: text.ends[end] - text.begins[start])
        }
        return none
    }

    // MARK: Bounds

    static func isLineSeparator(_ unit: UInt16, paragraphs: Bool) -> Bool {
        switch unit {
        case 0x0A, 0x0D, 0x85, 0x2029: return true
        case 0x2028: return !paragraphs
        default: return false
        }
    }

    /// The lines (or paragraphs) holding the range: where the first starts,
    /// where the last ends past its terminator, and where its contents end.
    /// A CR LF pair is one terminator.
    static func bounds(_ string: id?, _ range: CFRange, paragraphs: Bool, _ begin: UnsafeMutablePointer<Int>?,
                       _ end: UnsafeMutablePointer<Int>?, _ contentsEnd: UnsafeMutablePointer<Int>?) {
        let units = CFStrings.units(string)
        let count = units.count
        let scope = clamp(range, count)
        func separator(_ index: Int) -> Bool { isLineSeparator(units[index], paragraphs: paragraphs) }
        func insideCRLF(_ index: Int) -> Bool { index > 0 && index < count && units[index] == 0x0A && units[index - 1] == 0x0D }
        if let begin {
            var start = scope.lowerBound
            if insideCRLF(start) { start -= 1 }
            while start > 0, !separator(start - 1) { start -= 1 }
            begin.pointee = start
        }
        guard end != nil || contentsEnd != nil else { return }
        var index = scope.isEmpty ? scope.lowerBound : scope.upperBound - 1
        if insideCRLF(index) { index -= 1 }
        while index < count, !separator(index) { index += 1 }
        contentsEnd?.pointee = index
        if index < count {
            end?.pointee = units[index] == 0x0D && index + 1 < count && units[index + 1] == 0x0A ? index + 2 : index + 1
        } else {
            end?.pointee = count
        }
    }

    /// The range of the grapheme cluster (Swift's Character) holding a
    /// UTF-16 index, or {kCFNotFound, 0} past the end.
    static func cluster(_ string: id?, _ index: Int) -> CFRange {
        let units = CFStrings.units(string)
        guard index >= 0, index < units.count else { return CFRange(location: stringNotFound, length: 0) }
        var start = 0
        for character in CFStrings.string(units) {
            let width = character.utf16.count
            if index < start + width { return CFRange(location: start, length: width) }
            start += width
        }
        return CFRange(location: index, length: 1)
    }

    // MARK: Formats

    /// What a format's conversion takes from the arguments.
    enum Argument: Equatable {
        case int32, int64, double, object, cString, uniString, pointer
    }

    /// The arguments a printf-style format takes, by position (1 up), or nil
    /// if a conversion is unknown or a position is taken as two types.
    static func arguments(_ format: String) -> [Int: Argument]? {
        let bytes = Array(format.utf8)
        var result: [Int: Argument] = [:]
        var index = 0, next = 1
        func isDigit(_ byte: UInt8) -> Bool { (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) }
        func record(_ position: Int, _ argument: Argument) -> Bool {
            if let old = result[position], old != argument { return false }
            result[position] = argument
            return true
        }
        func sequential() -> Int {
            defer { next += 1 }
            return next
        }
        while index < bytes.count {
            guard bytes[index] == UInt8(ascii: "%") else {
                index += 1
                continue
            }
            index += 1
            guard index < bytes.count else { return nil }
            if bytes[index] == UInt8(ascii: "%") {
                index += 1
                continue
            }
            var digits = index
            while digits < bytes.count, isDigit(bytes[digits]) { digits += 1 }
            var position: Int?
            if digits > index, digits < bytes.count, bytes[digits] == UInt8(ascii: "$") {
                position = Int(String(decoding: bytes[index..<digits], as: UTF8.self))
                index = digits + 1
            }
            while index < bytes.count, "-+ #'0".utf8.contains(bytes[index]) { index += 1 }
            if index < bytes.count, bytes[index] == UInt8(ascii: "*") {
                index += 1
                guard record(sequential(), .int32) else { return nil }
            } else {
                while index < bytes.count, isDigit(bytes[index]) { index += 1 }
            }
            if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
                index += 1
                if index < bytes.count, bytes[index] == UInt8(ascii: "*") {
                    index += 1
                    guard record(sequential(), .int32) else { return nil }
                } else {
                    while index < bytes.count, isDigit(bytes[index]) { index += 1 }
                }
            }
            var length = ""
            while index < bytes.count, "hlqLzjt".utf8.contains(bytes[index]) {
                length.append(Character(Unicode.Scalar(bytes[index])))
                index += 1
            }
            guard index < bytes.count else { return nil }
            let conversion = bytes[index]
            index += 1
            let wide = ["ll", "q", "j"].contains(length) || (["l", "z", "t"].contains(length) && MemoryLayout<Int>.size == 8)
            let argument: Argument
            switch conversion {
            case UInt8(ascii: "d"), UInt8(ascii: "i"), UInt8(ascii: "u"), UInt8(ascii: "o"),
                 UInt8(ascii: "x"), UInt8(ascii: "X"), UInt8(ascii: "D"), UInt8(ascii: "U"), UInt8(ascii: "O"):
                argument = wide ? .int64 : .int32
            case UInt8(ascii: "c"), UInt8(ascii: "C"): argument = .int32
            case UInt8(ascii: "f"), UInt8(ascii: "F"), UInt8(ascii: "e"), UInt8(ascii: "E"),
                 UInt8(ascii: "g"), UInt8(ascii: "G"), UInt8(ascii: "a"), UInt8(ascii: "A"): argument = .double
            case UInt8(ascii: "@"): argument = .object
            case UInt8(ascii: "s"): argument = .cString
            case UInt8(ascii: "S"): argument = .uniString
            case UInt8(ascii: "p"): argument = .pointer
            default: return nil
            }
            guard record(position ?? sequential(), argument) else { return nil }
        }
        return result
    }

    /// Whether `format` takes only arguments `valid` takes, each where it
    /// takes it and of its type.
    static func validate(_ format: String, against valid: String) -> Bool {
        guard let used = arguments(format), let allowed = arguments(valid) else { return false }
        return used.allSatisfy { allowed[$0.key] == $0.value }
    }

    /// A formatted string, +1, once the format is found to take what the
    /// valid specifiers take; else NULL, with a CFError (+1) in `error`.
    static func validatedString(_ allocator: UnsafeRawPointer?, _ options: id?, _ valid: id?, _ format: id?,
                                _ arguments: UnsafeRawPointer?, _ error: UnsafeMutablePointer<id?>?) -> id? {
        let text = CFStrings.value(format), allowed = CFStrings.value(valid)
        guard validate(text, against: allowed) else {
            error?.pointee = ObjC.autoreleasepool {
                ObjC.retain(Errors.autoreleased(domain: Errors.cocoaDomain, code: 2048,   // NSFormattingError
                                                description: "Format '\(text)' does not match valid format specifiers '\(allowed)'"))
            }
            return nil
        }
        error?.pointee = nil
        return CFStringCreateWithFormatAndArguments(allocator, options, format, arguments)
    }
}

// MARK: - Pascal strings

/// Appends a Pascal string (a length byte, then the bytes) in an encoding;
/// bytes that don't decode append nothing.
@c(_CFStringAppendPascalString)
public func CFStringAppendPascalString(_ string: id?, _ pascal: UnsafePointer<UInt8>?, _ encoding: UInt32) {
    guard let pascal, let text = CFStringEncodings.decode(UnsafeRawBufferPointer(start: pascal + 1, count: Int(pascal[0])), encoding)
    else { return }
    CFStrings.mutate(string) { $0 += text }
}

/// A string from a Pascal string, +1: its bytes are copied here, so the
/// deallocator is never called, which Darwin allows.
@c(_CFStringCreateWithPascalStringNoCopy)
public func CFStringCreateWithPascalStringNoCopy(_ allocator: UnsafeRawPointer?, _ pascal: UnsafePointer<UInt8>?, _ encoding: UInt32,
                                                 _ deallocator: UnsafeRawPointer?) -> id? {
    CFStringCreateWithPascalString(allocator, pascal, encoding)
}

/// NULL: no string here is kept as a Pascal string, and Darwin returns
/// NULL for those that aren't; callers then use CFStringGetPascalString.
@c(_CFStringGetPascalStringPtr)
public func CFStringGetPascalStringPtr(_ string: id?, _ encoding: UInt32) -> UnsafePointer<UInt8>? { nil }

// MARK: - Searching

/// The ranges of every occurrence of `target` in the range, as an array of
/// CFRange pointers (the array copies and frees them), in the order found:
/// backwards with kCFCompareBackwards, and only one when anchored. NULL
/// when there are none.
@DarwinC("_CFStringCreateArrayWithFindResults")
public func CFStringCreateArrayWithFindResults(_ allocator: UnsafeRawPointer?, _ string: id?, _ target: id?, _ range: CFRange,
                                               _ flags: UInt) -> id? {
    let scope = CFStringMore.clamp(range, CFStrings.units(string).count)
    var ranges: [CFRange] = []
    var lower = scope.lowerBound, upper = scope.upperBound
    while lower < upper {
        let found = CFStringMore.find(string, target, CFRange(location: lower, length: upper - lower), flags, nil)
        guard found.location != stringNotFound, found.length > 0 else { break }
        ranges.append(found)
        if flags & CFStringMore.anchored != 0 { break }
        if flags & CFStringMore.backwards != 0 { upper = found.location } else { lower = found.location + found.length }
    }
    guard !ranges.isEmpty else { return nil }
    var callbacks = CFCallbacks(nil, hashed: false)
    callbacks.retain = rangeRetain
    callbacks.release = rangeRelease
    callbacks.equal = rangeEqual
    let storage = CFCollectionStorage(keyCallbacks: callbacks)
    storage.keys = ranges.map { range in withUnsafePointer(to: range) { callbacks.retained(UnsafeRawPointer($0)) } }
    return CFCollections.make(CFCollections.arrayClass, storage)
}

/// A find result array's callbacks: each value is its own CFRange, copied
/// as it is retained, freed as it is released.
private let rangeRetain: CFCallbacks.Retain = { _, value in
    guard let value else { return nil }
    let copy = UnsafeMutablePointer<CFRange>.allocate(capacity: 1)
    copy.initialize(to: value.load(as: CFRange.self))
    return UnsafeRawPointer(copy)
}

private let rangeRelease: CFCallbacks.Release = { _, value in
    guard let value else { return }
    UnsafeMutablePointer(mutating: value.assumingMemoryBound(to: CFRange.self)).deallocate()
}

private let rangeEqual: CFCallbacks.Equal = { a, b in
    guard let a, let b else { return a == b ? 1 : 0 }
    let x = a.load(as: CFRange.self), y = b.load(as: CFRange.self)
    return x.location == y.location && x.length == y.length ? 1 : 0
}

/// The first character in the range that is in the set (the last with
/// kCFCompareBackwards; with kCFCompareAnchored, only the one at the
/// range's start or end), a surrogate pair counting as one.
@DarwinC("_CFStringFindCharacterFromSet")
public func CFStringFindCharacterFromSet(_ string: id?, _ set: id?, _ range: CFRange, _ flags: UInt,
                                         _ result: UnsafeMutablePointer<CFRange>?) -> Bool {
    let contains: (Unicode.Scalar) -> Bool
    if let storage = CharacterSets.storage(set) {
        contains = storage.contains
    } else {
        typealias Member = @convention(c) (id?, SEL, UInt32) -> Bool
        let selector = ObjC.selector("longCharacterIsMember:")
        contains = { unsafeBitCast(ObjC.msgSend, to: Member.self)(set, selector, $0.value) }
    }
    let units = CFStrings.units(string)
    let scope = CFStringMore.clamp(range, units.count)
    var characters: [(offset: Int, width: Int, scalar: Unicode.Scalar)] = []
    var offset = scope.lowerBound
    for scalar in String(decoding: units[scope], as: UTF16.self).unicodeScalars {
        characters.append((offset, scalar.utf16.count, scalar))
        offset += scalar.utf16.count
    }
    if flags & CFStringMore.backwards != 0 { characters.reverse() }
    if flags & CFStringMore.anchored != 0 { characters = Array(characters.prefix(1)) }
    guard let found = characters.first(where: { contains($0.scalar) }) else { return false }
    result?.pointee = CFRange(location: found.offset, length: found.width)
    return true
}

/// CFStringFindWithOptions with kCFCompareDiacriticInsensitive and
/// kCFCompareWidthInsensitive too, and the locale's case folding for
/// Turkish and Azerbaijani; other locales search as no locale does.
@DarwinC("_CFStringFindWithOptionsAndLocale")
public func CFStringFindWithOptionsAndLocale(_ string: id?, _ target: id?, _ range: CFRange, _ flags: UInt, _ locale: id?,
                                             _ result: UnsafeMutablePointer<CFRange>?) -> Bool {
    let found = CFStringMore.find(string, target, range, flags, locale)
    guard found.location != stringNotFound else { return false }
    result?.pointee = found
    return true
}

// MARK: - Folding and normalizing

/// Folds the string as the flags say: case (Unicode's full case folding,
/// Turkic for a Turkish or Azerbaijani locale), diacritics, widths.
@c(_CFStringFold)
public func CFStringFold(_ string: id?, _ flags: UInt, _ locale: id?) {
    let turkic = flags & CFStringMore.caseInsensitive != 0 && CFStringMore.foldsTurkic(locale)
    CFStrings.mutate(string) { text in
        var folded = ""
        for scalar in text.unicodeScalars { folded += CFStringMore.fold(scalar, flags, turkic: turkic) }
        // Halfwidth voiced marks fold to combining ones: compose them.
        text = flags & CFStringMore.widthInsensitive != 0 ? CFStringMore.normalize(folded, 2) : folded
    }
}

/// Normalizes the string to a CFStringNormalizationForm (D 0, KD 1, C 2,
/// KC 3), by ICU.
@c(_CFStringNormalize)
public func CFStringNormalize(_ string: id?, _ form: Int) {
    CFStrings.mutate(string) { $0 = CFStringMore.normalize($0, form) }
}

// MARK: - Bounds and clusters

/// The lines holding the range, ended by LF, CR, CR LF, NEL, LINE
/// SEPARATOR or PARAGRAPH SEPARATOR.
@DarwinC("_CFStringGetLineBounds")
public func CFStringGetLineBounds(_ string: id?, _ range: CFRange, _ begin: UnsafeMutablePointer<Int>?,
                                  _ end: UnsafeMutablePointer<Int>?, _ contentsEnd: UnsafeMutablePointer<Int>?) {
    CFStringMore.bounds(string, range, paragraphs: false, begin, end, contentsEnd)
}

/// The paragraphs holding the range: as lines, but LINE SEPARATOR doesn't
/// end one.
@DarwinC("_CFStringGetParagraphBounds")
public func CFStringGetParagraphBounds(_ string: id?, _ range: CFRange, _ begin: UnsafeMutablePointer<Int>?,
                                       _ end: UnsafeMutablePointer<Int>?, _ contentsEnd: UnsafeMutablePointer<Int>?) {
    CFStringMore.bounds(string, range, paragraphs: true, begin, end, contentsEnd)
}

/// The composed character sequence at an index: its grapheme cluster.
@DarwinC("_CFStringGetRangeOfComposedCharactersAtIndex")
public func CFStringGetRangeOfComposedCharactersAtIndex(_ string: id?, _ index: Int) -> CFRange {
    CFStringMore.cluster(string, index)
}

/// The cluster at an index. Each CFStringCharacterClusterType (grapheme,
/// composed character, cursor movement, backward deletion) is the extended
/// grapheme cluster here; Darwin's backward deletion cluster can be smaller
/// in some scripts.
@DarwinC("_CFStringGetRangeOfCharacterClusterAtIndex")
public func CFStringGetRangeOfCharacterClusterAtIndex(_ string: id?, _ index: Int, _ type: Int) -> CFRange {
    CFStringMore.cluster(string, index)
}

// MARK: - Hyphenation

/// kCFNotFound: there are no hyphenation dictionaries here (ICU has none).
@DarwinC("_CFStringGetHyphenationLocationBeforeIndex")
public func CFStringGetHyphenationLocationBeforeIndex(_ string: id?, _ location: Int, _ limit: CFRange, _ options: UInt,
                                                      _ locale: id?, _ character: UnsafeMutablePointer<UInt32>?) -> Int {
    stringNotFound
}

/// False: hyphenation is available for no locale here.
@c(_CFStringIsHyphenationAvailableForLocale)
public func CFStringIsHyphenationAvailableForLocale(_ locale: id?) -> Bool { false }

// MARK: - Encodings

/// The encodings there are converters for, ending with
/// kCFStringEncodingInvalidId; the list lives as long as the program.
nonisolated(unsafe) private let availableEncodings: UnsafeMutablePointer<UInt32> = {
    let encodings = CFStringEncodings.names.keys.sorted() + [invalidEncoding]
    let list = UnsafeMutablePointer<UInt32>.allocate(capacity: encodings.count)
    list.initialize(from: encodings, count: encodings.count)
    return list
}()

@c(_CFStringGetListOfAvailableEncodings)
public func CFStringGetListOfAvailableEncodings() -> UnsafePointer<UInt32>? { UnsafePointer(availableEncodings) }

/// The Mac OS encoding closest to an encoding: a Mac one is itself, the
/// Unicode ones kCFStringEncodingUnicode, the ISO, Windows, DOS and East
/// Asian ones their script's; kCFStringEncodingInvalidId otherwise.
@c(_CFStringGetMostCompatibleMacStringEncoding)
public func CFStringGetMostCompatibleMacStringEncoding(_ encoding: UInt32) -> UInt32 {
    if encoding < 0x100 { return encoding }
    if encoding & 0x0FFF == 0x0100 { return CFStringEncodings.utf16 }
    let scripts: [UInt32: UInt32] = [
        // Western: ASCII, Latin 1, Windows Latin 1, NextStep, Latin 9, DOS Latin US and 1.
        0x0600: 0, 0x0201: 0, 0x0500: 0, 0x0B01: 0, 0x020F: 0, 0x0400: 0, 0x0410: 0,
        // Central European: Latin 2, Windows Latin 2, DOS Latin 2.
        0x0202: 29, 0x0501: 29, 0x0412: 29,
        // Cyrillic: ISO, Windows, KOI8-R, KOI8-U, DOS Russian.
        0x0205: 7, 0x0502: 7, 0x0A02: 7, 0x0A08: 7, 0x0413: 7,
        // Greek, Turkish, Arabic, Hebrew.
        0x0207: 6, 0x0503: 6, 0x0405: 6, 0x0209: 35, 0x0504: 35, 0x0414: 35,
        0x0206: 4, 0x0506: 4, 0x0419: 4, 0x0208: 5, 0x0505: 5, 0x0417: 5,
        // Japanese: Shift-JIS, EUC-JP, ISO-2022-JP, DOS Japanese.
        0x0A01: 1, 0x0920: 1, 0x0820: 1, 0x0420: 1,
        // Simplified Chinese: EUC-CN, GBK, GB 18030, HZ, DOS.
        0x0930: 25, 0x0631: 25, 0x0632: 25, 0x0A05: 25, 0x0421: 25,
        // Traditional Chinese: Big 5, EUC-TW, DOS.
        0x0A03: 2, 0x0931: 2, 0x0423: 2,
        // Korean: EUC-KR, ISO-2022-KR, DOS.
        0x0940: 3, 0x0840: 3, 0x0422: 3,
        // Thai and Vietnamese.
        0x020B: 21, 0x041D: 21, 0x0508: 30,
    ]
    return scripts[encoding] ?? invalidEncoding
}

// MARK: - Hashes

/// The hash CFHash gives a string of these UTF-16 units.
@c(_CFStringHashCharacters)
public func CFStringHashCharacters(_ characters: UnsafePointer<UInt16>?, _ length: Int) -> UInt {
    guard let characters, length > 0 else { return Strings.hash("") }
    return Strings.hash(CFStrings.string(UnsafeBufferPointer(start: characters, count: length)))
}

/// The hash CFHash gives a string of these ISO Latin 1 bytes.
@c(_CFStringHashISOLatin1CString)
public func CFStringHashISOLatin1CString(_ bytes: UnsafePointer<UInt8>?, _ length: Int) -> UInt {
    guard let bytes, length > 0 else { return Strings.hash("") }
    var scalars = String.UnicodeScalarView()
    for byte in UnsafeBufferPointer(start: bytes, count: length) { scalars.append(Unicode.Scalar(byte)) }
    return Strings.hash(String(scalars))
}

// MARK: - Validated formats

/// The variadic CFStringCreateStringWithValidatedFormat (variadic.S): its
/// five fixed arguments, then a Darwin va_list of the rest.
@c
public func perry_foundation_cf_create_with_validated_format(_ allocator: UnsafeRawPointer?, _ options: id?, _ valid: id?,
                                                             _ format: id?, _ error: UnsafeMutablePointer<id?>?,
                                                             _ arguments: UnsafeRawPointer?) -> id? {
    CFStringMore.validatedString(allocator, options, valid, format, arguments, error)
}

/// The formatted string, +1, if the format takes only arguments the valid
/// specifiers take, at their positions and of their types (a format may
/// take fewer); else NULL, and a kCFErrorDomainCocoa NSFormattingError.
@c(_CFStringCreateStringWithValidatedFormatAndArguments)
public func CFStringCreateStringWithValidatedFormatAndArguments(_ allocator: UnsafeRawPointer?, _ options: id?, _ valid: id?,
                                                                _ format: id?, _ arguments: UnsafeRawPointer?,
                                                                _ error: UnsafeMutablePointer<id?>?) -> id? {
    CFStringMore.validatedString(allocator, options, valid, format, arguments, error)
}
