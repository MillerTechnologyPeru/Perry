import CPerryFoundation
import FoundationEssentials
import Glibc
import PerryObjCInterop

// CoreFoundation's smaller calls: the user and system, sorting C arrays,
// logging, type IDs and allocators, more of CFSet, CFDictionary, CFData,
// CFUUID, CFCharacterSet, CFError and CFPreferences, the Gregorian date
// arithmetic CFCalendar replaced, and the older property list calls.

// MARK: - The user and the system

private enum UserAccounts {
    static func environment(_ name: String) -> String? { getenv(name).map { String(cString: $0) } }

    /// The current user's short name, as NSUserName has it.
    static var name: String {
        environment("USER") ?? getpwuid(getuid()).flatMap { $0.pointee.pw_name.map { String(cString: $0) } } ?? ""
    }

    /// A user's home directory: the current user's ($HOME) for nil.
    static func home(_ user: String?) -> String? {
        guard let user, user != name else {
            return environment("HOME") ?? getpwuid(getuid()).flatMap { $0.pointee.pw_dir.map { String(cString: $0) } }
        }
        return getpwnam(user).flatMap { $0.pointee.pw_dir.map { String(cString: $0) } }
    }

    /// CFGetUserName's string, made once and kept.
    nonisolated(unsafe) static var cachedName: id?
    static let lock = Monitor()
}

/// The current user's home directory as a directory URL, +1.
@c(_CFCopyHomeDirectoryURL)
public func CFCopyHomeDirectoryURL() -> id? {
    UserAccounts.home(nil).flatMap { CFURLs.make(URLs.fileURL($0, isDirectory: true)) }
}

/// A user's home directory as a directory URL, +1: the current user's for
/// NULL, NULL for a user the password database doesn't know.
@c(_CFCopyHomeDirectoryURLForUser)
public func CFCopyHomeDirectoryURLForUser(_ user: id?) -> id? {
    UserAccounts.home(Strings.value(of: user)).flatMap { CFURLs.make(URLs.fileURL($0, isDirectory: true)) }
}

/// The URLs of a standard directory, +1: one, in the user's home, as
/// NSSearchPathForDirectoriesInDomains gives it, whatever the domains
/// (an app's sandbox has every domain's directory in its home). The paths
/// are always full ones, so expandTilde changes nothing.
@c(_CFCopySearchPathForDirectoriesInDomains)
public func CFCopySearchPathForDirectoriesInDomains(_ directory: Int, _ domains: UInt, _ expandTilde: Bool) -> id? {
    guard domains != 0, directory >= 0, let path = FileManagers.directory(UInt(directory)),
          let url = URLs.autoreleased(URLs.fileURL(path, isDirectory: true)) else {
        return Arrays.make([])
    }
    return Arrays.make([url])
}

/// The current user's short name, +1.
@c(_CFCopyUserName)
public func CFCopyUserName() -> id? { Strings.make(UserAccounts.name) }

/// The current user's short name, +0: one string, kept for the process.
@c(_CFGetUserName)
public func CFGetUserName() -> id? {
    UserAccounts.lock.locked {
        if let name = UserAccounts.cachedName { return name }
        let name = Strings.make(UserAccounts.name)
        UserAccounts.cachedName = name
        return name
    }
}

/// "Version 14.2 (Build …)", +1: the system version NSProcessInfo reports,
/// as _CFCopySystemVersionDictionary gives it.
@c(_CFCopySystemVersionString)
public func CFCopySystemVersionString() -> id? {
    let version = Process.sdkVersion
    let text = "\(version.majorVersion).\(version.minorVersion)" + (version.patchVersion > 0 ? ".\(version.patchVersion)" : "")
    return Strings.make("Version \(text) (Build \(Process.buildVersion))")
}

/// Seconds since the system started, not counting time asleep, as
/// mach_absolute_time counts on Darwin: CLOCK_MONOTONIC.
@DarwinC("_CFGetSystemUptime")
public func CFGetSystemUptime() -> Double {
    var now = timespec()
    clock_gettime(CLOCK_MONOTONIC, &now)
    return Double(now.tv_sec) + Double(now.tv_nsec) / 1e9
}

