import CPerryFoundation
import FoundationEssentials
import PerryObjCInterop
import Synchronization

// The rest of CFAttributedString: substrings, reading attributes, the
// mutable string, and the bidirectional levels and writing directions of
// its text.

enum CFAttributedStringMore {
    static func nsRange(_ range: CFRange) -> NSRange {
        NSRange(location: UInt(max(0, range.location)), length: UInt(max(0, range.length)))
    }

    static func cfRange(_ range: NSRange) -> CFRange { CFRange(location: Int(range.location), length: Int(range.length)) }

    /// The mutable strings CFAttributedStringGetMutableString has given:
    /// the latest few, each given again for its attributed string while
    /// kept, as an autoreleased one lives a while.
    static let mutableStrings = Mutex<[UInt]>([])

    /// The attributed string's characters.
    static func units(_ string: id?) -> [UInt16] {
        if let storage = AttributedStrings.storage(string) { return storage.units }
        return ObjC.autoreleasepool { CFStrings.units(ObjC.send(string, ObjC.selector("string"))) }
    }

    // MARK: Bidirectional text

    /// The Unicode bidirectional classes these levels are resolved from.
    enum BidiClass {
        case l, r, al, en, an, nsm, paragraph, whitespace, neutral
    }

    /// A character's class, from its block and general category: an
    /// approximation of Unicode's Bidi_Class, which the standard library
    /// doesn't give.
    static func bidiClass(_ scalar: Unicode.Scalar) -> BidiClass {
        let value = scalar.value
        switch value {
        case 0x0A, 0x0D, 0x1C...0x1E, 0x85, 0x2029: return .paragraph
        case 0x09, 0x0B, 0x0C, 0x1F, 0x20, 0x2028: return .whitespace
        case 0x30...0x39, 0x06F0...0x06F9, 0x00B2, 0x00B3, 0x00B9, 0x2070...0x2079, 0x2080...0x2089, 0xFF10...0xFF19:
            return .en
        case 0x0600...0x0605, 0x0660...0x0669, 0x066B, 0x066C, 0x06DD, 0x08E2, 0x10E60...0x10E7E: return .an
        default: break
        }
        let category = scalar.properties.generalCategory
        if category == .nonspacingMark || category == .enclosingMark { return .nsm }
        if category == .spaceSeparator { return .whitespace }
        switch value {
        case 0x0590...0x05FF, 0x07C0...0x085F, 0xFB1D...0xFB4F, 0x10800...0x10CFF, 0x10E80...0x10EFF, 0x1E800...0x1EC6F:
            return .r
        case 0x0600...0x07BF, 0x0860...0x08FF, 0xFB50...0xFDCF, 0xFDF0...0xFDFF, 0xFE70...0xFEFF,
             0x10D00...0x10D3F, 0x10F30...0x10F6F, 0x1EC70...0x1ECBF, 0x1ED00...0x1ED4F, 0x1EE00...0x1EEFF:
            return .al
        default: break
        }
        switch category {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter, .spacingMark,
             .letterNumber, .privateUse:
            return .l
        default:
            return .neutral
        }
    }

    /// The text's paragraph levels and each UTF-16 unit's embedding level,
    /// by the Unicode bidirectional algorithm's weak, neutral and implicit
    /// rules (W1–W7, N1–N2, I1–I2, L1). Explicit embeddings, overrides and
    /// isolates count as neutrals. The base direction is 0 (left to right),
    /// 1 (right to left) or, for -1, each paragraph's own: its first strong
    /// character's or, `statistical`, its strong characters' majority.
    static func resolve(_ units: [UInt16], base: Int8, statistical: Bool) -> (levels: [UInt8], bases: [UInt8]) {
        // Each unit's class, a surrogate pair's both from its character.
        var classes: [BidiClass] = []
        for scalar in String(decoding: units, as: UTF16.self).unicodeScalars {
            classes += Array(repeating: bidiClass(scalar), count: scalar.utf16.count)
        }
        var levels = [UInt8](repeating: 0, count: units.count)
        var bases = [UInt8](repeating: 0, count: units.count)
        var start = 0
        while start < classes.count {
            var end = start
            while end < classes.count, classes[end] != .paragraph { end += 1 }
            let paragraphEnd = min(end + 1, classes.count)   // with its separator
            let level = paragraphLevel(classes[start..<end], base: base, statistical: statistical)
            resolveParagraph(&classes, start..<end, level: level, levels: &levels)
            for index in start..<paragraphEnd { bases[index] = level }
            if end < classes.count { levels[end] = level }
            start = paragraphEnd
        }
        return (levels, bases)
    }

