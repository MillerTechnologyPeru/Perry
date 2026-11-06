import CPerryFoundation
import FoundationEssentials
import Glibc
import PerryObjCInterop
import _FoundationICU

// NSRegularExpression over ICU's regular expressions (uregex), as Darwin's
// is, so patterns, flags and matching behave alike. Positions are UTF-16
// offsets, which ICU and NSString share. Templates ($1, \$) are expanded
// here, as NSRegularExpression does.

/// A compiled pattern, matched against UTF-16 text.
final class RegexStorage {
    let pattern: String
    let options: UInt
    private let regex: OpaquePointer
    let groups: Int
    private let lock = NSRecursiveLockStorage()

    /// NSRegularExpressionOptions as ICU's flags.
    static func flags(_ options: UInt) -> UInt32 {
        var flags: UInt32 = 0
        if options & 1 != 0 { flags |= UInt32(UREGEX_CASE_INSENSITIVE.rawValue) }
        if options & 2 != 0 { flags |= UInt32(UREGEX_COMMENTS.rawValue) }
        if options & 4 != 0 { flags |= UInt32(UREGEX_LITERAL.rawValue) }
        if options & 8 != 0 { flags |= UInt32(UREGEX_DOTALL.rawValue) }
        if options & 16 != 0 { flags |= UInt32(UREGEX_MULTILINE.rawValue) }
        if options & 32 != 0 { flags |= UInt32(UREGEX_UNIX_LINES.rawValue) }
        if options & 64 != 0 { flags |= UInt32(UREGEX_UWORD.rawValue) }
        return flags
    }

    init?(pattern: String, options: UInt) {
        var status = U_ZERO_ERROR
        let units = Array(pattern.utf16)
        guard let regex = units.withUnsafeBufferPointer({
            swift_uregex_open($0.baseAddress, Int32(units.count), RegexStorage.flags(options), nil, &status)
        }), !ICU.failed(status) else { return nil }
        self.pattern = pattern
        self.options = options
        self.regex = regex
        groups = Int(swift_uregex_groupCount(regex, &status))
    }

    deinit {
        swift_uregex_close(regex)
    }

    func group(named name: String) -> Int? {
        var status = U_ZERO_ERROR
        let units = Array(name.utf16)
        let number = units.withUnsafeBufferPointer {
            swift_uregex_groupNumberFromName(regex, $0.baseAddress, Int32(units.count), &status)
        }
        return ICU.failed(status) ? nil : Int(number)
    }

    /// Each match's group ranges in `range` of `text`, until `body` stops.
    /// NSMatchingOptions: anchored 4, transparent bounds 8, without
    /// anchoring bounds 16.
    func matches(in text: [UInt16], range: NSRange, options: UInt, _ body: ([NSRange]) -> Bool) {
        lock.locked {
            text.withUnsafeBufferPointer { buffer in
                var status = U_ZERO_ERROR
                swift_uregex_setText(regex, buffer.baseAddress, Int32(buffer.count), &status)
                swift_uregex_setRegion(regex, Int32(range.location), Int32(range.location + range.length), &status)
                swift_uregex_useTransparentBounds(regex, options & 8 != 0 ? 1 : 0, &status)
                swift_uregex_useAnchoringBounds(regex, options & 16 != 0 ? 0 : 1, &status)
                guard !ICU.failed(status) else { return }
                let anchored = options & 4 != 0
                var first = true
                while true {
                    let found = anchored && first ? swift_uregex_lookingAt(regex, -1, &status)
                                                   : swift_uregex_findNext(regex, &status)
                    guard found != 0, !ICU.failed(status) else { return }
                    first = false
                    let ranges = (0...groups).map { group -> NSRange in
                        var groupStatus = U_ZERO_ERROR
                        let start = swift_uregex_start(regex, Int32(group), &groupStatus)
                        let end = swift_uregex_end(regex, Int32(group), &groupStatus)
                        guard start >= 0, !ICU.failed(groupStatus) else { return NSRange(location: notFound, length: 0) }
                        return NSRange(location: UInt(start), length: UInt(end - start))
                    }
                    if !body(ranges) || anchored { return }
                }
            }
            var status = U_ZERO_ERROR
            swift_uregex_setText(regex, nil, 0, &status)
        }
    }

