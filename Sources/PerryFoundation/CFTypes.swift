import CPerryFoundation
import FoundationEssentials
import Glibc
import PerryObjCInterop

// CoreFoundation's value types over their toll-free bridged Foundation
// classes: numbers and booleans, data, dates, null, URLs, errors, character
// sets, time zones, locales, bundles and preferences; and CFUUID, which has
// no Foundation class. The type IDs are Darwin's.

enum CFTypeIDs {
    static let string: UInt = 7, null: UInt = 16, set: UInt = 17, dictionary: UInt = 18, array: UInt = 19, data: UInt = 20
    static let boolean: UInt = 21, number: UInt = 22, characterSet: UInt = 25, error: UInt = 27, url: UInt = 29
    static let bundle: UInt = 31, uuid: UInt = 34, date: UInt = 42, runLoop: UInt = 43, timeZone: UInt = 48, locale: UInt = 55

    /// The type ID of a bridged object, by its class.
    static func of(_ object: id) -> UInt? {
        let checks: [(Class?, UInt)] = [
            (Strings.stringClass, string), (Numbers.booleanClass, boolean), (Numbers.numberClass, number),
            (Arrays.arrayClass, array), (Dictionaries.dictionaryClass, dictionary), (Sets.setClass, set),
            (DataObjects.dataClass, data), (Dates.dateClass, date), (URLs.urlClass, url), (Errors.errorClass, error),
            (CharacterSets.setClass, characterSet), (TimeZones.zoneClass, timeZone), (Locales.localeClass, locale),
            (Bundles.bundleClass, bundle),
        ]
        if object == Nulls.null { return null }
        return checks.first { cls, _ in cls.map { ObjC.isKind(object, of: $0) } ?? false }?.1
    }
}

@c(_CFGetRetainCount)
public func CFGetRetainCount(_ object: id?) -> Int { Int(bitPattern: ObjC.sendUInt(object, ObjC.selector("retainCount"))) }

@c(_CFAutorelease)
public func CFAutorelease(_ object: id?) -> id? { ObjC.autorelease(object) }

@c(_CFMakeCollectable)
public func CFMakeCollectable(_ object: id?) -> id? { object }

@c(_CFCopyTypeIDDescription)
public func CFCopyTypeIDDescription(_ type: UInt) -> id? {
    let names: [UInt: String] = [
        CFTypeIDs.string: "CFString", CFTypeIDs.null: "CFNull", CFTypeIDs.set: "CFSet", CFTypeIDs.dictionary: "CFDictionary",
        CFTypeIDs.array: "CFArray", CFTypeIDs.data: "CFData", CFTypeIDs.boolean: "CFBoolean", CFTypeIDs.number: "CFNumber",
        CFTypeIDs.characterSet: "CFCharacterSet", CFTypeIDs.error: "CFError", CFTypeIDs.url: "CFURL", CFTypeIDs.bundle: "CFBundle",
        CFTypeIDs.uuid: "CFUUID", CFTypeIDs.date: "CFDate", CFTypeIDs.runLoop: "CFRunLoop", CFTypeIDs.timeZone: "CFTimeZone",
        CFTypeIDs.locale: "CFLocale",
    ]
    if let name = CFRuntimeClasses.runtimeClass(type)?.pointee.className {
        return Strings.make(String(cString: name))
    }
    return names[type].map(Strings.make)
}

@c(_CFNullGetTypeID) public func CFNullGetTypeID() -> UInt { CFTypeIDs.null }

// MARK: - Numbers

/// CFNumberType: kCFNumberSInt8Type 1 … kCFNumberCGFloatType 16.
enum CFNumberTypes {
    static let sint8 = 1, sint16 = 2, sint32 = 3, sint64 = 4, float32 = 5, float64 = 6, char = 7, short = 8, int = 9
    static let long = 10, longLong = 11, float = 12, double = 13, cfIndex = 14, nsInteger = 15, cgFloat = 16

    /// The canonical type of a number of `type`, as CFNumberGetType reports.
    static func canonical(_ type: Int) -> Int {
        switch type {
        case sint8, char: return sint8
        case sint16, short: return sint16
        case sint32, int: return sint32
        case float32, float: return float32
        case float64, double, cgFloat: return float64
        default: return sint64
        }
    }

    static func size(_ type: Int) -> Int {
        switch canonical(type) {
        case sint8: return 1
        case sint16: return 2
        case sint32, float32: return 4
        default: return 8
        }
    }
}

/// The canonical CFNumberType each number keeps, by object.
final class NumberTypeTable: @unchecked Sendable {
    static let shared = NumberTypeTable()
    private var lock = pthread_mutex_t()
    private var types: [id: Int] = [:]

    init() { pthread_mutex_init(&lock, nil) }

    func set(_ object: id, _ type: Int) {
        pthread_mutex_lock(&lock)
        types[object] = type
        pthread_mutex_unlock(&lock)
    }

    func type(_ object: id) -> Int? {
        pthread_mutex_lock(&lock)
        defer { pthread_mutex_unlock(&lock) }
        return types[object]
    }
}

@c(_CFNumberGetTypeID) public func CFNumberGetTypeID() -> UInt { CFTypeIDs.number }
@c(_CFBooleanGetTypeID) public func CFBooleanGetTypeID() -> UInt { CFTypeIDs.boolean }

@c(_CFBooleanGetValue)
public func CFBooleanGetValue(_ boolean: id?) -> Bool { Numbers.storage(boolean).int64 != 0 }

@c(_CFNumberCreate)
public func CFNumberCreate(_ allocator: UnsafeRawPointer?, _ type: Int, _ value: UnsafeRawPointer?) -> id? {
    guard let value else { return nil }
    let stored: NumberStorage.Value
    switch CFNumberTypes.canonical(type) {
    case CFNumberTypes.sint8: stored = .signed(Int64(value.load(as: Int8.self)))
    case CFNumberTypes.sint16: stored = .signed(Int64(value.load(as: Int16.self)))
    case CFNumberTypes.sint32: stored = .signed(Int64(value.load(as: Int32.self)))
    case CFNumberTypes.float32: stored = .double(Double(value.load(as: Float.self)))
    case CFNumberTypes.float64: stored = .double(value.load(as: Double.self))
    default: stored = .signed(value.load(as: Int64.self))
    }
    guard let number = Numbers.make(nil, stored) else { return nil }
    NumberTypeTable.shared.set(number, CFNumberTypes.canonical(type))
    return ObjC.retain(number)
}