// MARK: - Logging

/// void CFLog(CFLogLevel level, CFStringRef format, ...)'s body, from a
/// variadic entry point as NSLog's is: the formatted message goes to stderr
/// in NSLog's format, at every level, as there is no system log here.
@c
public func perry_foundation_cf_log(_ level: Int32, _ format: id?, _ arguments: UnsafeRawPointer?) {
    let format = Strings.value(of: format) ?? ""
    guard let arguments else {
        log(format)
        return
    }
    var darwin = DarwinArguments(arguments)
    log(Format.string(format, &darwin))
}

/// Prints what CoreFoundation knows of a string to stderr: its length,
/// whether it is mutable, and its contents.
@c(_CFShowStr)
public func CFShowStr(_ string: id?) {
    var text = "(null)\n"
    if let string, let value = Strings.value(of: string) {
        let eightBit = value.unicodeScalars.allSatisfy { $0.value < 0x80 }
        let mutable = MutableStrings.mutableClass.map { ObjC.isKind(string, of: $0) } ?? false
        text = """
            Length \(value.utf16.count)
            IsEightBit \(eightBit ? 1 : 0)
            HasLengthByte 0
            HasNullByte \(eightBit ? 1 : 0)
            InlineContents 0
            Allocator SystemDefault
            Mutable \(mutable ? 1 : 0)
            Contents "\(value)"

            """
    }
    text.withCString { _ = write(2, $0, strlen($0)) }
}

// MARK: - Sorting

private enum CArraySorting {
    /// Puts `count` elements of `size` bytes in the order `compare` gives
    /// them, keeping equal elements in the order they were in.
    static func sort(_ list: UnsafeMutableRawPointer?, _ count: Int, _ size: Int,
                     _ compare: (UnsafeRawPointer, UnsafeRawPointer) -> Int) {
        guard let list, count > 1, size > 0 else { return }
        let order = (0..<count).sorted { a, b in
            let result = compare(UnsafeRawPointer(list + a * size), UnsafeRawPointer(list + b * size))
            return result != 0 ? result < 0 : a < b
        }
        let sorted = UnsafeMutableRawPointer.allocate(byteCount: count * size, alignment: 16)
        defer { sorted.deallocate() }
        for (to, from) in order.enumerated() {
            (sorted + to * size).copyMemory(from: list + from * size, byteCount: size)
        }
        list.copyMemory(from: sorted, byteCount: count * size)
    }
}

/// Sorts a C array in place with a CFComparatorFunction, which is given
/// pointers to two elements and the context. Sorted stably, which a quick
/// sort may be.
@c(_CFQSortArray)
public func CFQSortArray(_ list: UnsafeMutableRawPointer?, _ count: Int, _ elementSize: Int,
                         _ comparator: (@convention(c) (UnsafeRawPointer?, UnsafeRawPointer?, UnsafeMutableRawPointer?) -> Int)?,
                         _ context: UnsafeMutableRawPointer?) {
    guard let comparator = comparator.map({ darwinCallable($0) }) else { return }
    CArraySorting.sort(list, count, elementSize) { comparator($0, $1, context) }
}

/// Sorts a C array in place, stably, with a CFComparatorFunction.
@c(_CFMergeSortArray)
public func CFMergeSortArray(_ list: UnsafeMutableRawPointer?, _ count: Int, _ elementSize: Int,
                             _ comparator: (@convention(c) (UnsafeRawPointer?, UnsafeRawPointer?, UnsafeMutableRawPointer?) -> Int)?,
                             _ context: UnsafeMutableRawPointer?) {
    guard let comparator = comparator.map({ darwinCallable($0) }) else { return }
    CArraySorting.sort(list, count, elementSize) { comparator($0, $1, context) }
}