    static func paragraphLevel(_ classes: ArraySlice<BidiClass>, base: Int8, statistical: Bool) -> UInt8 {
        if base == 0 || base == 1 { return UInt8(base) }
        if statistical {
            let left = classes.filter { $0 == .l }.count, right = classes.filter { $0 == .r || $0 == .al }.count
            if left != right { return right > left ? 1 : 0 }
        }
        let first = classes.first { $0 == .l || $0 == .r || $0 == .al }
        return first == .r || first == .al ? 1 : 0
    }

    static func resolveParagraph(_ classes: inout [BidiClass], _ range: Range<Int>, level: UInt8, levels: inout [UInt8]) {
        guard !range.isEmpty else { return }
        let embedding: BidiClass = level % 2 == 0 ? .l : .r
        // W1: a mark takes the class before it.
        var previous = embedding
        for index in range {
            if classes[index] == .nsm { classes[index] = previous }
            previous = classes[index]
        }
        // W2, W3: European numbers after Arabic letters are Arabic; Arabic
        // letters are right to left. W7: European numbers after left to
        // right letters are left to right.
        var strong = embedding
        for index in range {
            switch classes[index] {
            case .l, .r: strong = classes[index]
            case .al:
                strong = .al
                classes[index] = .r
            case .en:
                if strong == .al { classes[index] = .an } else if strong == .l { classes[index] = .l }
            default: break
            }
        }
        // N1, N2: neutrals between characters of one direction (numbers
        // counting as right to left) take it, others the embedding's.
        func direction(_ kind: BidiClass) -> BidiClass? {
            switch kind {
            case .l: return .l
            case .r, .en, .an: return .r
            default: return nil
            }
        }
        var index = range.lowerBound
        while index < range.upperBound {
            guard direction(classes[index]) == nil else {
                index += 1
                continue
            }
            var after = index
            while after < range.upperBound, direction(classes[after]) == nil { after += 1 }
            let before = index > range.lowerBound ? direction(classes[index - 1])! : embedding
            let next = after < range.upperBound ? direction(classes[after])! : embedding
            let resolved = before == next ? before : embedding
            // Whitespace is kept as such, for L1 below.
            for neutral in index..<after where classes[neutral] != .whitespace { classes[neutral] = resolved }
            for neutral in index..<after where classes[neutral] == .whitespace { levels[neutral] = resolved == .l ? 0 : 1 }
            index = after
        }
        // I1, I2.
        for index in range {
            switch (level % 2 == 0, classes[index]) {
            case (true, .r): levels[index] = level + 1
            case (true, .en), (true, .an): levels[index] = level + 2
            case (true, _): levels[index] = classes[index] == .whitespace ? implicit(levels[index], level) : level
            case (false, .l), (false, .en), (false, .an): levels[index] = level + 1
            case (false, _): levels[index] = classes[index] == .whitespace ? implicit(levels[index], level) : level
            }
        }
        // L1: whitespace ending the paragraph is at its level.
        var trailing = range.upperBound
        while trailing > range.lowerBound, classes[trailing - 1] == .whitespace {
            trailing -= 1
            levels[trailing] = level
        }
    }