@c(_CFNumberGetType)
public func CFNumberGetType(_ number: id?) -> Int {
    guard let number else { return 0 }
    if let type = NumberTypeTable.shared.type(number) { return type }
    return Numbers.storage(number).isFloatingPoint ? CFNumberTypes.float64 : CFNumberTypes.sint64
}

@c(_CFNumberGetByteSize) public func CFNumberGetByteSize(_ number: id?) -> Int { CFNumberTypes.size(CFNumberGetType(number)) }
@c(_CFNumberIsFloatType) public func CFNumberIsFloatType(_ number: id?) -> Bool { Numbers.storage(number).isFloatingPoint }

/// Stores the value as `type`; false when the conversion loses anything.
@c(_CFNumberGetValue)
public func CFNumberGetValue(_ number: id?, _ type: Int, _ value: UnsafeMutableRawPointer?) -> Bool {
    guard let value else { return false }
    let storage = Numbers.storage(number)
    let integer = storage.int64, real = storage.double
    func store<T: BinaryInteger>(_ kind: T.Type) -> Bool {
        let converted = T(truncatingIfNeeded: integer)
        value.storeBytes(of: converted, as: T.self)
        return Int64(converted) == integer && (!storage.isFloatingPoint || Double(integer) == real)
    }
    switch CFNumberTypes.canonical(type) {
    case CFNumberTypes.sint8: return store(Int8.self)
    case CFNumberTypes.sint16: return store(Int16.self)
    case CFNumberTypes.sint32: return store(Int32.self)
    case CFNumberTypes.float32:
        value.storeBytes(of: Float(real), as: Float.self)
        return Double(Float(real)) == real
    case CFNumberTypes.float64:
        value.storeBytes(of: real, as: Double.self)
        return storage.isFloatingPoint || Int64(exactly: real) == integer
    default: return store(Int64.self)
    }
}

@c(_CFNumberCompare)
public func CFNumberCompare(_ number: id?, _ other: id?, _ context: UnsafeRawPointer?) -> Int {
    Numbers.storage(number).compare(Numbers.storage(other))
}

// MARK: - Data

@c(_CFDataGetTypeID) public func CFDataGetTypeID() -> UInt { CFTypeIDs.data }

@c(_CFDataCreate)
public func CFDataCreate(_ allocator: UnsafeRawPointer?, _ bytes: UnsafePointer<UInt8>?, _ length: Int) -> id? {
    ObjC.retain(DataObjects.autoreleased(bytes.map { Data(bytes: $0, count: length) } ?? Data()))
}

@c(_CFDataCreateWithBytesNoCopy)
public func CFDataCreateWithBytesNoCopy(_ allocator: UnsafeRawPointer?, _ bytes: UnsafePointer<UInt8>?, _ length: Int,
                                        _ deallocator: UnsafeRawPointer?) -> id? {
    CFDataCreate(allocator, bytes, length)
}

@c(_CFDataCreateMutable)
public func CFDataCreateMutable(_ allocator: UnsafeRawPointer?, _ capacity: Int) -> id? {
    DataObjects.make(DataStorage(reserving: capacity), cls: UnsafeMutableRawPointer(DataObjects.mutableClass))
}

@c(_CFDataCreateCopy)
public func CFDataCreateCopy(_ allocator: UnsafeRawPointer?, _ data: id?) -> id? { ObjC.send(data, ObjC.selector("copy")) }

@c(_CFDataCreateMutableCopy)
public func CFDataCreateMutableCopy(_ allocator: UnsafeRawPointer?, _ capacity: Int, _ data: id?) -> id? {
    ObjC.send(data, ObjC.selector("mutableCopy"))
}

@c(_CFDataGetLength) public func CFDataGetLength(_ data: id?) -> Int { Int(ObjC.sendUInt(data, ObjC.selector("length"))) }

@c(_CFDataGetBytePtr)
public func CFDataGetBytePtr(_ data: id?) -> UnsafeRawPointer? { ObjC.send(data, ObjC.selector("bytes")).map(UnsafeRawPointer.init) }

@c(_CFDataGetMutableBytePtr)
public func CFDataGetMutableBytePtr(_ data: id?) -> UnsafeMutableRawPointer? { ObjC.send(data, ObjC.selector("mutableBytes")) }

@c(_CFDataGetBytes)
public func CFDataGetBytes(_ data: id?, _ range: CFRange, _ buffer: UnsafeMutableRawPointer?) {
    guard let buffer, let bytes = CFDataGetBytePtr(data) else { return }
    buffer.copyMemory(from: bytes + range.location, byteCount: range.length)
}

/// The NSMutableData selectors these use take NSRange and raw bytes.
private typealias ReplaceBytes = @convention(c) (id?, SEL, NSRange, UnsafeRawPointer?, UInt) -> Void

@c(_CFDataAppendBytes)
public func CFDataAppendBytes(_ data: id?, _ bytes: UnsafeRawPointer?, _ length: Int) {
    unsafeBitCast(ObjC.msgSend, to: (@convention(c) (id?, SEL, UnsafeRawPointer?, UInt) -> Void).self)(
        data, ObjC.selector("appendBytes:length:"), bytes, UInt(length))
}

@c(_CFDataReplaceBytes)
public func CFDataReplaceBytes(_ data: id?, _ range: CFRange, _ bytes: UnsafeRawPointer?, _ length: Int) {
    unsafeBitCast(ObjC.msgSend, to: ReplaceBytes.self)(
        data, ObjC.selector("replaceBytesInRange:withBytes:length:"),
        NSRange(location: UInt(range.location), length: UInt(range.length)), bytes, UInt(length))
}

@c(_CFDataDeleteBytes)
public func CFDataDeleteBytes(_ data: id?, _ range: CFRange) { CFDataReplaceBytes(data, range, nil, 0) }

