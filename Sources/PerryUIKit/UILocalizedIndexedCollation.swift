import PerryObjCInterop

// UILocalizedIndexedCollation: the sections of an alphabetical list and its
// index, as English collates them: A to Z, then # for everything else. An
// object's section is the first letter of the string its collation selector
// gives, with accents and case taken off.

@ObjCClass("UILocalizedIndexedCollation")
open class UILocalizedIndexedCollation: NSObject {
    nonisolated(unsafe) static var current: UILocalizedIndexedCollation?

    static let titles = (UInt8(ascii: "A")...UInt8(ascii: "Z")).map { String(UnicodeScalar($0)) } + ["#"]

    @ObjCClassMethod("currentCollation")
    static func currentCollation() -> UILocalizedIndexedCollation {
        if let current { return current }
        let collation = objCClass.object.newInstance().unsafeCast(to: UILocalizedIndexedCollation.self)
        current = collation
        return collation
    }

    @ObjCMethod("sectionTitles") func sectionTitles() -> NSObject { NSMutableArray.of(Self.titles.map { NSObject($0.objCArgument()!) }) }
    @ObjCMethod("sectionIndexTitles") func sectionIndexTitles() -> NSObject { sectionTitles() }

    /// Each index title is a section of its own.
    @ObjCMethod("sectionForSectionIndexTitleAtIndex:")
    func section(forSectionIndexTitleAt index: Int) -> Int { index }

    @ObjCMethod("sectionForObject:collationStringSelector:")
    func section(for object: NSObject?, collationStringSelector selector: ObjCSelector?) -> Int {
        Self.section(of: Self.collationString(object, selector))
    }

    /// The objects in the order of their collation strings, case and
    /// accents aside.
    @ObjCMethod("sortedArrayFromArray:collationStringSelector:")
    func sortedArray(from array: NSArray?, collationStringSelector selector: ObjCSelector?) -> NSObject {
        let objects = array?.elements ?? []
        let keyed = objects.map { (object: $0, key: Self.folded(Self.collationString($0, selector))) }
        return NSMutableArray.of(keyed.sorted { $0.key < $1.key }.map(\.object))
    }

    /// The string the selector gives for the object, or "" for none.
    static func collationString(_ object: NSObject?, _ selector: ObjCSelector?) -> String {
        guard let object, let selector else { return "" }
        typealias Send = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer) -> UnsafeMutableRawPointer?
        guard let string = unsafeBitCast(ObjCRuntime.msgSend, to: Send.self)(object.objcObject, selector.pointer) else { return "" }
        return String(objCArgument: string)
    }

    /// The section of a string: its first letter's, else # (the last).
    static func section(of string: String) -> Int {
        guard let first = folded(string).unicodeScalars.first, first.value >= 0x41, first.value <= 0x5A else {
            return titles.count - 1
        }
        return Int(first.value - 0x41)
    }

    /// Latin letters with accents, and the letters they collate as.
    private static let accented: [Character: Character] = {
        let groups: [(Character, String)] = [
            ("A", "ÀÁÂÃÄÅĀĂĄǍ"), ("C", "ÇĆĈĊČ"), ("D", "ĎĐ"), ("E", "ÈÉÊËĒĔĖĘĚ"), ("G", "ĜĞĠĢ"), ("H", "ĤĦ"),
            ("I", "ÌÍÎÏĨĪĬĮİ"), ("J", "Ĵ"), ("K", "Ķ"), ("L", "ĹĻĽĿŁ"), ("N", "ÑŃŅŇ"), ("O", "ÒÓÔÕÖØŌŎŐǑ"),
            ("R", "ŔŖŘ"), ("S", "ŚŜŞŠ"), ("T", "ŢŤŦ"), ("U", "ÙÚÛÜŨŪŬŮŰŲǓ"), ("W", "Ŵ"), ("Y", "ÝŶŸ"), ("Z", "ŹŻŽ"),
        ]
        var table: [Character: Character] = [:]
        for (letter, forms) in groups { for form in forms { table[form] = letter } }
        return table
    }()

    /// The string in capitals with Latin accents taken off.
    static func folded(_ string: String) -> String {
        String(string.uppercased().map { accented[$0] ?? $0 })
    }
}