    /// The template with $n and \x expanded for one match.
    func expand(_ template: String, ranges: [NSRange], text: [UInt16]) -> String {
        var output: [UInt16] = []
        let units = Array(template.utf16)
        var index = 0
        while index < units.count {
            let unit = units[index]
            if unit == 0x5C, index + 1 < units.count {   // \
                output.append(units[index + 1])
                index += 2
            } else if unit == 0x24, index + 1 < units.count, (0x30...0x39).contains(units[index + 1]) {   // $n
                var group = Int(units[index + 1] - 0x30)
                index += 2
                while index < units.count, (0x30...0x39).contains(units[index]) {
                    let longer = group * 10 + Int(units[index] - 0x30)
                    guard longer <= groups else { break }
                    group = longer
                    index += 1
                }
                if group < ranges.count, ranges[group].location != notFound {
                    let range = ranges[group]
                    output += text[Int(range.location)..<Int(range.location + range.length)]
                }
            } else {
                output.append(unit)
                index += 1
            }
        }
        return String(decoding: output, as: UTF16.self)
    }
}

/// A recursive mutex, for one regex used from several threads.
final class NSRecursiveLockStorage {
    private let storage = LockStorage(recursive: true)

    func locked<T>(_ body: () -> T) -> T {
        pthread_mutex_lock(storage.mutex)
        defer { pthread_mutex_unlock(storage.mutex) }
        return body()
    }
}

enum Regexes {
    nonisolated(unsafe) static var regexClass: Class!
    nonisolated(unsafe) static var resultClass: Class!

    static func storage(_ object: id?) -> RegexStorage? { Storage.get(object, as: RegexStorage.self) }

    /// NSString's NSRegularExpressionSearch: the first match of `pattern`.
    static func search(_ pattern: String, in text: String, options: UInt) -> NSRange {
        let flags: UInt = options & 1 != 0 ? 1 : 0   // NSCaseInsensitiveSearch
        guard let regex = RegexStorage(pattern: pattern, options: flags) else { return NSRange(location: notFound, length: 0) }
        let units = Array(text.utf16)
        var found = NSRange(location: notFound, length: 0)
        regex.matches(in: units, range: NSRange(location: 0, length: UInt(units.count)), options: options & 8 != 0 ? 4 : 0) { ranges in
            found = ranges[0]
            return options & 4 != 0     // NSBackwardsSearch: keep looking for the last
        }
        return found
    }
}

/// A match's ranges, and what a data detector found.
final class CheckingResultStorage {
    let ranges: [NSRange]
    let regex: id?
    /// NSTextCheckingType: regular expression, else what was detected.
    var type: UInt64 = DataDetectors.regularExpression
    var url: URL?
    var phoneNumber: String?

    init(ranges: [NSRange], regex: id?) {
        self.ranges = ranges
        self.regex = ObjC.retain(regex)
    }

    deinit {
        ObjC.release(regex)
    }
}