@c(_CFDataSetLength)
public func CFDataSetLength(_ data: id?, _ length: Int) {
    unsafeBitCast(ObjC.msgSend, to: (@convention(c) (id?, SEL, UInt) -> Void).self)(data, ObjC.selector("setLength:"), UInt(length))
}

@c(_CFDataIncreaseLength)
public func CFDataIncreaseLength(_ data: id?, _ extra: Int) {
    unsafeBitCast(ObjC.msgSend, to: (@convention(c) (id?, SEL, UInt) -> Void).self)(data, ObjC.selector("increaseLengthBy:"), UInt(extra))
}

// MARK: - Dates

/// kCFAbsoluteTimeIntervalSince1970 and 1904.
@ObjCConstants
enum CFTimeConstants {
    static let kCFAbsoluteTimeIntervalSince1970: Double = 978307200
    static let kCFAbsoluteTimeIntervalSince1904: Double = 3061152000
}

@c(_CFDateGetTypeID) public func CFDateGetTypeID() -> UInt { CFTypeIDs.date }

@c(_CFDateCreate)
public func CFDateCreate(_ allocator: UnsafeRawPointer?, _ time: Double.ObjCType) -> id? {
    ObjC.retain(Dates.autoreleased(Double(objCArgument: time)))
}

@c(_CFDateGetAbsoluteTime)
public func CFDateGetAbsoluteTime(_ date: id?) -> Double.ObjCResultType { darwinResult(Dates.interval(date)) }

@c(_CFDateGetTimeIntervalSinceDate)
public func CFDateGetTimeIntervalSinceDate(_ date: id?, _ other: id?) -> Double.ObjCResultType {
    darwinResult(Dates.interval(date) - Dates.interval(other))
}

@c(_CFDateCompare)
public func CFDateCompare(_ date: id?, _ other: id?, _ context: UnsafeRawPointer?) -> Int {
    let a = Dates.interval(date), b = Dates.interval(other)
    return a < b ? -1 : a > b ? 1 : 0
}

// MARK: - URLs

enum CFURLs {
    static func url(_ object: id?) -> URL? { URLs.url(object) }
    static func make(_ url: URL?) -> id? { url.flatMap { ObjC.retain(URLs.autoreleased($0)) } }
    static func string(_ text: String?) -> id? { text.map(Strings.make) }
}

@c(_CFURLGetTypeID) public func CFURLGetTypeID() -> UInt { CFTypeIDs.url }

@c(_CFURLCreateWithString)
public func CFURLCreateWithString(_ allocator: UnsafeRawPointer?, _ string: id?, _ base: id?) -> id? {
    guard let text = Strings.value(of: string) else { return nil }
    return CFURLs.make(URL(string: text, relativeTo: CFURLs.url(base)))
}

@c(_CFURLCreateWithBytes)
public func CFURLCreateWithBytes(_ allocator: UnsafeRawPointer?, _ bytes: UnsafePointer<UInt8>?, _ length: Int, _ encoding: UInt32,
                                 _ base: id?) -> id? {
    guard let bytes else { return nil }
    let text = String(decoding: UnsafeBufferPointer(start: bytes, count: length), as: UTF8.self)
    return CFURLs.make(URL(string: text, relativeTo: CFURLs.url(base)))
}

/// kCFURLPOSIXPathStyle 0 is the style there is.
@c(_CFURLCreateWithFileSystemPath)
public func CFURLCreateWithFileSystemPath(_ allocator: UnsafeRawPointer?, _ path: id?, _ style: Int, _ isDirectory: Bool) -> id? {
    guard let path = Strings.value(of: path) else { return nil }
    return CFURLs.make(URLs.fileURL(path, isDirectory: isDirectory))
}

@c(_CFURLCreateFromFileSystemRepresentation)
public func CFURLCreateFromFileSystemRepresentation(_ allocator: UnsafeRawPointer?, _ bytes: UnsafePointer<CChar>?, _ length: Int,
                                                    _ isDirectory: Bool) -> id? {
    guard let bytes else { return nil }
    let path = String(decoding: UnsafeRawBufferPointer(start: bytes, count: length), as: UTF8.self)
    return CFURLs.make(URLs.fileURL(path, isDirectory: isDirectory))
}

@c(_CFURLGetString)
public func CFURLGetString(_ url: id?) -> id? { ObjC.send(url, ObjC.selector("relativeString")) }

@c(_CFURLGetBaseURL)
public func CFURLGetBaseURL(_ url: id?) -> id? { ObjC.send(url, ObjC.selector("baseURL")) }

@c(_CFURLCopyAbsoluteURL)
public func CFURLCopyAbsoluteURL(_ url: id?) -> id? { ObjC.retain(ObjC.send(url, ObjC.selector("absoluteURL"))) }

@c(_CFURLCopyScheme) public func CFURLCopyScheme(_ url: id?) -> id? { CFURLs.string(CFURLs.url(url)?.scheme) }
@c(_CFURLCopyHostName) public func CFURLCopyHostName(_ url: id?) -> id? { CFURLs.string(CFURLs.url(url)?.host(percentEncoded: false)) }
@c(_CFURLGetPortNumber) public func CFURLGetPortNumber(_ url: id?) -> Int { CFURLs.url(url)?.port ?? -1 }
@c(_CFURLCopyUserName) public func CFURLCopyUserName(_ url: id?) -> id? { CFURLs.string(CFURLs.url(url)?.user(percentEncoded: false)) }
@c(_CFURLCopyPassword) public func CFURLCopyPassword(_ url: id?) -> id? { CFURLs.string(CFURLs.url(url)?.password(percentEncoded: false)) }
@c(_CFURLCopyPath) public func CFURLCopyPath(_ url: id?) -> id? { CFURLs.string(CFURLs.url(url)?.path(percentEncoded: true)) }

@c(_CFURLCopyQueryString)
public func CFURLCopyQueryString(_ url: id?, _ escapes: id?) -> id? { CFURLs.string(CFURLs.url(url)?.query(percentEncoded: true)) }