    /// Whitespace resolved by N1/N2 to a direction (0 left, 1 right), at
    /// the level a strong character of it would have.
    private static func implicit(_ resolved: UInt8, _ level: UInt8) -> UInt8 {
        let rightToLeft = resolved == 1
        if level % 2 == 0 { return rightToLeft ? level + 1 : level }
        return rightToLeft ? level : level + 1
    }

    /// Fills the caller's buffers for the range of the attributed string's
    /// text; false for a range outside it.
    static func directions(_ string: id?, _ range: CFRange, _ base: Int8, _ levels: UnsafeMutablePointer<UInt8>?,
                           _ bases: UnsafeMutablePointer<UInt8>?, statistical: Bool) -> Bool {
        let text = units(string)
        guard range.location >= 0, range.length >= 0, range.location + range.length <= text.count else { return false }
        let resolved = resolve(Array(text[range.location..<range.location + range.length]), base: base, statistical: statistical)
        for index in 0..<range.length {
            levels?[index] = resolved.levels[index]
            bases?[index] = resolved.bases[index]
        }
        return true
    }
}

/// CFAttributedString's type ID, as Darwin numbers it.
@c(_CFAttributedStringGetTypeID) public func CFAttributedStringGetTypeID() -> UInt { 62 }

/// An attributed string of a range of another, its attributes with it, +1.
@DarwinC("_CFAttributedStringCreateWithSubstring")
public func CFAttributedStringCreateWithSubstring(_ allocator: UnsafeRawPointer?, _ string: id?, _ range: CFRange) -> id? {
    typealias Substring = @convention(c) (id?, SEL, NSRange) -> id?
    return ObjC.autoreleasepool {
        ObjC.retain(unsafeBitCast(ObjC.msgSend, to: Substring.self)(string, ObjC.selector("attributedSubstringFromRange:"),
                                                                    CFAttributedStringMore.nsRange(range)))
    }
}

/// One attribute's value at an index, +0 (the string's own), and the range
/// it is the same over.
@c(_CFAttributedStringGetAttribute)
public func CFAttributedStringGetAttribute(_ string: id?, _ location: Int, _ name: id?,
                                           _ effectiveRange: UnsafeMutablePointer<CFRange>?) -> id? {
    typealias Attribute = @convention(c) (id?, SEL, id?, UInt, UnsafeMutablePointer<NSRange>?) -> id?
    var range = NSRange(location: 0, length: 0)
    let value = unsafeBitCast(ObjC.msgSend, to: Attribute.self)(string, ObjC.selector("attribute:atIndex:effectiveRange:"), name,
                                                              UInt(max(0, location)), &range)
    effectiveRange?.pointee = CFAttributedStringMore.cfRange(range)
    return value
}

/// One attribute's value at an index, +0, and the longest range within
/// `limit` it is the same over.
@DarwinC("_CFAttributedStringGetAttributeAndLongestEffectiveRange")
public func CFAttributedStringGetAttributeAndLongestEffectiveRange(_ string: id?, _ location: Int, _ name: id?, _ limit: CFRange,
                                                                   _ longestRange: UnsafeMutablePointer<CFRange>?) -> id? {
    typealias Attribute = @convention(c) (id?, SEL, id?, UInt, UnsafeMutablePointer<NSRange>?, NSRange) -> id?
    var range = NSRange(location: 0, length: 0)
    let value = unsafeBitCast(ObjC.msgSend, to: Attribute.self)(string, ObjC.selector("attribute:atIndex:longestEffectiveRange:inRange:"),
                                                              name, UInt(max(0, location)), &range, CFAttributedStringMore.nsRange(limit))
    longestRange?.pointee = CFAttributedStringMore.cfRange(range)
    return value
}

/// The attributes at an index, +0 (the string's own dictionary), and the
/// range they are the same over.
@c(_CFAttributedStringGetAttributes)
public func CFAttributedStringGetAttributes(_ string: id?, _ location: Int, _ effectiveRange: UnsafeMutablePointer<CFRange>?) -> id? {
    typealias Attributes = @convention(c) (id?, SEL, UInt, UnsafeMutablePointer<NSRange>?) -> id?
    var range = NSRange(location: 0, length: 0)
    let value = unsafeBitCast(ObjC.msgSend, to: Attributes.self)(string, ObjC.selector("attributesAtIndex:effectiveRange:"),
                                                               UInt(max(0, location)), &range)
    effectiveRange?.pointee = CFAttributedStringMore.cfRange(range)
    return value
}