/// Sorts a buffer of indexes in place by a block that compares two of them,
/// CFComparisonResult (^)(CFIndex, CFIndex). Always stably and on the
/// calling thread, which kCFSortStable and kCFSortConcurrent both allow.
@c(_CFSortIndexes)
public func CFSortIndexes(_ indexes: UnsafeMutablePointer<Int>?, _ count: Int, _ options: UInt, _ comparator: id?) {
    guard let indexes, let comparator, count > 1 else { return }
    let compare = Blocks.invoke(comparator, as: (@convention(c) (id, Int, Int) -> Int).self)
    let buffer = UnsafeMutableBufferPointer(start: indexes, count: count)
    let sorted = buffer.enumerated().sorted { a, b in
        let result = compare(comparator, a.element, b.element)
        return result != 0 ? result < 0 : a.offset < b.offset
    }.map(\.element)
    for (position, index) in sorted.enumerated() { buffer[position] = index }
}

// MARK: - Types and allocators

/// CFType's own type ID, Darwin's 1.
@c(_CFTypeGetTypeID) public func CFTypeGetTypeID() -> UInt { 1 }

/// CFAllocator's type ID, Darwin's 2.
@c(_CFAllocatorGetTypeID) public func CFAllocatorGetTypeID() -> UInt { 2 }

/// The allocator an object was made with, +0: allocators are ignored when
/// objects are made here, so every object's is kCFAllocatorSystemDefault,
/// as a toll-free bridged object's is on Darwin.
@c(_CFGetAllocator)
public func CFGetAllocator(_ object: id?) -> id? { Allocators.systemDefault }

/// Calls into a Darwin malloc_zone_t: { reserved1, reserved2, size, malloc,
/// calloc, valloc, free, realloc, … }, every field a word.
private enum MallocZones {
    typealias Allocate = @convention(c) (UnsafeMutableRawPointer?, Int) -> UnsafeMutableRawPointer?
    typealias Deallocate = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
    typealias Reallocate = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int) -> UnsafeMutableRawPointer?

    static let allocateOffset = 3 * DarwinLayout.word
    static let deallocateOffset = 6 * DarwinLayout.word
    static let reallocateOffset = 7 * DarwinLayout.word

    static func allocate(_ zone: UnsafeMutableRawPointer?, _ size: Int) -> UnsafeMutableRawPointer? {
        guard let zone, let function = zone.load(fromByteOffset: allocateOffset, as: Allocate?.self) else { return malloc(size) }
        return darwinCallable(function)(zone, size)
    }

    static func reallocate(_ zone: UnsafeMutableRawPointer?, _ pointer: UnsafeMutableRawPointer?, _ size: Int) -> UnsafeMutableRawPointer? {
        guard let zone, let function = zone.load(fromByteOffset: reallocateOffset, as: Reallocate?.self) else {
            return realloc(pointer, size)
        }
        return darwinCallable(function)(zone, pointer, size)
    }

    static func deallocate(_ zone: UnsafeMutableRawPointer?, _ pointer: UnsafeMutableRawPointer?) {
        guard let zone, let function = zone.load(fromByteOffset: deallocateOffset, as: Deallocate?.self) else {
            free(pointer)
            return
        }
        darwinCallable(function)(zone, pointer)
    }
}

/// A new allocator, +1, that allocates from a malloc zone by the zone's
/// own functions (malloc_zone_malloc and the rest would call the same), or
/// with malloc for a NULL zone.
@c(_CFAllocatorCreateWithZone)
public func CFAllocatorCreateWithZone(_ allocator: id?, _ zone: UnsafeMutableRawPointer?) -> id? {
    // The context's info is the zone.
    let allocate: AllocatorContext.Allocate = { size, _, info in MallocZones.allocate(info, size) }
    let reallocate: AllocatorContext.Reallocate = { pointer, size, _, info in MallocZones.reallocate(info, pointer, size) }
    let deallocate: AllocatorContext.Deallocate = { pointer, info in MallocZones.deallocate(info, pointer) }
    let context = AllocatorContext(version: 0, info: zone, retain: nil, release: nil, copyDescription: nil, allocate: allocate,
                                   reallocate: reallocate, deallocate: deallocate, preferredSize: nil)
    return withUnsafePointer(to: context) { CFAllocatorCreate(allocator, UnsafeRawPointer($0)) }
}

/// CFAllocatorAllocate under its newer name.
@c(_CFAllocatorAllocateBytes)
public func CFAllocatorAllocateBytes(_ allocator: id?, _ size: Int, _ hint: UInt) -> UnsafeMutableRawPointer? {
    CFAllocatorAllocate(allocator, size, hint)
}