@c(_CFURLCopyFragment)
public func CFURLCopyFragment(_ url: id?, _ escapes: id?) -> id? { CFURLs.string(CFURLs.url(url)?.fragment(percentEncoded: true)) }

@c(_CFURLCopyFileSystemPath)
public func CFURLCopyFileSystemPath(_ url: id?, _ style: Int) -> id? {
    guard let url = CFURLs.url(url) else { return nil }
    var path = url.path(percentEncoded: false)
    if path.count > 1, path.hasSuffix("/") { path.removeLast() }
    return Strings.make(path)
}

@c(_CFURLGetFileSystemRepresentation)
public func CFURLGetFileSystemRepresentation(_ url: id?, _ resolveAgainstBase: Bool, _ buffer: UnsafeMutablePointer<UInt8>?,
                                             _ length: Int) -> Bool {
    guard let buffer, let url = CFURLs.url(url) else { return false }
    var path = Array(url.path(percentEncoded: false).utf8)
    if path.count > 1, path.last == UInt8(ascii: "/") { path.removeLast() }
    guard path.count < length else { return false }
    buffer.update(from: path, count: path.count)
    buffer[path.count] = 0
    return true
}

@c(_CFURLCopyLastPathComponent)
public func CFURLCopyLastPathComponent(_ url: id?) -> id? { ObjC.retain(ObjC.send(url, ObjC.selector("lastPathComponent"))) }

@c(_CFURLCopyPathExtension)
public func CFURLCopyPathExtension(_ url: id?) -> id? {
    guard let ext = CFURLs.url(url)?.pathExtension, !ext.isEmpty else { return nil }
    return Strings.make(ext)
}

@c(_CFURLHasDirectoryPath) public func CFURLHasDirectoryPath(_ url: id?) -> Bool { CFURLs.url(url)?.hasDirectoryPath ?? false }

// MARK: Bookmarks: NSURL's, which name the URL itself

@c(_CFURLCreateBookmarkData)
public func CFURLCreateBookmarkData(_ allocator: UnsafeRawPointer?, _ url: id?, _ options: UInt, _ keys: id?, _ relativeTo: id?,
                                    _ error: UnsafeMutablePointer<id?>?) -> id? {
    guard let url = CFURLs.url(url) else { return nil }
    return ObjC.retain(DataObjects.autoreleased(NSURL.bookmark(for: url)))
}

@c(_CFURLCreateByResolvingBookmarkData)
public func CFURLCreateByResolvingBookmarkData(_ allocator: UnsafeRawPointer?, _ bookmark: id?, _ options: UInt, _ relativeTo: id?,
                                               _ keys: id?, _ isStale: UnsafeMutablePointer<UInt8>?,
                                               _ error: UnsafeMutablePointer<id?>?) -> id? {
    isStale?.pointee = 0
    guard let url = NSURL.bookmarkURL(DataObjects.data(bookmark)) else {
        error?.pointee = ObjC.retain(Errors.autoreleased(domain: Errors.cocoaDomain, code: 259,
            description: "The file couldn’t be opened because it isn’t in the correct format."))
        return nil
    }
    return CFURLs.make(url)
}

/// No file here is an alias file, which is what a bookmark file is.
@c(_CFURLCreateBookmarkDataFromFile)
public func CFURLCreateBookmarkDataFromFile(_ allocator: UnsafeRawPointer?, _ fileURL: id?, _ error: UnsafeMutablePointer<id?>?) -> id? {
    error?.pointee = ObjC.retain(Errors.autoreleased(domain: Errors.cocoaDomain, code: 259,
        description: "The file couldn’t be opened because it isn’t in the correct format."))
    return nil
}

@c(_CFURLWriteBookmarkDataToFile)
public func CFURLWriteBookmarkDataToFile(_ bookmark: id?, _ fileURL: id?, _ options: UInt, _ error: UnsafeMutablePointer<id?>?) -> Bool {
    guard let path = CFURLs.url(fileURL)?.path(percentEncoded: false), let file = fopen(path, "wb") else { return false }
    defer { fclose(file) }
    let bytes = DataObjects.data(bookmark)
    return bytes.withUnsafeBytes { fwrite($0.baseAddress, 1, $0.count, file) == $0.count }
}

@c(_CFURLCreateResourcePropertiesForKeysFromBookmarkData)
public func CFURLCreateResourcePropertiesForKeysFromBookmarkData(_ allocator: UnsafeRawPointer?, _ keys: id?, _ bookmark: id?) -> id? { nil }

@c(_CFURLCreateResourcePropertyForKeyFromBookmarkData)
public func CFURLCreateResourcePropertyForKeyFromBookmarkData(_ allocator: UnsafeRawPointer?, _ key: id?, _ bookmark: id?) -> id? { nil }

/// Nothing is security-scoped here.
@c(_CFURLStartAccessingSecurityScopedResource)
public func CFURLStartAccessingSecurityScopedResource(_ url: id?) -> Bool { true }

@c(_CFURLStopAccessingSecurityScopedResource)
public func CFURLStopAccessingSecurityScopedResource(_ url: id?) {}

@c(_CFURLCreateCopyAppendingPathComponent)
public func CFURLCreateCopyAppendingPathComponent(_ allocator: UnsafeRawPointer?, _ url: id?, _ component: id?, _ isDirectory: Bool) -> id? {
    guard let url = CFURLs.url(url), let component = Strings.value(of: component) else { return nil }
    return CFURLs.make(url.appending(path: component, directoryHint: isDirectory ? .isDirectory : .notDirectory))
}

@c(_CFURLCreateCopyDeletingLastPathComponent)
public func CFURLCreateCopyDeletingLastPathComponent(_ allocator: UnsafeRawPointer?, _ url: id?) -> id? {
    CFURLs.make(CFURLs.url(url)?.deletingLastPathComponent())
}

@c(_CFURLCreateCopyAppendingPathExtension)
public func CFURLCreateCopyAppendingPathExtension(_ allocator: UnsafeRawPointer?, _ url: id?, _ ext: id?) -> id? {
    guard let ext = Strings.value(of: ext) else { return nil }
    return CFURLs.make(CFURLs.url(url)?.appendingPathExtension(ext))
}

