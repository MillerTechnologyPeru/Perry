import CPerryGeometry
import PerryObjCInterop

// AppKit's word boundaries on NSAttributedString, which text views select a
// word by and apps count words with (Bean steps through its text with
// -nextWordFromIndex:forward:). A word is a run of letters, digits and
// marks, with an apostrophe or right single quote inside it ("don't").

enum Words {
    /// Whether the character at `index` of `units` is part of a word.
    static func isWordCharacter(_ units: [UInt16], _ index: Int) -> Bool {
        guard index >= 0, index < units.count else { return false }
        let unit = units[index]
        if unit == 0x27 || unit == 0x2019 {
            // An apostrophe joins letters on either side of it.
            return index > 0 && index + 1 < units.count && isLetterOrDigit(units[index - 1]) && isLetterOrDigit(units[index + 1])
        }
        return isLetterOrDigit(unit)
    }

    static func isLetterOrDigit(_ unit: UInt16) -> Bool {
        // A surrogate is half of a character past the BMP: counted as a
        // letter, as most such characters are.
        if (0xD800...0xDFFF).contains(unit) { return true }
        guard let scalar = Unicode.Scalar(unit) else { return false }
        let properties = scalar.properties
        return properties.isAlphabetic || properties.numericType != nil || properties.generalCategory == .nonspacingMark
            || properties.generalCategory == .spacingMark
    }

    /// The index of the next word's start after `index`, or the end.
    static func next(_ units: [UInt16], from index: Int) -> Int {
        var i = min(max(index, 0), units.count)
        while i < units.count, isWordCharacter(units, i) { i += 1 }
        while i < units.count, !isWordCharacter(units, i) { i += 1 }
        return i
    }

    /// The index of the start of the word before `index`, or 0.
    static func previous(_ units: [UInt16], from index: Int) -> Int {
        var i = min(max(index, 0), units.count)
        while i > 0, !isWordCharacter(units, i - 1) { i -= 1 }
        while i > 0, isWordCharacter(units, i - 1) { i -= 1 }
        return i
    }

    /// The word around `index`; a run of other characters, or one of them,
    /// where `index` isn't in a word.
    static func around(_ units: [UInt16], _ index: Int) -> NSRange {
        guard !units.isEmpty else { return NSRange(location: 0, length: 0) }
        let at = min(max(index, 0), units.count - 1)
        let inWord = isWordCharacter(units, at)
        var start = at, end = at + 1
        if inWord {
            while start > 0, isWordCharacter(units, start - 1) { start -= 1 }
            while end < units.count, isWordCharacter(units, end) { end += 1 }
        } else if units[at] == 0x20 || units[at] == 0x09 {
            while start > 0, units[start - 1] == units[at] { start -= 1 }
            while end < units.count, units[end] == units[at] { end += 1 }
        }
        return NSRange(location: UInt(start), length: UInt(end - start))
    }
}

@ObjCCategory("NSAttributedStringWords")
extension NSAttributedString {
    private var units: [UInt16] {
        Send.object(objcObject, "string").map { Array(String(objCArgument: $0).utf16) } ?? []
    }

    @ObjCMethod("nextWordFromIndex:forward:")
    func nextWord(from index: UInt, forward: Bool) -> UInt {
        let units = units
        let start = index > UInt(units.count) ? units.count : Int(index)
        return UInt(forward ? Words.next(units, from: start) : Words.previous(units, from: start))
    }

    @ObjCMethod("doubleClickAtIndex:")
    func doubleClick(at index: UInt) -> NSRange {
        let units = units
        return Words.around(units, index > UInt(units.count) ? units.count : Int(index))
    }
}
