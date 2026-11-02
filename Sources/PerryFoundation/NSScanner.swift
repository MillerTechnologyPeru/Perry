import CPerryFoundation
import FoundationEssentials
import Glibc
import PerryObjCInterop

/// A scanner's string, as UTF-16, and where it is.
final class ScannerStorage {
    let units: [UInt16]
    let string: id
    var location = 0
    var skipped: id?
    var caseSensitive = false
    var locale: id?

    init(_ string: id) {
        self.string = ObjC.retain(string)!
        units = Array((Strings.value(of: string) ?? "").utf16)
        skipped = ObjC.retain(CharacterSets.whitespaceAndNewline)
    }

    deinit {
        ObjC.release(string)
        ObjC.release(skipped)
        ObjC.release(locale)
    }

    func isSkipped(_ unit: UInt16) -> Bool {
        guard let skipped else { return false }
        return ObjC.sendBool(skipped, ObjC.selector("characterIsMember:"), UnsafeMutableRawPointer(bitPattern: UInt(unit)))
    }

    /// Where scanning starts: past the characters to skip.
    var start: Int {
        var index = location
        while index < units.count, isSkipped(units[index]) { index += 1 }
        return index
    }

    /// Runs a scan from past the skipped characters; it moves the
    /// location only when it succeeds.
    func scan<T>(_ body: (inout Int) -> T?) -> T? {
        var index = start
        guard let value = body(&index) else { return nil }
        location = index
        return value
    }

    func digits(_ index: inout Int, hex: Bool = false) -> String {
        var text = ""
        while index < units.count, let scalar = Unicode.Scalar(units[index]),
              hex ? scalar.properties.isASCIIHexDigit : ("0"..."9").contains(Character(scalar)) {
            text.unicodeScalars.append(scalar)
            index += 1
        }
        return text
    }

    /// An optionally signed run of decimal digits.
    func integerText(_ index: inout Int) -> String? {
        var text = ""
        if index < units.count, units[index] == 0x2D || units[index] == 0x2B {   // - +
            if units[index] == 0x2D { text = "-" }
            index += 1
        }
        let digits = digits(&index)
        return digits.isEmpty ? nil : text + digits
    }

    /// A floating-point number as strtod reads it.
    func doubleValue(_ index: inout Int) -> Double? {
        var text = ""
        var cursor = index
        if cursor < units.count, units[cursor] == 0x2D || units[cursor] == 0x2B {
            text.unicodeScalars.append(Unicode.Scalar(units[cursor])!)
            cursor += 1
        }
        let whole = digits(&cursor)
        var fraction = ""
        if cursor < units.count, units[cursor] == 0x2E {   // .
            var after = cursor + 1
            fraction = digits(&after)
            if !whole.isEmpty || !fraction.isEmpty { cursor = after }
        }
        guard !whole.isEmpty || !fraction.isEmpty else { return nil }
        text += whole + (fraction.isEmpty ? "" : "." + fraction)
        if cursor < units.count, units[cursor] == 0x65 || units[cursor] == 0x45 {   // e E
            var after = cursor + 1
            var exponent = "e"
            if after < units.count, units[after] == 0x2D || units[after] == 0x2B {
                exponent.unicodeScalars.append(Unicode.Scalar(units[after])!)
                after += 1
            }
            let power = digits(&after)
            if !power.isEmpty {
                text += exponent + power
                cursor = after
            }
        }
        index = cursor
        return strtod(text, nil)
    }

    func matches(_ needle: [UInt16], at index: Int) -> Bool {
        guard index + needle.count <= units.count else { return false }
        let slice = Array(units[index..<index + needle.count])
        if caseSensitive { return slice == needle }
        return String(decoding: slice, as: UTF16.self).lowercased() == String(decoding: needle, as: UTF16.self).lowercased()
    }

    func inSet(_ set: id, _ unit: UInt16) -> Bool {
        ObjC.sendBool(set, ObjC.selector("characterIsMember:"), UnsafeMutableRawPointer(bitPattern: UInt(unit)))
    }
}

enum Scanners {
    nonisolated(unsafe) static var scannerClass: Class!

    static func store<T>(_ pointer: UnsafeMutablePointer<T>?, _ value: T?) -> Bool {
        guard let value else { return false }
        pointer?.pointee = value
        return true
    }