@c(_CFURLCreateCopyDeletingPathExtension)
public func CFURLCreateCopyDeletingPathExtension(_ allocator: UnsafeRawPointer?, _ url: id?) -> id? {
    CFURLs.make(CFURLs.url(url)?.deletingPathExtension())
}

/// Percent-escapes what URLs may not hold, and `legal`'s characters too;
/// `unescaped` stays as it is.
@c(_CFURLCreateStringByAddingPercentEscapes)
public func CFURLCreateStringByAddingPercentEscapes(_ allocator: UnsafeRawPointer?, _ string: id?, _ unescaped: id?, _ legal: id?,
                                                   _ encoding: UInt32) -> id? {
    guard let text = Strings.value(of: string) else { return nil }
    let keep = Set((Strings.value(of: unescaped) ?? "").unicodeScalars)
    let escape = Set((Strings.value(of: legal) ?? "").unicodeScalars)
    // RFC 2396's characters that may appear unescaped.
    let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.!~*'();/?:@&=+$,#[]%".unicodeScalars)
    var output = ""
    for scalar in text.unicodeScalars {
        if keep.contains(scalar) || (allowed.contains(scalar) && !escape.contains(scalar)) {
            output.unicodeScalars.append(scalar)
        } else {
            for byte in String(scalar).utf8 { output += "%" + String(byte, radix: 16, uppercase: true).leftPadded(2) }
        }
    }
    return Strings.make(output)
}

@c(_CFURLCreateStringByReplacingPercentEscapes)
public func CFURLCreateStringByReplacingPercentEscapes(_ allocator: UnsafeRawPointer?, _ string: id?, _ leave: id?) -> id? {
    CFURLCreateStringByReplacingPercentEscapesUsingEncoding(allocator, string, leave, 0x0800_0100)
}

/// Decodes escapes except those for `leave`'s characters; nil if they are
/// not valid in the encoding.
@c(_CFURLCreateStringByReplacingPercentEscapesUsingEncoding)
public func CFURLCreateStringByReplacingPercentEscapesUsingEncoding(_ allocator: UnsafeRawPointer?, _ string: id?, _ leave: id?,
                                                                    _ encoding: UInt32) -> id? {
    guard let text = Strings.value(of: string) else { return nil }
    guard let leave = Strings.value(of: leave) else { return ObjC.retain(string) }
    let kept = Set(leave.utf8)
    var bytes: [UInt8] = []
    var input = Array(text.utf8)[...]
    while let byte = input.first {
        if byte == UInt8(ascii: "%"), input.count >= 3,
           let value = UInt8(String(decoding: input.dropFirst().prefix(2), as: UTF8.self), radix: 16), !kept.contains(value) {
            bytes.append(value)
            input = input.dropFirst(3)
        } else {
            bytes.append(byte)
            input = input.dropFirst()
        }
    }
    return String(validating: bytes, as: UTF8.self).map(Strings.make)
}

extension String {
    func leftPadded(_ width: Int) -> String { count >= width ? self : String(repeating: "0", count: width - count) + self }
}

// MARK: - UUIDs

final class UUIDBox {
    let uuid: UUID

    init(_ uuid: UUID) {
        self.uuid = uuid
    }
}

/// CFUUID, which is not NSUUID.
@ObjCClass("__NSCFUUID")
public class NSCFUUID: NSObject {
    nonisolated(unsafe) static var uuidClass: Class!

    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        uuidClass = cls.storage
    }

    static func uuid(_ object: id?) -> UUID? { Storage.get(object, as: UUIDBox.self)?.uuid }

    /// The CFUUID for a value, +1. CoreFoundation keeps one object per value.
    static func make(_ uuid: UUID) -> id {
        let object = Storage.allocate(UnsafeMutableRawPointer(uuidClass))!
        Storage.set(object, UUIDBox(uuid))
        return object
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: NSCFUUID.uuidClass)
    }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: ObjCObject?) -> Bool { NSCFUUID.uuid(other?.objcObject).map { $0 == NSCFUUID.uuid(objcObject) } ?? false }
    @ObjCMethod("hash") func hash() -> UInt { UInt(bitPattern: NSCFUUID.uuid(objcObject)?.hashValue ?? 0) }
    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { CFTypeIDs.uuid }

    @ObjCMethod("description")
    func description() -> String { "<CFUUID \(objcObject)> \(NSCFUUID.uuid(objcObject)?.uuidString ?? "")" }
}

@c(_CFUUIDGetTypeID) public func CFUUIDGetTypeID() -> UInt { CFTypeIDs.uuid }
@c(_CFUUIDCreate) public func CFUUIDCreate(_ allocator: UnsafeRawPointer?) -> id? { NSCFUUID.make(UUID()) }

@c(_CFUUIDCreateFromString)
public func CFUUIDCreateFromString(_ allocator: UnsafeRawPointer?, _ string: id?) -> id? {
    Strings.value(of: string).flatMap(UUID.init(uuidString:)).map(NSCFUUID.make)
}

@c(_CFUUIDCreateString)
public func CFUUIDCreateString(_ allocator: UnsafeRawPointer?, _ uuid: id?) -> id? { NSCFUUID.uuid(uuid).map { Strings.make($0.uuidString) } }

@c(_CFUUIDGetUUIDBytes)
public func CFUUIDGetUUIDBytes(_ uuid: id?) -> CFUUIDBytes {
    let u = NSCFUUID.uuid(uuid)?.uuid ?? UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)).uuid
    return CFUUIDBytes(byte0: u.0, byte1: u.1, byte2: u.2, byte3: u.3, byte4: u.4, byte5: u.5, byte6: u.6, byte7: u.7,
                       byte8: u.8, byte9: u.9, byte10: u.10, byte11: u.11, byte12: u.12, byte13: u.13, byte14: u.14, byte15: u.15)
}