/// NSRegularExpression.
@ObjCClass("NSRegularExpression")
public class NSRegularExpression: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        Regexes.regexClass = cls.storage
    }

    var regex: RegexStorage? { Regexes.storage(objcObject) }

    @ObjCMethod("dealloc")
    func dealloc() {
        DataDetectors.forget(objcObject)
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: Regexes.regexClass)
    }

    static func failure(_ pattern: String, _ error: UnsafeMutablePointer<id?>?) {
        error?.pointee = ObjC.autorelease(Errors.make(domain: Errors.cocoaDomain, code: 2048, entries: [
            ("NSInvalidValue", Strings.autoreleased(pattern))]))
    }

    @ObjCClassMethod("regularExpressionWithPattern:options:error:")
    static func make(_ cls: ObjCClass, pattern: String, options: UInt, error: UnsafeMutablePointer<id?>?) -> UnsafeMutableRawPointer? {
        guard let regex = RegexStorage(pattern: pattern, options: options), let object = Storage.allocate(cls.pointer) else {
            failure(pattern, error)
            return nil
        }
        Storage.set(object, regex)
        return ObjC.autorelease(object)
    }

    @ObjCMethod("initWithPattern:options:error:")
    func initialize(pattern: String, options: UInt, error: UnsafeMutablePointer<id?>?) -> UnsafeMutableRawPointer? {
        guard let regex = RegexStorage(pattern: pattern, options: options) else {
            NSRegularExpression.failure(pattern, error)
            return nil
        }
        Storage.set(objcObject, regex)
        return ObjC.retain(objcObject)
    }

    @ObjCMethod("pattern") func pattern() -> String { regex?.pattern ?? "" }
    @ObjCMethod("options") func options() -> UInt { regex?.options ?? 0 }
    @ObjCMethod("numberOfCaptureGroups") func numberOfCaptureGroups() -> UInt { UInt(regex?.groups ?? 0) }
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjC.retain(objcObject)! }

    @ObjCClassMethod("escapedPatternForString:")
    static func escapedPattern(for string: String) -> String {
        var escaped = ""
        for character in string {
            if "\\*?+[(){}^$|./".contains(character) { escaped.append("\\") }
            escaped.append(character)
        }
        return escaped
    }

    @ObjCClassMethod("escapedTemplateForString:")
    static func escapedTemplate(for string: String) -> String {
        var escaped = ""
        for character in string {
            if character == "$" || character == "\\" { escaped.append("\\") }
            escaped.append(character)
        }
        return escaped
    }

    /// A match as a result: a data detector's with what it found, its
    /// whole match its one range.
    private func checkingResult(_ ranges: [NSRange], _ string: String) -> id {
        let object = Storage.allocate(UnsafeMutableRawPointer(Regexes.resultClass))!
        let result: CheckingResultStorage
        if let types = DataDetectors.groupTypes(objcObject) {
            result = CheckingResultStorage(ranges: [ranges[0]], regex: nil)
            let units = Array(string.utf16)
            let match = ranges[0]
            let text = String(decoding: units[Int(match.location)..<Int(match.location + match.length)], as: UTF16.self)
            let group = ranges.indices.dropFirst().first { ranges[$0].location != notFound }
            let type = group.flatMap { $0 - 1 < types.count ? types[$0 - 1] : nil } ?? DataDetectors.link
            result.type = type
            if type == DataDetectors.link { result.url = DataDetectors.url(text) }
            if type == DataDetectors.phoneNumber { result.phoneNumber = text }
        } else {
            result = CheckingResultStorage(ranges: ranges, regex: objcObject)
        }
        Storage.set(object, result)
        return ObjC.autorelease(object)!
    }

    private func each(_ string: String, _ options: UInt, _ range: NSRange, _ body: ([NSRange]) -> Bool) {
        regex?.matches(in: Array(string.utf16), range: range, options: options, body)
    }

    @ObjCMethod("matchesInString:options:range:")
    func matches(in string: String, options: UInt, range: NSRange) -> ObjCObject {
        var results: [id] = []
        each(string, options, range) { ranges in
            results.append(checkingResult(ranges, string))
            return true
        }
        return ObjCObject(Arrays.autoreleased(results))
    }

    @ObjCMethod("numberOfMatchesInString:options:range:")
    func numberOfMatches(in string: String, options: UInt, range: NSRange) -> UInt {
        var count: UInt = 0
        each(string, options, range) { _ in
            count += 1
            return true
        }
        return count
    }

    @ObjCMethod("firstMatchInString:options:range:")
    func firstMatch(in string: String, options: UInt, range: NSRange) -> UnsafeMutableRawPointer? {
        var first: [NSRange]?
        each(string, options, range) { ranges in
            first = ranges
            return false
        }
        return first.map { checkingResult($0, string) }
    }

    @ObjCMethod("rangeOfFirstMatchInString:options:range:")
    func rangeOfFirstMatch(in string: String, options: UInt, range: NSRange) -> NSRange {
        var first = NSRange(location: notFound, length: 0)
        each(string, options, range) { ranges in
            first = ranges[0]
            return false
        }
        return first
    }

    /// The block: void (^)(NSTextCheckingResult *, NSMatchingFlags, BOOL *stop).
    @ObjCMethod("enumerateMatchesInString:options:range:usingBlock:")
    func enumerateMatches(in string: String, options: UInt, range: NSRange, using block: ObjCObject) {
        typealias Invoke = @convention(c) (id, id?, UInt, UnsafeMutablePointer<Bool>) -> Void
        let invoke = Blocks.invoke(block.id, as: Invoke.self)
        each(string, options, range) { ranges in
            var stop = false
            ObjC.autoreleasepool { invoke(block.id, checkingResult(ranges, string), 0, &stop) }
            return !stop
        }
    }

    private func replaced(_ string: String, options: UInt, range: NSRange, template: String) -> (String, UInt) {
        let units = Array(string.utf16)
        var output: [UInt16] = []
        var cursor = 0
        var count: UInt = 0
        each(string, options, range) { ranges in
            let match = ranges[0]
            output += units[cursor..<Int(match.location)]
            output += Array((regex?.expand(template, ranges: ranges, text: units) ?? "").utf16)
            cursor = Int(match.location + match.length)
            count += 1
            return true
        }
        output += units[cursor...]
        return (String(decoding: output, as: UTF16.self), count)
    }

    @ObjCMethod("stringByReplacingMatchesInString:options:range:withTemplate:")
    func replacingMatches(in string: String, options: UInt, range: NSRange, template: String) -> String {
        replaced(string, options: options, range: range, template: template).0
    }

    /// For an NSMutableString: replaces its contents, returning the count.
    @ObjCMethod("replaceMatchesInString:options:range:withTemplate:")
    func replaceMatches(in string: ObjCObject, options: UInt, range: NSRange, template: String) -> UInt {
        let (text, count) = replaced(Strings.value(of: string.id) ?? "", options: options, range: range, template: template)
        if count > 0 { _ = ObjC.send(string.id, ObjC.selector("setString:"), Strings.autoreleased(text)) }
        return count
    }

    @ObjCMethod("replacementStringForResult:inString:offset:template:")
    func replacement(for result: ObjCObject, in string: String, offset: Int, template: String) -> String {
        let ranges = Storage.get(result.id, as: CheckingResultStorage.self)?.ranges ?? []
        let shifted = ranges.map { $0.location == notFound ? $0 : NSRange(location: UInt(Int($0.location) + offset), length: $0.length) }
        return regex?.expand(template, ranges: shifted, text: Array(string.utf16)) ?? template
    }
}