/// CFAllocatorAllocate: the type descriptor, for Darwin's typed malloc,
/// has no use here.
@DarwinC("_CFAllocatorAllocateTyped")
public func CFAllocatorAllocateTyped(_ allocator: id?, _ size: Int, _ descriptor: UInt64, _ hint: UInt) -> UnsafeMutableRawPointer? {
    CFAllocatorAllocate(allocator, size, hint)
}

/// CFAllocatorReallocate under its newer name.
@c(_CFAllocatorReallocateBytes)
public func CFAllocatorReallocateBytes(_ allocator: id?, _ pointer: UnsafeMutableRawPointer?, _ size: Int,
                                       _ hint: UInt) -> UnsafeMutableRawPointer? {
    CFAllocatorReallocate(allocator, pointer, size, hint)
}

/// CFAllocatorReallocate: the type descriptor has no use here.
@DarwinC("_CFAllocatorReallocateTyped")
public func CFAllocatorReallocateTyped(_ allocator: id?, _ pointer: UnsafeMutableRawPointer?, _ size: Int, _ descriptor: UInt64,
                                       _ hint: UInt) -> UnsafeMutableRawPointer? {
    CFAllocatorReallocate(allocator, pointer, size, hint)
}

// MARK: - Sets, dictionaries, data and UUIDs

/// Whether a set has a member equal to the candidate, and that member, +0.
@c(_CFSetGetValueIfPresent)
public func CFSetGetValueIfPresent(_ set: id?, _ candidate: CFValue, _ value: UnsafeMutablePointer<CFValue>?) -> Bool {
    guard let found = CFSets.member(set, candidate) else { return false }
    value?.pointee = found
    return true
}

/// A new CFUUID of sixteen bytes, +1.
#if arch(arm64)
/// What uuid_bytes.S's _CFUUIDCreateWithBytes calls with the bytes gathered,
/// as Darwin's arm64 ABI packs them on the stack.
@c
public func perry_foundation_cf_uuid_create_with_bytes(_ allocator: UnsafeRawPointer?, _ bytes: UnsafePointer<UInt8>) -> id? {
    NSCFUUID.make(UUIDBytes.uuid(bytes))
}
#else
@c(_CFUUIDCreateWithBytes)
public func CFUUIDCreateWithBytes(_ allocator: UnsafeRawPointer?, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8, _ b3: UInt8,
                                  _ b4: UInt8, _ b5: UInt8, _ b6: UInt8, _ b7: UInt8, _ b8: UInt8, _ b9: UInt8,
                                  _ b10: UInt8, _ b11: UInt8, _ b12: UInt8, _ b13: UInt8, _ b14: UInt8, _ b15: UInt8) -> id? {
    NSCFUUID.make(UUID(uuid: (b0, b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11, b12, b13, b14, b15)))
}
#endif

enum UUIDBytes {
    /// A UUID of sixteen bytes in memory.
    static func uuid(_ b: UnsafePointer<UInt8>) -> UUID {
        UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }
}

/// Where bytes are found in a range of data: the first place, or with
/// kCFDataSearchBackwards (1) the last; with kCFDataSearchAnchored (2)
/// only at the range's start, or its end going backwards. kCFNotFound
/// when they aren't there, or are empty.
@DarwinC("_CFDataFind")
public func CFDataFind(_ data: id?, _ find: id?, _ range: CFRange, _ options: UInt) -> CFRange {
    let notFound = CFRange(location: -1, length: 0)
    let length = CFDataGetLength(find)
    guard length > 0, range.location >= 0, range.length >= length, range.location + range.length <= CFDataGetLength(data),
          let haystack = CFDataGetBytePtr(data), let needle = CFDataGetBytePtr(find) else { return notFound }
    let backwards = options & 1 != 0, anchored = options & 2 != 0
    let first = range.location, last = range.location + range.length - length
    let starts = backwards ? stride(from: last, through: first, by: -1) : stride(from: first, through: last, by: 1)
    for start in starts {
        if memcmp(haystack + start, needle, length) == 0 { return CFRange(location: start, length: length) }
        if anchored { break }
    }
    return notFound
}