@c(_CFUUIDCreateFromUUIDBytes)
public func CFUUIDCreateFromUUIDBytes(_ allocator: UnsafeRawPointer?, _ b: CFUUIDBytes) -> id? {
    NSCFUUID.make(UUID(uuid: (b.byte0, b.byte1, b.byte2, b.byte3, b.byte4, b.byte5, b.byte6, b.byte7,
                              b.byte8, b.byte9, b.byte10, b.byte11, b.byte12, b.byte13, b.byte14, b.byte15)))
}

// MARK: - Errors

@c(_CFErrorGetTypeID) public func CFErrorGetTypeID() -> UInt { CFTypeIDs.error }

@c(_CFErrorCreate)
public func CFErrorCreate(_ allocator: UnsafeRawPointer?, _ domain: id?, _ code: Int, _ userInfo: id?) -> id? {
    let entries = Dictionaries.entries(userInfo).compactMap { entry in Strings.value(of: entry.key).map { ($0, entry.value) } }
    return ObjC.retain(ObjC.autorelease(Errors.make(domain: domain, code: code, entries: entries)))
}

@c(_CFErrorGetDomain) public func CFErrorGetDomain(_ error: id?) -> id? { ObjC.send(error, ObjC.selector("domain")) }
@c(_CFErrorGetCode) public func CFErrorGetCode(_ error: id?) -> Int { Int(bitPattern: ObjC.sendUInt(error, ObjC.selector("code"))) }
@c(_CFErrorCopyUserInfo) public func CFErrorCopyUserInfo(_ error: id?) -> id? { ObjC.retain(ObjC.send(error, ObjC.selector("userInfo"))) }

@c(_CFErrorCopyDescription)
public func CFErrorCopyDescription(_ error: id?) -> id? { ObjC.retain(ObjC.send(error, ObjC.selector("localizedDescription"))) }

@c(_CFErrorCopyFailureReason)
public func CFErrorCopyFailureReason(_ error: id?) -> id? { ObjC.retain(ObjC.send(error, ObjC.selector("localizedFailureReason"))) }

// MARK: - Character sets

/// CFCharacterSetPredefinedSet, as NSCharacterSet's class methods.
@c(_CFCharacterSetGetPredefined)
public func CFCharacterSetGetPredefined(_ which: Int) -> id? {
    let names = [1: "controlCharacterSet", 2: "whitespaceCharacterSet", 3: "whitespaceAndNewlineCharacterSet",
                 4: "decimalDigitCharacterSet", 5: "letterCharacterSet", 6: "lowercaseLetterCharacterSet",
                 7: "uppercaseLetterCharacterSet", 8: "nonBaseCharacterSet", 9: "decomposableCharacterSet",
                 10: "alphanumericCharacterSet", 11: "punctuationCharacterSet", 12: "illegalCharacterSet",
                 13: "capitalizedLetterCharacterSet", 14: "symbolCharacterSet", 15: "newlineCharacterSet"]
    guard let name = names[which] else { return nil }
    return ObjC.send(UnsafeMutableRawPointer(CharacterSets.setClass), ObjC.selector(name))
}

@c(_CFCharacterSetGetTypeID) public func CFCharacterSetGetTypeID() -> UInt { CFTypeIDs.characterSet }

@c(_CFCharacterSetCreateWithCharactersInString)
public func CFCharacterSetCreateWithCharactersInString(_ allocator: UnsafeRawPointer?, _ string: id?) -> id? {
    ObjC.retain(ObjC.send(UnsafeMutableRawPointer(CharacterSets.setClass), ObjC.selector("characterSetWithCharactersInString:"), string))
}

@c(_CFCharacterSetIsCharacterMember)
public func CFCharacterSetIsCharacterMember(_ set: id?, _ character: UInt16) -> Bool {
    unsafeBitCast(ObjC.msgSend, to: (@convention(c) (id?, SEL, UInt16) -> Bool).self)(set, ObjC.selector("characterIsMember:"), character)
}

@c(_CFCharacterSetIsLongCharacterMember)
public func CFCharacterSetIsLongCharacterMember(_ set: id?, _ character: UInt32) -> Bool {
    unsafeBitCast(ObjC.msgSend, to: (@convention(c) (id?, SEL, UInt32) -> Bool).self)(set, ObjC.selector("longCharacterIsMember:"), character)
}

@c(_CFCharacterSetCreateInvertedSet)
public func CFCharacterSetCreateInvertedSet(_ allocator: UnsafeRawPointer?, _ set: id?) -> id? {
    ObjC.retain(ObjC.send(set, ObjC.selector("invertedSet")))
}

// MARK: - Time zones and locales

@c(_CFTimeZoneGetTypeID) public func CFTimeZoneGetTypeID() -> UInt { CFTypeIDs.timeZone }

@c(_CFTimeZoneCopySystem)
public func CFTimeZoneCopySystem() -> id? { ObjC.retain(ObjC.send(UnsafeMutableRawPointer(TimeZones.zoneClass), ObjC.selector("systemTimeZone"))) }

@c(_CFTimeZoneCopyDefault)
public func CFTimeZoneCopyDefault() -> id? { ObjC.retain(ObjC.send(UnsafeMutableRawPointer(TimeZones.zoneClass), ObjC.selector("defaultTimeZone"))) }

@c(_CFTimeZoneCreateWithName)
public func CFTimeZoneCreateWithName(_ allocator: UnsafeRawPointer?, _ name: id?, _ tryAbbreviation: Bool) -> id? {
    ObjC.retain(ObjC.send(UnsafeMutableRawPointer(TimeZones.zoneClass), ObjC.selector("timeZoneWithName:"), name))
}

@c(_CFTimeZoneCreateWithTimeIntervalFromGMT)
public func CFTimeZoneCreateWithTimeIntervalFromGMT(_ allocator: UnsafeRawPointer?, _ interval: Double.ObjCType) -> id? {
    TimeZone(secondsFromGMT: Int(Double(objCArgument: interval))).map { ObjC.retain(TimeZones.autoreleased($0))! }
}

@c(_CFTimeZoneGetName) public func CFTimeZoneGetName(_ zone: id?) -> id? { ObjC.send(zone, ObjC.selector("name")) }