    static func text(_ storage: ScannerStorage, _ from: Int, _ to: Int) -> id {
        Strings.autoreleased(String(decoding: storage.units[from..<to], as: UTF16.self))
    }
}

/// NSScanner.
@ObjCClass("NSScanner")
public final class NSScanner: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        Scanners.scannerClass = cls.storage
    }

    var storage: ScannerStorage { Storage.get(objcObject, as: ScannerStorage.self)! }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: Scanners.scannerClass)
    }

    @ObjCClassMethod("scannerWithString:")
    static func make(_ cls: ObjCClass, string: ObjCObject) -> UnsafeMutableRawPointer? {
        guard let object = Storage.allocate(cls.pointer) else { return nil }
        Storage.set(object, ScannerStorage(string.id))
        return ObjC.autorelease(object)
    }

    @ObjCClassMethod("localizedScannerWithString:")
    static func localized(_ cls: ObjCClass, string: ObjCObject) -> UnsafeMutableRawPointer? { make(cls, string: string) }

    @ObjCMethod("initWithString:")
    func initialize(string: ObjCObject) -> Self {
        Storage.set(objcObject, ScannerStorage(string.id))
        return self
    }

    @ObjCMethod("string") func string() -> UnsafeMutableRawPointer { storage.string }
    @ObjCMethod("scanLocation") func scanLocation() -> UInt { UInt(storage.location) }

    @ObjCMethod("setScanLocation:")
    func setScanLocation(_ location: UInt) {
        guard Int(location) <= storage.units.count else {
            foundationFatal("-[NSScanner setScanLocation:]: Index \(location) out of bounds; string length \(storage.units.count)")
        }
        storage.location = Int(location)
    }

    @ObjCMethod("currentIndex") func currentIndex() -> UInt { UInt(storage.location) }
    @ObjCMethod("caseSensitive") func caseSensitive() -> Bool { storage.caseSensitive }
    @ObjCMethod("setCaseSensitive:") func setCaseSensitive(_ value: Bool) { storage.caseSensitive = value }
    @ObjCMethod("charactersToBeSkipped") func charactersToBeSkipped() -> UnsafeMutableRawPointer? { storage.skipped }

    @ObjCMethod("setCharactersToBeSkipped:")
    func setCharactersToBeSkipped(_ set: ObjCObject?) {
        let old = storage.skipped
        storage.skipped = ObjC.retain(set?.id)
        ObjC.release(old)
    }

    @ObjCMethod("locale") func locale() -> UnsafeMutableRawPointer? { storage.locale }

    @ObjCMethod("setLocale:")
    func setLocale(_ locale: ObjCObject?) {
        let old = storage.locale
        storage.locale = ObjC.retain(locale?.id)
        ObjC.release(old)
    }

    /// At the end once only characters to skip remain.
    @ObjCMethod("isAtEnd") func isAtEnd() -> Bool { storage.start >= storage.units.count }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        guard let object = Storage.allocate(UnsafeMutableRawPointer(Scanners.scannerClass)) else { return nil }
        let copy = ScannerStorage(storage.string)
        copy.location = storage.location
        copy.caseSensitive = storage.caseSensitive
        Storage.set(object, copy)
        return object
    }

    // MARK: Numbers

    /// Overflow clamps to the type's limits, as Darwin's does.
    private func integer<T: FixedWidthInteger>(_ type: T.Type) -> T? {
        storage.scan { index in
            guard let text = storage.integerText(&index) else { return nil }
            return T(text) ?? (text.hasPrefix("-") ? T.min : T.max)
        }
    }

    @ObjCMethod("scanInt:")
    func scanInt(_ value: UnsafeMutablePointer<Int32>?) -> Bool { Scanners.store(value, integer(Int32.self)) }

    @ObjCMethod("scanInteger:")
    func scanInteger(_ value: UnsafeMutablePointer<Int>?) -> Bool { Scanners.store(value, integer(Int.self)) }

    @ObjCMethod("scanLongLong:")
    func scanLongLong(_ value: UnsafeMutablePointer<Int64>?) -> Bool { Scanners.store(value, integer(Int64.self)) }

    @ObjCMethod("scanUnsignedLongLong:")
    func scanUnsignedLongLong(_ value: UnsafeMutablePointer<UInt64>?) -> Bool {
        Scanners.store(value, storage.scan { index -> UInt64? in
            guard let text = storage.integerText(&index), !text.hasPrefix("-") else { return nil }
            return UInt64(text) ?? .max
        })
    }

    @ObjCMethod("scanDouble:")
    func scanDouble(_ value: UnsafeMutablePointer<Double>?) -> Bool {
        Scanners.store(value, storage.scan { storage.doubleValue(&$0) })
    }

    @ObjCMethod("scanFloat:")
    func scanFloat(_ value: UnsafeMutablePointer<Float>?) -> Bool {
        Scanners.store(value, storage.scan { storage.doubleValue(&$0).map(Float.init) })
    }

    private func hex() -> UInt64? {
        storage.scan { index in
            let units = storage.units
            if index + 1 < units.count, units[index] == 0x30, units[index + 1] == 0x78 || units[index + 1] == 0x58 {
                var after = index + 2
                let digits = storage.digits(&after, hex: true)
                if !digits.isEmpty {
                    index = after
                    return UInt64(digits, radix: 16) ?? .max
                }
            }
            let digits = storage.digits(&index, hex: true)
            return digits.isEmpty ? nil : UInt64(digits, radix: 16) ?? .max
        }
    }

    @ObjCMethod("scanHexInt:")
    func scanHexInt(_ value: UnsafeMutablePointer<UInt32>?) -> Bool {
        Scanners.store(value, hex().map { UInt32(clamping: $0) })
    }

    @ObjCMethod("scanHexLongLong:")
    func scanHexLongLong(_ value: UnsafeMutablePointer<UInt64>?) -> Bool { Scanners.store(value, hex()) }

    @ObjCMethod("scanHexDouble:")
    func scanHexDouble(_ value: UnsafeMutablePointer<Double>?) -> Bool { Scanners.store(value, hex().map(Double.init)) }

    @ObjCMethod("scanHexFloat:")
    func scanHexFloat(_ value: UnsafeMutablePointer<Float>?) -> Bool { Scanners.store(value, hex().map(Float.init)) }

    // MARK: Strings

    @ObjCMethod("scanString:intoString:")
    func scan(_ string: String, into result: UnsafeMutablePointer<id?>?) -> Bool {
        let needle = Array(string.utf16)
        let found: (Int, Int)? = storage.scan { index in
            guard !needle.isEmpty, storage.matches(needle, at: index) else { return nil }
            let start = index
            index += needle.count
            return (start, index)
        }
        guard let found else { return false }
        result?.pointee = Scanners.text(storage, found.0, found.1)
        return true
    }

    @ObjCMethod("scanUpToString:intoString:")
    func scanUp(to string: String, into result: UnsafeMutablePointer<id?>?) -> Bool {
        let needle = Array(string.utf16)
        let found: (Int, Int)? = storage.scan { index in
            let start = index
            while index < storage.units.count, !storage.matches(needle, at: index) { index += 1 }
            return index > start ? (start, index) : nil
        }
        guard let found else { return false }
        result?.pointee = Scanners.text(storage, found.0, found.1)
        return true
    }

    @ObjCMethod("scanCharactersFromSet:intoString:")
    func scanCharacters(from set: ObjCObject, into result: UnsafeMutablePointer<id?>?) -> Bool {
        let found: (Int, Int)? = storage.scan { index in
            let start = index
            while index < storage.units.count, storage.inSet(set.id, storage.units[index]) { index += 1 }
            return index > start ? (start, index) : nil
        }
        guard let found else { return false }
        result?.pointee = Scanners.text(storage, found.0, found.1)
        return true
    }

    @ObjCMethod("scanUpToCharactersFromSet:intoString:")
    func scanUpToCharacters(from set: ObjCObject, into result: UnsafeMutablePointer<id?>?) -> Bool {
        let found: (Int, Int)? = storage.scan { index in
            let start = index
            while index < storage.units.count, !storage.inSet(set.id, storage.units[index]) { index += 1 }
            return index > start ? (start, index) : nil
        }
        guard let found else { return false }
        result?.pointee = Scanners.text(storage, found.0, found.1)
        return true
    }
}