// MARK: - Character sets

/// An immutable copy of a character set, +1.
@c(_CFCharacterSetCreateCopy)
public func CFCharacterSetCreateCopy(_ allocator: id?, _ set: id?) -> id? {
    guard let storage = CharacterSets.storage(set) else { return ObjC.send(set, ObjC.selector("copy")) }
    return CharacterSets.make(UnsafeMutableRawPointer(CharacterSets.setClass), storage.contains)
}

/// Fills a CFCharacterSetInlineBuffer: { cset, uint32 flags, rangeStart,
/// rangeLimit, const uint8_t *bitmap }. It says there is no bitmap
/// (kCFCharacterSetNoBitmapAvailable) over all of Unicode, so the inline
/// lookups ask the set itself for every character.
@c(_CFCharacterSetInitInlineBuffer)
public func CFCharacterSetInitInlineBuffer(_ set: id?, _ buffer: UnsafeMutableRawPointer?) {
    guard let buffer else { return }
    let word = DarwinLayout.word
    buffer.storeBytes(of: set, as: id?.self)
    buffer.storeBytes(of: UInt32(2), toByteOffset: word, as: UInt32.self)
    buffer.storeBytes(of: UInt32(0), toByteOffset: word + 4, as: UInt32.self)
    buffer.storeBytes(of: UInt32(0x11_0000), toByteOffset: word + 8, as: UInt32.self)
    buffer.storeBytes(of: nil, toByteOffset: (word + 12 + word - 1) / word * word, as: UnsafeRawPointer?.self)
}

/// Whether a set has the character a UTF-16 surrogate pair stands for;
/// false if they aren't a high and a low surrogate.
@c(_CFCharacterSetIsSurrogatePairMember)
public func CFCharacterSetIsSurrogatePairMember(_ set: id?, _ high: UInt16, _ low: UInt16) -> Bool {
    guard (0xD800...0xDBFF).contains(high), (0xDC00...0xDFFF).contains(low) else { return false }
    let scalar = (UInt32(high - 0xD800) << 10 | UInt32(low - 0xDC00)) + 0x1_0000
    return CFCharacterSetIsLongCharacterMember(set, scalar)
}

// MARK: - Mach ports

/// The messages a port has received that its run loop source has yet to
/// give the program, which are the ones this process can see waiting.
@c(_CFMachPortGetQueuedMessageCount)
public func CFMachPortGetQueuedMessageCount(_ port: id?) -> Int {
    guard let storage = MachPorts.storage(port) else { return 0 }
    return MachPorts.locked { storage.valid ? storage.messages.count : 0 }
}

// MARK: - Errors

/// The error's localized recovery suggestion, +1, or NULL.
@c(_CFErrorCopyRecoverySuggestion)
public func CFErrorCopyRecoverySuggestion(_ error: id?) -> id? {
    ObjC.retain(ObjC.send(error, ObjC.selector("localizedRecoverySuggestion")))
}

/// A new error, +1, whose user info has the keys and values given.
@c(_CFErrorCreateWithUserInfoKeysAndValues)
public func CFErrorCreateWithUserInfoKeysAndValues(_ allocator: UnsafeRawPointer?, _ domain: id?, _ code: Int,
                                                   _ keys: UnsafePointer<id?>?, _ values: UnsafePointer<id?>?,
                                                   _ count: Int) -> id? {
    var entries: [(key: id, value: id)] = []
    if let keys, let values {
        for index in 0..<max(count, 0) {
            if let key = keys[index], let value = values[index] { entries.append((key: key, value: value)) }
        }
    }
    return Errors.make(domain: domain, code: code, userInfo: Dictionaries.autoreleased(entries))
}

// MARK: - Preferences

/// No preference is forced here: Linux has no managed preferences.
@c(_CFPreferencesAppValueIsForced)
public func CFPreferencesAppValueIsForced(_ key: id?, _ application: id?) -> Bool { false }

/// The applications with preferences, +1: only the current application's
/// are kept here, so it is the one, by its bundle identifier.
@c(_CFPreferencesCopyApplicationList)
public func CFPreferencesCopyApplicationList(_ user: id?, _ host: id?) -> id? {
    Arrays.make(CFBundleGetIdentifier(CFBundleGetMainBundle()).map { [$0] } ?? [])
}