@c(_CFTimeZoneGetSecondsFromGMT)
public func CFTimeZoneGetSecondsFromGMT(_ zone: id?, _ time: Double.ObjCType) -> Double.ObjCResultType {
    let date = Date(timeIntervalSinceReferenceDate: Double(objCArgument: time))
    return darwinResult(Double(TimeZones.zone(zone)?.secondsFromGMT(for: date) ?? 0))
}

@c(_CFTimeZoneIsDaylightSavingTime)
public func CFTimeZoneIsDaylightSavingTime(_ zone: id?, _ time: Double.ObjCType) -> Bool {
    TimeZones.zone(zone)?.isDaylightSavingTime(for: Date(timeIntervalSinceReferenceDate: Double(objCArgument: time))) ?? false
}

@c(_CFLocaleGetTypeID) public func CFLocaleGetTypeID() -> UInt { CFTypeIDs.locale }

@c(_CFLocaleCopyCurrent)
public func CFLocaleCopyCurrent() -> id? { ObjC.retain(ObjC.send(UnsafeMutableRawPointer(Locales.localeClass), ObjC.selector("currentLocale"))) }

@c(_CFLocaleGetSystem)
public func CFLocaleGetSystem() -> id? { ObjC.send(UnsafeMutableRawPointer(Locales.localeClass), ObjC.selector("systemLocale")) }

@c(_CFLocaleCreate)
public func CFLocaleCreate(_ allocator: UnsafeRawPointer?, _ identifier: id?) -> id? {
    ObjC.retain(ObjC.send(UnsafeMutableRawPointer(Locales.localeClass), ObjC.selector("localeWithLocaleIdentifier:"), identifier))
}

@c(_CFLocaleGetIdentifier) public func CFLocaleGetIdentifier(_ locale: id?) -> id? { ObjC.send(locale, ObjC.selector("localeIdentifier")) }
@c(_CFLocaleGetValue) public func CFLocaleGetValue(_ locale: id?, _ key: id?) -> id? { ObjC.send(locale, ObjC.selector("objectForKey:"), key) }

@c(_CFLocaleCopyPreferredLanguages)
public func CFLocaleCopyPreferredLanguages() -> id? {
    ObjC.retain(ObjC.send(UnsafeMutableRawPointer(Locales.localeClass), ObjC.selector("preferredLanguages")))
}

// MARK: - Bundles

/// The CFBundle keys of the Info.plist.
@ObjCConstants
enum BundleKeys {
    static let kCFBundleInfoDictionaryVersionKey = "CFBundleInfoDictionaryVersion"
    static let kCFBundleExecutableKey = "CFBundleExecutable"
    static let kCFBundleIdentifierKey = "CFBundleIdentifier"
    static let kCFBundleVersionKey = "CFBundleVersion"
    static let kCFBundleDevelopmentRegionKey = "CFBundleDevelopmentRegion"
    static let kCFBundleNameKey = "CFBundleName"
    static let kCFBundleLocalizationsKey = "CFBundleLocalizations"
}

@c(_CFBundleGetTypeID) public func CFBundleGetTypeID() -> UInt { CFTypeIDs.bundle }

@c(_CFBundleGetMainBundle)
public func CFBundleGetMainBundle() -> id? { ObjC.send(UnsafeMutableRawPointer(Bundles.bundleClass), ObjC.selector("mainBundle")) }

@c(_CFBundleGetBundleWithIdentifier)
public func CFBundleGetBundleWithIdentifier(_ identifier: id?) -> id? {
    ObjC.send(UnsafeMutableRawPointer(Bundles.bundleClass), ObjC.selector("bundleWithIdentifier:"), identifier)
}

@c(_CFBundleCreate)
public func CFBundleCreate(_ allocator: UnsafeRawPointer?, _ url: id?) -> id? {
    ObjC.retain(ObjC.send(UnsafeMutableRawPointer(Bundles.bundleClass), ObjC.selector("bundleWithURL:"), url))
}

@c(_CFBundleGetIdentifier) public func CFBundleGetIdentifier(_ bundle: id?) -> id? { ObjC.send(bundle, ObjC.selector("bundleIdentifier")) }
@c(_CFBundleGetInfoDictionary) public func CFBundleGetInfoDictionary(_ bundle: id?) -> id? { ObjC.send(bundle, ObjC.selector("infoDictionary")) }

@c(_CFBundleGetLocalInfoDictionary)
public func CFBundleGetLocalInfoDictionary(_ bundle: id?) -> id? { ObjC.send(bundle, ObjC.selector("infoDictionary")) }

@c(_CFBundleGetValueForInfoDictionaryKey)
public func CFBundleGetValueForInfoDictionaryKey(_ bundle: id?, _ key: id?) -> id? {
    ObjC.send(bundle, ObjC.selector("objectForInfoDictionaryKey:"), key)
}

@c(_CFBundleCopyBundleURL) public func CFBundleCopyBundleURL(_ bundle: id?) -> id? { ObjC.retain(ObjC.send(bundle, ObjC.selector("bundleURL"))) }

@c(_CFBundleCopyResourcesDirectoryURL)
public func CFBundleCopyResourcesDirectoryURL(_ bundle: id?) -> id? { ObjC.retain(ObjC.send(bundle, ObjC.selector("resourceURL"))) }

@c(_CFBundleCopyExecutableURL)
public func CFBundleCopyExecutableURL(_ bundle: id?) -> id? { ObjC.retain(ObjC.send(bundle, ObjC.selector("executableURL"))) }

@c(_CFBundleCopyAuxiliaryExecutableURL)
public func CFBundleCopyAuxiliaryExecutableURL(_ bundle: id?, _ name: id?) -> id? {
    ObjC.retain(ObjC.send(bundle, ObjC.selector("URLForAuxiliaryExecutable:"), name))
}

@c(_CFBundleCopyResourceURL)
public func CFBundleCopyResourceURL(_ bundle: id?, _ name: id?, _ type: id?, _ subdirectory: id?) -> id? {
    ObjC.retain(unsafeBitCast(ObjC.msgSend, to: (@convention(c) (id?, SEL, id?, id?, id?) -> id?).self)(
        bundle, ObjC.selector("URLForResource:withExtension:subdirectory:"), name, type, subdirectory))
}