/// NSTextCheckingResult, of the regular-expression type.
@ObjCClass("NSTextCheckingResult")
public final class NSTextCheckingResult: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        Regexes.resultClass = cls.storage
    }

    var storage: CheckingResultStorage? { Storage.get(objcObject, as: CheckingResultStorage.self) }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: Regexes.resultClass)
    }

    /// NSTextCheckingTypeRegularExpression.
    @ObjCMethod("resultType") func resultType() -> UInt64 { storage?.type ?? DataDetectors.regularExpression }
    @ObjCMethod("URL") func url() -> ObjCObject? { storage?.url.flatMap { URLs.autoreleased($0) }.map(ObjCObject.init) }
    @ObjCMethod("phoneNumber") func phoneNumber() -> String? { storage?.phoneNumber }
    @ObjCMethod("range") func range() -> NSRange { storage?.ranges.first ?? NSRange(location: notFound, length: 0) }
    @ObjCMethod("numberOfRanges") func numberOfRanges() -> UInt { UInt(storage?.ranges.count ?? 0) }

    @ObjCMethod("rangeAtIndex:")
    func range(at index: UInt) -> NSRange {
        guard let ranges = storage?.ranges, Int(index) < ranges.count else {
            foundationFatal("-[NSTextCheckingResult rangeAtIndex:]: index \(index) out of bounds")
        }
        return ranges[Int(index)]
    }

    @ObjCMethod("rangeWithName:")
    func range(withName name: String) -> NSRange {
        guard let storage, let group = Regexes.storage(storage.regex)?.group(named: name), group < storage.ranges.count else {
            return NSRange(location: notFound, length: 0)
        }
        return storage.ranges[group]
    }

    @ObjCMethod("regularExpression") func regularExpression() -> UnsafeMutableRawPointer? { storage?.regex }

    @ObjCMethod("resultByAdjustingRangesWithOffset:")
    func adjusted(offset: Int) -> UnsafeMutableRawPointer? {
        guard let storage, let object = Storage.allocate(UnsafeMutableRawPointer(Regexes.resultClass)) else { return nil }
        let ranges = storage.ranges.map {
            $0.location == notFound ? $0 : NSRange(location: UInt(Int($0.location) + offset), length: $0.length)
        }
        Storage.set(object, CheckingResultStorage(ranges: ranges, regex: storage.regex))
        return ObjC.autorelease(object)
    }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjC.retain(objcObject)! }
}