/// The values of several keys, +1: those that have values, or all of
/// them for NULL. The current application's, whatever the user and host.
@c(_CFPreferencesCopyMultiple)
public func CFPreferencesCopyMultiple(_ keys: id?, _ application: id?, _ user: id?, _ host: id?) -> id? {
    let defaults = Preferences.defaults
    guard let keys else {
        return Dictionaries.make(Dictionaries.entries(ObjC.send(defaults, ObjC.selector("dictionaryRepresentation"))))
    }
    let entries = Arrays.elements(keys).compactMap { key in
        ObjC.send(defaults, ObjC.selector("objectForKey:"), key).map { (key: key, value: $0) }
    }
    return Dictionaries.make(entries)
}

/// Writes out what has changed, as the standard user defaults keep no
/// other cache to drop.
@c(_CFPreferencesFlushCaches)
public func CFPreferencesFlushCaches() { _ = ObjC.sendBool(Preferences.defaults, ObjC.selector("synchronize"), nil) }

// MARK: - Property lists

/// A property list as XML property list data, +1.
@c(_CFPropertyListCreateXMLData)
public func CFPropertyListCreateXMLData(_ allocator: id?, _ plist: id?) -> id? {
    CFPropertyListCreateData(allocator, plist, 100, 0, nil)
}

/// Whether an object is a property list a format can hold: strings, data,
/// arrays and dictionaries with string keys in kCFPropertyListOpenStepFormat
/// (1); numbers, booleans and dates too in the XML (100) and binary (200)
/// formats. A collection that holds itself is not one.
@c(_CFPropertyListIsValid)
public func CFPropertyListIsValid(_ plist: id?, _ format: Int) -> Bool {
    guard [1, 100, 200].contains(format) else { return false }
    var open: Set<id> = []
    func valid(_ object: id?) -> Bool {
        guard let object else { return false }
        switch CFGetTypeID(object) {
        case CFTypeIDs.string, CFTypeIDs.data:
            return true
        case CFTypeIDs.number, CFTypeIDs.boolean, CFTypeIDs.date:
            return format != 1
        case CFTypeIDs.array:
            guard open.insert(object).inserted else { return false }
            defer { open.remove(object) }
            return CFArrays.values(object).allSatisfy { valid($0.map { UnsafeMutableRawPointer(mutating: $0) }) }
        case CFTypeIDs.dictionary:
            guard open.insert(object).inserted else { return false }
            defer { open.remove(object) }
            return CFDictionaries.entries(object).allSatisfy { entry in
                let key = entry.key.map { UnsafeMutableRawPointer(mutating: $0) }
                return key.map { CFGetTypeID($0) == CFTypeIDs.string } == true
                    && valid(entry.value.map { UnsafeMutableRawPointer(mutating: $0) })
            }
        default:
            return false
        }
    }
    return valid(plist)
}

// MARK: - Gregorian dates

private enum GregorianDates {
    /// CFGregorianUnitFlags.
    static let years: UInt = 1 << 0, months: UInt = 1 << 1, days: UInt = 1 << 2
    static let hours: UInt = 1 << 3, minutes: UInt = 1 << 4, seconds: UInt = 1 << 5

    /// The Gregorian calendar in a time zone, GMT for NULL.
    static func calendar(_ zone: id?) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZones.zone(zone) ?? TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    static func isLeap(_ year: Int) -> Bool { year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) }

    static func daysInMonth(_ month: Int, _ year: Int) -> Int {
        switch month {
        case 2: return isLeap(year) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }
}