@c(_CFBundleCopyLocalizedString)
public func CFBundleCopyLocalizedString(_ bundle: id?, _ key: id?, _ value: id?, _ table: id?) -> id? {
    ObjC.retain(unsafeBitCast(ObjC.msgSend, to: (@convention(c) (id?, SEL, id?, id?, id?) -> id?).self)(
        bundle, ObjC.selector("localizedStringForKey:value:table:"), key, value, table))
}

@c(_CFBundleGetVersionNumber)
public func CFBundleGetVersionNumber(_ bundle: id?) -> UInt32 {
    let version = Strings.value(of: CFBundleGetValueForInfoDictionaryKey(bundle, Strings.autoreleased("CFBundleVersion"))) ?? ""
    let parts = version.split(separator: ".").compactMap { UInt32($0) }
    let major = parts.first ?? 0, minor = parts.count > 1 ? parts[1] : 0, bugfix = parts.count > 2 ? parts[2] : 0
    // 'vers' resource layout: major (BCD), minor and bug-fix nibbles, stage, build.
    return (major / 10 % 10) << 28 | (major % 10) << 24 | (minor % 10) << 20 | (bugfix % 10) << 16 | 0x8000
}

// MARK: - Preferences

/// The applications and users CFPreferences takes; only the current
/// application's values, in the standard user defaults, are kept.
@ObjCConstants
enum PreferenceConstants {
    static let kCFPreferencesAnyApplication = "kCFPreferencesAnyApplication"
    static let kCFPreferencesCurrentApplication = "kCFPreferencesCurrentApplication"
    static let kCFPreferencesAnyHost = "kCFPreferencesAnyHost"
    static let kCFPreferencesCurrentHost = "kCFPreferencesCurrentHost"
    static let kCFPreferencesAnyUser = "kCFPreferencesAnyUser"
    static let kCFPreferencesCurrentUser = "kCFPreferencesCurrentUser"
}

enum Preferences {
    static var defaults: id? {
        ObjC.send(ObjC.getClass("NSUserDefaults").map(UnsafeMutableRawPointer.init), ObjC.selector("standardUserDefaults"))
    }
}

@c(_CFPreferencesCopyAppValue)
public func CFPreferencesCopyAppValue(_ key: id?, _ application: id?) -> id? {
    ObjC.retain(ObjC.send(Preferences.defaults, ObjC.selector("objectForKey:"), key))
}

@c(_CFPreferencesCopyValue)
public func CFPreferencesCopyValue(_ key: id?, _ application: id?, _ user: id?, _ host: id?) -> id? {
    CFPreferencesCopyAppValue(key, application)
}

@c(_CFPreferencesSetAppValue)
public func CFPreferencesSetAppValue(_ key: id?, _ value: id?, _ application: id?) {
    if let value {
        _ = ObjC.send(Preferences.defaults, ObjC.selector("setObject:forKey:"), value, key)
    } else {
        _ = ObjC.send(Preferences.defaults, ObjC.selector("removeObjectForKey:"), key)
    }
}

@c(_CFPreferencesSetValue)
public func CFPreferencesSetValue(_ key: id?, _ value: id?, _ application: id?, _ user: id?, _ host: id?) {
    CFPreferencesSetAppValue(key, value, application)
}

@c(_CFPreferencesGetAppBooleanValue)
public func CFPreferencesGetAppBooleanValue(_ key: id?, _ application: id?, _ valid: UnsafeMutablePointer<Bool>?) -> Bool {
    let value = ObjC.send(Preferences.defaults, ObjC.selector("objectForKey:"), key)
    guard let value else {
        valid?.pointee = false
        return false
    }
    valid?.pointee = true
    if let text = Strings.value(of: value) { return ["yes", "true"].contains(text.lowercased()) || (Int(text) ?? 0) != 0 }
    return Numbers.storage(value).int64 != 0
}

@c(_CFPreferencesGetAppIntegerValue)
public func CFPreferencesGetAppIntegerValue(_ key: id?, _ application: id?, _ valid: UnsafeMutablePointer<Bool>?) -> Int {
    let value = ObjC.send(Preferences.defaults, ObjC.selector("objectForKey:"), key)
    guard let value else {
        valid?.pointee = false
        return 0
    }
    if let text = Strings.value(of: value) {
        valid?.pointee = Int(text) != nil
        return Int(text) ?? 0
    }
    valid?.pointee = true
    return Int(Numbers.storage(value).int64)
}

@c(_CFPreferencesAppSynchronize)
public func CFPreferencesAppSynchronize(_ application: id?) -> Bool { ObjC.sendBool(Preferences.defaults, ObjC.selector("synchronize"), nil) }

@c(_CFPreferencesSynchronize)
public func CFPreferencesSynchronize(_ application: id?, _ user: id?, _ host: id?) -> Bool { CFPreferencesAppSynchronize(application) }

/// Sets and removes several values at once.
@c(_CFPreferencesSetMultiple)
public func CFPreferencesSetMultiple(_ set: id?, _ remove: id?, _ application: id?, _ user: id?, _ host: id?) {
    for (key, value) in Dictionaries.entries(set) { CFPreferencesSetAppValue(key, value, application) }
    for key in Arrays.elements(remove) { CFPreferencesSetAppValue(key, nil, application) }
}

/// An app's preferences are one domain here, searched alone: there are no
/// suites to add to its search or take from it.
@c(_CFPreferencesAddSuitePreferencesToApp)
public func CFPreferencesAddSuitePreferencesToApp(_ application: id?, _ suite: id?) {}

@c(_CFPreferencesRemoveSuitePreferencesFromApp)
public func CFPreferencesRemoveSuitePreferencesFromApp(_ application: id?, _ suite: id?) {}

@c(_CFPreferencesCopyKeyList)
public func CFPreferencesCopyKeyList(_ application: id?, _ user: id?, _ host: id?) -> id? {
    ObjC.retain(ObjC.send(ObjC.send(Preferences.defaults, ObjC.selector("dictionaryRepresentation")), ObjC.selector("allKeys")))
}