// MARK: - NSDataDetector

/// What data detectors find, as NSTextCheckingTypes, and the patterns they
/// find them by: links (URLs, www addresses and email addresses) and phone
/// numbers (North American, and international ones written with a +).
/// Dates, addresses and transit information are not detected.
enum DataDetectors {
    static let date: UInt64 = 1 << 3, address: UInt64 = 1 << 4, link: UInt64 = 1 << 5
    static let regularExpression: UInt64 = 1 << 10, phoneNumber: UInt64 = 1 << 11

    static let patterns: [(type: UInt64, pattern: String)] = [
        (link, #"(?i:(?:(?:https?|ftp)://|www\.)[^\s<>"]*[^\s<>".,;:!?)\]']|[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,})"#),
        (phoneNumber, #"(?:\+\d[\d\s().-]{7,}\d|(?<!\d)(?:\+?1[\s.-]?)?\(?\d{3}\)?[\s.-]?\d{3}[\s.-]?\d{4}(?!\d))"#),
    ]

    /// Each detector's types, a capturing group's each, by object.
    nonisolated(unsafe) static var detectors: [UInt: [UInt64]] = [:]
    nonisolated(unsafe) static let lock = NSRecursiveLockStorage()

    static func groupTypes(_ object: id) -> [UInt64]? { lock.locked { detectors[UInt(bitPattern: object)] } }
    static func forget(_ object: id) { lock.locked { detectors[UInt(bitPattern: object)] = nil } }

    /// The pattern for `types`, a group each, and the types in group order.
    static func pattern(_ types: UInt64) -> (String, [UInt64]) {
        let chosen = patterns.filter { types & $0.type != 0 }
        // A detector of nothing matches nothing.
        guard !chosen.isEmpty else { return ("(?!)", []) }
        return (chosen.map { "(" + $0.pattern + ")" }.joined(separator: "|"), chosen.map(\.type))
    }

    static func url(_ text: String) -> URL? {
        if text.contains("@"), !text.contains("://") { return URL(string: "mailto:" + text) }
        if text.lowercased().hasPrefix("www.") { return URL(string: "http://" + text) }
        return URL(string: text)
    }
}

/// NSDataDetector: a regular expression for the kinds of data it is asked
/// to find.
@ObjCClass("NSDataDetector")
public final class NSDataDetector: NSRegularExpression {
    @ObjCClassMethod("dataDetectorWithTypes:error:")
    static func detector(_ cls: ObjCClass, types: UInt64, error: UnsafeMutablePointer<id?>?) -> UnsafeMutableRawPointer? {
        let (pattern, groups) = DataDetectors.pattern(types)
        guard let regex = RegexStorage(pattern: pattern, options: 0), let object = Storage.allocate(cls.pointer) else {
            NSRegularExpression.failure(pattern, error)
            return nil
        }
        Storage.set(object, regex)
        DataDetectors.lock.locked { DataDetectors.detectors[UInt(bitPattern: object)] = groups }
        return ObjC.autorelease(object)
    }

    @ObjCMethod("initWithTypes:error:")
    func initialize(types: UInt64, error: UnsafeMutablePointer<id?>?) -> UnsafeMutableRawPointer? {
        let (pattern, groups) = DataDetectors.pattern(types)
        guard let regex = RegexStorage(pattern: pattern, options: 0) else {
            NSRegularExpression.failure(pattern, error)
            return nil
        }
        Storage.set(objcObject, regex)
        let object = objcObject
        DataDetectors.lock.locked { DataDetectors.detectors[UInt(bitPattern: object)] = groups }
        return ObjC.retain(objcObject)
    }

    @ObjCMethod("checkingTypes")
    func checkingTypes() -> UInt64 { DataDetectors.groupTypes(objcObject)?.reduce(0, |) ?? 0 }
}
