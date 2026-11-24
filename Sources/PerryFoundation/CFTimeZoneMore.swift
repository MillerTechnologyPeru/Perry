import CPerryFoundation
import FoundationEssentials
import FoundationInternationalization
import PerryObjCInterop
import Synchronization

// The rest of CFTimeZone: creating one with data, abbreviations and their
// dictionary, the known names, localized names, a zone's data, and the
// default and system zones.

enum CFTimeZoneMore {
    /// The zones' data CFTimeZoneGetData has given, by zone name: each is
    /// kept for as long as the program runs, as the zone's data is
    /// immutable and there are a few hundred zones at most.
    static let data = Mutex<[String: UInt]>([:])
}

/// A zone of a name, +1. The data, a TZif file's bytes, isn't read: the
/// system's zone database gives the rules, so a name it doesn't know gives
/// NULL, where Darwin would make a zone of the data.
@c(_CFTimeZoneCreate)
public func CFTimeZoneCreate(_ allocator: UnsafeRawPointer?, _ name: id?, _ data: id?) -> id? {
    guard let identifier = Strings.value(of: name), let zone = TimeZone(identifier: identifier) else { return nil }
    return ObjC.autoreleasepool { ObjC.retain(TimeZones.autoreleased(zone)) }
}

/// The zone's abbreviation at an absolute time ("EST", "EDT"), +1.
@DarwinC("_CFTimeZoneCopyAbbreviation")
public func CFTimeZoneCopyAbbreviation(_ zone: id?, _ time: Double) -> id? {
    guard let zone = TimeZones.zone(zone) else { return nil }
    return TimeZones.abbreviation(zone, Date(timeIntervalSinceReferenceDate: time)).map(Strings.make)
}

/// Abbreviations and the zone names they stand for, +1.
@c(_CFTimeZoneCopyAbbreviationDictionary)
public func CFTimeZoneCopyAbbreviationDictionary() -> id? {
    ObjC.autoreleasepool {
        ObjC.retain(Dictionaries.autoreleased(TimeZone.abbreviationDictionary.sorted { $0.key < $1.key }.map {
            (key: Strings.autoreleased($0.key), value: Strings.autoreleased($0.value))
        }))
    }
}

/// Replaces the abbreviation dictionary, which zones made by abbreviation
/// and +[NSTimeZone abbreviationDictionary] then use. Entries that aren't
/// strings are left out.
@c(_CFTimeZoneSetAbbreviationDictionary)
public func CFTimeZoneSetAbbreviationDictionary(_ dictionary: id?) {
    var abbreviations: [String: String] = [:]
    for entry in Dictionaries.entries(dictionary) {
        if let key = Strings.value(of: entry.key), let value = Strings.value(of: entry.value) { abbreviations[key] = value }
    }
    TimeZone.abbreviationDictionary = abbreviations
}

/// The names of the zones in the system's database, +1.
@c(_CFTimeZoneCopyKnownNames)
public func CFTimeZoneCopyKnownNames() -> id? {
    ObjC.autoreleasepool { ObjC.retain(Arrays.autoreleased(TimeZone.knownTimeZoneIdentifiers.map { Strings.autoreleased($0) })) }
}

/// The zone's name in a locale's language, in a CFTimeZoneNameStyle
/// (standard 0, short standard 1, daylight saving 2, short daylight saving
/// 3, generic 4, short generic 5), +1.
@c(_CFTimeZoneCopyLocalizedName)
public func CFTimeZoneCopyLocalizedName(_ zone: id?, _ style: Int, _ locale: id?) -> id? {
    guard let zone = TimeZones.zone(zone) else { return nil }
    return zone.localizedName(for: TimeZones.nameStyle(style), locale: Locales.locale(locale)).map(Strings.make)
}

/// The zone's rules as a TZif file, +0, from the system's zone database;
/// NULL for a fixed offset. Kept for as long as the program runs.
@c(_CFTimeZoneGetData)
public func CFTimeZoneGetData(_ zone: id?) -> id? {
    guard let name = TimeZones.zone(zone)?.identifier else { return nil }
    if let kept = CFTimeZoneMore.data.withLock({ $0[name] }) { return id(bitPattern: kept) }
    guard let data = ObjC.autoreleasepool({ ObjC.retain(ObjC.send(zone, ObjC.selector("data"))) }) else { return nil }
    let kept = CFTimeZoneMore.data.withLock { table -> UInt in
        if let other = table[name] { return other }
        table[name] = UInt(bitPattern: data)
        return UInt(bitPattern: data)
    }
    // Another thread's, kept meanwhile, is the one given out.
    if kept != UInt(bitPattern: data) { ObjC.release(data) }
    return id(bitPattern: kept)
}

/// Sets the zone that CFTimeZoneCopyDefault, +[NSTimeZone defaultTimeZone]
/// and formatters and calendars without one use.
@c(_CFTimeZoneSetDefault)
public func CFTimeZoneSetDefault(_ zone: id?) {
    guard let zone = TimeZones.zone(zone) else { return }
    TimeZones.defaultZone = zone
}

/// Nothing to clear: the system zone isn't cached here beyond what
/// TimeZone.current keeps, as +[NSTimeZone resetSystemTimeZone] does.
@c(_CFTimeZoneResetSystem)
public func CFTimeZoneResetSystem() {}