/// The attributes at an index, +0, and the longest range within `limit`
/// they are the same over.
@DarwinC("_CFAttributedStringGetAttributesAndLongestEffectiveRange")
public func CFAttributedStringGetAttributesAndLongestEffectiveRange(_ string: id?, _ location: Int, _ limit: CFRange,
                                                                    _ longestRange: UnsafeMutablePointer<CFRange>?) -> id? {
    typealias Attributes = @convention(c) (id?, SEL, UInt, UnsafeMutablePointer<NSRange>?, NSRange) -> id?
    var range = NSRange(location: 0, length: 0)
    let value = unsafeBitCast(ObjC.msgSend, to: Attributes.self)(string, ObjC.selector("attributesAtIndex:longestEffectiveRange:inRange:"),
                                                               UInt(max(0, location)), &range, CFAttributedStringMore.nsRange(limit))
    longestRange?.pointee = CFAttributedStringMore.cfRange(range)
    return value
}

/// The characters as a mutable string, +0, whose changes change the
/// attributed string, the attributes around them kept. The same string is
/// given each time while the latest few are kept.
@c(_CFAttributedStringGetMutableString)
public func CFAttributedStringGetMutableString(_ string: id?) -> id? {
    guard let storage = AttributedStrings.storage(string) else {
        return ObjC.send(string, ObjC.selector("mutableString"))
    }
    let match = CFAttributedStringMore.mutableStrings.withLock { kept in
        kept.first { Storage.get(id(bitPattern: $0), as: StringStorage.self)?.attributed === storage }
    }
    if let match { return id(bitPattern: match) }
    guard let proxy = ObjC.autoreleasepool({ ObjC.retain(ObjC.send(string, ObjC.selector("mutableString"))) }) else { return nil }
    let dropped = CFAttributedStringMore.mutableStrings.withLock { kept -> [UInt] in
        kept.append(UInt(bitPattern: proxy))
        guard kept.count > 256 else { return [] }
        let old = Array(kept.prefix(64))
        kept.removeFirst(64)
        return old
    }
    dropped.forEach { ObjC.release(id(bitPattern: $0)) }
    return proxy
}

/// Each UTF-16 unit's bidirectional embedding level, and its paragraph's
/// base direction (0 left to right, 1 right to left), in the caller's
/// buffers of range.length bytes; base direction -1 is each paragraph's
/// own (kCFWritingDirectionNatural). The algorithm is Unicode's implicit
/// one over approximate character classes: see CFAttributedStringMore.
/// Writing direction attributes aren't read.
@DarwinC("_CFAttributedStringGetBidiLevelsAndResolvedDirections")
public func CFAttributedStringGetBidiLevelsAndResolvedDirections(_ string: id?, _ range: CFRange, _ base: Int8,
                                                                 _ levels: UnsafeMutablePointer<UInt8>?,
                                                                 _ bases: UnsafeMutablePointer<UInt8>?) -> Bool {
    CFAttributedStringMore.directions(string, range, base, levels, bases, statistical: false)
}

/// As CFAttributedStringGetBidiLevelsAndResolvedDirections, but a natural
/// paragraph's direction is that of most of its strong characters, not of
/// its first.
@DarwinC("_CFAttributedStringGetStatisticalWritingDirections")
public func CFAttributedStringGetStatisticalWritingDirections(_ string: id?, _ range: CFRange, _ base: Int8,
                                                             _ levels: UnsafeMutablePointer<UInt8>?,
                                                             _ bases: UnsafeMutablePointer<UInt8>?) -> Bool {
    CFAttributedStringMore.directions(string, range, base, levels, bases, statistical: true)
}