/// Whether the fields `flags` names are in range: a year after 0, a month
/// of 1 to 12, a day of 1 to 31 (and in its month, with the year and month
/// checked too), hours to 23, minutes to 59, seconds under 60.
@c(_CFGregorianDateIsValid)
public func CFGregorianDateIsValid(_ date: CFGregorianDate, _ flags: UInt) -> Bool {
    if flags & GregorianDates.years != 0, date.year <= 0 { return false }
    if flags & GregorianDates.months != 0, !(1...12).contains(date.month) { return false }
    if flags & GregorianDates.days != 0, !(1...31).contains(date.day) { return false }
    if flags & GregorianDates.hours != 0, !(0...23).contains(date.hour) { return false }
    if flags & GregorianDates.minutes != 0, !(0...59).contains(date.minute) { return false }
    if flags & GregorianDates.seconds != 0, !(date.second >= 0 && date.second < 60) { return false }
    let whole = GregorianDates.years | GregorianDates.months | GregorianDates.days
    if flags & whole == whole, Int(date.day) > GregorianDates.daysInMonth(Int(date.month), Int(date.year)) { return false }
    return true
}

/// The day of the year a time falls on in a time zone, from 1.
@DarwinC("_CFAbsoluteTimeGetDayOfYear")
public func CFAbsoluteTimeGetDayOfYear(_ time: Double, _ zone: id?) -> Int32 {
    let date = Date(timeIntervalSinceReferenceDate: time)
    return Int32(GregorianDates.calendar(zone).ordinality(of: .day, in: .year, for: date) ?? 1)
}

/// The ISO 8601 week of the year a time falls in, 1 to 53: weeks start on
/// Monday, and the first is the one with the year's first Thursday.
@DarwinC("_CFAbsoluteTimeGetWeekOfYear")
public func CFAbsoluteTimeGetWeekOfYear(_ time: Double, _ zone: id?) -> Int32 {
    var calendar = GregorianDates.calendar(zone)
    calendar.firstWeekday = 2
    calendar.minimumDaysInFirstWeek = 4
    return Int32(calendar.component(.weekOfYear, from: Date(timeIntervalSinceReferenceDate: time)))
}

/// A time with Gregorian units added in a time zone's calendar: the years,
/// months and days by the calendar, a day past the end of a shorter month
/// moving back to its last; then the hours, minutes and seconds.
@DarwinC("_CFAbsoluteTimeAddGregorianUnits")
public func CFAbsoluteTimeAddGregorianUnits(_ time: Double, _ zone: id?, _ units: CFGregorianUnits) -> Double {
    var parts = DateComponents()
    parts.year = Int(units.years)
    parts.month = Int(units.months)
    parts.day = Int(units.days)
    let start = Date(timeIntervalSinceReferenceDate: time)
    let moved = GregorianDates.calendar(zone).date(byAdding: parts, to: start) ?? start
    return moved.timeIntervalSinceReferenceDate + Double(units.hours) * 3600 + Double(units.minutes) * 60 + units.seconds
}

/// How far the first time is after the second in the units `flags` names,
/// in a time zone's calendar; the seconds keep their fraction.
@DarwinC("_CFAbsoluteTimeGetDifferenceAsGregorianUnits")
public func CFAbsoluteTimeGetDifferenceAsGregorianUnits(_ time: Double, _ other: Double, _ zone: id?, _ flags: UInt) -> CFGregorianUnits {
    let calendar = GregorianDates.calendar(zone)
    let end = Date(timeIntervalSinceReferenceDate: time), start = Date(timeIntervalSinceReferenceDate: other)
    var components: Set<Calendar.Component> = []
    if flags & GregorianDates.years != 0 { components.insert(.year) }
    if flags & GregorianDates.months != 0 { components.insert(.month) }
    if flags & GregorianDates.days != 0 { components.insert(.day) }
    if flags & GregorianDates.hours != 0 { components.insert(.hour) }
    if flags & GregorianDates.minutes != 0 { components.insert(.minute) }
    let parts = components.isEmpty ? DateComponents() : calendar.dateComponents(components, from: start, to: end)
    var units = CFGregorianUnits()
    units.years = Int32(parts.year ?? 0)
    units.months = Int32(parts.month ?? 0)
    units.days = Int32(parts.day ?? 0)
    units.hours = Int32(parts.hour ?? 0)
    units.minutes = Int32(parts.minute ?? 0)
    if flags & GregorianDates.seconds != 0 {
        let reached = components.isEmpty ? start : calendar.date(byAdding: parts, to: start) ?? start
        units.seconds = end.timeIntervalSince(reached)
    }
    return units
}
